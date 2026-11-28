import XCTest
@testable import LingoCore

final class InstalledControlInfoTests: XCTestCase {
    private func write(_ info: [String:Any], at root: URL) throws {
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        try PropertyListSerialization.data(fromPropertyList:info,format:.xml,options:0).write(to:root.appendingPathComponent("Info.plist"))
    }
    func testStrippedExtensionIsReportedAgainstTheActualAppBuild() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        try write(["CFBundleShortVersionString":"0.5.0","CFBundleVersion":"14"],at:root)
        let info = InstalledControlInfo.inspect(appURL:root)
        XCTAssertEqual(info.appBuild,"14")
        XCTAssertNil(info.controlBuild)
        XCTAssertNil(info.versionsMatch)
    }
    func testRepackagedMismatchedExtensionIsVisibleAndCanBeCorrected() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        try write(["CFBundleShortVersionString":"0.5.0","CFBundleVersion":"14"],at:root)
        let plugin = root.appendingPathComponent("PlugIns/RenamedControls.appex")
        var info: [String:Any] = ["CFBundleVersion":"13","NSExtension":["NSExtensionPointIdentifier":"com.apple.widgetkit-extension"]]
        try write(info,at:plugin)
        XCTAssertEqual(InstalledControlInfo.inspect(appURL:root).versionsMatch,false)
        info["CFBundleVersion"] = "14"; try write(info,at:plugin)
        XCTAssertEqual(InstalledControlInfo.inspect(appURL:root).versionsMatch,true)
    }
    func testInstalledIconMetadataAndLooseResourcesAreReportedWithoutSigningClaim() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        try write(["CFBundleVersion":"15","CFBundleIcons":["CFBundlePrimaryIcon":["CFBundleIconName":"AppIcon"]]],at:root)
        try Data("synthetic PNG presence only".utf8).write(to:root.appendingPathComponent("AppIcon60x60@3x.png"))
        let info = InstalledControlInfo.inspect(appURL:root)
        XCTAssertEqual(info.iconName,"AppIcon"); XCTAssertEqual(info.iconPNGCount,1)
        XCTAssertNil(info.controlBuild)
    }
}
