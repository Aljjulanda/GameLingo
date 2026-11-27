import SwiftUI
import UIKit
import UserNotifications

@MainActor
protocol SessionNotificationClient {
    func authorization() async -> UNAuthorizationStatus
    func requestAuthorization() async throws -> Bool
    func replace(_ notice: SessionNotice) async throws
    func clear()
}

@MainActor
private final class LocalSessionNotifications: SessionNotificationClient {
    private let center = UNUserNotificationCenter.current()
    private let identifier = "dev.gamelingo.session.status"
    func authorization() async -> UNAuthorizationStatus { (await center.notificationSettings()).authorizationStatus }
    func requestAuthorization() async throws -> Bool { try await center.requestAuthorization(options:[.alert]) }
    func replace(_ notice: SessionNotice) async throws {
        let content = UNMutableNotificationContent()
        content.title = notice.title; content.body = notice.body
        content.threadIdentifier = "gamelingo.session"
        // Quiet status feedback: no sound, badge, gameplay text, or screenshots.
        try await center.add(UNNotificationRequest(identifier:identifier,content:content,trigger:nil))
    }
    func clear() {
        center.removePendingNotificationRequests(withIdentifiers:[identifier])
        center.removeDeliveredNotifications(withIdentifiers:[identifier])
    }
}

@MainActor
final class SessionFeedbackPresenter: ObservableObject {
    @Published private(set) var notice: SessionNotice?
    @Published private(set) var authorization: UNAuthorizationStatus = .notDetermined
    private var state = SessionFeedbackState()
    private let client: SessionNotificationClient
    private let foreground: () -> Bool
    private var delivery: Task<Void,Never>?
    private var dismissal: Task<Void,Never>?
    private var permission: Task<Void,Never>?
    private var latest: UUID?

    init(client: SessionNotificationClient? = nil, foreground: @escaping () -> Bool = { UIApplication.shared.applicationState == .active }) {
        self.client = client ?? LocalSessionNotifications(); self.foreground = foreground
    }
    func observe(_ phase: SessionControlSnapshot.Phase, detail: String = "") {
        if let value = state.observe(phase,detail:detail) { present(value) }
    }
    func failure(_ message: String) { present(state.failure(message)) }
    func dismiss() { dismissal?.cancel(); notice = nil }
    func refreshAuthorization() async { authorization = await client.authorization() }
    func requestAuthorizationIfNeeded() {
        // Ask in context after an in-app start press or the settings button.
        // A Control Center command never opens the app to request permission.
        guard foreground(), permission == nil else { return }
        permission = Task { [weak self] in
            guard let self else { return }
            defer { self.permission = nil }
            await self.refreshAuthorization()
            if self.authorization == .notDetermined && self.foreground() {
                _ = try? await self.client.requestAuthorization()
                await self.refreshAuthorization()
            }
        }
    }
    private func present(_ value: SessionNotice) {
        notice = value; latest = value.id
        let previousDelivery = delivery
        previousDelivery?.cancel(); dismissal?.cancel(); client.clear()
        if foreground(), UIAccessibility.isVoiceOverRunning {
            UIAccessibility.post(notification:.announcement,argument:value.title+". "+value.body)
        }
        dismissal = Task { [weak self] in
            try? await Task.sleep(nanoseconds:value.kind == .failed ? 8_000_000_000 : 5_000_000_000)
            guard !Task.isCancelled, self?.notice?.id == value.id else { return }
            self?.notice = nil
        }
        delivery = Task { [weak self] in
            guard let self else { return }
            // Serialize with an older add() already in flight. Its completion
            // cannot reinstall stale "started" feedback after a newer stop.
            await previousDelivery?.value
            guard !Task.isCancelled, self.latest == value.id else { return }
            self.client.clear()
            guard !self.foreground() else { return }
            let permission = await self.client.authorization()
            guard !Task.isCancelled, self.latest == value.id, !self.foreground(),
                  [.authorized,.provisional,.ephemeral].contains(permission) else { return }
            try? await self.client.replace(value)
        }
    }
}
