import XCTest
@testable import LingoCore

final class TypewriterPublicationTests: XCTestCase {
    private func reading(_ text: String) -> TypewriterReading { TypewriterReading(text:text,speaker:nil,box:.dialogue) }
    private func job(_ text: String) -> DialogueJob { DialogueJob(id:"synthetic",text:text,generation:1,correction:false,box:.dialogue,frameMilliseconds:0) }
    func testWorkerCanTranslateEarlyThenPublishAfterTwoActualReads() {
        var gate = TypewriterPublication(knownTypewriter:true)
        let source = reading("We should leave")
        XCTAssertTrue(gate.observe(source,now:0,enabled:true).isEmpty)
        XCTAssertFalse(gate.canPublish(job(source.text)))
        // The worker completes at0.1s; a bitmap signature is NOT an OCR read.
        XCTAssertTrue(gate.needsConfirmation)
        XCTAssertEqual(gate.observe(source,now:0.5,enabled:true),[source])
        XCTAssertTrue(gate.canPublish(job(source.text)))
        XCTAssertFalse(gate.needsConfirmation)
    }
    func testInterruptedFastLineFlushesBeforeTrackerAdvancesWithoutNewIdentityLogic() {
        var gate = TypewriterPublication(knownTypewriter:true), tracker = DialogueTracker()
        var stability = PublicationStability(), published: [String] = []
        let first = reading("Wait here"), next = reading("Run!")
        _ = gate.observe(first,now:0,enabled:true)
        guard case .dialogue(let old,_) = tracker.observe(text:first.text,box:first.box,now:0,frameMilliseconds:0) else { return XCTFail("Missing actual tracker job") }
        XCTAssertFalse(gate.canPublish(old)) // Result is ready at0.1s, held in RAM.
        let ready = gate.observe(next,now:0.5,enabled:true)
        if TypewriterPublication.canFlush(old,ready:ready), tracker.accepts(old), stability.shouldPublish(old) {
            published.append(old.text); stability.didPublish(old)
        }
        guard case .dialogue(let current,_) = tracker.observe(text:next.text,box:next.box,now:0.5,frameMilliseconds:500) else { return XCTFail("Missing next tracker job") }
        XCTAssertTrue(gate.canPublish(current))
        if tracker.accepts(current), stability.shouldPublish(current) { published.append(current.text); stability.didPublish(current) }
        XCTAssertEqual(published,[first.text,next.text])
        XCTAssertFalse(tracker.accepts(old),"Late worker completion remains rejected by the unchanged tracker")
    }
    func testSettledLongerSourceDoesNotPublishOlderPrefixResult() {
        var gate = TypewriterPublication(knownTypewriter:true)
        _ = gate.observe(reading("We should"),now:0,enabled:true)
        _ = gate.observe(reading("We should leave"),now:0.5,enabled:true)
        _ = gate.observe(reading("We should leave"),now:1,enabled:true)
        XCTAssertFalse(gate.canPublish(job("We should")))
        XCTAssertTrue(gate.canPublish(job("We should leave")))
    }
    func testTerminalUnknownGameOffAndZeroDurationAreImmediate() {
        var known = TypewriterPublication(knownTypewriter:true)
        _ = known.observe(reading("Go!"),now:0,enabled:true)
        XCTAssertTrue(known.canPublish(job("Go!")))
        var unknown = TypewriterPublication()
        _ = unknown.observe(reading("Wait here"),now:0,enabled:true)
        XCTAssertTrue(unknown.canPublish(job("Wait here")))
        for enabled in [true,false] {
            var gate = TypewriterPublication(knownTypewriter:true)
            _ = gate.observe(reading("Wait here"),now:0,enabled:enabled,maxWait:0)
            XCTAssertTrue(gate.canPublish(job("Wait here"))); XCTAssertFalse(gate.needsConfirmation)
        }
    }
    func testNewSpeakerAndRemoteRegionCannotFlushAnUnrelatedHeldResult() {
        var other = reading("Wait here now"); other.speaker = "John"
        var old = job("Wait here"); old.speaker = "Arthur"
        XCTAssertFalse(TypewriterPublication.canFlush(old,ready:[other]))
        other.speaker = nil; other.box.x = 0.8
        XCTAssertFalse(TypewriterPublication.canFlush(old,ready:[other]))
    }
}
