import XCTest
@testable import LingoCore

final class SpeakerQualityTests: XCTestCase {
    private func flags(_ values: QualityFlag...) -> QualitySettings {
        var q = QualitySettings(); for value in values { q[value] = true }; return q
    }
    func testRecognizedCuesNeverEnterTranslationOrSpeakerClassification() {
        let q = flags(.stageCues,.speakerClassification)
        for word in ["laughs","laughing","chuckles","giggles","coughs","sighs","groans","grunts","gasps","screams","shouts","whispers","whispering","sobs","cries","sniffs","panting","music","gunshots","footsteps","door opens"] {
            let result = DialogueContent.parse("[\(word)] We should go.",knownNames:word,quality:q)
            XCTAssertEqual(result.engineText,"We should go.",word)
            XCTAssertNotNil(result.cue,word); XCTAssertNil(result.speaker,word)
            XCTAssertTrue(result.text.contains(word),"Cue must retain distinct source identity")
        }
        let only = DialogueContent.parse("(sighs)",knownNames:"",quality:q)
        XCTAssertEqual(only.engineText,""); XCTAssertEqual(only.cue,"(تنهّد)")
        XCTAssertEqual(DialogueContent.parse("laughing",knownNames:"",quality:q).engineText,"")
        XCTAssertNil(DialogueContent.parse("Music",knownNames:"",quality:q).cue,"An unwrapped ambiguous HUD word is not a cue")
        let combined = DialogueContent.parse("Arthur: [laughs] Go now.",knownNames:"",quality:q)
        XCTAssertEqual(combined.speaker,"Arthur"); XCTAssertEqual(combined.engineText,"Go now.")
        XCTAssertEqual(combined.cue,"(ضحك)")
        let multiple = DialogueContent.parse("[laughs] [coughs] Arthur: (sighs) Go now.",knownNames:"",quality:q)
        XCTAssertEqual(multiple.engineText,"Go now."); XCTAssertEqual(multiple.cue,"(ضحك) (سعال) (تنهّد)"); XCTAssertEqual(multiple.speaker,"Arthur")
        for metadata in ["Arthur:","[Arthur]"] {
            XCTAssertTrue(DialogueContent.parse(metadata,knownNames:"Arthur",quality:q).text.isEmpty)
        }
        XCTAssertEqual(DialogueContent.parse("Wait:",knownNames:"",quality:q).text,"Wait:")
        XCTAssertEqual(DialogueContent.parse("[Dead End]",knownNames:"",quality:q).text,"[Dead End]","An unknown bracket-only narrative is preserved")
    }
    func testMiddleBracketsNarrativeAndOrdinaryPrefixesSurvive() {
        let q = flags(.stageCues,.speakerClassification)
        for input in ["Wait: don't go.","Look: there is a boat.","Objective: Find the key.","[the wind settles] We should go.","We (laughs) should go.","[I do not know what to say.]","[A distant memory] I remember you."] {
            let result = DialogueContent.parse(input,knownNames:"",quality:q)
            XCTAssertEqual(result.text,input); XCTAssertNil(result.engineText); XCTAssertNil(result.speaker)
            XCTAssertFalse(result.speakerHidden)
        }
    }
    func testRelaxedNamesRequireDistinctiveTokenOrExplicitDigitPattern() {
        let q = flags(.speakerClassification)
        for name in ["The Stranger","Arthur Morgan","47","2B","9S","BT-7274","Agent 47","O’Driscoll","José"] {
            XCTAssertTrue(DialogueContent.isName(name,knownNames:"",confidence:0.9,quality:q),name)
            XCTAssertEqual(DialogueContent.parse(name+": We must go.",knownNames:"",quality:q).speaker,name)
        }
        for value in ["The","Wait","Main Menu","Health","HP 47","2026","PS5","Music","Mission Objective","Press A"] {
            XCTAssertFalse(DialogueContent.isName(value,knownNames:value,confidence:1,quality:q),value)
        }
        XCTAssertFalse(DialogueContent.isName("the wind",knownNames:"",confidence:1,quality:q))
        XCTAssertFalse(DialogueContent.isName("The Stranger",knownNames:"",confidence:1),"Independent rollback restores strict classifier")
    }
    func testConfirmedUnknownLabelIsRemovedBeforeIdentityIsKnown() {
        let q = flags(.speakerClassification)
        let before = DialogueContent.parse("Arthur\nWe need to leave.",knownNames:"",separateLabel:true,confidence:0.5,quality:q)
        XCTAssertEqual(before.text,"We need to leave."); XCTAssertTrue(before.speakerHidden); XCTAssertNil(before.speaker)
        let after = DialogueContent.parse("Arthur\nWe need to leave.",knownNames:"Arthur",separateLabel:true,confidence:0.5,quality:q)
        XCTAssertEqual(before.text,after.text); XCTAssertEqual(after.speaker,"Arthur")
        XCTAssertEqual(before.labelForm,.separate)
        let uncertain = DialogueContent.parse("[Arthur] We need to leave.",knownNames:"",confidence:0.5,quality:q)
        XCTAssertTrue(uncertain.text.contains("Arthur"),"No spatial or accepted-name evidence: preserve the source")
    }
    func testGeometryAllowsLeftOffsetButRejectsRemoteOrHUDElements() {
        let q = flags(.speakerClassification,.speakerGeometry)
        let body = OCRLine(text:"We need to leave now.",box:SourceBox(x:0.38,y:0.78,w:0.4,h:0.03))
        let label = OCRLine(text:"Arthur",box:SourceBox(x:0.26,y:0.70,w:0.10,h:0.038))
        XCTAssertNil(StructuredDialogue.resolve([label,body],roi:.dialogue,knownNames:""))
        let result = StructuredDialogue.resolve([label,body],roi:.dialogue,knownNames:"",quality:q)
        XCTAssertEqual(result?.content.speaker,"Arthur"); XCTAssertEqual(result?.content.text,body.text)
        var remote = label; remote.box.x = 0.02
        XCTAssertNil(StructuredDialogue.resolve([remote,body],roi:.dialogue,knownNames:"",quality:q))
        var hud = label; hud.text = "Health"
        XCTAssertNil(StructuredDialogue.resolve([hud,body],roi:.dialogue,knownNames:"Health",quality:q))
        var small = label; small.box.h = 0.004; small.text = "HP 47"
        XCTAssertNil(StructuredDialogue.resolve([small,body],roi:.dialogue,knownNames:"HP 47",quality:q))
        var uncertain = label; uncertain.text = "M0rgan"; uncertain.confidence = 0.5
        let hidden = StructuredDialogue.resolve([uncertain,body],roi:.dialogue,knownNames:"",quality:q)
        XCTAssertEqual(hidden?.content.text,body.text); XCTAssertTrue(hidden?.content.speakerHidden == true)
    }
    func testAllOffAndIndependentRollbacksRetainLegacyOutput() {
        let inputs = ["[laughs] We should go.","The Stranger: Come here.","Wait: don't go.","Arthur: Follow me.","[Arthur] Follow me."]
        for input in inputs {
            let legacy = DialogueContent.parse(input,knownNames:"Arthur")
            var q = flags(.stageCues,.speakerClassification,.speakerGeometry,.visionNames)
            for flag in [QualityFlag.stageCues,.speakerClassification,.speakerGeometry,.visionNames] { q[flag] = false }
            let off = DialogueContent.parse(input,knownNames:"Arthur",quality:q)
            XCTAssertEqual(off.text,legacy.text); XCTAssertEqual(off.speaker,legacy.speaker); XCTAssertNil(off.cue)
        }
        var q = flags(.stageCues,.speakerClassification); q[.stageCues] = false
        XCTAssertNil(DialogueContent.parse("[laughs] Go.",knownNames:"",quality:q).cue)
        q = flags(.stageCues,.speakerClassification); q[.speakerClassification] = false
        XCTAssertNil(DialogueContent.parse("The Stranger: Come here.",knownNames:"",quality:q).speaker)
    }
    func testDictionaryCapDedupExclusionsAndConfidenceCountsAreContentFree() {
        let names = (0..<250).map { "Name"+String(UnicodeScalar(97+$0/26)!)+String(UnicodeScalar(97+$0%26)!) }.joined(separator:",")
        let words = VisionNameDictionary.words(["Arthur,arthur,Wait,music,2026,PS5",names])
        XCTAssertEqual(words.count,200); XCTAssertEqual(words.first,"Arthur"); XCTAssertFalse(words.contains("Wait"))
        var counts = NameConfidenceCounts()
        counts.observe([OCRLine(text:"Arthur",box:.dialogue,confidence:0.3),OCRLine(text:"Dutch",box:.dialogue,confidence:0.7),OCRLine(text:"John",box:.dialogue,confidence:0.9),OCRLine(text:"Health",box:.dialogue)])
        XCTAssertEqual(counts.low,1); XCTAssertEqual(counts.medium,1); XCTAssertEqual(counts.high,1)
        counts.observe([OCRLine(text:"Arthur: We should go.",box:.dialogue,confidence:0.8),OCRLine(text:"We should go",box:.dialogue),OCRLine(text:"Wait: do not go.",box:.dialogue)])
        XCTAssertEqual(counts.high,2,"Only actual name candidates, not short ordinary dialogue")
        XCTAssertFalse(counts.summary.contains("Arthur"))
    }
    func testGeometryPreferencesPersistAndRejectNonFiniteValues() {
        let d = UserDefaults(suiteName:UUID().uuidString)!
        defer { for key in d.dictionaryRepresentation().keys { d.removeObject(forKey:key) } }
        var q = QualitySettings(); q.nameHeightRatio = 1.6; q.nameGapRatio = 2.4; q.nameOverlap = 0.2; q.nameLeftOffset = 0.22; q.save(d)
        XCTAssertEqual(QualitySettings.load(d),q)
        d.set(Double.infinity,forKey:"quality.nameHeightRatio")
        XCTAssertEqual(QualitySettings.load(d).nameHeightRatio,1.4)
    }
    func testSharedReplayOnlySendsDialogueBodyToStub() throws {
        let q = flags(.stageCues,.speakerClassification)
        let record = QualityCaptureRecord(eventID:"synthetic-cue",lines:[CaptureLine(text:"[laughs] We should leave now.",box:SourceBox(x:0.25,y:0.78,w:0.5,h:0.04),confidence:1)],parsed:"",engineInput:"",engineOutput:"",origin:nil,stage:.observation,timestamp:1)
        var inputs: [String] = []
        _ = try QualityReplay.run(JSONEncoder().encode(record),quality:q) { input in inputs.append(input); return "علينا المغادرة الآن." }
        XCTAssertEqual(inputs,["We should leave now."])
    }
}
