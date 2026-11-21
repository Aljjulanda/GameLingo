import XCTest
@testable import LingoCore

final class PlayExperienceTests: XCTestCase {
    func testWrappedMenuContinuationDoesNotMergeSpacedRowsOrColumns() {
        let input = [OCRLine(text:"A very long item",box:SourceBox(x:0.1,y:0.2,w:0.3,h:0.03)),
                     OCRLine(text:"continues here",box:SourceBox(x:0.1,y:0.235,w:0.2,h:0.03)),
                     OCRLine(text:"Next item 137",box:SourceBox(x:0.1,y:0.32,w:0.3,h:0.03)),
                     OCRLine(text:"On",box:SourceBox(x:0.6,y:0.32,w:0.05,h:0.03))]
        let rows = MenuItemGrouping.rows(input)
        XCTAssertEqual(rows.count,3);XCTAssertEqual(rows[0].text,"A very long item continues here")
        XCTAssertTrue(rows.contains{$0.text == "Next item 137"})
    }
    func testStopAndNewSessionInvalidateAlreadyQueuedPublication() {
        let fence = DeliveryFence(); let queued = fence.snapshot()
        fence.invalidate(); XCTAssertFalse(fence.accepts(queued))
        let next = fence.snapshot(); XCTAssertTrue(fence.accepts(next))
        fence.invalidate(); XCTAssertFalse(fence.accepts(next)); XCTAssertFalse(fence.accepts(queued))
    }
    func testProfilesMigrateOnlyFirstScopeAndRetainUndoAndDisabledOptions() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let store = try GameProfileStore(root:root)
        var legacy = GameOptions(); legacy.display.set("font_size",.number(48)); legacy.destination = .both
        try store.ensure("game-a",title:"A",migration:legacy)
        try store.ensure("game-b",title:"B",migration:legacy)
        XCTAssertEqual(store.profile("game-a")?.options.destination,.both)
        XCTAssertEqual(store.profile("game-b")?.options,GameOptions())
        var edit = legacy; edit.dialogueRegion = SourceBox(x:0.1,y:0.5,w:0.8,h:0.3)
        try store.update("game-a",options:edit); try store.enable("game-a",false)
        XCTAssertEqual(store.profile("game-a")?.effective,GameOptions())
        try store.enable("game-a",true); XCTAssertEqual(store.profile("game-a")?.effective,edit)
        try store.undo("game-a"); XCTAssertEqual(store.profile("game-a")?.options,legacy)
        let reopened = try GameProfileStore(root:root)
        XCTAssertEqual(reopened.profile("game-b")?.options,GameOptions())
        XCTAssertThrowsError(try reopened.ensure("../escape",title:"unsafe"))
        var invalid = edit; invalid.dialogueRegion.w = 2
        XCTAssertThrowsError(try reopened.update("game-a",options:invalid))
    }
    func testPreviewPersistsAcrossDialogueExpiryAndHideCannotReplayOldID() {
        var state = LocalSubtitleState(); let settings = TVSettings()
        let line: [String:Any] = ["type":"subtitle_show","id":"old","translated":"لا تذهب إلى هناك."]
        state.apply(line,settings:settings,now:0)
        state.apply(["type":"subtitle_preview_show"],settings:settings,now:1)
        state.expire(now:3600); XCTAssertTrue(state.preview); XCTAssertTrue(state.entries.isEmpty)
        state.apply(["type":"subtitle_clear"],settings:settings,now:3601); XCTAssertTrue(state.preview)
        state.apply(["type":"subtitle_preview_hide"],settings:settings,now:3602); XCTAssertFalse(state.preview)
        state.apply(line,settings:settings,now:3603); XCTAssertTrue(state.entries.isEmpty)
        state.apply(["type":"subtitle_show","id":"new","translated":"نعم"],settings:settings,now:3604)
        XCTAssertEqual(state.entries.map(\.id),["new"])
        let deadline = state.entries.first!.until
        state.apply(["type":"subtitle_update","id":"new","translated":"نعم!"],settings:settings,now:3605)
        XCTAssertEqual(state.entries.first!.until,deadline)
    }
    func testViewportRejectsLetterboxAndRotatesWithoutChangingSourceCoordinates() throws {
        let portrait = VideoViewport(frameWidth:1280,frameHeight:720,viewWidth:400,viewHeight:800)
        XCTAssertNil(portrait.normalized(x:10,y:10))
        let center = try XCTUnwrap(portrait.normalized(x:200,y:400))
        XCTAssertEqual(center.0,0.5,accuracy:0.0001); XCTAssertEqual(center.1,0.5,accuracy:0.0001)
        let landscape = VideoViewport(frameWidth:1920,frameHeight:1080,viewWidth:800,viewHeight:400)
        XCTAssertEqual(landscape.normalized(x:400,y:200)?.0,0.5)
        XCTAssertEqual(SourceBox(x:-0.1,y:1,w:0.5,h:0.2).clamped(),SourceBox(x:0,y:0.8,w:0.5,h:0.2))
    }
    func testMenuRequiresAllDistinctiveSpatialAnchorsAndAbstainsOnAmbiguity() {
        let texts = ["Moonlight Lodge","Save game","Return to camp"]
        let lines = texts.enumerated().map { index,text in OCRLine(text:text,box:SourceBox(x:0.1,y:0.2+Double(index)*0.1,w:0.3,h:0.03),confidence:0.95) }
        let menu = AllowedMenu(title:"Pause",region:SourceBox(x:0,y:0,w:1,h:1),anchors:lines.map{MenuAnchor(text:$0.text,box:$0.box)})
        XCTAssertTrue(menu.valid); XCTAssertNotNil(MenuRecognition.recognized([menu],lines:lines))
        XCTAssertNil(MenuRecognition.recognized([menu],lines:Array(lines.prefix(1))))
        var moved = lines; moved[1].box.y += 0.15
        XCTAssertNil(MenuRecognition.recognized([menu],lines:moved))
        var weak = lines; weak[2].confidence = 0.3
        XCTAssertNil(MenuRecognition.recognized([menu],lines:weak))
        var second = menu; second.id = UUID().uuidString
        XCTAssertNil(MenuRecognition.recognized([menu,second],lines:lines))
        var generic = menu; generic.anchors = zip(["Settings","Options","Back"],lines).map{MenuAnchor(text:$0,box:$1.box)}
        XCTAssertFalse(generic.valid)
        var dynamic = menu; dynamic.anchors[0].text = "Gold 44"; XCTAssertFalse(dynamic.valid)
    }
    func testQRRejectsPublicAddressExpiryWrongKindAndOversizedPayload() throws {
        let now: Int64 = 100_000
        let qr = QRBootstrap(v:1,kind:"gamelingo-tv-pair",host:"192.168.3.138",port:38444,session:UUID().uuidString,nonce:Data(repeating:1,count:32).base64EncodedString(),fingerprint:String(repeating:"a",count:64),name:"TCL",expires:now+120_000)
        XCTAssertNoThrow(try qr.validate(now:now))
        for index in 0..<4 {
            var bad = qr
            if index == 0 { bad.host = "8.8.8.8" }; if index == 1 { bad.expires = now }; if index == 2 { bad.kind = "ps5" }; if index == 3 { bad.nonce = "bad" }
            XCTAssertThrowsError(try bad.validate(now:now))
        }
        XCTAssertThrowsError(try QRBootstrap.decode(String(repeating:"x",count:2049),now:now))
    }
}
