import XCTest
@testable import LingoCore

final class Maintenance021Tests: XCTestCase {
    private func line(_ text: String,_ x: Double,_ y: Double,_ w: Double,_ h: Double = 0.035,_ confidence: Double = 0.95) -> OCRLine {
        OCRLine(text:text,box:SourceBox(x:x,y:y,w:w,h:h),confidence:confidence)
    }
    func testInlineNamesApostrophesPeriodsAndFalseLabels() {
        for name in ["Arthur","John","Master Chief","Lara Croft","O'Brien","Dr. Smith"] {
            let read = DialogueContent.parse(name+": Move now.",knownNames:"")
            XCTAssertEqual(read.speaker,name); XCTAssertEqual(read.text,"Move now.")
        }
        for label in ["WARNING","MISSION","OBJECTIVE","PRESS","HOLD","INVENTORY","OPTIONS","PLEASE","WAIT","RELOAD"] {
            XCTAssertNil(DialogueContent.parse(label+": Move now.",knownNames:label).speaker,label)
        }
    }
    func testStructuredAboveAndSmallerNameKeepOnlyDialogueBox() {
        for name in ["ARTHUR","MASTER CHIEF","Dr. Smith"] {
            let body = line("We need to leave now.",0.25,0.78,0.5)
            let label = line(name,0.4,0.747,0.2,0.018)
            let read = StructuredDialogue.resolve([body,label],roi:.dialogue,knownNames:"")
            XCTAssertEqual(read?.content.speaker,name)
            XCTAssertEqual(read?.content.text,body.text)
            XCTAssertEqual(read?.box,body.box)
        }
    }
    func testStructuredLeftAndRightSideNamesAndWrapping() {
        for x in [0.2,0.72] {
            let read = StructuredDialogue.resolve([line("Arthur",x,0.78,0.08,0.025),
                line("We need to leave now.",0.31,0.78,0.4),line("Before the guards arrive.",0.31,0.82,0.4)],roi:.dialogue,knownNames:"")
            XCTAssertEqual(read?.content.speaker,"Arthur")
            XCTAssertEqual(read?.content.text,"We need to leave now. Before the guards arrive.")
        }
    }
    func testStructuredDoesNotGuessWithoutEvidence() {
        let body = line("We need to leave now.",0.25,0.78,0.5)
        XCTAssertNil(StructuredDialogue.resolve([body],roi:.dialogue,knownNames:""))
        for label in [line("Arthur",0.4,0.747,0.15,0.018,0.2),line("Arthur",0.05,0.2,0.15),line("WAIT",0.4,0.747,0.15,0.018)] {
            XCTAssertNil(StructuredDialogue.resolve([label,body],roi:.dialogue,knownNames:""))
        }
    }
    func testTwentyObservationsKeepOneEventAndLateIdenticalReadingIsNotNew() {
        var tracker = DialogueTracker(); var jobs: [DialogueJob] = []
        for i in 0..<20 {
            if case .dialogue(let job,_) = tracker.observe(text:i%2==0 ? "We need to leave." : "We need to leave!",box:.dialogue,now:Double(i)*0.4,frameMilliseconds:Int64(i)*400,speaker:i%3==0 ? "Arthur" : nil) { jobs.append(job) }
        }
        XCTAssertEqual(jobs.count,1); XCTAssertEqual(tracker.duplicatesSuppressed,19)
        guard case .unchanged = tracker.observe(text:"We need to leave.",box:.dialogue,now:30,frameMilliseconds:30000,speaker:"Arthur") else { return XCTFail("A callback gap is not evidence of a new utterance") }
    }
    func testShortOCRDropoutDoesNotAllocateIDButConfirmedGapDoes() {
        var t = DialogueTracker()
        guard case .dialogue(let a,_) = t.observe(text:"Wait here.",box:.dialogue,now:0,frameMilliseconds:0) else { return XCTFail() }
        for time in [0.2,0.4] { _ = t.observe(text:"",box:.dialogue,now:time,frameMilliseconds:0) }
        guard case .unchanged = t.observe(text:"Wait here.",box:.dialogue,now:0.5,frameMilliseconds:500) else { return XCTFail() }
        _ = t.observe(text:"",box:.dialogue,now:0.7,frameMilliseconds:700)
        guard case .gone = t.observe(text:"",box:.dialogue,now:1.4,frameMilliseconds:1400) else { return XCTFail() }
        guard case .dialogue(let b,_) = t.observe(text:"Wait here.",box:.dialogue,now:1.5,frameMilliseconds:1500) else { return XCTFail() }
        XCTAssertNotEqual(a.id,b.id); XCTAssertEqual(b.eventBoundary,"source_gap"); XCTAssertGreaterThanOrEqual(b.sourceGapMilliseconds,750)
    }
    func testSpeakerEnrichmentAndInterveningDialoguePreserveRealRepetition() {
        var t = DialogueTracker()
        guard case .dialogue(let first,_) = t.observe(text:"Wait here.",box:.dialogue,now:0,frameMilliseconds:0) else { return XCTFail() }
        guard case .dialogue(let named,_) = t.observe(text:"Wait here.",box:.dialogue,now:0.2,frameMilliseconds:200,speaker:"Arthur") else { return XCTFail() }
        XCTAssertEqual(first.id,named.id); XCTAssertTrue(t.accepts(first))
        _ = t.observe(text:"What happened?",box:.dialogue,now:0.4,frameMilliseconds:400,speaker:"John")
        guard case .dialogue(let again,_) = t.observe(text:"Wait here.",box:.dialogue,now:0.6,frameMilliseconds:600,speaker:"Arthur") else { return XCTFail() }
        XCTAssertNotEqual(again.id,first.id)
    }
    func testCaseOnlySpeakerChangeAndLateEnrichmentCannotReplayAfterInterruption() {
        var t = DialogueTracker()
        guard case .dialogue(let first,_) = t.observe(text:"Wait here.",box:.dialogue,now:0,frameMilliseconds:0,speaker:"ARTHUR") else { return XCTFail() }
        guard case .unchanged = t.observe(text:"Wait here!",box:.dialogue,now:0.2,frameMilliseconds:200,speaker:"Arthur") else { return XCTFail() }
        XCTAssertEqual(first.id,t.current?.id)
        var doctor = DialogueTracker()
        _ = doctor.observe(text:"Wait here.",box:.dialogue,now:0,frameMilliseconds:0,speaker:"Dr. Smith")
        guard case .unchanged = doctor.observe(text:"Wait here.",box:.dialogue,now:0.2,frameMilliseconds:200,speaker:"Dr Smith") else { return XCTFail("Name punctuation alone is not a new person") }
        var unnamed = DialogueTracker()
        _ = unnamed.observe(text:"Wait here.",box:.dialogue,now:0,frameMilliseconds:0)
        unnamed.markInterrupted()
        guard case .unchanged = unnamed.observe(text:"Wait here.",box:.dialogue,now:20,frameMilliseconds:20000,speaker:"Arthur") else { return XCTFail("Enriching an old line must not replay it") }
    }
    func testCanonicalGlyphAliasesCannotHideChangedProperDestination() {
        var t = DialogueTracker()
        guard case .dialogue(let a,_) = t.observe(text:"Go to Berlin",box:.dialogue,now:0,frameMilliseconds:0) else { return XCTFail() }
        guard case .dialogue(let b,_) = t.observe(text:"Go to Beriin",box:.dialogue,now:0.2,frameMilliseconds:200) else { return XCTFail() }
        XCTAssertNotEqual(a.id,b.id);XCTAssertFalse(t.accepts(a))
    }
    func testMissingWordsAndWrappingRetainBestReference() {
        var t = DialogueTracker()
        guard case .dialogue(let a,_) = t.observe(text:"Something happened near the gate.",box:.dialogue,now:0,frameMilliseconds:0) else { return XCTFail() }
        for (i,text) in ["Something happened near gate.","Something happened\nnear the gate!","Somethlng happened near the gate."].enumerated() {
            _ = t.observe(text:text,box:.dialogue,now:Double(i+1)*0.2,frameMilliseconds:0,confidence:0.6)
            XCTAssertEqual(t.current?.id,a.id)
        }
        XCTAssertEqual(t.current?.text,"Something happened near the gate.")
    }
    func testHighConfidenceDifferentInstructionsAreNewEvenDuringAcquisition() {
        for (a,b) in [("We will go","We will not go"),("Go left","Go right"),("Collect 10 coins","Collect 11 coins"),("He is coming","She is coming"),("Open the door","Close the door"),("Follow the trail","Follow the train"),("Wait here","Wait there")] {
            XCTAssertFalse(DialogueText.same(a,b))
            var t = DialogueTracker()
            guard case .dialogue(let old,_) = t.observe(text:a,box:.dialogue,now:0,frameMilliseconds:0) else { return XCTFail() }
            guard case .dialogue(let new,_) = t.observe(text:b,box:.dialogue,now:0.2,frameMilliseconds:200) else { return XCTFail() }
            XCTAssertNotEqual(old.id,new.id,"\(a) -> \(b)")
        }
    }
    func testPunctuationAndQuotesSurviveEveryWirePresentationStage() throws {
        let text = "(تحرك الآن) [صوت إطلاق نار] «John» قال: اجمع 11 قطعة، ثم اسأل: لماذا؟"
        XCTAssertEqual(SubtitlePresentation.clean(text),text)
        XCTAssertEqual(SubtitlePresentation.clean("\u{202e}"+text+"\u{2069}"),text)
        let job = DialogueJob(id:"fixture",text:"(Move now.)",generation:1,correction:false,box:.dialogue,frameMilliseconds:0)
        let decoded = try TVProtocol.decode(TVProtocol.encode(TVProtocol.subtitle(job,arabic:text,now:100)))
        XCTAssertEqual(decoded["translated"] as? String,text)
        XCTAssertFalse(SubtitlePresentation.punctuation(text).contains("John"))
    }
    func testRetryOwnershipCountersAndStopRejectStaleSuccess() {
        var r = RecoveryAccounting(); r.initial(now:0)
        XCTAssertFalse(r.reserveRecovery(hasSession:true,stalled:true,age:20,now:20)) // Still connecting.
        XCTAssertTrue(r.established(now:1)); XCTAssertEqual(r.metrics.successes,0)
        r.ended(); r.scheduleRetry()
        for _ in 0..<20 { XCTAssertFalse(r.reserveRecovery(hasSession:false,stalled:false,age:20,now:2)) }
        XCTAssertTrue(r.beginRetry(now:3)); XCTAssertFalse(r.beginRetry(now:3))
        XCTAssertEqual(r.metrics.attempts,1)
        XCTAssertTrue(r.established(now:4)); XCTAssertFalse(r.established(now:4.1))
        XCTAssertEqual(r.metrics.successes,1); XCTAssertEqual(r.metrics.lastRecoverySeconds,1)
        r.ended();r.scheduleRetry();XCTAssertTrue(r.beginRetry(now:6));r.ended()
        XCTAssertEqual(r.metrics.attempts,2);XCTAssertEqual(r.metrics.failures,1)
        r.scheduleRetry();r.stop();XCTAssertFalse(r.beginRetry(now:10));XCTAssertFalse(r.established(now:11))
    }
    func testStarvationThresholdAndLoginRemainProtected() {
        var r = RecoveryAccounting();r.initial(now:0);r.established(now:1)
        XCTAssertFalse(r.reserveRecovery(hasSession:true,stalled:false,age:20,now:20))
        XCTAssertFalse(r.reserveRecovery(hasSession:true,stalled:true,age:12,now:20))
        XCTAssertTrue(r.reserveRecovery(hasSession:true,stalled:true,age:12.1,now:20))
        XCTAssertFalse(r.reserveRecovery(hasSession:true,stalled:true,age:20,now:21))
        XCTAssertEqual(r.metrics.starvations,1);XCTAssertEqual(r.metrics.attempts,1)
        r.loginRequired();XCTAssertFalse(r.reserveRecovery(hasSession:true,stalled:true,age:30,now:30))
        r.loginSubmitted();r.established(now:31);XCTAssertEqual(r.metrics.successes,1)
    }
    func testDiagnosticsAreBoundedAndCaptureStateWithoutDialogue() {
        var log = SessionDiagnostics()
        for i in 0..<200 { log.record("reconnect.attempt",detail:"native retry",now:Double(i),foreground:false,network:true,interrupted:false) }
        XCTAssertEqual(log.lines.count,80);XCTAssertTrue(log.lines.last!.contains("fg=false net=true"))
    }
    func testSyntheticMaintenanceWorkload() {
        let start = ProcessInfo.processInfo.systemUptime
        var t = DialogueTracker()
        for i in 0..<1000 {
            let content = StructuredDialogue.resolve([line("Arthur",0.2,0.78,0.08,0.025),line("We need to leave now.",0.31,0.78,0.4)],roi:.dialogue,knownNames:"")!
            _ = t.observe(text:content.content.text,box:content.box,now:Double(i)*0.35,frameMilliseconds:Int64(i)*350,speaker:content.content.speaker)
        }
        XCTAssertEqual(t.duplicatesSuppressed,999)
        print("SYNTHETIC_021_MAINTENANCE 1000 structured observations ms=\((ProcessInfo.processInfo.systemUptime-start)*1000); not physical iPhone")
    }
}
