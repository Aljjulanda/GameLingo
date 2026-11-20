import XCTest
@testable import LingoCore

final class TypewriterSettlingTests: XCTestCase {
    private func line(_ text: String) -> TypewriterReading { TypewriterReading(text:text,speaker:nil,box:.dialogue) }
    func testNoWaitingForCompleteGamesAndDetectionStaysAvailableLater() {
        var gate = TypewriterSettling()
        for i in 0..<30 {
            let input = line("This is unrelated line \(i)")
            XCTAssertEqual(gate.observe(input,now:Double(i),enabled:true).ready,[input])
            XCTAssertFalse(gate.detected)
        }
        for (i,text) in ["We should", "We should lea", "We should leave now"].enumerated() {
            let result = gate.observe(line(text),now:31+Double(i)*0.5,enabled:true)
            XCTAssertEqual(result.waiting,i == 2)
        }
        XCTAssertTrue(gate.detected); XCTAssertTrue(gate.needsConfirmation)
    }
    func testTwoRealIdenticalReadsSettleWithoutAnyHashObservation() {
        var gate = TypewriterSettling(knownTypewriter:true)
        let input = line("We should leave")
        XCTAssertTrue(gate.observe(input,now:0,enabled:true).waiting)
        XCTAssertTrue(gate.needsConfirmation)
        XCTAssertEqual(gate.observe(input,now:0.5,enabled:true).ready,[input])
        XCTAssertFalse(gate.needsConfirmation)
    }
    func testTerminalShortDialogueAndZeroDurationDoNotWait() {
        for text in ["Go!","No?","Wait...","\"Run!\""] {
            var gate = TypewriterSettling(knownTypewriter:true)
            XCTAssertEqual(gate.observe(line(text),now:0,enabled:true).ready,[line(text)])
        }
        var gate = TypewriterSettling(knownTypewriter:true)
        XCTAssertEqual(gate.observe(line("Go"),now:0,enabled:true,maxWait:0).ready,[line("Go")])
        XCTAssertEqual(gate.observe(line("We should"),now:0,enabled:false).ready,[line("We should")])
    }
    func testContinuousGrowthUsesOriginalThreeSecondDeadline() {
        var gate = TypewriterSettling(knownTypewriter:true)
        for i in 0..<6 {
            XCTAssertTrue(gate.observe(line("We should"+String(repeating:" go",count:i)),now:Double(i)*0.5,enabled:true).waiting)
        }
        let last = line("We should"+String(repeating:" go",count:6))
        XCTAssertEqual(gate.observe(last,now:3,enabled:true).ready,[last])
    }
    func testInterruptedGrowthReturnsPendingAndNewLineInOrderWithoutLoss() {
        var gate = TypewriterSettling(knownTypewriter:true)
        let incomplete = line("We should leave"), next = line("Run!")
        XCTAssertTrue(gate.observe(incomplete,now:0,enabled:true).waiting)
        XCTAssertEqual(gate.observe(next,now:0.5,enabled:true).ready,[incomplete,next])
        XCTAssertFalse(gate.needsConfirmation)
    }
    func testReleasedTextDoesNotRequestContinuousExtraConfirmations() {
        var gate = TypewriterSettling(knownTypewriter:true)
        let input = line("We should leave")
        _ = gate.observe(input,now:0,enabled:true)
        _ = gate.observe(input,now:0.5,enabled:true)
        var differentConfidence = input; differentConfidence.confidence = 0.82
        XCTAssertEqual(gate.observe(differentConfidence,now:1,enabled:true).ready,[differentConfidence])
        XCTAssertFalse(gate.needsConfirmation)
    }
    func testOCRJitterPunctuationAndSourceChangesAreNotGrowthEvidence() {
        for inputs in [["We should","We shou1d","We should leave"],["Wait","Wait.","Wait!"],["Arthur","ARTHUR","Arthur Morgan"],["We should leave","We should","We should leave now"]] {
            var gate = TypewriterSettling()
            for (i,text) in inputs.enumerated() { _ = gate.observe(line(text),now:Double(i)*0.5,enabled:true) }
            XCTAssertFalse(gate.detected)
        }
        var gate = TypewriterSettling()
        _ = gate.observe(line("We should"),now:0,enabled:true)
        var changed = line("We should leave"); changed.speaker = "Arthur"
        _ = gate.observe(changed,now:0.5,enabled:true)
        changed.text += " now"; changed.box.x = 0.8
        _ = gate.observe(changed,now:1,enabled:true)
        XCTAssertFalse(gate.detected)
    }
}
