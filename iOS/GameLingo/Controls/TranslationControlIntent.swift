import AppIntents
import WidgetKit

@available(iOS 18.0, *)
struct SetTranslationIntent: SetValueIntent {
    static var title: LocalizedStringResource = "GameLingo Translation"
    // Sustained Remote Play/Vision work belongs to the containing application.
    // Both actions foreground it; this is also the reliable cold-start path.
    static var openAppWhenRun: Bool = true
    @Parameter(title:"Translation enabled") var value: Bool
    @MainActor func perform() async throws -> some IntentResult {
        SessionControlStore.request(value)
        NotificationCenter.default.post(name:Notification.Name("GameLingoControlRequest"),object:nil)
        // The provider reads actual state. A start request does not switch it on.
        ControlCenter.shared.reloadControls(ofKind:SessionControlStore.kind)
        return .result()
    }
}
