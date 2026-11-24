import XCTest
@testable import LingoCore

final class CurrentMenuTests: XCTestCase {
    // Authored OCR layouts, not screenshots or evidence from any real game.
    private func column(_ texts: [String], x: Double = 0.12, y: Double = 0.2) -> [OCRLine] {
        texts.enumerated().map { OCRLine(text:$0.element,box:SourceBox(x:x,y:y+Double($0.offset)*0.12,w:0.25,h:0.035),confidence:0.96) }
    }
    func testUnregisteredColumnsAndTabsNeedNoAnchors() {
        for rows in [column(["Resume","Settings","Exit"]),column(["Quick slot","Armor 20","Potion 3"],x:0.55),column(["Audio","Music volume 80%","Back"],x:0.08,y:0.3)] {
            XCTAssertEqual(CurrentMenuLayout.candidate(rows)?.map(\.text),rows.map(\.text))
        }
    }
    func testDialogueScatteredHUDDenseAndOversizedTextAreRejected() {
        XCTAssertNil(CurrentMenuLayout.candidate(column(["We must not leave John behind."])))
        var hud = column(["Health 100","Ammo 12"]); hud[1].box.x = 0.65
        XCTAssertNil(CurrentMenuLayout.candidate(hud))
        XCTAssertNil(CurrentMenuLayout.candidate(column(["Health 100","Ammo 12"])))
        var dense = column(Array(repeating:"Page",count:21))
        for index in dense.indices { dense[index].box.y = 0.05+Double(index)*0.04; dense[index].box.h = 0.02 }
        XCTAssertNil(CurrentMenuLayout.candidate(dense))
        XCTAssertNil(CurrentMenuLayout.candidate(column([String(repeating:"a",count:601),"Back"])))
    }
    func testWrappedSourceIsJoinedWithoutChangingNumbersOrNegation() throws {
        var rows = column(["Do not spend 20", "coins yet", "Back"])
        rows[1].box.y = rows[0].box.y+rows[0].box.h+0.003; rows[1].box.w = 0.18
        let grouped = try XCTUnwrap(CurrentMenuLayout.candidate(rows))
        XCTAssertEqual(grouped.first?.text,"Do not spend 20 coins yet")
        XCTAssertEqual(grouped.count,2)
    }
    func testTwoFreshReadingsAndGeometryJitterKeepCurrentCoordinates() {
        var state = CurrentMenuSession(); let ticket = UUID()
        state.request(ticket,now:10); let rows = column(["Audio","Back"])
        state.observe(rows,width:1280,height:720,now:10.1); XCTAssertFalse(state.stable)
        let generation = state.generation
        var jitter = rows; jitter[0].box.x += 0.004
        state.observe(jitter,width:1280,height:720,now:10.6)
        XCTAssertTrue(state.stable); XCTAssertEqual(state.generation,generation)
        XCTAssertEqual(state.rows[0].box.x,jitter[0].box.x)
    }
    func testValueChangeScrollAndSubmenuRejectOldResultsImmediately() {
        var state = CurrentMenuSession(); let ticket = UUID()
        state.request(ticket,now:10)
        let rows = column(["Music 80","Back"])
        state.observe(rows,width:1280,height:720,now:10.1); state.observe(rows,width:1280,height:720,now:10.6)
        let before = state.generation
        XCTAssertTrue(state.accepts(ticket:ticket,generation:before,source:"Music 80",now:10.7))
        for (i,texts) in [["Music 20","Back"],["Brightness","Back"],["Cancel","Apply"]].enumerated() {
            let time = 11.0+Double(i)
            state.observe(column(texts),width:1280,height:720,now:time)
            XCTAssertFalse(state.accepts(ticket:ticket,generation:before,source:"Music 80",now:time))
            XCTAssertFalse(state.stable)
            state.observe(column(texts),width:1280,height:720,now:time+0.5); XCTAssertTrue(state.stable)
        }
    }
    func testCloseDisappearanceAndNewSourceDimensionsInvalidate() {
        var state = CurrentMenuSession(); let ticket = UUID(); let rows = column(["Save","Load"])
        state.request(ticket,now:10); state.observe(rows,width:1280,height:720,now:10.1); state.observe(rows,width:1280,height:720,now:10.6)
        let generation = state.generation
        state.observe([],width:1280,height:720,now:11)
        XCTAssertFalse(state.active); XCTAssertFalse(state.accepts(ticket:ticket,generation:generation,source:"Save",now:11))
        state.request(UUID(),now:12); state.observe(rows,width:1280,height:720,now:12.1)
        state.observe(rows,width:1920,height:1080,now:12.6); XCTAssertFalse(state.active)
        state.request(UUID(),now:13); state.close(); XCTAssertFalse(state.active)
    }
    func testSourceSilenceAndAcquisitionHaveBoundedSeparateDeadlines() {
        var state = CurrentMenuSession(); state.request(UUID(),now:10)
        XCTAssertFalse(state.expire(now:15.9)); XCTAssertTrue(state.expire(now:16.1))
        state.request(UUID(),now:20); state.observe(column(["Yes","No"]),width:1280,height:720,now:20.1)
        XCTAssertFalse(state.expire(now:21.5)); XCTAssertTrue(state.expire(now:21.7))
        XCTAssertTrue(state.rows.isEmpty)
    }
    func testDictionaryIsExactAndCannotFuzzNumbersOrNegation() {
        XCTAssertEqual(MenuTerminology.translation(" SETTINGS "),"الإعدادات")
        XCTAssertEqual(MenuTerminology.translation("No"),"لا")
        XCTAssertNil(MenuTerminology.translation("Not save")); XCTAssertNil(MenuTerminology.translation("Save 2"))
        XCTAssertNil(MenuTerminology.translation("Sett1ngs"))
    }
    func testColdOCRSeedsOnlyRegionAndRequiresTwoFreshConfirmations() {
        var state = CurrentMenuSession(); let ticket = UUID(), rows = column(["Settings","Audio","Back"])
        state.request(ticket,now:10); state.beginFrame()
        state.prepareFreshFrame(rows,width:1280,height:720)
        XCTAssertFalse(state.expire(now:23.6,sourceAge:0.1))
        XCTAssertNotNil(state.region); XCTAssertTrue(state.rows.isEmpty); XCTAssertFalse(state.stable)
        XCTAssertFalse(state.accepts(ticket:ticket,generation:state.generation,source:"Settings",now:23.6))
        state.observe(rows,width:1280,height:720,now:23.7); XCTAssertFalse(state.stable)
        state.observe(rows,width:1280,height:720,now:24.2); XCTAssertTrue(state.stable)
        XCTAssertTrue(state.accepts(ticket:ticket,generation:state.generation,source:"Settings",now:24.3))
    }
    func testSourceStoppingDuringColdOCRStillClosesAtOriginalLease() {
        var state = CurrentMenuSession(); state.request(UUID(),now:10); state.beginFrame()
        XCTAssertTrue(state.expire(now:23.6,sourceAge:8.94))
        state.prepareFreshFrame(column(["Settings","Audio"]),width:1280,height:720)
        XCTAssertFalse(state.active); XCTAssertTrue(state.rows.isEmpty)
    }
    func testFreshDecodedFramesCannotAuthorizeAnOldTranslation() {
        var state = CurrentMenuSession(); let ticket = UUID(), rows = column(["Settings","Audio"])
        state.request(ticket,now:10)
        state.observe(rows,width:1280,height:720,now:10.1); state.observe(rows,width:1280,height:720,now:10.6)
        let generation = state.generation
        XCTAssertFalse(state.expire(now:12.4,sourceAge:0.1))
        XCTAssertFalse(state.accepts(ticket:ticket,generation:generation,source:"Settings",now:12.4))
    }
    func testNumbersSignsDecimalsAndPercentMustSurvive() {
        XCTAssertTrue(MenuTranslationGuard.safe("السطوع ٨٠٪",source:"Brightness 80%"))
        XCTAssertTrue(MenuTranslationGuard.safe("قيمة -٢٫٥",source:"Value -2.5"))
        XCTAssertFalse(MenuTranslationGuard.safe("قيمة 2.5",source:"Value -2.5"))
        XCTAssertFalse(MenuTranslationGuard.safe("السطوع 60%",source:"Brightness 80%"))
        XCTAssertFalse(MenuTranslationGuard.safe("قيمة 20 10",source:"Value 10 20"))
    }
    func testNegationSymbolsVariablesAndKnownNamesCannotBeDropped() {
        XCTAssertFalse(MenuTranslationGuard.safe("احفظ اللعبة",source:"Do not save game"))
        XCTAssertTrue(MenuTranslationGuard.safe("لا تحفظ اللعبة",source:"Do not save game"))
        XCTAssertFalse(MenuTranslationGuard.safe("إيقاف",source:"On"))
        XCTAssertTrue(MenuTranslationGuard.safe("معطّل",source:"Disabled"))
        XCTAssertTrue(MenuTranslationGuard.safe("اضغط △ [L1] {player} %s",source:"Press △ [L1] {player} %s"))
        XCTAssertFalse(MenuTranslationGuard.safe("اضغط [L1] {player} %s",source:"Press △ [L1] {player} %s"))
        XCTAssertFalse(MenuTranslationGuard.safe("جون",source:"John",names:["John":"يوحنا"]))
        XCTAssertTrue(MenuTranslationGuard.safe("يوحنا",source:"John",names:["John":"يوحنا"]))
    }
    func testOverflowAndCollisionsUseReadoutInsteadOfOverlapping() {
        let sources = column(["Audio","Video","Back"])
        let items = sources.enumerated().map { MenuOverlayItem(id:String($0.offset),source:$0.element.text,translated:"الصوت",box:$0.element.box,color:nil) }
        XCTAssertEqual(CurrentMenuLayout.overlay(items,appearance:MenuAppearance(),aspect:16/9).count,3)
        XCTAssertFalse(CurrentMenuLayout.overlay(items,appearance:MenuAppearance(),aspect:16/9,
            sourceBoxes:sources.map(\.box)+[SourceBox(x:0.4,y:0.17,w:0.2,h:0.1)]).contains{$0.id == "0"})
        var long = items; long[0].translated = String(repeating:"نص ",count:100)
        XCTAssertFalse(CurrentMenuLayout.overlay(long,appearance:MenuAppearance(),aspect:16/9).contains{$0.id == "0"})
        var edge = items; edge[0].box.x = 0.8
        XCTAssertFalse(CurrentMenuLayout.overlay(edge,appearance:MenuAppearance(),aspect:16/9).contains{$0.id == "0"})
    }
    func testLegacyProfilesRetainDestinationAndAppearanceWithoutNewField() throws {
        var original = GameOptions(); original.destination = .both; original.display.set("x",.number(-25))
        let data = try JSONEncoder().encode(original)
        XCTAssertFalse(String(decoding:data,as:UTF8.self).contains("currentMenuAppearance"))
        let restored = try JSONDecoder().decode(GameOptions.self,from:data)
        XCTAssertEqual(restored,original); XCTAssertNil(restored.currentMenuAppearance)
        var edited = restored; edited.currentMenuAppearance = MenuAppearance(); edited.currentMenuAppearance?.side = "left"
        XCTAssertEqual(try JSONDecoder().decode(GameOptions.self,from:JSONEncoder().encode(edited)),edited)
        XCTAssertEqual(edited.destination,.both); XCTAssertEqual(edited.display.number("x"),-25)
    }
}
