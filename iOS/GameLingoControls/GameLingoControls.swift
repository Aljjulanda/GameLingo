import SwiftUI
import WidgetKit
import AppIntents

@main
struct GameLingoControls: WidgetBundle {
    var body: some Widget { TranslationControl() }
}
struct TranslationControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind:SessionControlStore.kind,provider:Provider()) { enabled in
            // Put the symbol in the primary label, including the compact tile.
            // The command resolves the next state inside the app, never from a
            // potentially unavailable/stale shared-defaults value.
            ControlWidgetButton(action:ToggleTranslationIntent()) {
                Label(enabled.map { $0 ? "إيقاف الترجمة" : "بدء الترجمة" } ?? "GameLingo",systemImage:"gamecontroller.fill")
            }
        }
        .displayName("GameLingo")
        .description("بدء أو إيقاف ترجمة اللعبة باستخدام إعداداتك المحفوظة")
    }
    struct Provider: ControlValueProvider {
        var previewValue: Bool? { false }
        func currentValue() async throws -> Bool? {
            guard FileManager.default.containerURL(forSecurityApplicationGroupIdentifier:SessionControlStore.group) != nil else {
                // Sideload signing can omit App Groups. Keep the tile usable
                // with an unknown status instead of failing its entire render.
                return nil
            }
            return SessionControlStore.snapshot().enabledValue()
        }
    }
}
