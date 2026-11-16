import XCTest
import Foundation
@testable import GameLingo

final class QualityIntegrationTests: XCTestCase {
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
