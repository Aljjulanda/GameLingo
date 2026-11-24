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
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive }),"Visual evidence requires a foreground window scene")
        let blank = UIGraphicsImageRenderer(size:CGSize(width:64,height:64)).image { context in
            UIColor.black.setFill(); context.fill(CGRect(x:0,y:0,width:64,height:64))
        }
        XCTAssertEqual(contrastRange(blank),0,"The screenshot guard must reject the previous black attachments")
        let pages: [(String,AnyView)] = [
            ("home",AnyView(MainView())),
            ("games",AnyView(NavigationStack { GamesView() })),
            ("settings",AnyView(NavigationStack { AppSettingsView() })),
            ("appearance",AnyView(NavigationStack { AppearanceOverviewView() })),
            ("setup",AnyView(NavigationStack { SetupGuideView() })),
            ("model",AnyView(NavigationStack { LocalModelView() })),
            ("console",AnyView(NavigationStack { ConnectionView(scope:.console) }))
        ]
        for large in [false,true] {
            for (name,page) in pages {
                let content = page.environmentObject(model).environment(\.layoutDirection,.rightToLeft)
                    .environment(\.dynamicTypeSize,large ? .accessibility3 : .large)
                    .environment(\.colorScheme,large ? .dark : .light)
                let host = UIHostingController(rootView:content)
                let previousKey = scene.windows.first(where: { $0.isKeyWindow })
                let window = UIWindow(windowScene:scene)
                window.frame = scene.coordinateSpace.bounds
                // A contained controller gives the fixture a real scene while
                // preserving the requested viewport on a larger simulator.
                let container = UIViewController()
                window.rootViewController = container
                container.addChild(host); container.view.addSubview(host.view)
                host.didMove(toParent:container)
                host.overrideUserInterfaceStyle = large ? .dark : .light
                host.view.autoresizingMask = []
                host.view.frame = CGRect(x:0,y:0,width:large ? 320 : 393,height:large ? 568 : 852)
                window.makeKeyAndVisible()
                defer { window.isHidden = true; window.rootViewController = nil; previousKey?.makeKeyAndVisible() }
                window.setNeedsLayout(); window.layoutIfNeeded(); host.view.layoutIfNeeded()
                try await Task.sleep(nanoseconds:300_000_000)
                XCTAssertEqual(host.view.bounds.width,large ? 320 : 393,accuracy:1)
                var drewHierarchy = false
                let rendered = UIGraphicsImageRenderer(bounds:host.view.bounds).image { _ in
                    drewHierarchy = host.view.drawHierarchy(in:host.view.bounds,afterScreenUpdates:true)
                }
                let attachment = XCTAttachment(image:rendered)
                attachment.name = "navigation-\(name)-\(large ? "small-AX3-dark" : "normal-light")-RTL"
                attachment.lifetime = .keepAlways; add(attachment)
                XCTAssertTrue(drewHierarchy,"UIKit must report a completed hierarchy capture: \(name)")
                XCTAssertGreaterThan(contrastRange(rendered),20,"Blank or unrendered screenshot: \(name)")
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

    private func contrastRange(_ image: UIImage) -> Int {
        guard let cg = image.cgImage else { return 0 }
        var pixels = [UInt8](repeating:0,count:64*64*4)
        return pixels.withUnsafeMutableBytes { bytes in
            guard let context = CGContext(data:bytes.baseAddress,width:64,height:64,bitsPerComponent:8,bytesPerRow:64*4,
                space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else { return 0 }
            context.draw(cg,in:CGRect(x:0,y:0,width:64,height:64))
            let values = bytes.bindMemory(to:UInt8.self)
            var minimum = 255, maximum = 0
            for offset in stride(from:0,to:values.count,by:4) {
                let brightness = (Int(values[offset])+Int(values[offset+1])+Int(values[offset+2]))/3
                minimum = min(minimum,brightness); maximum = max(maximum,brightness)
            }
            return maximum-minimum
        }
    }
}
