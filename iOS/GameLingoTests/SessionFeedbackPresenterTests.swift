import XCTest
import UserNotifications
@testable import GameLingo

final class SessionFeedbackPresenterTests: XCTestCase {
    @MainActor
    func testDelayedOldStatusCannotOverwriteTheLatestStopNotification() async {
        let read = expectation(description:"Old status waits on notification settings")
        let delivered = expectation(description:"Latest stop delivered")
        let client = FeedbackNotificationSpy()
        client.onFirstRead = { read.fulfill() }
        client.onDelivery = { delivered.fulfill() }
        let feedback = SessionFeedbackPresenter(client:client,foreground:{ false })
        feedback.observe(.recovering)
        await fulfillment(of:[read],timeout:3)
        feedback.observe(.active)
        feedback.observe(.stopped,detail:"manual stop")
        client.waiting?.resume(returning:.authorized); client.waiting = nil
        await fulfillment(of:[delivered],timeout:3)
        XCTAssertEqual(client.delivered.map(\.kind),[.stopped])
        XCTAssertEqual(client.permissionRequests,0,"Background control must not ask for permission or open the app")
        XCTAssertEqual(feedback.notice?.kind,.stopped)
    }
    @MainActor
    func testSystemTestUsesAuthorizedDeliveryWithoutRequestingPermissionAgain() async {
        let client = FeedbackNotificationSpy(); client.gateFirstRead = false
        let feedback = SessionFeedbackPresenter(client:client,foreground:{ true })
        await feedback.testSystemNotification()
        XCTAssertEqual(client.testsSent,1)
        XCTAssertEqual(client.permissionRequests,0)
        XCTAssertFalse(feedback.testingNotification)
        XCTAssertTrue(feedback.notificationDiagnostic.contains("سُجل"))
    }
    @MainActor
    func testDeniedPermissionDoesNotPretendToScheduleAnAlert() async {
        let client = FeedbackNotificationSpy(); client.gateFirstRead = false; client.status = .denied
        let feedback = SessionFeedbackPresenter(client:client,foreground:{ true })
        await feedback.testSystemNotification()
        XCTAssertEqual(client.testsSent,0)
        XCTAssertEqual(client.permissionRequests,0)
        XCTAssertTrue(feedback.notificationDiagnostic.contains("لم يُسمح"))
    }
    @MainActor
    func testSystemSchedulingErrorsRemainVisible() async {
        let client = FeedbackNotificationSpy(); client.gateFirstRead = false; client.failTest = true
        let feedback = SessionFeedbackPresenter(client:client,foreground:{ true })
        await feedback.testSystemNotification()
        XCTAssertTrue(feedback.notificationDiagnostic.contains("synthetic scheduling failure"))
        XCTAssertFalse(feedback.testingNotification)
    }
}

@MainActor
private final class FeedbackNotificationSpy: SessionNotificationClient {
    var waiting: CheckedContinuation<UNAuthorizationStatus,Never>?
    var onFirstRead: (() -> Void)?
    var onDelivery: (() -> Void)?
    var delivered: [SessionNotice] = []
    var permissionRequests = 0
    var testsSent = 0
    var gateFirstRead = true
    var status = UNAuthorizationStatus.authorized
    var failTest = false
    private var firstRead = true
    func authorization() async -> UNAuthorizationStatus {
        if firstRead && gateFirstRead {
            firstRead = false
            return await withCheckedContinuation { waiting = $0; onFirstRead?() }
        }
        return status
    }
    func requestAuthorization() async throws -> Bool { permissionRequests += 1; return true }
    func replace(_ notice: SessionNotice) async throws { delivered.append(notice); onDelivery?() }
    func sendTest() async throws {
        if failTest { throw NSError(domain:"synthetic scheduling failure",code:1,userInfo:[NSLocalizedDescriptionKey:"synthetic scheduling failure"]) }
        testsSent += 1
    }
    func clear() {}
}
