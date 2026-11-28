import XCTest
@testable import LingoCore

final class FieldRepairTests: XCTestCase {
    private func row(_ text: String, x: Double = 0.12, y: Double = 0.2, w: Double = 0.25) -> OCRLine {
        OCRLine(text:text,box:SourceBox(x:x,y:y,w:w,h:0.04),confidence:0.98)
    }
    func testEmptyLegacyMenuSetupCannotDisableAutomaticDiscovery() {
        var options = GameOptions(); options.menusEnabled = true
        XCTAssertFalse(options.usesConfiguredMenus)
        let rows = [row("Audio"),row("Back",y:0.4)]
        XCTAssertEqual(SpatialRecognition.category(rows),.menu)
        XCTAssertEqual(SpatialRecognition.category([row("POLICE")]),.gameplay)
        XCTAssertEqual(SpatialRecognition.category([row("Audio"),row("Back",x:0.7,y:0.4)]),.gameplay)
    }
    func testObjectiveSelectsItsOwnRowsWithoutWorldTextOrDialogue() {
        let rows = [row("Escape the police"),row("POLICE",x:0.6,y:0.5,w:0.1),row("ABC 1234",y:0.65),row("We should go now.",y:0.8)]
        XCTAssertEqual(SpatialRecognition.category(rows),.objective)
        XCTAssertEqual(SpatialRecognition.rows(rows,dialogue:.dialogue,category:.objective).map(\.text),["Escape the police"])
        XCTAssertEqual(MenuTerminology.translation("Escape the police"),"اهرب من الشرطة")
        XCTAssertFalse(SpatialRecognition.isObjective(row("Escape the police.",y:0.8)))
    }
    func testVehicleLetteringIsRejectedWithGeometryWhileSimilarSpeechSurvives() {
        for text in ["POLICE","SHERIFF","TAXI","LOS SANTOS CUSTOMS","AMBULANCE"] {
            var selector = DialogueSelection()
            let line = row(text,x:0.46,y:0.75,w:0.08)
            for _ in 0..<4 {
                XCTAssertTrue(DialogueObservation.resolve([line],roi:.dialogue,knownNames:"Arthur",selector:&selector).content.text.isEmpty,text)
            }
        }
        for text in ["Police!","Taxi!","Arthur: POLICE","Arthur: 42","The plate is ABC 1234.","I need 42 dollars.","Stop!"] {
            var selector = DialogueSelection()
            XCTAssertFalse(DialogueObservation.resolve([row(text,x:0.3,y:0.75,w:0.4)],roi:.dialogue,knownNames:"Arthur",selector:&selector).content.text.isEmpty,text)
        }
    }
    func testSpatialWireDecodesForPhoneAndExcludesRemovedAndMovedSources() throws {
        let line = row("Audio")
        let element = SpatialElement(source:line.text,normalized:SpatialRecognition.key(line.text),translated:"الصوت",box:line.box,scale:line.box.h,dynamic:false,origin:"command",confidence:0.98)
        let screen = SpatialScreen(game:"synthetic",gameVersion:"1",id:"menu",fingerprint:"one",category:.menu,visualHash:"",elements:[element],observed:1)
        let message = try XCTUnwrap(SpatialPresentation.snapshot(screen,rows:[line],aspect:16.0/9))
        let wire = try TVProtocol.decode(TVProtocol.encode(message))
        let style = try JSONDecoder().decode(MenuAppearance.self,from:JSONSerialization.data(withJSONObject:try XCTUnwrap(wire["appearance"])))
        let items = try JSONDecoder().decode([MenuOverlayItem].self,from:JSONSerialization.data(withJSONObject:try XCTUnwrap(wire["items"])))
        XCTAssertTrue(style.valid); XCTAssertEqual(items.map(\.translated),["الصوت"])
        for rows in [[],[row("Audio",x:0.7)],[row("Back")]] {
            let absent = try XCTUnwrap(SpatialPresentation.snapshot(screen,rows:rows,aspect:16.0/9))
            XCTAssertTrue((absent["items"] as? [[String:Any]])?.isEmpty == true)
        }
        XCTAssertTrue(SpatialRecognition.sameObservation([line],[row("Audio",y:0.21)]))
        XCTAssertFalse(SpatialRecognition.sameObservation([line],[row("Audio",y:0.5)]))
    }
    func testSourceLeaseOutlivesReadingTimerButRejectsLateResultsAndOldClears() {
        var state = LocalSubtitleState(); let settings = TVSettings()
        func message(_ type: String, _ id: String, _ generation: Int) -> [String:Any] {
            TVProtocol.envelope(type,fields:["id":id,"source_generation":generation,"translated":"الجملة الطويلة ما زالت ظاهرة"])
        }
        state.apply(message("subtitle_show","a",1),settings:settings,now:0)
        for tick in 1...20 { state.apply(message("subtitle_source_present","a",1),settings:settings,now:Double(tick)) }
        XCTAssertEqual(state.entries.count,1)
        state.apply(message("subtitle_source_present","a",2),settings:settings,now:20.1)
        state.apply(message("subtitle_source_gone","a",1),settings:settings,now:20.2)
        XCTAssertEqual(state.entries.count,1,"An old clear cannot delete a newer generation")
        state.apply(message("subtitle_source_gone","a",2),settings:settings,now:20.3)
        XCTAssertTrue(state.entries.isEmpty)
        state.apply(message("subtitle_show","a",2),settings:settings,now:20.4)
        state.apply(message("subtitle_source_present","a",3),settings:settings,now:20.5)
        XCTAssertTrue(state.entries.isEmpty,"A closed source cannot resurrect")
        state.apply(message("subtitle_source_gone","late",7),settings:settings,now:21)
        state.apply(message("subtitle_show","late",7),settings:settings,now:21.1)
        XCTAssertTrue(state.entries.isEmpty)
        state.apply(message("subtitle_show","b",8),settings:settings,now:22)
        state.expire(now:23.81); XCTAssertTrue(state.entries.isEmpty,"Lost frames do not leave a hanging card")
    }
    func testPackMatchingKeepsNumbersNamesDirectionsAndNegationProtected() {
        for (source,reference) in [("Do not leave John here.","Do leave John here."),("Take 42 coins from John.","Take 43 coins from John."),("Go left with John now.","Go right with John now."),("Stay here with John now.","Stay here with Jack now.")] {
            XCTAssertNil(PackFuzzyMatching.kind(source:source,reference:reference))
        }
    }
}
