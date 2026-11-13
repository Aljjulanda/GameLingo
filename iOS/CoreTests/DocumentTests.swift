import XCTest
@testable import LingoCore

final class DocumentTests: XCTestCase {
    func testReconstructsParagraphsAndNumberingInsteadOfTranslatingIndividualLines() {
        let lines = [
            DocumentLine(text:"Dear John,",box:SourceBox(x:0.2,y:0.1,w:0.4,h:0.03)),
            DocumentLine(text:"We will not leave",box:SourceBox(x:0.2,y:0.2,w:0.4,h:0.03)),
            DocumentLine(text:"until you bring 11 coins.",box:SourceBox(x:0.2,y:0.24,w:0.4,h:0.03)),
            DocumentLine(text:"1. Find the gate.",box:SourceBox(x:0.2,y:0.28,w:0.4,h:0.03))]
        XCTAssertEqual(DocumentText.paragraphs(lines),["Dear John,","We will not leave until you bring 11 coins.","1. Find the gate."])
    }
    func testClearTwoColumnLayoutReadsDownEachColumn() {
        let lines = (0..<4).flatMap { row in [
            DocumentLine(text:"Left \(row)",box:SourceBox(x:0.1,y:0.1+Double(row)*0.04,w:0.3,h:0.03)),
            DocumentLine(text:"Right \(row)",box:SourceBox(x:0.6,y:0.1+Double(row)*0.04,w:0.3,h:0.03))] }
        XCTAssertEqual(DocumentText.paragraphs(lines),["Left 0 Left 1 Left 2 Left 3","Right 0 Right 1 Right 2 Right 3"])
    }
    func testParagraphChunkingPreservesWordsAndNumbers() {
        let text = Array(repeating:"Bring 11 coins before leaving the camp.",count:30).joined(separator:" ")
        let chunks = DocumentText.chunks([text])
        XCTAssertTrue(chunks.count>1); XCTAssertTrue(chunks.allSatisfy { $0.count<=600 })
        XCTAssertEqual(DialogueText.words(chunks.joined(separator:" ")),DialogueText.words(text))
    }
    func testLongArabicPagesHaveBoundsAndNoLostWords() {
        let text = Array(repeating:"لن نغادر المعسكر قبل أن تجمع 11 قطعة نقدية.",count:100).joined(separator:" ")
        let pages = DocumentText.pages([text])
        XCTAssertTrue(pages.count>1); XCTAssertTrue(pages.allSatisfy { $0.count<=600 })
        let actual = DialogueText.words(pages.joined(separator:" ")), expected = DialogueText.words(text)
        XCTAssertEqual(actual.count,expected.count,"Document pages must retain every source word")
        let mismatch = zip(actual,expected).enumerated().first { $0.element.0 != $0.element.1 }
        XCTAssertNil(mismatch?.offset,"Pagination changed a word")
    }
    func testLowConfidenceAndInvalidGeometryAreNotDocumentText() {
        XCTAssertTrue(DocumentText.paragraphs([
            DocumentLine(text:"uncertain",box:.dialogue,confidence:0.1),
            DocumentLine(text:"invalid",box:SourceBox(x:0,y:0,w:0,h:1))]).isEmpty)
    }
}
