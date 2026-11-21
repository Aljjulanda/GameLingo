import XCTest
@testable import LingoCore

final class StreamRecoveryPolicyTests: XCTestCase {
    func testTransientSilenceAndDecoderOnlyStallNeverReplaceHealthyNativeSession() {
        var p = StreamRecoveryPolicy()
        XCTAssertFalse(p.replacementNeeded(encodedAge:0.1,decodedAge:40,sessionAge:100,now:100))
        XCTAssertFalse(p.replacementNeeded(encodedAge:30,decodedAge:30,sessionAge:100,now:101))
        XCTAssertFalse(p.replacementNeeded(encodedAge:0.1,decodedAge:0.1,sessionAge:100,now:103))
        XCTAssertFalse(p.replacementNeeded(encodedAge:30,decodedAge:30,sessionAge:100,now:110))
        XCTAssertFalse(p.replacementNeeded(encodedAge:32,decodedAge:32,sessionAge:100,now:112))
        XCTAssertTrue(p.replacementNeeded(encodedAge:35,decodedAge:35,sessionAge:100,now:115))
        XCTAssertFalse(p.replacementNeeded(encodedAge:40,decodedAge:40,sessionAge:100,now:120))
        XCTAssertFalse(p.replacementNeeded(encodedAge:50,decodedAge:50,sessionAge:100,now:130))
        XCTAssertTrue(p.replacementNeeded(encodedAge:90,decodedAge:90,sessionAge:100,now:176))
    }
    func testNoEvidenceDoesNotInventStarvationAndBackoffIsBounded() {
        var p = StreamRecoveryPolicy()
        XCTAssertFalse(p.replacementNeeded(encodedAge:nil,decodedAge:nil,sessionAge:100,now:100))
        XCTAssertFalse(p.replacementNeeded(encodedAge:30,decodedAge:30,sessionAge:2,now:100))
        XCTAssertEqual((1...9).map(StreamRecoveryPolicy.delay),[2,4,8,15,30,60,60,60,60])
    }
}
