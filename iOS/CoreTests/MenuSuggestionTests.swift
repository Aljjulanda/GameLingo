import XCTest
@testable import LingoCore

final class MenuSuggestionTests: XCTestCase {
    // Authored geometry only; no game-specific fixtures.
    private func rows(_ texts: [String] = ["Settings","Audio","Back"]) -> [OCRLine] {
        texts.enumerated().map { OCRLine(text:$0.element,box:SourceBox(x:0.15,y:0.2+Double($0.offset)*0.12,w:0.2,h:0.035),confidence:0.96) }
    }
    func testTwoFreshActualObservationsAreRequiredForAdvisory() {
        var state = MenuSuggestionSession()
        state.observe(rows(),frameAt:10,now:10.1); XCTAssertFalse(state.visible)
        state.observe(rows(),frameAt:11,now:11.1); XCTAssertTrue(state.visible)
        state.expire(now:12.49); XCTAssertTrue(state.visible)
        state.expire(now:12.5); XCTAssertFalse(state.visible)
    }
    func testDuplicateStaleFutureAndGappedObservationsNeverConfirm() {
        for (frame,now) in [(10.0,10.1),(9,10.1),(11,12.5),(14,13)] {
            var state = MenuSuggestionSession()
            state.observe(rows(),frameAt:10,now:10.1)
            state.observe(rows(),frameAt:frame,now:now); XCTAssertFalse(state.visible)
        }
        var state = MenuSuggestionSession()
        state.observe(rows(),frameAt:10,now:10.1)
        state.observe(rows(),frameAt:11.5,now:11.6); XCTAssertFalse(state.visible)
    }
    func testDialogueHUDUnknownAndWeakVocabularyNeedExplicitFallback() {
        for texts in [["We must go.","Stay here.","Wait for me."],["Health 100","Ammo 12","Score 20"],
                      ["Armor","Potions","Quick slots"],["Settings","Back"],["On","Off","Yes"],
                      ["No settings","Audio 2","Go back"],["Settings","Audio","This is a long spoken instruction."]] {
            XCTAssertNil(MenuSuggestionSession.candidate(rows(texts)))
        }
    }
    func testConfidenceScatteredGeometryAndDuplicateLabelsAreRejected() {
        var weak = rows(); weak[0].confidence = 0.89
        XCTAssertNil(MenuSuggestionSession.candidate(weak))
        var scattered = rows(); scattered[2].box.x = 0.6
        XCTAssertNil(MenuSuggestionSession.candidate(scattered))
        XCTAssertNil(MenuSuggestionSession.candidate(rows(["Back","Back","Back"])))
        XCTAssertNil(MenuSuggestionSession.candidate(rows(Array(repeating:"Settings",count:9))))
    }
    func testChangeDisappearanceJitterAndClearCannotKeepAnOldSuggestion() {
        var state = MenuSuggestionSession()
        state.observe(rows(),frameAt:10,now:10.1)
        var jitter = rows(); jitter[0].box.x += 0.004
        state.observe(jitter,frameAt:10.5,now:10.6); XCTAssertTrue(state.visible)
        state.observe(rows(["Graphics","Language","Exit"]),frameAt:11,now:11.1); XCTAssertFalse(state.visible)
        state.observe(rows(["Graphics","Language","Exit"]),frameAt:11.5,now:11.6); XCTAssertTrue(state.visible)
        state.observe([],frameAt:12,now:12.1); XCTAssertFalse(state.visible)
        state.observe(rows(),frameAt:12.5,now:12.6); XCTAssertFalse(state.visible)
        state.clear(); state.observe(rows(),frameAt:13,now:13.1); XCTAssertFalse(state.visible)
    }
    func testLegacyOptionsAndSearchKeepSuggestionOptInAndDiscoverable() throws {
        var original = GameOptions(); original.destination = .phone
        let data = try JSONEncoder().encode(original)
        XCTAssertFalse(String(decoding:data,as:UTF8.self).contains("suggestMenus"))
        var restored = try JSONDecoder().decode(GameOptions.self,from:data)
        XCTAssertEqual(restored,original); XCTAssertNil(restored.suggestMenus)
        restored.suggestMenus = true
        XCTAssertEqual(try JSONDecoder().decode(GameOptions.self,from:JSONEncoder().encode(restored)),restored)
        restored.suggestMenus = false; XCTAssertEqual(restored.destination,.phone)
        for word in ["قوائم","منيو","اقتراح","تلقائي","محاذاة"] { XCTAssertTrue(SettingsPage.menus.matches(word)) }
    }
}
