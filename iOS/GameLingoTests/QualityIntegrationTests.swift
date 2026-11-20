import XCTest
import Foundation
@testable import GameLingo

final class QualityIntegrationTests: XCTestCase {
    private func translate(_ translator: OfflineTranslator, _ source: String) async throws -> TranslationDecision {
        let result: Result<TranslationDecision,Error> = await withCheckedContinuation { continuation in
            translator.translateDetailed(source) { value,_ in continuation.resume(returning:value) }
        }
        return try result.get()
    }
    func testRealPipelinePunctuationFlagsCacheRollbackAndRawTrace() async throws {
        let folder = try XCTUnwrap(Bundle(for:Self.self).url(forResource:"en_ar",withExtension:nil))
        let translator = OfflineTranslator(folder:folder)
        let loaded: Result<Void,Error> = await withCheckedContinuation { translator.load(completion:$0.resume(returning:)) }; try loaded.get()
        var quality = QualitySettings()
        translator.configureEngineDiagnostics(true)
        let legacy = try await translate(translator,"Wait?")
        XCTAssertEqual(legacy.text,"انتظر!"); XCTAssertEqual(legacy.origin,.command)
        quality[.commandPunctuation] = true; translator.configureQuality(quality)
        for (source,target) in [("Wait","انتظر"),("Wait?","انتظر؟"),("Wait!","انتظر!"),("Run.","اركض.")] {
            let first = try await translate(translator,source), cached = try await translate(translator,source)
            XCTAssertEqual(first.text,target); XCTAssertEqual(first.origin,.command)
            XCTAssertEqual(cached.text,target); XCTAssertEqual(cached.origin,.command)
        }
        quality[.punctuationRepair] = true; translator.configureQuality(quality)
        let source = "Where are you going?"
        let repaired = try await translate(translator,source)
        var error: NSError?
        let baseline = try XCTUnwrap(GLTranslation(modelPath:folder.path,error:&error))
        let raw = try XCTUnwrap(baseline.translate(source,error:&error))
        XCTAssertEqual(repaired.rawOutput,raw); XCTAssertEqual(repaired.engineInput,source)
        XCTAssertEqual(repaired.text,SourceGuidedPunctuation.repair(raw,source:source).text)
        XCTAssertEqual(repaired.origin,.argosInference)
        let cached = try await translate(translator,source)
        XCTAssertEqual(cached.text,repaired.text); XCTAssertEqual(cached.origin,.argosCache)
        quality[.punctuationRepair] = false; translator.configureQuality(quality)
        let rollback = try await translate(translator,source)
        XCTAssertEqual(rollback.origin,.argosInference); XCTAssertEqual(rollback.text,raw)
        let commandStillOn = try await translate(translator,"Wait?")
        XCTAssertEqual(commandStillOn.text,"انتظر؟")
        quality[.commandPunctuation] = false; quality[.punctuationRepair] = true; translator.configureQuality(quality)
        let commandOff = try await translate(translator,"Wait?")
        XCTAssertEqual(commandOff.text,"انتظر!")
        translator.configureQuality(QualitySettings())
        let allOff = try await translate(translator,"Wait?")
        XCTAssertEqual(allOff.text,legacy.text)
    }
    func testPunctuationRepairNeverRewritesExplicitCorrection() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let store = try GameCorrectionsStore(root:root,game:"synthetic")
        try store.save(source:"Where are you going?",target:")Arthur العزيز( أين أنت?")
        let translator = OfflineTranslator(folder:root.appendingPathComponent("no-model"))
        var quality = QualitySettings(); quality[.punctuationRepair] = true; quality[.commandPunctuation] = true
        translator.configureQuality(quality); translator.configureCorrections(store.snapshot,enabled:true)
        let result = try await translate(translator,"Where are you going?")
        XCTAssertEqual(result.origin,.userCorrection); XCTAssertEqual(result.text,")Arthur العزيز( أين أنت?")
        XCTAssertTrue(result.punctuationUnbalanced)
    }
    func testNativeSentenceSplittingResearchFixtures() throws {
        // Research only: production keeps the whole-input native bridge. These
        // explicit synthetic candidates preserve abbreviations/quotes/ellipsis;
        // no speculative splitter or flag is installed in the shipping path.
        let folder = try XCTUnwrap(Bundle(for:Self.self).url(forResource:"en_ar",withExtension:nil))
        var error: NSError?
        let engine = try XCTUnwrap(GLTranslation(modelPath:folder.path,error:&error))
        let fixtures = [
            ["Mr. Morgan, wait.","Where are you going?"],
            ["Dr. Smith is here.","Let him in."],
            ["We reached St. Denis.","What happens now?"],
            ["Mr. Morgan is here."], ["Dr. Smith lives in St. Denis."], ["\"Wait... please.\""]
        ]
        var reports: [[String:Any]] = []
        for parts in fixtures {
            let source = parts.joined(separator:" "), start = ProcessInfo.processInfo.systemUptime
            let whole = try XCTUnwrap(engine.translate(source,error:&error))
            let wholeMS = (ProcessInfo.processInfo.systemUptime-start)*1000
            let splitStart = ProcessInfo.processInfo.systemUptime
            let split = parts.count == 1 ? whole : try parts.map { try XCTUnwrap(engine.translate($0,error:&error)) }.joined(separator:" ")
            let splitMS = parts.count == 1 ? wholeMS : (ProcessInfo.processInfo.systemUptime-splitStart)*1000
            XCTAssertFalse(whole.isEmpty); XCTAssertFalse(split.isEmpty)
            reports.append(["source":source,"whole":whole,"split":split,"whole_ms":wholeMS,"split_ms":splitMS,"single_sentence":parts.count == 1])
        }
        let report = try JSONSerialization.data(withJSONObject:reports,options:[.prettyPrinted,.sortedKeys])
        let attachment = XCTAttachment(data:report,uniformTypeIdentifier:"public.json")
        attachment.name = "Synthetic-Argos-sentence-research"; attachment.lifetime = .keepAlways; add(attachment)
        print("SYNTHETIC_ARGOS_SENTENCE_RESEARCH "+String(decoding:report,as:UTF8.self))
    }
    @MainActor
    func testGameSwitchCannotShowPreviousGamesWorkingCount() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let library = GamePackLibrary(store:TranslationPackStore(root:root))
        var first = GamePackState(); first.registry.selectedGame = "synthetic-a"; first.loaded = true
        library.store.onChange?(first)
        library.metrics.recordPublished(PublishedTranslation(eventID:"1",game:"synthetic-a",pack:"synthetic-pack",origin:.packExact,fallback:nil))
        library.store.onChange?(first)
        XCTAssertEqual(library.metrics.publishedPack,1,"A same-scope notification must preserve counts")
        var second = first; second.registry.selectedGame = "synthetic-b"
        library.store.onChange?(second)
        XCTAssertEqual(library.metrics.published,0); XCTAssertEqual(library.metrics.publishedPack,0)
        XCTAssertFalse(library.metrics.status(active:true,damaged:false).contains("تعمل"))
    }
    func testOptInCaptureExcludesBackupAndNeverResumes() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:folder) }
        let capture = QualityCapture(folder:folder)
        try capture.start(consent:true)
        XCTAssertEqual(try folder.resourceValues(forKeys:[.isExcludedFromBackupKey]).isExcludedFromBackup,true)
        XCTAssertTrue(capture.active); capture.stop()
        XCTAssertFalse(QualityCapture(folder:folder).active)
    }
    func testCompleteProtectionWhenRuntimeReportsFileProtection() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:folder) }
        let capture = QualityCapture(folder:folder)
        try capture.start(consent:true)
        let raw = try FileManager.default.attributesOfItem(atPath:capture.file.path)[.protectionKey]
        print("SYNTHETIC_CAPTURE_PROTECTION present=\(raw != nil) type=\(raw.map{String(reflecting:type(of:$0))} ?? "none") class=\(capture.protectionClass ?? "not reported")")
        #if targetEnvironment(simulator)
        if capture.protectionClass == nil {
            // Distinguish an application bug from missing OS metadata using a
            // second file written directly with the public Foundation APIs.
            let control = folder.appendingPathComponent("synthetic-control")
            try Data("synthetic".utf8).write(to:control,options:[.atomic,.completeFileProtection])
            try FileManager.default.setAttributes([.protectionKey:FileProtectionType.complete],ofItemAtPath:control.path)
            let direct = try FileManager.default.attributesOfItem(atPath:control.path)[.protectionKey]
            print("SYNTHETIC_DIRECT_PROTECTION_METADATA_PRESENT \(direct != nil)")
            guard raw == nil && direct == nil else { XCTFail("OS reports protection for control but not capture, or an unsupported value type"); return }
            throw XCTSkip("This iOS Simulator reports no file-protection metadata for capture OR direct Foundation control. Physical iPhone read-back is enforced before recording; hardware protection remains unverified here.")
        }
        #endif
        XCTAssertEqual(capture.protectionClass,FileProtectionType.complete.rawValue)
    }
    func testRealArgosProvenanceCacheAndUnchangedLegacyOutput() async throws {
        let folder = try XCTUnwrap(Bundle(for:Self.self).url(forResource:"en_ar",withExtension:nil))
        let translator = OfflineTranslator(folder:folder)
        let loaded: Result<Void,Error> = await withCheckedContinuation { translator.load(completion:$0.resume(returning:)) }
        try loaded.get()
        let first: Result<TranslationDecision,Error> = await withCheckedContinuation { continuation in
            translator.translateDetailed("Where are you going?") { result,_ in continuation.resume(returning:result) }
        }
        let decision = try first.get()
        XCTAssertEqual(decision.origin,.argosInference); XCTAssertEqual(decision.fallback,.noDatabase)
        let second: Result<TranslationDecision,Error> = await withCheckedContinuation { continuation in
            translator.translateDetailed("Where are you going?") { result,_ in continuation.resume(returning:result) }
        }
        XCTAssertEqual(try second.get().origin,.argosCache)
        XCTAssertEqual(try second.get().text,decision.text)
        var error: NSError?
        let baseline = try XCTUnwrap(GLTranslation(modelPath:folder.path,error:&error))
        XCTAssertEqual(decision.text,baseline.translate("Where are you going?",error:&error))
    }
}
