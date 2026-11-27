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
}

@MainActor
private final class FeedbackNotificationSpy: SessionNotificationClient {
    var waiting: CheckedContinuation<UNAuthorizationStatus,Never>?
    var onFirstRead: (() -> Void)?
    var onDelivery: (() -> Void)?
    var delivered: [SessionNotice] = []
    var permissionRequests = 0
    private var firstRead = true
    func authorization() async -> UNAuthorizationStatus {
        if firstRead {
            firstRead = false
            return await withCheckedContinuation { waiting = $0; onFirstRead?() }
        }
        return .authorized
    }
    func requestAuthorization() async throws -> Bool { permissionRequests += 1; return true }
    func replace(_ notice: SessionNotice) async throws { delivered.append(notice); onDelivery?() }
    func clear() {}
}
