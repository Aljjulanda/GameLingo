import XCTest
import Foundation
import CryptoKit
import SQLite3
import ZIPFoundation
import UniformTypeIdentifiers
import UIKit
@testable import GameLingo

final class PackIntegrationTests: XCTestCase {
    func testQualityImportV2ProfilesAndNamesRetainOriginalAndRollback() async throws {
        let root = try folder(), file = root.appendingPathComponent("quality.json"), store = TranslationPackStore(root:root.appendingPathComponent("packs"))
        let bytes = Data(#"{"game_id":"quality","entries":[{"en":"Arthur: ~z~Stay~n~here?","ar":"Arthur: <C>ابق هنا.</C>"},{"en":"Arthur","ar":"آرثر"},{"en":"Take {0} items.","ar":"خذ {0} أغراض."}]}"#.utf8)
        try bytes.write(to:file)
        let (result,report) = await inspect(file,store:store); try result.get()
        let saved = await state(store), manifest = try XCTUnwrap(saved.registry.packs.first?.manifest)
        XCTAssertEqual(manifest.schemaVersion,2); XCTAssertEqual(report.gameId,"quality")
        XCTAssertEqual(report.quality?.rawUsable,3); XCTAssertEqual(report.quality?.markupUsable,2)
        XCTAssertEqual(report.quality?.cleaned,1); XCTAssertEqual(report.quality?.excluded,1)
        XCTAssertTrue(manifest.speakerNames?.isEmpty == true)
        XCTAssertEqual(manifest.quality?.speakerNames,["Arthur"])
        XCTAssertEqual(try Data(contentsOf:file),bytes); XCTAssertNil(saved.registry.selectedGame)
        store.changeSelection(game:"quality"); try await waitLoaded(store)
        XCTAssertEqual(store.lookup("Arthur: ~z~Stay~n~here?",category:"dialogue",eventID:nil),"Arthur: <C>ابق هنا.</C>")
        store.configureQuality(PackQualityOptions(markup:true,labels:true,punctuation:true))
        let match = store.lookupDetailed("Stay, here!",category:"dialogue",eventID:nil)
        XCTAssertEqual(match.text,"ابق هنا."); XCTAssertEqual(match.origin,.packPunctuationless)
        XCTAssertNil(store.lookup("Take {0} items.",category:"dialogue",eventID:nil))
        let names: [GameName] = await withCheckedContinuation { continuation in store.qualityNames{_,_,names in continuation.resume(returning:names)} }
        XCTAssertEqual(names.first?.arabic,"آرثر"); XCTAssertEqual(names.first?.source,.pack)
        XCTAssertEqual(names.first?.packLabel,true); XCTAssertEqual(names.first?.approximate,false)
        store.configureQuality(PackQualityOptions(labels:true))
        XCTAssertEqual(store.lookup("~z~Stay~n~here?",category:"dialogue",eventID:nil),"<C>ابق هنا.</C>")
        store.configureQuality(PackQualityOptions())
        XCTAssertNil(store.lookup("Stay, here!",category:"dialogue",eventID:nil))
        XCTAssertEqual(store.lookup("Take {0} items.",category:"dialogue",eventID:nil),"خذ {0} أغراض.")
        let offNames: [GameName] = await withCheckedContinuation { continuation in store.qualityNames{_,_,names in continuation.resume(returning:names)} }
        XCTAssertTrue(offNames.isEmpty)
        let restored = TranslationPackStore(root:store.root); try await waitLoaded(restored)
        XCTAssertEqual(restored.lookup("Arthur: ~z~Stay~n~here?",category:"dialogue",eventID:nil),"Arthur: <C>ابق هنا.</C>")
    }
    @MainActor func testQualityActivateNowIsExplicitAndRetainsLegacyNamesWhenOff() async throws {
        let root = try folder(), file = root.appendingPathComponent("activation.json")
        try Data(#"{"game_id":"activation","entries":[{"en":"Arthur: Stay here.","ar":"ابق هنا."}]}"#.utf8).write(to:file)
        let library = GamePackLibrary(store:TranslationPackStore(root:root.appendingPathComponent("packs")))
        var names = ""
        library.onNamesChanged = { names = $0 }
        XCTAssertTrue(library.importFile(file))
        for _ in 0..<250 { if !library.busy { break }; try await Task.sleep(nanoseconds:20_000_000) }
        XCTAssertFalse(library.busy); XCTAssertEqual(library.inspection?.gameId,"activation")
        XCTAssertNil(library.state.registry.selectedGame)
        library.activateImported(); try await waitLoaded(library.store)
        for _ in 0..<100 { if library.state.loaded { break }; try await Task.sleep(nanoseconds:20_000_000) }
        XCTAssertEqual(library.state.registry.selectedGame,"activation"); XCTAssertEqual(names,"")
        var quality = QualitySettings(); quality[.packLabels] = true
        library.configureQuality(quality); XCTAssertEqual(names,"Arthur")
        library.configureQuality(QualitySettings()); XCTAssertEqual(names,"")
    }
    func testQualityCacheAndCorrectionsFollowActualActiveGame() async throws {
        let root = try folder(), store = TranslationPackStore(root:root.appendingPathComponent("packs"))
        try await importFile(pack(),to:store); try await importFile(pack(game:"other"),to:store)
        store.changeSelection(game:"fixture"); try await waitLoaded(store)
        let model = try XCTUnwrap(Bundle(for:Self.self).url(forResource:"en_ar",withExtension:nil))
        let translator = OfflineTranslator(folder:model,packs:store)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void,Error>) in translator.load{continuation.resume(with:$0)} }
        func translated() async throws -> TranslationDecision {
            try await withCheckedThrowingContinuation { continuation in translator.translateDetailed("Where are you going?"){ result,_ in continuation.resume(with:result) } }
        }
        let first = try await translated(), cached = try await translated()
        XCTAssertEqual(first.origin,.argosInference); XCTAssertEqual(cached.origin,.argosCache)
        var quality = QualitySettings(); quality[.packPunctuation] = true
        translator.configureQuality(quality)
        let flag = try await translated(); XCTAssertEqual(flag.origin,.argosInference); XCTAssertEqual(flag.text,first.text)
        var names = GameNamesSnapshot(game:"fixture"); names.version = 1; translator.configureNames(names)
        let renamed = try await translated(); XCTAssertEqual(renamed.origin,.argosInference)
        store.changeSelection(game:"other"); try await waitLoaded(store)
        let changed = try await translated(); XCTAssertEqual(changed.origin,.argosInference); XCTAssertEqual(changed.game,"other")
        let corrections = try GameCorrectionsStore(root:root.appendingPathComponent("corrections"),game:"fixture")
        try corrections.save(source:"Where are you going?",target:"تصحيح اللعبة الأولى")
        translator.configureCorrections(corrections.snapshot,enabled:true)
        let isolated = try await translated(); XCTAssertNotEqual(isolated.origin,.userCorrection); XCTAssertEqual(isolated.text,first.text)
        let selected = await state(store), item = try XCTUnwrap(selected.registry.packs.first{$0.manifest.gameId == "other"})
        store.enable(item.id,false); _ = await state(store)
        let disabled = try await translated(); XCTAssertEqual(disabled.origin,.argosInference); XCTAssertNil(disabled.pack)
        XCTAssertEqual(disabled.game,"other"); XCTAssertEqual(disabled.fallback,.noDatabase)
    }
    func testExplicitCorrectionWinsOverActivePackAndDeletionRestoresExactPack() async throws {
        let root = try folder(), store = TranslationPackStore(root:root.appendingPathComponent("packs"))
        try await importFile(pack(),to:store)
        store.changeSelection(game:"fixture"); try await waitLoaded(store)
        let corrections = try GameCorrectionsStore(root:root.appendingPathComponent("corrections"),game:"fixture")
        try corrections.save(source:"Move now.",target:"انطلق الآن.")
        let translator = OfflineTranslator(folder:root.appendingPathComponent("no-model"),packs:store)
        func translate(_ source: String) async throws -> TranslationDecision {
            let result: Result<TranslationDecision,Error> = await withCheckedContinuation { continuation in
                translator.translateDetailed(source) { result,_ in continuation.resume(returning:result) }
            }
            return try result.get()
        }
        translator.configureCorrections(corrections.snapshot,enabled:true)
        let exact = try await translate("Move now."), normalized = try await translate("MOVE NOW!")
        XCTAssertEqual(exact.text,"انطلق الآن."); XCTAssertEqual(exact.origin,.userCorrection)
        XCTAssertEqual(normalized.text,exact.text); XCTAssertEqual(normalized.origin,.userCorrection)
        translator.configureCorrections(corrections.snapshot,enabled:false)
        let rollback = try await translate("Move now.")
        XCTAssertEqual(rollback.text,"تحرك الآن."); XCTAssertEqual(rollback.origin,.packExact)
        try corrections.remove(corrections.snapshot.entries[0].id)
        translator.configureCorrections(corrections.snapshot,enabled:true)
        let deleted = try await translate("Move now.")
        XCTAssertEqual(deleted.text,rollback.text); XCTAssertEqual(deleted.origin,.packExact)
    }
    func testOversizedSparseInputIsRejectedAndTemporaryFilesAreRemoved() async throws {
        let root = try folder(), file = root.appendingPathComponent("oversized.unknown"), temporary = try folder()
        XCTAssertTrue(FileManager.default.createFile(atPath:file.path,contents:nil))
        let handle = try FileHandle(forWritingTo:file); try handle.truncate(atOffset:129*1024*1024); try handle.close()
        let (result,report) = await inspect(file,store:TranslationPackStore(root:try folder()),temporaryRoot:temporary)
        XCTAssertThrowsError(try result.get()); XCTAssertEqual(report.bytes,129*1024*1024)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath:temporary.path).isEmpty)
    }
    @MainActor
    func testCancellationAfterParsingBeforeAtomicInstallation() async throws {
        let root = try folder(), file = root.appendingPathComponent("source.json"), temporary = try folder(), store = TranslationPackStore(root:try folder())
        try Data(#"[{"en":"Move now.","ar":"تحرك الآن."}]"#.utf8).write(to:file)
        let result: Result<Void,Error> = await withCheckedContinuation { continuation in
            var control: LocalizationImportControl?
            control = GameTranslationImporter(temporaryRoot:temporary).start(file,store:store,update:{ report in
                if report.stage == "جارٍ تجهيز حزمة الترجمة" { control?.cancel() }
            }) { result,report in
                XCTAssertTrue(report.result.contains("أُلغي")); continuation.resume(returning:result)
            }
        }
        XCTAssertThrowsError(try result.get())
        let saved = await state(store); XCTAssertTrue(saved.registry.packs.isEmpty)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath:temporary.path).isEmpty)
    }
    private func inspect(_ file: URL, store: TranslationPackStore, temporaryRoot: URL? = nil, cancel: Bool = false) async -> (Result<Void,Error>,LocalizationInspection) {
        await withCheckedContinuation { continuation in
            let importer = temporaryRoot.map{GameTranslationImporter(temporaryRoot:$0)} ?? GameTranslationImporter()
            let control = importer.start(file,store:store,update:{ _ in }) { continuation.resume(returning:($0,$1)) }
            if cancel { control.cancel() }
        }
    }
    func testUniversalImportRecognizesPackWithWrongAndUnknownExtensions() async throws {
        let original = try pack(), store = TranslationPackStore(root:try folder())
        for ext in ["exe","zip","unknown-extension",""] {
            let file = original.deletingPathExtension().appendingPathExtension(ext)
            if file != original { try FileManager.default.copyItem(at:original,to:file) }
            let (result,report) = await inspect(file,store:store)
            try result.get(); XCTAssertEqual(report.format,"GLPACK"); XCTAssertEqual(report.usable,1)
        }
        let installed = await state(store); XCTAssertEqual(installed.registry.packs.count,1)
    }
    func testRawJSONConversionPreservesMetadataAndUsesExistingLibrary() async throws {
        let root = try folder(), file = root.appendingPathComponent("renamed.bin"), store = TranslationPackStore(root:root.appendingPathComponent("library"))
        try Data(#"{"game_id":"raw-test","game_title":"Original game","attribution":"Original author","license":"Original license","permission":"Original permission","entries":[{"source":"Move now.","target":"تحرك الآن."}]}"#.utf8).write(to:file)
        let (result,report) = await inspect(file,store:store); try result.get()
        XCTAssertEqual(report.format,"JSON"); XCTAssertEqual(report.usable,1); XCTAssertEqual(report.mapping,true)
        let saved = await state(store), manifest = try XCTUnwrap(saved.registry.packs.first?.manifest)
        XCTAssertEqual(manifest.attribution,"Original author"); XCTAssertTrue(manifest.permission.contains("Original license")); XCTAssertTrue(manifest.permission.contains("Original permission"))
        store.changeSelection(game:"raw-test"); try await waitLoaded(store)
        XCTAssertEqual(store.lookup("Move now.",category:"dialogue",eventID:"raw"),"تحرك الآن.")
    }
    func testZipExtractionUsesContentsAndRejectsUnsafePaths() async throws {
        let root = try folder(), raw = root.appendingPathComponent("raw.bytes")
        try Data(#"[{"en":"Move now.","ar":"تحرك الآن."}]"#.utf8).write(to:raw)
        let zipped = root.appendingPathComponent("archive.dat"), archive = try Archive(url:zipped,accessMode:.create)
        try archive.addEntry(with:"localization.custom",fileURL:raw,compressionMethod:.deflate)
        let store = TranslationPackStore(root:try folder()), (result,report) = await inspect(zipped,store:store)
        try result.get(); XCTAssertEqual(report.format,"ZIP → JSON"); XCTAssertEqual(report.usable,1)
        let bad = try pack(corruption:"traversal"), (rejected,_) = await inspect(bad,store:store)
        XCTAssertThrowsError(try rejected.get())
        let saved = await state(store); XCTAssertEqual(saved.registry.packs.count,1)
        let text = root.appendingPathComponent("readme.txt"), textZip = root.appendingPathComponent("readme.zip")
        try Data("No translated records here.".utf8).write(to:text)
        let plainArchive = try Archive(url:textZip,accessMode:.create); try plainArchive.addEntry(with:"readme.txt",fileURL:text)
        let (noRecords,noRecordsReport) = await inspect(textZip,store:store)
        XCTAssertThrowsError(try noRecords.get()); XCTAssertNil(noRecordsReport.localization)
    }
    func testUnsupportedContainersAndCancellationPreserveWorkingPack() async throws {
        let root = try folder(), store = TranslationPackStore(root:try folder())
        try await importFile(pack(),to:store)
        let old = try Data(contentsOf:store.root.appendingPathComponent("library.json"))
        var pe = Data(repeating:0,count:68); pe[0] = 0x4d; pe[1] = 0x5a; pe[60] = 64; pe.replaceSubrange(64..<68,with:[0x50,0x45,0,0])
        for (index,data) in [pe,Data([0x52,0x61,0x72,0x21,0x1a,7,0]),Data([0x37,0x7a,0xbc,0xaf,0x27,0x1c]),Data([0xff,0,0xff]),Data()].enumerated() {
            let file = root.appendingPathComponent("input-\(index).glpack"); try data.write(to:file)
            let (result,report) = await inspect(file,store:store); XCTAssertThrowsError(try result.get()); XCTAssertFalse(report.result.isEmpty)
            XCTAssertEqual(try Data(contentsOf:store.root.appendingPathComponent("library.json")),old)
        }
        let temporary = try folder(), cancelFile = try pack()
        let (cancelled,report) = await inspect(cancelFile,store:store,temporaryRoot:temporary,cancel:true)
        XCTAssertThrowsError(try cancelled.get()); XCTAssertTrue(report.result.contains("أُلغي"))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath:temporary.path).isEmpty)
        XCTAssertEqual(try Data(contentsOf:store.root.appendingPathComponent("library.json")),old)
    }
    @MainActor
    func testNativePickerUsesCopyModeAndInboxIncludesArbitraryFiles() throws {
        let root = try folder(), inbox = LocalizationInbox(directory:root)
        try inbox.prepare()
        for ext in ["exe","zip","glpack","rar","7z","xml","json","csv","txt","unrecognized"] { try Data("fixture".utf8).write(to:root.appendingPathComponent("file."+ext)) }
        try FileManager.default.createDirectory(at:root.appendingPathComponent("nested"),withIntermediateDirectories:true)
        try FileManager.default.createSymbolicLink(at:root.appendingPathComponent("link"),withDestinationURL:root.appendingPathComponent("file.exe"))
        XCTAssertEqual(try inbox.files().count,10)
        let controller = LocalizationFilePicker.controller(directory:root,delegate:nil)
        XCTAssertEqual(controller.documentPickerMode,.import); XCTAssertFalse(controller.allowsMultipleSelection)
        // Selection and delivered filenames are exercised by actual XCUITest;
        // UIKit does not reliably read back its cosmetic extension preference here.
        XCTAssertEqual(controller.directoryURL,root)
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey:"UIFileSharingEnabled") as? Bool,true)
    }
    func testDocumentRegistrationAndProviderFallback() throws {
        let info = try XCTUnwrap(Bundle.main.infoDictionary)
        let exports = try XCTUnwrap(info["UTExportedTypeDeclarations"] as? [[String:Any]])
        let declaration = try XCTUnwrap(exports.first { $0["UTTypeIdentifier"] as? String == GamePackDocument.type.identifier })
        XCTAssertTrue((declaration["UTTypeConformsTo"] as? [String] ?? []).contains("public.data"))
        XCTAssertTrue(GamePackDocument.type.conforms(to:.data))
        XCTAssertEqual(UTType(filenameExtension:"glpack"),GamePackDocument.type)
        let documents = try XCTUnwrap(info["CFBundleDocumentTypes"] as? [[String:Any]])
        XCTAssertTrue(documents.contains { ($0["LSItemContentTypes"] as? [String] ?? []).contains(GamePackDocument.type.identifier) })
        XCTAssertEqual(info["LSSupportsOpeningDocumentsInPlace"] as? Bool,true)
        let providerType = try XCTUnwrap(UTType(tag:"gamelingo-provider-fixture",tagClass:.filenameExtension,conformingTo:.item))
        XCTAssertTrue(providerType.isDynamic)
        for type in [providerType,.data,.zip,GamePackDocument.type] {
            XCTAssertTrue(GamePackDocument.pickerTypes.contains { type.conforms(to:$0) })
        }
    }

    @MainActor
    func testDocumentImportValidatesContentsAndProtectsActiveSession() async throws {
        let library = GamePackLibrary(store:TranslationPackStore(root:try folder()))
        let file = try pack(), upper = file.deletingLastPathComponent().appendingPathComponent("rdr2-Arabic.GLPACK")
        try FileManager.default.copyItem(at:file,to:upper)
        XCTAssertFalse(library.importFile(upper,sessionRunning:true)); XCTAssertFalse(library.busy)
        XCTAssertFalse(library.importFile(URL(string:"https://example.com/RDR2.glpack")!))
        XCTAssertTrue(GamePackDocument.accepts(file.deletingPathExtension().appendingPathExtension("exe")))
        XCTAssertTrue(library.importFile(upper)); XCTAssertTrue(library.busy)
        XCTAssertFalse(library.importFile(upper)) // A second document must not start another import.
        for _ in 0..<250 { if !library.busy { break }; try await Task.sleep(nanoseconds:20_000_000) }
        XCTAssertFalse(library.busy); XCTAssertEqual(library.state.registry.packs.count,1)
        let bad = upper.deletingLastPathComponent().appendingPathComponent("invalid.glpack")
        try Data("not a translation pack".utf8).write(to:bad)
        XCTAssertTrue(library.importFile(bad))
        for _ in 0..<250 { if !library.busy { break }; try await Task.sleep(nanoseconds:20_000_000) }
        XCTAssertFalse(library.busy); XCTAssertEqual(library.state.registry.packs.count,1)
        XCTAssertFalse(library.message.hasPrefix("تم استيراد"))
    }
    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:url,withIntermediateDirectories:true)
        addTeardownBlock { try? FileManager.default.removeItem(at:url) }; return url
    }
    private func pack(game: String = "fixture", target: String = "تحرك الآن.", version: String = "1", corruption: String = "", ambiguous: Bool = false) throws -> URL {
        let root = try folder(), file = root.appendingPathComponent("translations.sqlite")
        var db: OpaquePointer?; XCTAssertEqual(sqlite3_open(file.path,&db),SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(db,PackDatabase.table,nil,nil,nil),SQLITE_OK)
        for sql in PackDatabase.indexes.values { XCTAssertEqual(sqlite3_exec(db,sql,nil,nil,nil),SQLITE_OK) }
        XCTAssertEqual(sqlite3_exec(db,"PRAGMA user_version=1",nil,nil,nil),SQLITE_OK)
        var statement: OpaquePointer?
        XCTAssertEqual(sqlite3_prepare_v2(db,"INSERT INTO entries VALUES (?,?,?,?,?,?,?,?,1)",-1,&statement,nil),SQLITE_OK)
        for (i,value) in ["0x00000001","FIXTURE","Move now.","move now",target,"general","synthetic","[]"].enumerated() {
            value.withCString { _ = sqlite3_bind_text(statement,Int32(i+1),$0,-1,unsafeBitCast(-1,to:sqlite3_destructor_type.self)) }
        }
        XCTAssertEqual(sqlite3_step(statement),SQLITE_DONE); sqlite3_finalize(statement)
        if ambiguous { XCTAssertEqual(sqlite3_exec(db,"INSERT INTO entries SELECT '0x00000002', 'ALT', source, normalized, 'انطلق الآن.', category, source_file, flags, usable FROM entries",nil,nil,nil),SQLITE_OK) }
        sqlite3_close(db)
        if corruption == "database" { try Data("not SQLite".utf8).write(to:file) }
        if corruption == "bomb" { try Data(repeating:0,count:1024*1024).write(to:file) }
        let hash = try TranslationPackStore.hash(file)
        let manifest: [String:Any] = ["format_version":corruption == "version" ? 99 : 1,"schema_version":1,"game_id":game,"game_title":"Synthetic game","source_language":"en","target_language":"ar","pack_version":version,"record_count":ambiguous ? 2 : 1,"usable_count":ambiguous ? 2 : 1,"categories":["general"],"attribution":"Original synthetic tests","permission":"Synthetic fixture only","built_at":"2026-11-14","arabic_order":"logical","database_sha256":hash,"speaker_names":["Arthur"]]
        let raw = try JSONSerialization.data(withJSONObject:manifest,options:[.sortedKeys])
        try raw.write(to:root.appendingPathComponent("manifest.json"))
        let hashes = ["manifest.json":corruption == "checksum" ? String(repeating:"0",count:64) : SHA256.hash(data:raw).map{String(format:"%02x",$0)}.joined(),"translations.sqlite":hash]
        try JSONEncoder().encode(hashes).write(to:root.appendingPathComponent("checksums.json"))
        let output = root.appendingPathComponent("fixture.glpack"), archive = try Archive(url:output,accessMode:.create)
        for name in ["manifest.json","translations.sqlite","checksums.json"] { try archive.addEntry(with:name,relativeTo:root,compressionMethod:corruption == "bomb" ? .deflate : .none) }
        if corruption == "traversal" { try archive.addEntry(with:"../escape.txt",fileURL:root.appendingPathComponent("manifest.json")) }
        if corruption == "extra" { try archive.addEntry(with:"run.exe",fileURL:root.appendingPathComponent("manifest.json")) }
        if corruption == "duplicate" { try archive.addEntry(with:"manifest.json",relativeTo:root) }
        return output
    }
    private func importFile(_ file: URL, to store: TranslationPackStore) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void,Error>) in store.importPack(file) { continuation.resume(with:$0) } }
    }
    private func state(_ store: TranslationPackStore) async -> GamePackState {
        await withCheckedContinuation { continuation in store.sampleState { continuation.resume(returning:$0) } }
    }
    private func waitLoaded(_ store: TranslationPackStore) async throws {
        for _ in 0..<200 { if await state(store).loaded { return }; try await Task.sleep(nanoseconds:20_000_000) }
        XCTFail("Selected fixture did not become ready")
    }
    func testImportSelectionIsolationDisablePersistenceReplacementAndDeletion() async throws {
        let root = try folder(), store = TranslationPackStore(root:root)
        let first = try pack(), other = try pack(game:"other",target:"انطلق الآن.")
        try await importFile(first,to:store); try await importFile(first,to:store); try await importFile(other,to:store)
        let initial = await state(store); XCTAssertEqual(initial.registry.packs.count,2); XCTAssertNil(initial.registry.selectedGame)
        XCTAssertNil(store.lookup("Move now.",category:"dialogue",eventID:"a"))
        store.changeSelection(game:"fixture"); try await waitLoaded(store)
        XCTAssertEqual(store.lookup("Move now.",category:"dialogue",eventID:"a"),"تحرك الآن.")
        XCTAssertEqual(store.lookup("Move now.",category:"document",eventID:nil),"تحرك الآن.")
        store.changeSelection(game:"other"); try await waitLoaded(store)
        XCTAssertEqual(store.lookup("Move now.",category:"dialogue",eventID:"other"),"انطلق الآن.")
        store.changeSelection(game:"fixture"); try await waitLoaded(store)
        let selectedState = await state(store)
        let fixtureID = try XCTUnwrap(selectedState.registry.packs.first{$0.manifest.gameId == "fixture"}?.id)
        store.enable(fixtureID,false)
        _ = await state(store); XCTAssertNil(store.lookup("Move now.",category:"dialogue",eventID:"b"))
        store.enable(fixtureID,true); try await waitLoaded(store)
        let updated = try pack(target:"تحرك بسرعة.",version:"2"); try await importFile(updated,to:store)
        XCTAssertEqual(store.lookup("Move now.",category:"dialogue",eventID:"c"),"تحرك بسرعة.")
        let restored = TranslationPackStore(root:root); try await waitLoaded(restored)
        XCTAssertEqual(restored.lookup("Move now.",category:"dialogue",eventID:"d"),"تحرك بسرعة.")
        let updatedState = await state(store)
        let selected = try XCTUnwrap(updatedState.registry.packs.first{$0.manifest.gameId == "fixture"})
        store.remove(selected.id); let removed = await state(store)
        XCTAssertNil(removed.registry.selectedGame); XCTAssertNil(store.lookup("Move now.",category:"dialogue",eventID:"e"))
        XCTAssertEqual(removed.registry.packs.count,1)
    }
    func testFailedImportsNeverReplaceWorkingPackOrEscapeStorage() async throws {
        let root = try folder(), store = TranslationPackStore(root:root)
        try await importFile(pack(),to:store); store.changeSelection(game:"fixture"); try await waitLoaded(store)
        let old = try Data(contentsOf:root.appendingPathComponent("library.json"))
        for damage in ["checksum","version","database","traversal","extra","duplicate","bomb"] {
            do { try await importFile(pack(version:"2",corruption:damage),to:store); XCTFail("Accepted malicious fixture: "+damage) } catch { }
            XCTAssertEqual(try Data(contentsOf:root.appendingPathComponent("library.json")),old)
            XCTAssertEqual(store.lookup("Move now.",category:"dialogue",eventID:"a"),"تحرك الآن.")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath:root.deletingLastPathComponent().appendingPathComponent("escape.txt").path))
    }
    func testHybridSelectsPackBeforePublicationAndFallsBackToNativeArgos() async throws {
        let store = TranslationPackStore(root:try folder()); try await importFile(pack(),to:store)
        store.changeSelection(game:"fixture"); try await waitLoaded(store)
        let model = try XCTUnwrap(Bundle(for:Self.self).url(forResource:"en_ar",withExtension:nil))
        let translator = OfflineTranslator(folder:model,packs:store)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void,Error>) in translator.load { continuation.resume(with:$0) } }
        func translated(_ source: String) async throws -> String {
            try await withCheckedThrowingContinuation { continuation in translator.translate(source,eventID:source) { result,_ in continuation.resume(with:result) } }
        }
        let packed = try await translated("Move now."); XCTAssertEqual(packed,"تحرك الآن.")
        translator.cancel() // Interruption must not discard selected game or reload DB.
        let afterInterruption = try await translated("Move now."); XCTAssertEqual(afterInterruption,packed)
        let fallback = try await translated("Collect 11 coins."); XCTAssertFalse(fallback.isEmpty)
        store.changeSelection(game:nil); _ = await state(store)
        let noPack = try await translated("Move now."); XCTAssertFalse(noPack.isEmpty)
        store.changeSelection(game:"fixture"); try await waitLoaded(store)
        try await importFile(pack(version:"2",ambiguous:true),to:store)
        let ambiguous = try await translated("Move now."); XCTAssertEqual(ambiguous,noPack)
        let metrics = await withCheckedContinuation { continuation in store.sampleMetrics { continuation.resume(returning:$0) } }
        XCTAssertEqual(metrics.ambiguous,1); XCTAssertGreaterThan(metrics.argos,0)
    }
    func testCorruptionAfterRestartFallsBackWithoutClearingSelectedGame() async throws {
        let root = try folder(), store = TranslationPackStore(root:root)
        try await importFile(pack(),to:store); store.changeSelection(game:"fixture"); try await waitLoaded(store)
        let saved = await state(store), item = try XCTUnwrap(saved.registry.packs.first)
        try Data("corrupt database".utf8).write(to:root.appendingPathComponent(item.id).appendingPathComponent("translations.sqlite"))
        let restarted = TranslationPackStore(root:root)
        var observed = await state(restarted)
        for _ in 0..<200 {
            if observed.error != nil { break }; try await Task.sleep(nanoseconds:20_000_000); observed = await state(restarted)
        }
        XCTAssertNotNil(observed.error); XCTAssertFalse(observed.loaded); XCTAssertEqual(observed.registry.selectedGame,"fixture")
        XCTAssertNil(restarted.lookup("Move now.",category:"dialogue",eventID:"after-restart"))
    }
}
