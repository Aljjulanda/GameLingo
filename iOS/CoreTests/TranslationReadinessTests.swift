import XCTest
@testable import LingoCore

final class TranslationReadinessTests: XCTestCase {
    private func ready(_ destination: DisplayDestination) -> TranslationReadiness {
        TranslationReadiness(modelReady:true,hasConsole:true,validRegion:true,importing:false,pairing:false,destination:destination,tvConnected:false)
    }
    func testPhoneNeedsNoTVPairing() {
        let state = ready(.phone)
        XCTAssertTrue(state.canStart)
        XCTAssertTrue(state.canFinishSetup)
        XCTAssertFalse(state.waitingForTV)
    }
    func testBothCanStartWithLocalOutputWhileTVIsMissing() {
        var state = ready(.both)
        XCTAssertTrue(state.canStart)
        XCTAssertTrue(state.waitingForTV)
        XCTAssertTrue(state.canFinishSetup)
        state.tvConnected = true
        XCTAssertFalse(state.waitingForTV)
        XCTAssertEqual(state.nextStep,.ready)
    }
    func testTVOnlyCanStartListenerButDoesNotClaimTVIsReady() {
        let state = ready(.television)
        XCTAssertTrue(state.canStart)
        XCTAssertTrue(state.waitingForTV)
        XCTAssertFalse(state.canFinishSetup)
        XCTAssertTrue(state.title.contains("غير متصل"))
    }
    func testTVSetupFinishesOnlyAfterSelectedOutputConnects() {
        var state = ready(.television)
        state.tvConnected = true
        XCTAssertTrue(state.canFinishSetup)
        state.modelReady = false
        XCTAssertFalse(state.canFinishSetup)
    }
    func testSetupExplainsActualBlockingStepAndRecovers() {
        var state = ready(.phone)
        state.hasConsole = false; state.modelReady = false
        XCTAssertEqual(state.nextStep,.model)
        state.modelReady = true
        XCTAssertEqual(state.nextStep,.console)
        state.hasConsole = true; state.validRegion = false
        XCTAssertEqual(state.nextStep,.region)
        XCTAssertFalse(state.canStart)
        state.validRegion = true
        XCTAssertTrue(state.canStart)
    }
    func testBusyOperationsCannotStartAnotherSession() {
        var state = ready(.both)
        state.importing = true
        XCTAssertEqual(state.nextStep,.importing)
        XCTAssertFalse(state.canStart)
        state.pairing = true
        XCTAssertEqual(state.nextStep,.pairing)
        state.pairing = false; state.importing = false
        XCTAssertTrue(state.canStart)
    }
}
