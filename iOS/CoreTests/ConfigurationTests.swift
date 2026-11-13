import XCTest
@testable import LingoCore

final class ConfigurationTests: XCTestCase {
    func testPrivateIPv4MatchesExistingTVRules() {
        for value in ["10.0.0.1","172.16.0.3","172.31.255.1","192.168.1.8"] { XCTAssertTrue(LAN.isPrivateIPv4(value)) }
        for value in ["127.0.0.1","8.8.8.8","172.32.0.1","192.168.0.256","192.168.1","evil.local","1.2.3.4.5"] { XCTAssertFalse(LAN.isPrivateIPv4(value)) }
    }
    func testPairingValidationRequiresAccountBytesAndExactPINLength() throws {
        XCTAssertEqual(try ConsoleCredentials.accountID("AQIDBAUGBwg=",pin:"00123456").count,8)
        XCTAssertThrowsError(try ConsoleCredentials.accountID("AQID",pin:"12345678"))
        XCTAssertThrowsError(try ConsoleCredentials.accountID("AQIDBAUGBwg=",pin:"1234567"))
        XCTAssertThrowsError(try ConsoleCredentials.accountID("AQIDBAUGBwg=",pin:"１２３４５６７８"))
        XCTAssertThrowsError(try ConsoleCredentials(id:"x",name:"x",host:"192.168.1.1",registrationKey:Data(count:15),key:Data(count:16)).validate())
    }
    func testDefaultsAndValidationPreserveTVContract() {
        var settings = TVSettings()
        XCTAssertEqual(settings.number("max_width"),60); XCTAssertEqual(settings.number("max_entries"),3)
        XCTAssertEqual(settings.number("min_seconds"),4); XCTAssertEqual(settings.number("max_seconds"),8)
        settings.set("font_size",.number(999)); XCTAssertEqual(settings.number("font_size"),100)
        settings.set("min_seconds",.number(20)); XCTAssertGreaterThanOrEqual(settings.number("max_seconds"),20)
        settings.set("text_color",.string("invalid")); XCTAssertEqual(settings.string("text_color"),"#FFFFFF")
        settings.set("x",.number(.nan)); XCTAssertEqual(settings.number("x"),0)
    }
    func testWindowsSettingsImportKeepsStyleAndAdvancesRevision() throws {
        let data = Data(#"{"display":{"font_size":32,"max_width":88,"x":-17,"revision":9999999999999},"unrelated_secret":"ignored"}"#.utf8)
        let settings = try TVSettings.importWire(data)
        XCTAssertEqual(settings.number("max_width"),88); XCTAssertEqual(settings.number("x"),-17)
        XCTAssertGreaterThan(settings.revision,9999999999999); XCTAssertNil(settings.values["unrelated_secret"])
    }
    func testSettingsRoundTrip() throws {
        let name = "dev.gamelingo.test."+UUID().uuidString
        let defaults = UserDefaults(suiteName:name)!
        defer { defaults.removePersistentDomain(forName:name) }
        var source = AppSettings(); source.mode = .economy; source.display.set("x",.number(-10))
        try source.save(to:defaults)
        let loaded = AppSettings.load(from:defaults)
        XCTAssertEqual(loaded.mode,.economy); XCTAssertEqual(loaded.display.number("x"),-10)
    }
    func testThermalAndLowPowerCaps() {
        XCTAssertEqual(PerformanceMode.performance.samplingRate(thermal:0,lowPower:false),8)
        XCTAssertEqual(PerformanceMode.performance.samplingRate(thermal:2,lowPower:false),2)
        XCTAssertEqual(PerformanceMode.performance.samplingRate(thermal:0,lowPower:true),2)
        XCTAssertEqual(PerformanceMode.performance.samplingRate(thermal:3,lowPower:false),0)
    }
    func testSequenceNeverRestartsAtReconnectAndSessionChangesAtNewListener() {
        var sequence = TVSequence()
        let first = sequence.stamp(TVProtocol.envelope("subtitle_show"))
        let second = sequence.stamp(TVProtocol.envelope("settings_sync"))
        XCTAssertEqual(first["session"] as? String,second["session"] as? String)
        XCTAssertEqual(second["seq"] as? UInt64,2)
        XCTAssertNotEqual(sequence.session,TVSequence().session)
    }
    func testMessagesRejectOversizeAndWrongVersion() throws {
        XCTAssertThrowsError(try TVProtocol.decode(Data(#"{"v":2,"type":"hello"}"#.utf8)))
        XCTAssertThrowsError(try TVProtocol.encode(TVProtocol.envelope("hello",fields:["token":String(repeating:"x",count:17000)])))
        let message = try TVProtocol.decode(TVProtocol.encode(TVProtocol.envelope("hello",fields:["token":"test"])))
        XCTAssertEqual(message["type"] as? String,"hello")
    }
}
