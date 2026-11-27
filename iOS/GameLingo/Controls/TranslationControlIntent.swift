import AppIntents
import WidgetKit

@available(iOS 18.0, *)
struct SetTranslationIntent: SetValueIntent {
    static var title: LocalizedStringResource = "GameLingo Translation"
    static var openAppWhenRun: Bool = false
    @Parameter(title:"Translation enabled") var value: Bool
    @MainActor func perform() async throws -> some IntentResult {
        #if GAMELINGO_APP
        // Execute against the same model as the UI, including a cold launch.
        try AppModel.shared.setTranslationFromControl(value)
        #else
        // Never silently succeed after executing in the wrong process.
        throw TranslationControlError(message:"تعذر تشغيل التحكم. افتح GameLingo مرة واحدة وتأكد من توقيع التطبيق وامتداد التحكم معًا.")
        #endif
        ControlCenter.shared.reloadControls(ofKind:SessionControlStore.kind)
        return .result()
    }
}

// iOS 18 runs this intent in the app process, initially in the background.
// This does not grant unlimited background Remote Play/OCR execution time.
@available(iOS 18.0, *)
@available(iOSApplicationExtension, unavailable)
extension SetTranslationIntent: ForegroundContinuableIntent {}

struct TranslationControlError: LocalizedError {
    var message: String
    var errorDescription: String? { message }
}
