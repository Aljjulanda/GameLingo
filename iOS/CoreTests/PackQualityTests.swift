import XCTest
@testable import LingoCore

final class PackQualityTests: XCTestCase {
    private func row(_ source: String, _ target: String, markup: Bool = false, labels: Bool = false,
                     flags: String = "[]", usable: Bool = true) -> PackQualityText {
        PackQualityPolicy.transform(source:source,target:target,flags:flags,usable:usable,
                                    options:PackQualityOptions(markup:markup,labels:labels))
    }
    func testRawProfileAndIndependentRollbackPreserveLegacyTextAndFlags() {
        let source = "Arthur: ~z~Stay~n~here.", target = "Arthur: <C>ابق هنا.</C>"
        let raw = row(source,target)
        XCTAssertEqual(raw,PackQualityText(source:source,target:target,flags:"[]",usable:true))
        let markup = row(source,target,markup:true)
        XCTAssertEqual(markup.source,"Arthur: Stay here."); XCTAssertEqual(markup.target,"Arthur: ابق هنا.")
        XCTAssertNil(markup.speaker)
        let labels = row(source,target,labels:true)
        XCTAssertEqual(labels.source,"~z~Stay~n~here."); XCTAssertEqual(labels.target,"<C>ابق هنا.</C>")
        XCTAssertEqual(labels.speaker,"Arthur")
        let both = row(source,target,markup:true,labels:true)
        XCTAssertEqual(both.source,"Stay here."); XCTAssertEqual(both.target,"ابق هنا.")
        XCTAssertTrue(both.flags.contains("speaker:Arthur"))
        XCTAssertEqual(PackLookupKey.normalized("  CAN’T...! "),"can't")
    }
    func testTargetedMarkupPreservesUnknownContentAndBalancedInnerText() {
        for text in ["  Keep\n this spacing  ","Only ordinary text.","Literal ~a story~ with  spaces"] {
            XCTAssertEqual(PackQualityPolicy.cleanMarkup(text),text)
        }
        XCTAssertEqual(PackQualityPolicy.cleanMarkup("<C>One <C>two</C> three</C>"),"One two three")
        for text in ["<C>unfinished", "</C>before<C>", "literal ~a story~", "Use {name}", "<Other>visible</Other>"] {
            XCTAssertEqual(PackQualityPolicy.cleanMarkup(text),text)
        }
        XCTAssertEqual(row("Stay.","<C>ابق.</C>",markup:true).target,"ابق.")
        XCTAssertEqual(row("Stay.","<Other>ابق.</Other>",markup:true).target,"<Other>ابق.</Other>")
        XCTAssertFalse(row("Stay.","<Other>ابق.</Other>",markup:true).usable)
    }
    func testPlaceholdersArePreservedButExcludedOnlyByMarkupProfile() {
        for source in ["Take {0} items.","Take {12:000} items.","Take %s.","Take %1$s.","Take %02d."] {
            XCTAssertTrue(row(source,"خذ الغرض.").usable)
            let value = row(source,"خذ الغرض.",markup:true)
            XCTAssertEqual(value.source,source); XCTAssertFalse(value.usable)
        }
        XCTAssertFalse(row("Take it.","خذ {0}.",markup:true).usable)
        XCTAssertFalse(PackQualityPolicy.hasPlaceholder("100% complete. %%s {literal}"))
    }
    func testUnusableRowsRecoverOnlyWhenTheirSoleBlockerWasKnownMarkup() {
        XCTAssertTrue(row("Stay.","<C>ابق.</C>",markup:true,flags:"[\"unresolved_markup_or_placeholder\"]",usable:false).usable)
        for flags in ["[]","not-json","[\"invalid_text\"]","[\"unresolved_markup_or_placeholder\",\"complex_visual_order\"]"] {
            XCTAssertFalse(row("Stay.","<C>ابق.</C>",markup:true,flags:flags,usable:false).usable)
        }
    }
    func testPackLabelsNeedNamesAndNeverHideUnverifiedArabicPrefixes() {
        XCTAssertEqual(row("47: Keep going.","واصل.",labels:true).speaker,"47")
        for label in ["Wait","Look","Objective","Press A","Music","2026","PS5"] {
            let source = label+": Keep going."
            XCTAssertEqual(row(source,"واصل.",labels:true).source,source)
        }
        XCTAssertEqual(row("The Stranger: Keep going.","واصل.",labels:true).speaker,"The Stranger")
        XCTAssertEqual(row("Arthur: Keep going.","آرثر: واصل.",labels:true).target,"آرثر: واصل.")
        XCTAssertNil(PackQualityPolicy.label("Arthur:"))
    }
    func testCorrectionScopeMustMatchSelectedGameAndGeneralRole() {
        XCTAssertTrue(CorrectionContext(CorrectionsSnapshot(game:"a"),enabled:true).matches(game:"a"))
        XCTAssertFalse(CorrectionContext(CorrectionsSnapshot(game:"a"),enabled:true).matches(game:"b"))
        XCTAssertFalse(CorrectionContext(CorrectionsSnapshot(game:"general"),enabled:true).matches(game:nil))
        XCTAssertTrue(CorrectionContext(CorrectionsSnapshot(game:"general",general:true),enabled:true).matches(game:nil))
        XCTAssertFalse(CorrectionContext(CorrectionsSnapshot(game:"general",general:true),enabled:true).matches(game:"general"))
    }
    func testPunctuationTierRetainsWordBoundariesContractionsAndSignedDecimals() {
        XCTAssertEqual(PackQualityPolicy.punctuationless("“Stop, go!”"),"stop go")
        XCTAssertEqual(PackQualityPolicy.punctuationless("Stop — go?"),"stop go")
        XCTAssertNotEqual(PackQualityPolicy.punctuationless("Stop,go"),PackQualityPolicy.punctuationless("stopgo"))
        XCTAssertEqual(PackQualityPolicy.punctuationless("CAN’T"),"can't")
        XCTAssertNotEqual(PackQualityPolicy.punctuationless("can't"),PackQualityPolicy.punctuationless("cant"))
        XCTAssertNotEqual(PackQualityPolicy.punctuationless("-5"),PackQualityPolicy.punctuationless("5"))
        XCTAssertNotEqual(PackQualityPolicy.punctuationless("5.2"),PackQualityPolicy.punctuationless("52"))
        XCTAssertEqual(PackQualityPolicy.punctuationless("Go: -5.2!"),"go -5.2")
    }
    func testArabicOrderIndicatorsWarnWithoutChangingText() {
        var normal = PackArabicOrderEvidence(), reverse = PackArabicOrderEvidence()
        let correct = "هذا هو الطريق من هنا إلى هناك في كل يوم وعلى كل حال"
        normal.observe(correct); XCTAssertFalse(normal.warning)
        let reversed = "اذه وه قيرطلا نم انه ىلإ كانه يف لك موي ىلعو لك لاح"
        reverse.observe(reversed); XCTAssertTrue(reverse.warning)
        XCTAssertEqual(row("The road.",reversed,markup:true).target,reversed)
        var short = PackArabicOrderEvidence(); short.observe("نم الآن"); XCTAssertFalse(short.warning)
    }
}
