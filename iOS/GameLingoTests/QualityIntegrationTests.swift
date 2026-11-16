import XCTest
import Foundation
@testable import GameLingo

final class QualityIntegrationTests: XCTestCase {
    func testOptInCaptureUsesProtectedBackupExcludedFiles() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:folder) }
        let capture = QualityCapture(folder:folder)
        try capture.start(consent:true)
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath:capture.file.path)[.protectionKey] as? FileProtectionType,.complete)
        XCTAssertEqual(try folder.resourceValues(forKeys:[.isExcludedFromBackupKey]).isExcludedFromBackup,true)
        capture.stop()
        XCTAssertFalse(QualityCapture(folder:folder).active)
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
