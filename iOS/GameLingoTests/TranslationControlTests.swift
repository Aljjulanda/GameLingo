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
        XCTAssertEqual(model.feedback.notice?.kind,.failed)
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
    @available(iOS 18.0, *)
    @MainActor
    func testButtonStopsTheActualSessionEvenWhenSharedStateSaysStopped() async throws {
        XCTAssertFalse(ToggleTranslationIntent.openAppWhenRun)
        let model = AppModel.shared
        let originalIntent = SessionIntentStore.load()
        defer { model.stop(); SessionIntentStore.save(originalIntent) }
        model.running = true // Authored session state; no PS5 connection.
        SessionControlStore.save(.stopped) // Simulate stale/missing widget data.
        _ = try await ToggleTranslationIntent().perform()
        XCTAssertFalse(model.running)
        XCTAssertEqual(model.sessionStatus,"أُوقفت من مركز التحكم")
    }
    @available(iOS 18.0, *)
    @MainActor
    func testButtonReportsMissingSetupFromTheContainingApp() async throws {
        let model = AppModel.shared
        let consoles = model.consoles, originalIntent = SessionIntentStore.load()
        model.stop(); model.consoles = []
        defer { model.stop(); model.consoles = consoles; SessionIntentStore.save(originalIntent) }
        do {
            _ = try await ToggleTranslationIntent().perform()
            XCTFail("A background control must not silently accept missing setup")
        } catch { XCTAssertTrue(error.localizedDescription.contains("PS5"),error.localizedDescription) }
        XCTAssertEqual(model.feedback.notice?.kind,.failed)
    }
}
