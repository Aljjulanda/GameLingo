import XCTest
import SwiftUI
import UIKit
@testable import GameLingo

final class NavigationPresentationTests: XCTestCase {
    /// Generated simulator screens, not gameplay or physical-device acceptance.
    @MainActor
    func testDailyScreensRenderInRTLWithoutChangingSavedChoices() async throws {
        let originalSettings = AppSettings.load()
        let originalQuality = QualitySettings.load()
        let originalIntent = SessionIntentStore.load()
        SessionIntentStore.save(false)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = AppModel(profileRoot:root)
        defer {
            model.stop()
            try? originalSettings.save(); originalQuality.save(); SessionIntentStore.save(originalIntent)
            try? FileManager.default.removeItem(at:root)
        }
        for _ in 0..<100 {
            if !model.gameProfiles.isEmpty { break }
            try await Task.sleep(nanoseconds:50_000_000)
        }
        XCTAssertFalse(model.gameProfiles.isEmpty)
        let display = model.settings.display
        let advanced = model.settings.advanced
        let console = model.settings.selectedConsoleID
        let options = model.gameOptions
        let credentials = try KeychainStore.read("consoles.v1")
        let identity = try TLSIdentity().fingerprint
        let pages: [(String,AnyView)] = [
            ("home",AnyView(MainView())),
            ("games",AnyView(NavigationStack { GamesView() })),
            ("settings",AnyView(NavigationStack { AppSettingsView() })),
            ("appearance",AnyView(NavigationStack { AppearanceOverviewView() }))
        ]
        for large in [false,true] {
            for (name,page) in pages {
                let content = page.environmentObject(model).environment(\.layoutDirection,.rightToLeft)
                    .environment(\.dynamicTypeSize,large ? .accessibility3 : .large)
                    .environment(\.colorScheme,large ? .dark : .light)
                let host = UIHostingController(rootView:content)
                let window = UIWindow(frame:CGRect(x:0,y:0,width:large ? 320 : 393,height:large ? 568 : 852))
                window.rootViewController = host; window.isHidden = false
                host.view.setNeedsLayout(); host.view.layoutIfNeeded()
                try await Task.sleep(nanoseconds:100_000_000)
                let rendered = UIGraphicsImageRenderer(size:window.bounds.size).image { _ in
                    window.drawHierarchy(in:window.bounds,afterScreenUpdates:true)
                }
                let attachment = XCTAttachment(image:rendered)
                attachment.name = "navigation-\(name)-\(large ? "small-AX3-dark" : "normal-light")-RTL"
                attachment.lifetime = .keepAlways; add(attachment)
                window.isHidden = true; window.rootViewController = nil
            }
        }
        XCTAssertFalse(model.running,"Opening pages must not create a translation session")
        XCTAssertFalse(model.learningConsent)
        XCTAssertFalse(model.qualityCaptureActive)
        XCTAssertEqual(model.settings.display,display)
        XCTAssertEqual(model.settings.advanced,advanced)
        XCTAssertEqual(model.settings.selectedConsoleID,console)
        XCTAssertEqual(model.gameOptions,options)
        XCTAssertEqual(try KeychainStore.read("consoles.v1"),credentials)
        XCTAssertEqual(try TLSIdentity().fingerprint,identity)
    }
}
