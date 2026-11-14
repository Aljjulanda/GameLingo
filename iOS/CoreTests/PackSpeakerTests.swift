import XCTest
@testable import LingoCore

final class PackSpeakerTests: XCTestCase {
    func testWrappedInlineAndSeparateNamesAreMetadataOnly() {
        for input in ["(Arthur) We need to leave now", "[Arthur] We need to leave now", "Arthur: We need to leave now", "(Arthur)\nWe need to leave now"] {
            let value = DialogueContent.parse(input,knownNames:"")
            XCTAssertEqual(value.speaker,"Arthur"); XCTAssertEqual(value.text,"We need to leave now")
        }
        for name in ["Master Chief","O'Brien","Dr. Smith","Agent 47"] {
            let value = DialogueContent.parse("[\(name)] Move now.",knownNames:"Agent 47")
            XCTAssertEqual(value.speaker,name); XCTAssertEqual(value.text,"Move now.")
        }
        XCTAssertEqual(DialogueContent.parse("(arthur) Move now.",knownNames:"Arthur").speaker,"arthur")
    }
    func testSoundEffectsAndUncertainLabelsStayDialogue() {
        for effect in ["Laughing","Gunshots","Sighs","Door opens","Music playing"] {
            let text = "(\(effect)) Move now."
            let value = DialogueContent.parse(text,knownNames:effect)
            XCTAssertNil(value.speaker); XCTAssertEqual(value.text,text)
        }
        XCTAssertNil(DialogueContent.parse("(Arthur) Move now.",knownNames:"",confidence:0.2).speaker)
        XCTAssertNil(DialogueContent.parse("(We need to leave now)",knownNames:"").speaker)
        XCTAssertNil(DialogueContent.parse("[Arthur Move now.",knownNames:"").speaker)
    }
    func testWrappedStructuredLabelHasStableBodyGeometry() {
        let body = OCRLine(text:"We need to leave now.",box:SourceBox(x:0.31,y:0.78,w:0.4,h:0.035),confidence:0.95)
        for label in ["(Arthur)","[Arthur]"] {
            let name = OCRLine(text:label,box:SourceBox(x:0.2,y:0.78,w:0.08,h:0.025),confidence:0.95)
            let value = StructuredDialogue.resolve([name,body],roi:.dialogue,knownNames:"")
            XCTAssertEqual(value?.content.speaker,"Arthur"); XCTAssertEqual(value?.content.text,body.text)
            XCTAssertEqual(value?.box,body.box)
        }
    }
}
