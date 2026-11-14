import SwiftUI

@main
struct GameLingoApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup {
            MainView().environmentObject(model).environment(\.layoutDirection,.rightToLeft)
                .onOpenURL { model.openTranslationPack($0) }
                .onChange(of:phase) {
                    if $0 == .background { model.background() }
                    else if $0 == .active { model.foreground() }
                    else { model.relaxDisplay() }
                }
                .onChange(of:model.settings.dimScreen) { _ in model.applyDim() }
        }
    }
}
