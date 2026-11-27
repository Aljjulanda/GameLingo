import SwiftUI
import UIKit
import UserNotifications

final class SessionNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    private static let retained = SessionNotificationDelegate()
    static func install() { UNUserNotificationCenter.current().delegate = retained }
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        let identifier = notification.request.identifier
        let active = await MainActor.run { UIApplication.shared.applicationState == .active }
        let show = SessionNotificationPolicy.showSystemBanner(identifier:identifier,appIsActive:active)
        // Control Center may leave the app inactive while notifications
        // are still delivered through this foreground delegate.
        return show ? [.banner,.list] : []
    }
}

@MainActor
protocol SessionNotificationClient {
    func authorization() async -> UNAuthorizationStatus
    func requestAuthorization() async throws -> Bool
    func replace(_ notice: SessionNotice) async throws
    func sendTest() async throws
    func presentationSummary() async -> String
    func clear()
}

extension SessionNotificationClient {
    func presentationSummary() async -> String { "" }
}

@MainActor
private final class LocalSessionNotifications: SessionNotificationClient {
    private let center = UNUserNotificationCenter.current()
    private let identifier = SessionNotificationPolicy.statusIdentifier
    func authorization() async -> UNAuthorizationStatus { (await center.notificationSettings()).authorizationStatus }
    func requestAuthorization() async throws -> Bool { try await center.requestAuthorization(options:[.alert]) }
    func presentationSummary() async -> String {
        let settings = await center.notificationSettings()
        let alerts = settings.alertSetting == .enabled ? "مسموحة" : "غير مفعّلة"
        let style = settings.alertStyle == .none ? "دون لافتة" : "لافتة أو تنبيه"
        return "تنبيهات النظام: "+alerts+" · "+style
    }
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
    func sendTest() async throws {
        let content = UNMutableNotificationContent()
        content.title = "إشعارات GameLingo تعمل"
        content.body = "هذا إشعار تجريبي فقط؛ لم تتغير جلسة الترجمة."
        let id = SessionNotificationPolicy.testIdentifier
        center.removeDeliveredNotifications(withIdentifiers:[id])
        try await center.add(UNNotificationRequest(identifier:id,content:content,trigger:UNTimeIntervalNotificationTrigger(timeInterval:1,repeats:false)))
    }
}

@MainActor
final class SessionFeedbackPresenter: ObservableObject {
    @Published private(set) var notice: SessionNotice?
    @Published private(set) var authorization: UNAuthorizationStatus = .notDetermined
    @Published private(set) var notificationDiagnostic = ""
    @Published private(set) var testingNotification = false
    @Published private(set) var presentationSummary = ""
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
    func previewBanner() {
        present(SessionNotice(kind:.active,title:"التنبيه الزجاجي يعمل",body:"معاينة فقط؛ لم تتغير جلسة الترجمة."))
    }
    func testSystemNotification() async {
        guard foreground(), !testingNotification else { return }
        testingNotification = true
        defer { testingNotification = false }
        await refreshAuthorization()
        if authorization == .notDetermined && foreground() {
            do { _ = try await client.requestAuthorization() }
            catch { notificationDiagnostic = "تعذر طلب الإذن: "+error.localizedDescription; return }
            await refreshAuthorization()
        }
        guard [.authorized,.provisional,.ephemeral].contains(authorization) else {
            notificationDiagnostic = "لم يُسمح بالإشعارات. فعّل السماح واللافتات من إعدادات الآيفون."
            return
        }
        do {
            try await client.sendTest()
            notificationDiagnostic = "سُجل الإشعار التجريبي. إذا لم يظهر، راجع اللافتات ووضع التركيز في إعدادات الآيفون."
        } catch { notificationDiagnostic = "تعذر جدولة الإشعار: "+error.localizedDescription }
    }
    func refreshAuthorization() async {
        authorization = await client.authorization()
        presentationSummary = await client.presentationSummary()
    }
    func requestAuthorizationIfNeeded() {
        // Ask in context after an in-app start press or the settings button.
        // A Control Center command never opens the app to request permission.
        guard foreground(), permission == nil else { return }
        permission = Task { [weak self] in
            guard let self else { return }
            defer { self.permission = nil }
            await self.refreshAuthorization()
            if self.authorization == .notDetermined && self.foreground() {
                do { _ = try await self.client.requestAuthorization() }
                catch { self.notificationDiagnostic = "تعذر طلب إذن الإشعارات: "+error.localizedDescription }
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
            do { try await self.client.replace(value) }
            catch { self.notificationDiagnostic = "تعذر جدولة إشعار الحالة: "+error.localizedDescription }
        }
    }
}
