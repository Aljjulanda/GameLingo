import XCTest
import AppIntents
@testable import GameLingo

final class TranslationControlTests: XCTestCase {
    @available(iOS 18.0, *)
    @MainActor
    func testControlReportsMissingSetupInsteadOfSilentlyAcceptingStart() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let originalIntent = SessionIntentStore.load()
        SessionIntentStore.save(false)
        let model = AppModel(profileRoot:root)
        defer { model.stop(); SessionIntentStore.save(originalIntent); try? FileManager.default.removeItem(at:root) }
        model.consoles = []
        XCTAssertThrowsError(try model.setTranslationFromControl(true)) { error in
            XCTAssertTrue(error.localizedDescription.contains("PS5"),error.localizedDescription)
        }
        XCTAssertFalse(model.running)
        XCTAssertFalse(SessionControlStore.snapshot().isEnabled())
        XCTAssertNoThrow(try model.setTranslationFromControl(false))
    }
    @available(iOS 18.0, *)
    @MainActor
    func testControlIntentExecutesStopInAppWithoutForegroundRequirement() async throws {
        XCTAssertFalse(SetTranslationIntent.openAppWhenRun)
        let model = AppModel.shared
        let originalIntent = SessionIntentStore.load()
        defer { SessionIntentStore.save(originalIntent) }
        var intent = SetTranslationIntent()
        intent.value = false
        _ = try await intent.perform()
        XCTAssertFalse(model.running)
        XCTAssertEqual(model.sessionStatus,"أُوقفت من مركز التحكم")
        XCTAssertEqual(SessionControlStore.snapshot().phase,.stopped)
    }
}
