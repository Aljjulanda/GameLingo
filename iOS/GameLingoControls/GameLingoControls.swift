import SwiftUI
import WidgetKit
import AppIntents

@main
struct GameLingoControls: WidgetBundle {
    var body: some Widget { TranslationControl() }
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
