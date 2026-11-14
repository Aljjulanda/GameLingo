import XCTest
import Foundation
import CryptoKit
import SQLite3
import ZIPFoundation
import UniformTypeIdentifiers
@testable import GameLingo

final class PackIntegrationTests: XCTestCase {
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
        XCTAssertFalse(library.importFile(file.deletingPathExtension().appendingPathExtension("exe")))
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
