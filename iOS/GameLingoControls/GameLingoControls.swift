import SwiftUI
import WidgetKit
import AppIntents

@main
struct GameLingoControls: WidgetBundle {
    var body: some Widget { TranslationControl() }
}
struct TranslationControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind:SessionControlStore.kind,provider:Provider()) { active in
            ControlWidgetToggle("GameLingo",isOn:active,action:SetTranslationIntent()) { enabled in
                Label(enabled ? "إيقاف الترجمة" : "بدء الترجمة",systemImage:"gamecontroller.fill")
            }
        }
        .displayName("GameLingo")
        .description("بدء أو إيقاف ترجمة اللعبة باستخدام إعداداتك المحفوظة")
    }
    struct Provider: ControlValueProvider {
        var previewValue: Bool { false }
        func currentValue() async throws -> Bool {
            guard FileManager.default.containerURL(forSecurityApplicationGroupIdentifier:SessionControlStore.group) != nil else {
                throw TranslationControlError(message:"يلزم توقيع GameLingo وامتداد التحكم بنفس App Group حتى تظهر حالة الجلسة.")
            }
            return SessionControlStore.snapshot().isEnabled()
        }
    }
}
