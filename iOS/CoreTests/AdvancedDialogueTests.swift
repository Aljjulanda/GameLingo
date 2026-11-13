import XCTest
@testable import LingoCore

final class AdvancedDialogueTests: XCTestCase {
    private func job(_ id: String = "a", _ text: String = "Wait here", correction: Bool = false, important: Bool = false) -> DialogueJob {
        DialogueJob(id:id,text:text,generation:1,correction:correction,box:.dialogue,frameMilliseconds:0,meaningfulCorrection:important)
    }
    func testGlyphAndPunctuationCorrectionsRemainEquivalent() {
        for value in ["Something happened!","Something happene.","Something happened..","Somethlng happened"] {
            XCTAssertTrue(DialogueText.same("Something happened.",value),value)
        }
    }
    func testSemanticMarkersAndDestinationsAreProtected() {
        for (a,b) in [("We will go","We will not go"),("Collect 10 coins","Collect 11 coins"),("We go left","We go right"),("Go to Berlin","Go to Beriin")] {
            XCTAssertFalse(DialogueText.same(a,b))
        }
    }
    func testPublicationFreezesCosmeticCorrectionsButAllowsMeaningfulRepair() {
        var policy = PublicationStability(); let first = job("a","Something happened")
        XCTAssertTrue(policy.shouldPublish(first)); policy.didPublish(first)
        XCTAssertFalse(policy.shouldPublish(job("a","Something happene",correction:true)))
        XCTAssertTrue(policy.shouldPublish(job("a","Something did not happen",correction:true,important:true)))
        XCTAssertTrue(policy.shouldPublish(job("a","Something happened at the gate",correction:true)))
        XCTAssertTrue(policy.shouldPublish(job("new","Something happened")))
    }
    func testSpeakerLabelsRequireDictionaryAndAreRemovedBeforeTranslation() {
        for source in ["Arthur: We should go.","Arthur:\nWe should go.","ARTHUR\nWe should go."] {
            let content = DialogueContent.parse(source,knownNames:"Arthur,John")
            XCTAssertNotNil(content.speaker); XCTAssertEqual(content.text,"We should go.")
        }
        for source in ["WARNING: We should go.","HELLO\nWe should go.","We should go."] {
            XCTAssertNil(DialogueContent.parse(source,knownNames:"Arthur,John").speaker)
        }
    }
    func testDifferentSpeakerCreatesFreshEventAndSemanticRepairKeepsID() {
        var tracker = DialogueTracker()
        guard case .dialogue(let a,_) = tracker.observe(text:"We will go",box:.dialogue,now:0,frameMilliseconds:0,speaker:"Arthur") else { return XCTFail() }
        guard case .dialogue(let repair,_) = tracker.observe(text:"We will not go",box:.dialogue,now:0.3,frameMilliseconds:300,speaker:"Arthur") else { return XCTFail() }
        XCTAssertEqual(a.id,repair.id); XCTAssertTrue(repair.meaningfulCorrection)
        guard case .dialogue(let b,_) = tracker.observe(text:"We will not go",box:.dialogue,now:0.5,frameMilliseconds:500,speaker:"John") else { return XCTFail() }
        XCTAssertNotEqual(a.id,b.id)
    }
    func testClearLabelsAcrossGamesAndAmbiguousWords() {
        XCTAssertEqual(DialogueContent.parse("Lara: We should leave.",knownNames:"").speaker,"Lara")
        XCTAssertEqual(DialogueContent.parse("Master Chief: Move now.",knownNames:"").speaker,"Master Chief")
        XCTAssertEqual(DialogueContent.parse("SAMUEL\nWe should leave.",knownNames:"",separateLabel:true).speaker,"SAMUEL")
        XCTAssertNil(DialogueContent.parse("PLEASE\nWe should leave.",knownNames:"",separateLabel:true).speaker)
        XCTAssertNil(DialogueContent.parse("Lara: We should leave.",knownNames:"",confidence:0.2).speaker)
        XCTAssertNil(DialogueContent.parse("We should leave: soon.",knownNames:"").speaker)
    }
    func testLateMeaningChangeIsNewDialogue() {
        var tracker = DialogueTracker()
        guard case .dialogue(let a,_) = tracker.observe(text:"We will go",box:.dialogue,now:0,frameMilliseconds:0) else { return XCTFail() }
        _ = tracker.observe(text:"We will go",box:.dialogue,now:2,frameMilliseconds:2000)
        guard case .dialogue(let b,_) = tracker.observe(text:"We will not go",box:.dialogue,now:2.3,frameMilliseconds:2300) else { return XCTFail() }
        XCTAssertNotEqual(a.id,b.id)
    }
    func testBoundedContextAtEveryCapacityAndExpiry() {
        for capacity in [1,5,10,20] {
            var memory = DialogueMemory(); memory.capacity = capacity
            for index in 0..<30 { memory.observe(job("\(index)"),now:Double(index)) }
            XCTAssertEqual(memory.entries.count,capacity)
            memory.observe(job("29","Wait here!",correction:true),now:30)
            XCTAssertEqual(memory.entries.count,capacity)
            memory.prune(now:200); XCTAssertTrue(memory.entries.isEmpty)
            memory.enabled = false; memory.observe(job(),now:201); XCTAssertTrue(memory.entries.isEmpty)
        }
    }
    func testContextRulesOnlyTranslateNewSentenceAndNeverGuessIdioms() {
        var memory = DialogueMemory(); memory.observe(job("a","Walk beside the river"),now:0)
        let rules = "river | Go to the bank. = اذهب إلى ضفة النهر.\nWait! = انتظر!"
        XCTAssertEqual(Terminology.resolve("Go to the bank.",rules:rules,context:memory.entries),"اذهب إلى ضفة النهر.")
        XCTAssertNil(Terminology.resolve("Go to the bank.",rules:rules,context:[]))
        XCTAssertNil(Terminology.resolve("It is raining cats and dogs.",rules:rules,context:memory.entries))
        XCTAssertEqual(Terminology.resolve("Wait!",rules:rules,context:[]),"انتظر!")
    }
}
