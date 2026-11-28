import SwiftUI
import WidgetKit
import AppIntents

/// Compiled only in the extension target: no app-process routing, PS5,
/// model loading or notification delivery is needed to prove this action.
struct DiagnoseControlIntent: AppIntent {
    static var title: LocalizedStringResource = "Test GameLingo Control"
    static var openAppWhenRun = false
    func perform() async throws -> some IntentResult {
        ControlCommandReceipt.record("extension.diagnostic.executed",extensionProcess:true)
        return .result()
    }
}

@main
struct GameLingoControls: WidgetBundle {
    var body: some Widget {
        TranslationControl()
        DiagnosticControl()
    }
}

struct DiagnosticControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind:"dev.gamelingo.ios.control-diagnostic") {
            ControlWidgetButton(action:DiagnoseControlIntent()) {
                Label("اختبار GameLingo",systemImage:"checkmark.circle")
            }
        }
        .displayName("اختبار تحكم GameLingo")
        .description("اختبار الزر فقط؛ لا يبدأ جلسة. راجع النتيجة في إعدادات GameLingo.")
    }
}
struct TranslationControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        // Rendering does not depend on a provider, App Group, or optional value.
        // The containing app resolves start/stop from its actual session state.
        StaticControlConfiguration(kind:SessionControlStore.kind) {
            ControlWidgetButton(action:ToggleTranslationIntent()) {
                Label("GameLingo",systemImage:"gamecontroller.fill")
            }
        }
        .displayName("GameLingo")
        .description("بدء أو إيقاف ترجمة اللعبة باستخدام إعداداتك المحفوظة")
    }
}
