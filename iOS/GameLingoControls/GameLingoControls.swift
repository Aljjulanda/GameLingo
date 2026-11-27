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
                Label(enabled ? "الترجمة نشطة" : "بدء الترجمة",systemImage:"captions.bubble")
            }
        }
        .displayName("GameLingo")
        .description("بدء أو إيقاف ترجمة اللعبة باستخدام إعداداتك المحفوظة")
    }
    struct Provider: ControlValueProvider {
        var previewValue: Bool { false }
        func currentValue() async throws -> Bool { SessionControlStore.snapshot().isActive() }
    }
}
