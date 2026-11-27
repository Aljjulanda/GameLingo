import XCTest
@testable import LingoCore

final class DialogueNoiseTests: XCTestCase {
    private func read(_ texts: [String], selector: inout DialogueSelection, names: String = "Arthur") -> PostOCRReading {
        let lines = texts.enumerated().map { index,text in
            OCRLine(text:text,box:.init(x:0.3,y:0.72+Double(index)*0.04,w:0.4,h:0.03),confidence:0.96)
        }
        return DialogueObservation.resolve(lines,roi:.dialogue,knownNames:names,selector:&selector)
    }
    func testPlateAndCounterEvidenceNeverBecomesDialogueAfterRepeatedReads() {
        for text in ["ABC 1234","7ABC123","AB12 CDE","123-ABC","AB 123 CD","abc-1234","123456","HP 100","120 KM/H","NO PARKING","FOR SALE"] {
            var selector = DialogueSelection()
            for _ in 0..<4 { XCTAssertTrue(read([text],selector:&selector).content.text.isEmpty,text) }
        }
    }
    func testSpeakerLabelsCannotMakePlatesEligible() {
        for texts in [["Arthur: ABC 1234"],["Arthur","ABC 1234"],["Arthur: HP 100"]] {
            var selector = DialogueSelection()
            XCTAssertTrue(read(texts,selector:&selector).content.text.isEmpty,texts.joined(separator:"|"))
        }
    }
    func testNoiseDoesNotPolluteNearbyRealDialogue() {
        var selector = DialogueSelection()
        let result = read(["ABC 1234","We should leave now."],selector:&selector)
        XCTAssertEqual(result.content.text,"We should leave now.")
        let labelled = read(["Arthur: We should leave now.","AB 123 CD"],selector:&selector)
        XCTAssertEqual(labelled.content.text,"We should leave now.")
        XCTAssertEqual(labelled.content.speaker,"Arthur")
    }
    func testNumbersCodesAndShortCommandsInRealDialogueRemainEligible() {
        for text in ["I need 42 dollars.","Meet me at 10:30.","The plate is ABC 1234.","Go to room B12.","The code is 123456.","Take Route 66.","Room 12","I AM 42","R2D2, come here!","Wait!","No!","Stop!"] {
            XCTAssertFalse(DialogueNoise.rejects(text),text)
            var selector = DialogueSelection()
            XCTAssertFalse(read([text],selector:&selector).content.text.isEmpty,text)
        }
    }
    func testNoNoiseRetainedAcrossObservations() {
        var selector = DialogueSelection()
        XCTAssertFalse(read(["We should leave now."],selector:&selector).content.text.isEmpty)
        XCTAssertTrue(read(["7ABC123"],selector:&selector).content.text.isEmpty)
        XCTAssertFalse(read(["Go!"],selector:&selector).content.text.isEmpty)
    }
    func testControlCanDisableStartingAndRecoveringSessionsAndExpiresStaleState() {
        let now = Date(timeIntervalSince1970:100)
        for phase in [SessionControlSnapshot.Phase.starting,.active,.recovering,.suspended] {
            let snapshot = SessionControlSnapshot(phase:phase,updated:now)
            XCTAssertTrue(snapshot.isEnabled(now:now))
            XCTAssertFalse(snapshot.isEnabled(now:now.addingTimeInterval(13)))
            XCTAssertFalse(snapshot.isEnabled(now:now.addingTimeInterval(-1)))
        }
        XCTAssertFalse(SessionControlSnapshot(phase:.stopped,updated:now).isEnabled(now:now))
    }
    func testFiniteExecutionOpportunityDoesNotBecomePermanentBackgroundPermission() {
        var policy = SessionPolicy(); policy.start(); policy.foreground = false
        XCTAssertFalse(policy.canExecute)
        policy.executionGrace = true
        XCTAssertTrue(policy.canRecover)
        policy.executionGrace = false
        XCTAssertFalse(policy.canExecute)
        XCTAssertTrue(policy.wanted)
        policy.executionGrace = true; policy.stop()
        XCTAssertFalse(policy.executionGrace)
        XCTAssertFalse(policy.canRecover)
    }
}
