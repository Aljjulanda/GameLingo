import XCTest
@testable import LingoCore

final class DialogueTests: XCTestCase {
    func testDesktopCorrectionFixtures() {
        for (before,after) in [("Let's go.","Lets go!"),("Don't go","Dont go"),("Follow me","Follow me to the gate."),("Something happened.","Somethlng happened."),("Captain: We should leave through the gate.","We should leave through the gate.")] {
            XCTAssertTrue(DialogueText.same(before,after),"\(before) → \(after)")
        }
    }
    func testMeaningfulChangesAreNeverCorrections() {
        for (before,after) in [("Go!","No!"),("Wait!","What?"),("Collect 10 coins","Collect 11 coins"),("Get -10 coins","Get 10 coins"),("Come here","Stay here"),("We should not enter the gate.","We should enter the gate."),("Collect 10 coins before leaving.","Collect coins before leaving.")] {
            XCTAssertFalse(DialogueText.same(before,after),"\(before) → \(after)")
        }
    }
    func testCorrectionsKeepIdentityAndUnchangedTextCreatesNoEvent() {
        var tracker = DialogueTracker()
        guard case .dialogue(let first,_) = tracker.observe(text:"Follow me",box:.dialogue,now:0,frameMilliseconds:0) else { return XCTFail() }
        guard case .unchanged = tracker.observe(text:"Follow me!",box:.dialogue,now:0.2,frameMilliseconds:200) else { return XCTFail() }
        guard case .dialogue(let second,_) = tracker.observe(text:"Follow me to the gate",box:.dialogue,now:0.5,frameMilliseconds:500) else { return XCTFail() }
        XCTAssertEqual(first.id,second.id); XCTAssertTrue(second.correction)
    }
    func testRepeatedDialogueAfterTwoEmptyObservationsHasFreshIdentity() {
        var tracker = DialogueTracker()
        guard case .dialogue(let first,_) = tracker.observe(text:"Wait!",box:.dialogue,now:0,frameMilliseconds:0) else { return XCTFail() }
        guard case .unchanged = tracker.observe(text:"",box:.dialogue,now:0.1,frameMilliseconds:100) else { return XCTFail() }
        guard case .gone(let id) = tracker.observe(text:"",box:.dialogue,now:0.4,frameMilliseconds:400) else { return XCTFail() }
        XCTAssertEqual(id,first.id)
        guard case .dialogue(let again,_) = tracker.observe(text:"Wait!",box:.dialogue,now:0.5,frameMilliseconds:500) else { return XCTFail() }
        XCTAssertNotEqual(first.id,again.id); XCTAssertFalse(again.correction)
    }
    func testStaleTranslationCannotReplaceNewEvent() {
        var tracker = DialogueTracker()
        guard case .dialogue(let first,_) = tracker.observe(text:"Go!",box:.dialogue,now:0,frameMilliseconds:0) else { return XCTFail() }
        _ = tracker.observe(text:"No!",box:.dialogue,now:0.2,frameMilliseconds:200)
        XCTAssertFalse(tracker.accepts(first))
        tracker.reset(); XCTAssertFalse(tracker.accepts(first))
    }
    func testCorrectedFullLineRejectsOlderNonPrefixResult() {
        var tracker = DialogueTracker()
        guard case .dialogue(let first,_) = tracker.observe(text:"Something happened.",box:.dialogue,now:0,frameMilliseconds:0) else { return XCTFail() }
        _ = tracker.observe(text:"Sometheng happened.",box:.dialogue,now:0.2,frameMilliseconds:200)
        XCTAssertFalse(tracker.accepts(first))
    }
    func testSpatialMoveStartsNewEvent() {
        var tracker = DialogueTracker()
        guard case .dialogue(let first,_) = tracker.observe(text:"Wait!",box:.dialogue,now:0,frameMilliseconds:0) else { return XCTFail() }
        let moved = SourceBox(x:0.16,y:0.15,w:0.68,h:0.28)
        guard case .dialogue(let next,_) = tracker.observe(text:"Wait!",box:moved,now:0.2,frameMilliseconds:200) else { return XCTFail() }
        XCTAssertNotEqual(first.id,next.id)
    }
    func testBoundedCacheEvictsLeastRecentlyUsedAcrossLongSessions() {
        var cache = BoundedLRU<Int,String>(capacity:256)
        for i in 0..<10000 { cache.put(String(i),for:i) }
        XCTAssertEqual(cache.values.count,256); XCTAssertNil(cache.get(0)); XCTAssertEqual(cache.get(9999),"9999")
    }
}
