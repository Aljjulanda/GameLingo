import XCTest
@testable import LingoCore

final class SettingsCatalogTests: XCTestCase {
    func testArabicSpellingVariantsAndDiacriticsFindDevices() {
        for query in ["آيفون", "ايفون", "إقتران", "شَبَكَة", "شَـبَـكَة", "إِقْتِرَان", "QR", "ps5"] {
            XCTAssertTrue(SettingsPage.devices.matches(query),query)
        }
    }
    func testSearchFindsEffectsAndSeparatesExperimentsFromNormalSettings() {
        XCTAssertTrue(SettingsPage.appearance.matches("ظل خط"))
        XCTAssertTrue(SettingsPage.model.matches("نَمُوذَج مَحَلِّي"))
        XCTAssertTrue(SettingsPage.experiments.matches("صوت خلفية"))
        XCTAssertFalse(SettingsPage.translation.matches("صوت خلفية"))
        XCTAssertFalse(SettingsPage.appearance.matches("ظل نموذج"),"All search words must match the same destination")
        XCTAssertFalse(SettingsPage.allCases.contains { $0.matches("غيرموجود123") })
        XCTAssertTrue(SettingsPage.allCases.allSatisfy { $0.matches("  ") })
    }
    func testHidingEffectsPreservesValuesAndDeviceSelectionAcrossReload() throws {
        let name = "dev.gamelingo.navigation."+UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName:name))
        defer { defaults.removePersistentDomain(forName:name) }
        var settings = AppSettings()
        settings.selectedConsoleID = "existing-console"
        settings.localIP = "192.168.1.24"
        settings.advanced.backgroundAudio = true
        settings.display.set("shadow_blur",.number(7))
        settings.display.set("outline_width",.number(4))
        settings.display.set("background_opacity",.number(63))
        for key in ["shadow","outline","background"] { settings.display.set(key,.bool(false)) }
        try settings.save(to:defaults)
        var loaded = AppSettings.load(from:defaults)
        XCTAssertEqual(loaded.selectedConsoleID,"existing-console")
        XCTAssertEqual(loaded.localIP,"192.168.1.24")
        XCTAssertTrue(loaded.advanced.backgroundAudio,"Reorganization must preserve explicit opt-ins too")
        for key in ["shadow","outline","background"] { XCTAssertFalse(loaded.display.bool(key)); loaded.display.set(key,.bool(true)) }
        XCTAssertEqual(loaded.display.number("shadow_blur"),7)
        XCTAssertEqual(loaded.display.number("outline_width"),4)
        XCTAssertEqual(loaded.display.number("background_opacity"),63)
    }
}
