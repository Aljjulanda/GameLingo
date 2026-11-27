import XCTest
@testable import LingoCore

final class Upgrade050Tests: XCTestCase {
    func testTerminalReasonsCannotRecoverEvenAfterReady() {
        for reason in [ConsoleDisconnect.rest,.shutdown,.unknown,.user] {
            var state = ConsoleLifecycle(); state.activate(); state.connected()
            state.disconnect(reason,now:10); state.discovered(ready:true,standby:false,now:11)
            XCTAssertFalse(state.canRetry(now:12,network:true)); XCTAssertFalse(state.wanted)
            state.activate(); state.connected(); XCTAssertTrue(state.wanted)
        }
    }
    func testNetworkRecoveryNeedsFreshReadyAndRestCancelsIt() {
        var state = ConsoleLifecycle(); state.activate(); state.connected()
        state.discovered(ready:true,standby:false,now:1); state.disconnect(.network,now:2)
        XCTAssertFalse(state.canRetry(now:3,network:true))
        state.discovered(ready:true,standby:false,now:4)
        XCTAssertFalse(state.canRetry(now:5,network:false)); XCTAssertTrue(state.canRetry(now:5,network:true))
        state.discovered(ready:false,standby:true,now:6)
        XCTAssertFalse(state.canRetry(now:7,network:true)); XCTAssertFalse(state.wanted)
    }
    func testControlShowsConnectedStateOnlyWithFreshLease() {
        let now = Date(timeIntervalSince1970:100)
        for phase in [SessionControlSnapshot.Phase.stopped,.starting,.recovering,.suspended] {
            XCTAssertFalse(SessionControlSnapshot(phase:phase,updated:now).isActive(now:now))
        }
        let active = SessionControlSnapshot(phase:.active,updated:now)
        XCTAssertTrue(active.isActive(now:now.addingTimeInterval(5)))
        XCTAssertFalse(active.isActive(now:now.addingTimeInterval(13)))
        XCTAssertFalse(active.isActive(now:now.addingTimeInterval(-1)))
    }
    func testPrivacyNoiseAndUnrelatedUIAreRejectedBeforeLearning() {
        for text in ["Signed in to personal account", "My blue jacket looks nice.", "You unlocked a trophy.", "Arthur: We go. John: No.", "My am4zin9 jaaaacket", "Write me at player@example.com"] {
            XCTAssertNil(LearningSafety.confidence(source:text,speaker:"Arthur",speakerConfidence:1,ocr:1,ui:false),text)
        }
        XCTAssertNil(LearningSafety.confidence(source:"We should leave now.",speaker:"Arthur",speakerConfidence:1,ocr:1,ui:true))
        XCTAssertNotNil(LearningSafety.confidence(source:"We should leave now.",speaker:"Arthur",speakerConfidence:0.95,ocr:0.97,ui:false))
    }
    func testAutomaticLearningRequiresIndependentReferenceAndSurvivesRestart() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:root)}
        let store = try ImprovementMemoryStore(root:root)
        var sample = ImprovementExample(game:"test",source:"We should leave now.",context:"Arthur|mission-a",confidence:0.98)
        sample.evidence = LearningSafety.confidence(source:sample.source,speaker:"Arthur",speakerConfidence:0.96,ocr:0.98,ui:false)
        for _ in 0..<3 {try store.observe(sample,consent:true)}
        XCTAssertEqual(try store.approveAutomatic(),0,"Repeated model output is not authority")
        sample.trustedTarget = "علينا المغادرة الآن."; sample.authority = "pack-exact:fixture"
        try store.observe(sample,consent:true)
        XCTAssertEqual(try store.approveAutomatic(),1)
        let reloaded = try ImprovementMemoryStore(root:root)
        XCTAssertEqual(ImprovedMemorySnapshot(entries:reloaded.approved).lookup(game:"test",source:sample.source,context:sample.context),sample.trustedTarget)
        XCTAssertEqual(try reloaded.approveAutomatic(),0)
    }
    func testSpatialStorePersistsAndDoesNotCrossGameOrVersion() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:root)}
        let url = root.appendingPathComponent("spatial.sqlite")
        do {
            let store = try SpatialMemoryStore(url:url)
            try store.saveTranslation(game:"test",version:"1",source:"Graphics",target:"الرسومات",origin:"packExact",now:100)
            XCTAssertNil(try store.translation(game:"other",version:"1",source:"Graphics"))
        }
        let reloaded = try SpatialMemoryStore(url:url)
        XCTAssertEqual(try reloaded.translation(game:"test",version:"1",source:"Graphics")?.0,"الرسومات")
        XCTAssertNil(try reloaded.translation(game:"test",version:"2",source:"Graphics"))
        XCTAssertFalse(SpatialTarget.valid(source:"Price $120",target:"السعر $130"))
        XCTAssertTrue(SpatialTarget.valid(source:"Price $120",target:"السعر $120"))
    }
    func testScreenMatchingToleratesSmallLayoutChangesButNotNewText() {
        let rows = [OCRLine(text:"Graphics",box:.init(x:0.1,y:0.1,w:0.2,h:0.04)),OCRLine(text:"Audio",box:.init(x:0.1,y:0.2,w:0.2,h:0.04)),OCRLine(text:"Controls",box:.init(x:0.1,y:0.3,w:0.2,h:0.04))]
        XCTAssertEqual(SpatialRecognition.category(rows),.settings)
        let elements = rows.map{SpatialElement(source:$0.text,normalized:SpatialRecognition.key($0.text),translated:"نص",box:$0.box,scale:0.04,dynamic:false,origin:"packExact",confidence:0.98)}
        let moved = rows.map{OCRLine(text:$0.text,box:.init(x:$0.box.x+0.005,y:$0.box.y+0.005,w:$0.box.w,h:$0.box.h))}
        XCTAssertGreaterThan(SpatialRecognition.layoutScore(elements,observed:moved),0.9)
        XCTAssertEqual(SpatialRecognition.layoutScore(elements,observed:[OCRLine(text:"Other screen",box:rows[0].box)]),0)
    }
    func testFuzzyRejectsMeaningChangesAndAmbiguity() {
        XCTAssertNil(PackFuzzyMatching.kind(source:"You should go left now.",reference:"You should go right now."))
        XCTAssertNil(PackFuzzyMatching.kind(source:"We must take 12 coins.",reference:"We must take 13 coins."))
        XCTAssertNil(PackFuzzyMatching.kind(source:"He should leave now please.",reference:"She should leave now please."))
        XCTAssertEqual(PackFuzzyMatching.kind(source:"We must f0llow the road.",reference:"We must follow the road."),.ocrTolerant)
        XCTAssertEqual(PackFuzzyMatching.choose(source:"We must follow the road",candidates:[.init(source:"We must follow the road!",target:"أ"),.init(source:"We must follow the road.",target:"ب")]).kind,.ambiguous)
    }
}
