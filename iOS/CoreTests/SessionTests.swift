import XCTest
@testable import LingoCore

final class SessionTests: XCTestCase {
    func testManualStopDominatesAllRecoveryTriggers() {
        var policy = SessionPolicy(); policy.start(); let old = policy.epoch
        policy.stop(); policy.audioActive = true; policy.foreground = true; policy.network = true
        XCTAssertFalse(policy.canRecover); XCTAssertFalse(policy.accepts(old))
    }
    func testAppSwitchAndLockNeedActiveExperiment() {
        var policy = SessionPolicy(); policy.start(); policy.foreground = false
        XCTAssertFalse(policy.canRecover)
        policy.experimentalAudio = true; policy.audioActive = true
        XCTAssertTrue(policy.canRecover)
        policy.interrupted = true
        XCTAssertTrue(policy.wanted); XCTAssertFalse(policy.canRecover)
        policy.interrupted = false; XCTAssertTrue(policy.canRecover)
    }
    func testNetworkAndForegroundAreIndependentOfAudio() {
        var policy = SessionPolicy(); policy.start(); policy.network = false
        XCTAssertFalse(policy.canRecover); XCTAssertTrue(policy.wanted)
        policy.network = true; policy.interrupted = true
        XCTAssertTrue(policy.canRecover)
        policy.foreground = false; XCTAssertFalse(policy.canRecover)
    }
    func testRetriesBoundedWithJitterAndOldStartInvalidated() {
        XCTAssertEqual((0...5).map { SessionPolicy.retryDelay($0) },[2,4,8,15,30,30])
        XCTAssertEqual(SessionPolicy.retryDelay(100,jitter:10),31)
        var policy = SessionPolicy(); policy.start(); let old = policy.epoch; policy.stop(); policy.start()
        XCTAssertFalse(policy.accepts(old))
    }
    func testOldSettingsMigrateWithoutLosingConsoleOrStyle() throws {
        let data = Data(#"{"display":{"values":{"font_size":31},"revision":2},"roi":{"x":0.16,"y":0.65,"w":0.68,"h":0.28},"mode":"economy","selectedConsoleID":"existing-ps5","localIP":"192.168.3.179","dimScreen":true}"#.utf8)
        let settings = try JSONDecoder().decode(AppSettings.self,from:data)
        XCTAssertEqual(settings.selectedConsoleID,"existing-ps5"); XCTAssertEqual(settings.display.number("font_size"),31)
        XCTAssertFalse(settings.advanced.backgroundAudio); XCTAssertEqual(settings.advanced.contextCapacity,5)
    }
    func testReconnectDoesNotRepublishStillVisibleOldLine() {
        var tracker = DialogueTracker()
        _ = tracker.observe(text:"Wait here.",box:.dialogue,now:0,frameMilliseconds:0)
        tracker.markInterrupted()
        guard case .unchanged = tracker.observe(text:"Wait here!",box:.dialogue,now:20,frameMilliseconds:20000) else { return XCTFail() }
        _ = tracker.observe(text:"",box:.dialogue,now:21,frameMilliseconds:21000)
        _ = tracker.observe(text:"",box:.dialogue,now:22,frameMilliseconds:22000)
        guard case .dialogue = tracker.observe(text:"Wait here.",box:.dialogue,now:23,frameMilliseconds:23000) else { return XCTFail() }
    }
}
