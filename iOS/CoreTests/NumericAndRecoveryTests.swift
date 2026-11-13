import XCTest
@testable import LingoCore

final class NumericAndRecoveryTests: XCTestCase {
    func testArabicDigitsAndDecimalInput() {
        XCTAssertEqual(NumericInput.parse("١٢٫٥",range:0...100),12.5)
        XCTAssertEqual(NumericInput.parse("-٥",range:-100...100),-5)
        XCTAssertEqual(NumericInput.parse("۲۵",range:0...100),25)
        XCTAssertEqual(NumericInput.format(1000),"1000")
    }
    func testInvalidInputCannotAlterSettingsAndBoundsAreApplied() {
        for input in ["nan","inf","12abc","1.2.3","--2",""] { XCTAssertNil(NumericInput.parse(input,range:0...100)) }
        XCTAssertEqual(NumericInput.parse("200",range:0...100),100)
        XCTAssertEqual(NumericInput.parse("-2",range:1...20),1)
        XCTAssertEqual(NumericInput.parse("2.8",range:1...3,integer:true),3)
    }
    func testPartialAdvancedSettingsMigrateAndValidate() throws {
        let value = try JSONDecoder().decode(AdvancedSettings.self,from:Data(#"{"contextCapacity":99,"speakerColor":"invalid"}"#.utf8))
        XCTAssertEqual(value.contextCapacity,20); XCTAssertEqual(value.movementStep,5)
        XCTAssertFalse(value.backgroundAudio); XCTAssertEqual(value.speakerColor,"#A6C7D8")
    }
    func testManualStopSurvivesRelaunchAndRecoveryDoesNotChangeIntent() throws {
        let name = "Lingo.recovery."+UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName:name))
        defer { defaults.removePersistentDomain(forName:name) }
        XCTAssertFalse(SessionIntentStore.load(defaults))
        SessionIntentStore.save(true,to:defaults); XCTAssertTrue(SessionIntentStore.load(defaults))
        SessionIntentStore.save(false,to:defaults)
        let reloaded = try XCTUnwrap(UserDefaults(suiteName:name))
        XCTAssertFalse(SessionIntentStore.load(reloaded))
    }
    func testLatencyWindowIsBoundedAndRejectsInvalidSamples() {
        var values = LatencySamples()
        for value in 0..<1000 { values.record(Double(value)) }
        values.record(.nan); values.record(.infinity); values.record(-1)
        XCTAssertEqual(values.values.count,120); XCTAssertEqual(values.p95,993)
    }
}
