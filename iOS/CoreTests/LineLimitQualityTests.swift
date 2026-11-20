import XCTest
@testable import LingoCore

final class LineLimitQualityTests: XCTestCase {
    private func rows(_ texts: [String]) -> [OCRLine] {
        texts.enumerated().map { i,text in OCRLine(text:text,box:SourceBox(x:0.25,y:0.72+Double(i)*0.034,w:0.5,h:0.025)) }
    }
    private var quality: QualitySettings { var q = QualitySettings(); q[.lineLimits] = true; return q }
    func testSpeakerAnchoredFiveLinesAndIndependentRollback() throws {
        let texts = ["Arthur: We need to leave now.","The guards are on their way.","I can hear them outside.","Take the money and follow me.","We will meet at the bridge."]
        let input = rows(texts)
        let legacy = try XCTUnwrap(StructuredDialogue.resolve(input,roi:.dialogue,knownNames:"Arthur"))
        let extended = try XCTUnwrap(StructuredDialogue.resolve(input,roi:.dialogue,knownNames:"Arthur",quality:quality))
        XCTAssertEqual(legacy.content.text,"We need to leave now. "+texts[1])
        XCTAssertEqual(extended.content.text,"We need to leave now. "+texts[1...4].joined(separator:" "))
        XCTAssertEqual(extended.content.speaker,"Arthur")
        var q = quality; q[.stageCues] = true; q[.speakerClassification] = true; q[.lineLimits] = false
        XCTAssertEqual(StructuredDialogue.resolve(input,roi:.dialogue,knownNames:"Arthur",quality:q)?.content.text,legacy.content.text)
        q[.lineLimits] = true; q.anchoredLineCap = 4
        XCTAssertEqual(StructuredDialogue.resolve(input,roi:.dialogue,knownNames:"Arthur",quality:q)?.content.text,"We need to leave now. "+texts[1...3].joined(separator:" "))
    }
    func testExpandedAnchoredBodyExcludesCountersAndMenuScreen() throws {
        let input = rows(["Arthur: We need to leave now.","HP 100","The guards are on their way.","Take the money and follow me.","We will meet at the bridge."])
        let result = try XCTUnwrap(StructuredDialogue.resolve(input,roi:.dialogue,knownNames:"Arthur",quality:quality))
        XCTAssertFalse(result.content.text.contains("HP 100"))
        XCTAssertNil(StructuredDialogue.resolve(rows(["Settings","Options","Arthur","Audio","Controls"]),roi:.dialogue,knownNames:"Arthur",quality:quality))
    }
    func testSixFallbackLinesNeedSpatialSentenceAndTemporalEvidence() {
        let input = rows(["We need to leave this place.","Right now.","Come on.","Stay close.","This way.","Let's go."])
        var legacy = DialogueSelection(), selector = DialogueSelection()
        XCTAssertTrue(legacy.select(input,roi:.dialogue).isEmpty)
        XCTAssertTrue(selector.select(input,roi:.dialogue,quality:quality).isEmpty)
        XCTAssertEqual(selector.select(input,roi:.dialogue,quality:quality),input)
        var q = quality; q.fallbackLineCap = 5
        XCTAssertTrue(selector.select(input,roi:.dialogue,quality:q).isEmpty)
    }
    func testMenusHUDAndSeparatedColumnsDoNotBecomeLongDialogue() {
        for texts in [
            ["Settings","Options","Audio","Controls","Graphics"],
            ["Press A","Hold B","HP 100","Ammo 12","FPS 60"],
            ["One","Two","Three","Four","Five"]
        ] {
            var selector = DialogueSelection(); let input = rows(texts)
            XCTAssertTrue(selector.select(input,roi:.dialogue,quality:quality).isEmpty)
            XCTAssertTrue(selector.select(input,roi:.dialogue,quality:quality).isEmpty)
        }
        var input = rows(["We need to leave this place.","Right now.","Come on.","Stay close.","HP 100"])
        input[4].box = SourceBox(x:0.8,y:0.73,w:0.15,h:0.025)
        var selector = DialogueSelection()
        let accepted = selector.select(input,roi:.dialogue,quality:quality)
        XCTAssertFalse(accepted.contains{ $0.text == "HP 100" })
    }
    func testShortDialogueAndInterjectionsRemainEligible() {
        for texts in [["Wait!"],["No!","Why?"],["We need to leave now.","Go!","Wait!","No!"]] {
            let input = rows(texts); var a = DialogueSelection(), b = DialogueSelection()
            XCTAssertEqual(b.select(input,roi:.dialogue,quality:quality),a.select(input,roi:.dialogue))
        }
    }
    func testAdvancedCapsArePersistedBoundedAndDefaultOff() throws {
        let key = "synthetic.line-limits."+UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName:key)); defer { defaults.removePersistentDomain(forName:key) }
        XCTAssertFalse(QualitySettings.load(defaults)[.lineLimits])
        var q = quality; q.anchoredLineCap = 4; q.fallbackLineCap = 5; q.save(defaults)
        XCTAssertEqual(QualitySettings.load(defaults).anchoredLineCap,4); XCTAssertEqual(QualitySettings.load(defaults).fallbackLineCap,5)
        defaults.set(100,forKey:"quality.anchoredLineCap"); defaults.set(-1,forKey:"quality.fallbackLineCap")
        XCTAssertEqual(QualitySettings.load(defaults).anchoredLineCap,5); XCTAssertEqual(QualitySettings.load(defaults).fallbackLineCap,4)
        QualitySettings().save(defaults); XCTAssertFalse(QualitySettings.load(defaults)[.lineLimits])
    }
}
