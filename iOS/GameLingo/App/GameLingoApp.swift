import SwiftUI
import UIKit

final class GameLingoAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey:Any]? = nil) -> Bool {
        SessionNotificationDelegate.install()
        return true
    }
}

@main
struct GameLingoApp: App {
    @UIApplicationDelegateAdaptor(GameLingoAppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel.shared
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
