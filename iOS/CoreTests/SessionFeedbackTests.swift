import XCTest
@testable import LingoCore

final class SessionFeedbackTests: XCTestCase {
    func testInactiveAppGetsABannerWhileActiveAppUsesGlassUnlessTesting() {
        let status = SessionNotificationPolicy.statusIdentifier
        let test = SessionNotificationPolicy.testIdentifier
        XCTAssertFalse(SessionNotificationPolicy.showSystemBanner(identifier:status,appIsActive:true))
        XCTAssertTrue(SessionNotificationPolicy.showSystemBanner(identifier:status,appIsActive:false),"Control Center can leave the app inactive")
        XCTAssertTrue(SessionNotificationPolicy.showSystemBanner(identifier:test,appIsActive:true))
        XCTAssertFalse(SessionNotificationPolicy.showSystemBanner(identifier:"unrelated",appIsActive:false))
    }
    func testRequestedConnectionNeverClaimsSuccessAndRepeatedSamplesStayQuiet() {
        var state = SessionFeedbackState()
        XCTAssertNil(state.observe(.stopped))
        XCTAssertEqual(state.observe(.starting)?.kind,.starting)
        XCTAssertNil(state.observe(.starting))
        XCTAssertEqual(state.observe(.recovering)?.kind,.starting)
        XCTAssertEqual(state.observe(.active)?.kind,.active)
        XCTAssertNil(state.observe(.active))
        XCTAssertEqual(state.observe(.stopped,detail:"manual")?.body,"manual")
        XCTAssertNil(state.observe(.stopped))
    }
    func testFailureIsNotOverwrittenByAnIdleSampleAndANewStartCanRetry() {
        var state = SessionFeedbackState()
        XCTAssertEqual(state.failure("Choose PS5").kind,.failed)
        XCTAssertNil(state.observe(.stopped))
        XCTAssertEqual(state.observe(.recovering)?.kind,.starting)
        XCTAssertEqual(state.failure(String(repeating:"x",count:400)).body.count,180)
        XCTAssertNil(state.observe(.stopped))
    }
    func testExecutionSuspensionAndReconnectionAreDifferentFromSuccessfulStart() {
        var state = SessionFeedbackState()
        XCTAssertEqual(state.observe(.active)?.kind,.active)
        XCTAssertEqual(state.observe(.suspended)?.kind,.suspended)
        XCTAssertEqual(state.observe(.recovering)?.kind,.recovering)
        XCTAssertNil(state.observe(.recovering))
        XCTAssertEqual(state.observe(.active)?.kind,.active)
    }
    func testExpiredSharedStateIsUnknownRatherThanOff() {
        let now = Date(timeIntervalSince1970:100)
        XCTAssertEqual(SessionControlSnapshot(phase:.stopped,updated:now).enabledValue(now:now),false)
        XCTAssertEqual(SessionControlSnapshot(phase:.starting,updated:now).enabledValue(now:now),true)
        for phase in [SessionControlSnapshot.Phase.stopped,.active,.recovering] {
            let snapshot = SessionControlSnapshot(phase:phase,updated:now)
            XCTAssertNil(snapshot.enabledValue(now:now.addingTimeInterval(13)))
            XCTAssertNil(snapshot.enabledValue(now:now.addingTimeInterval(-1)))
        }
    }
}
