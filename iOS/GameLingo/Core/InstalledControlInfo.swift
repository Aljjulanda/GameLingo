import Foundation

/// Inspect installed bundle metadata, not signing validity or OS registration.
struct InstalledControlInfo {
    let appVersion: String
    let appBuild: String?
    let controlBuild: String?
    var versionsMatch: Bool? {
        guard let appBuild, let controlBuild else { return nil }
        return appBuild == controlBuild
    }
    static func inspect(appURL: URL = Bundle.main.bundleURL) -> InstalledControlInfo {
        func metadata(_ root: URL) -> [String:Any] {
            guard let data = try? Data(contentsOf:root.appendingPathComponent("Info.plist")),
                  let value = try? PropertyListSerialization.propertyList(from:data,format:nil) as? [String:Any] else { return [:] }
            return value
        }
        let app = metadata(appURL)
        let version = app["CFBundleShortVersionString"] as? String ?? "غير معروف"
        let build = app["CFBundleVersion"] as? String
        let plugins = (try? FileManager.default.contentsOfDirectory(at:appURL.appendingPathComponent("PlugIns"),includingPropertiesForKeys:nil)) ?? []
        let control = plugins.prefix(32).filter { $0.pathExtension == "appex" }.map(metadata).first {
            ($0["NSExtension"] as? [String:Any])?["NSExtensionPointIdentifier"] as? String == "com.apple.widgetkit-extension"
        }
        return InstalledControlInfo(appVersion:version,appBuild:build,controlBuild:control?["CFBundleVersion"] as? String)
    }
}
