import XCTest
@testable import LingoCore

final class TranslationQualityTests: XCTestCase {
    func testDisabledRepairIsByteEquivalentAndEachFixCanRollBackIndependently() {
        for text in [". مرحبًا", "كيف حالك?", ")آرثر(", "  . مرحبًا\n"] {
            XCTAssertEqual(SourceGuidedPunctuation.repair(text,source:"Hello?",enabled:false).text,text)
        }
        XCTAssertEqual(DialogueCommands.value("Wait",sourcePunctuation:false),"انتظر!")
        XCTAssertEqual(DialogueCommands.value("Wait",sourcePunctuation:true),"انتظر")
        XCTAssertEqual(SourceGuidedPunctuation.repair("انتظر!",source:"Wait?").text,"انتظر!")
    }
    func testMisplacedLeadingTerminalNeedsSourceEvidenceAndArabicBody() {
        XCTAssertEqual(SourceGuidedPunctuation.repair(". مرحبًا",source:"Hello.").text,"مرحبًا.")
        XCTAssertEqual(SourceGuidedPunctuation.repair("؟أين أنت",source:"Where are you?").text,"أين أنت؟")
        XCTAssertEqual(SourceGuidedPunctuation.repair("... لا أعرف",source:"I don't know...").text,"لا أعرف...")
        XCTAssertEqual(SourceGuidedPunctuation.repair("  . مرحبًا\n",source:"Hello.").text,"  مرحبًا.\n")
        XCTAssertEqual(SourceGuidedPunctuation.repair(". مرحبًا",source:"Hello").text,". مرحبًا")
        XCTAssertEqual(SourceGuidedPunctuation.repair(". مرحبًا!",source:"Hello!").text,". مرحبًا!")
    }
    func testQuestionMarkConversionDoesNotInventMissingPunctuation() {
        XCTAssertEqual(SourceGuidedPunctuation.repair("إلى أين أنت ذاهب?",source:"Where are you going?").text,"إلى أين أنت ذاهب؟")
        XCTAssertEqual(SourceGuidedPunctuation.repair("أعرف?",source:"I know.").text,"أعرف?")
        XCTAssertEqual(SourceGuidedPunctuation.repair("أين أنت",source:"Where are you?").text,"أين أنت")
        XCTAssertEqual(SourceGuidedPunctuation.repair("كيف حالك؟",source:"How are you?").repairs,0)
    }
    func testReversedPairsRequireUniqueBalancedSourceWitness() {
        XCTAssertEqual(SourceGuidedPunctuation.repair("أعرف )آرثر(",source:"I know (Arthur).").text,"أعرف (آرثر)")
        XCTAssertEqual(SourceGuidedPunctuation.repair("افتح ]الباب[",source:"Open [the door].").text,"افتح [الباب]")
        for (source,text) in [("No pair.",")آرثر("),("(One) (two)",")واحد( )اثنان("),("(One)",")واحد"),("(One)","(واحد)"),("(One)","\")واحد(\""),("(One)",")Arthur(")] {
            XCTAssertEqual(SourceGuidedPunctuation.repair(text,source:source).text,text)
        }
        XCTAssertTrue(SourceGuidedPunctuation.repair("افتح [الباب",source:"Open [the door].").unbalanced)
        XCTAssertTrue(SourceGuidedPunctuation.repair("افتح ]الباب",source:"Open [the door].").unbalanced)
    }
    func testNumericAndMixedScriptIdentifiersAndCorrectQuotedTextArePreserved() {
        for text in [".5", ".NET يعمل", "Arthur (آرثر) قال: \"نعم!\"", "القيمة -5.2.", "هل قال \"لا؟\"", ")Arthur العزيز(", ". قال \"مرحبًا\"", "قال \"نعم\"?"] {
            XCTAssertEqual(SourceGuidedPunctuation.repair(text,source:"The result (value)?").text,text)
        }
    }
    func testCommandPunctuationFollowsSourceWithoutChangingLegacyRecognition() {
        for (source,target) in [("Go","انطلق"),("Go!","انطلق!"),("Run.","اركض."),("Wait?","انتظر؟"),("No...","لا...")] {
            XCTAssertEqual(DialogueCommands.value(source,sourcePunctuation:true),target)
            XCTAssertEqual(DialogueCommands.value(source,sourcePunctuation:false),DialogueCommands.legacy[DialogueCommands.key(source)])
        }
        XCTAssertNil(DialogueCommands.value("Go left",sourcePunctuation:true))
        XCTAssertNil(DialogueCommands.value("Arthur",sourcePunctuation:true))
    }
}
