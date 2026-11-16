import XCTest
@testable import LingoCore

final class QualityMeasurementTests: XCTestCase {
    func testPublishedDenominatorExcludesAttemptsCorrectionsAndSyntheticResults() {
        var metrics = HybridMetrics()
        metrics.lookups = 100; metrics.matches = 100
        metrics.recordAttempt(.rule); metrics.recordAttempt(.reuse)
        XCTAssertEqual(metrics.attemptOrigins[.reuse],1)
        XCTAssertEqual(metrics.published,0)
        XCTAssertFalse(metrics.status(active:true,damaged:false).contains("تعمل"))
        for (id,origin) in [("1",TranslationOrigin.rule),("2",.packExact),("3",.reuse),("4",.argosInference)] {
            metrics.recordPublished(PublishedTranslation(eventID:id,game:"synthetic",pack:"p",origin:origin,fallback:origin == .argosInference ? .missing : nil))
        }
        metrics.recordPublished(PublishedTranslation(eventID:"2",game:"synthetic",pack:"p",origin:.packNormalized,fallback:nil))
        XCTAssertEqual(metrics.published,4); XCTAssertEqual(metrics.publishedPack,1)
        XCTAssertEqual(metrics.origins[.rule],1); XCTAssertEqual(metrics.origins[.reuse],1)
        XCTAssertEqual(metrics.status(active:true,damaged:false),"تعمل · 1 من 4 من الحزمة")
        XCTAssertEqual(metrics.lastEvent?.eventID,"4")
    }
    func testFallbackStatusThresholdAndInactiveDamagedStates() {
        var metrics = HybridMetrics()
        XCTAssertEqual(metrics.status(active:false,damaged:false),"غير مفعّلة (اختر اللعبة)")
        for i in 0..<20 { metrics.recordPublished(PublishedTranslation(eventID:String(i),game:nil,pack:nil,origin:.argosCache,fallback:.ambiguous)) }
        XCTAssertTrue(metrics.status(active:true,damaged:false).contains("20 حوار"))
        XCTAssertTrue(metrics.status(active:true,damaged:false).contains("غامضة"))
        XCTAssertFalse(metrics.status(active:true,damaged:false,threshold:21).contains("السبب"))
        XCTAssertEqual(metrics.status(active:true,damaged:true),"تالفة")
    }
    func testFlagsPersistIndependentlyAndResetReproducesAllOff() {
        let defaults = UserDefaults(suiteName:UUID().uuidString)!
        defer { for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("quality.") { defaults.removeObject(forKey:key) } }
        var flags = QualitySettings()
        XCTAssertTrue(QualityFlag.allCases.allSatisfy{!flags[$0]})
        for flag in QualityFlag.allCases {
            flags[flag] = true; flags.save(defaults)
            XCTAssertTrue(QualitySettings.load(defaults)[flag])
            flags[flag] = false; flags.save(defaults)
            XCTAssertEqual(QualitySettings.load(defaults),QualitySettings())
        }
        for flag in QualityFlag.allCases { flags[flag] = true }
        for flag in QualityFlag.allCases {
            var rollback = flags; rollback[flag] = false
            XCTAssertFalse(rollback[flag])
            XCTAssertEqual(QualityFlag.allCases.filter{rollback[$0]}.count,QualityFlag.allCases.count-1)
        }
        QualitySettings().save(defaults); XCTAssertEqual(QualitySettings.load(defaults).outputKey,"")
    }
    func testLogicalPunctuationHasNoDialogueAndPreservesString() {
        let input = "Arthur: (هل أنت هنا)؟"
        let signature = SubtitlePresentation.punctuation(input)
        XCTAssertTrue(signature.contains("first=L")); XCTAssertTrue(signature.contains("(:middle")); XCTAssertTrue(signature.contains("؟:end"))
        XCTAssertFalse(signature.contains("Arthur")); XCTAssertFalse(signature.contains("أنت"))
        XCTAssertTrue(SubtitlePresentation.punctuation("(نعم!)").contains("first=R"))
        XCTAssertTrue(SubtitlePresentation.punctuation("123").contains("none"))
        XCTAssertEqual(SubtitlePresentation.clean(input),input)
        XCTAssertTrue(SubtitlePresentation.isSafeRenderSignature("visual=RTL; logical first=L; ::middle (:middle ؟:end"))
        XCTAssertFalse(SubtitlePresentation.isSafeRenderSignature("visual=RTL; logical first=L; private-dialogue"))
        XCTAssertFalse(SubtitlePresentation.isSafeRenderSignature(String(repeating:"!",count:1025)))
    }
    func testOptionalTransportAllOffAndIndependentMarkerRollback() throws {
        let baseline: [String:Any] = ["v":1,"type":"subtitle_show","id":"fixture","translated":"تحرك الآن.","source":"Move now."]
        let off = QualitySettings()
        XCTAssertEqual(try TVProtocol.encode(TVProtocol.qualityFields(baseline,settings:off,origin:.packExact)),try TVProtocol.encode(baseline))
        var all = off
        for flag in QualityFlag.allCases { all[flag] = true }
        XCTAssertEqual(TVProtocol.qualityFields(baseline,settings:all,origin:.packExact)["provenance"] as? String,"packExact")
        all[.provenanceMarker] = false
        let markerOff = TVProtocol.qualityFields(baseline,settings:all,origin:.packExact)
        XCTAssertNil(markerOff["provenance"])
        XCTAssertEqual(try TVProtocol.encode(markerOff.filter{baseline.keys.contains($0.key)}),try TVProtocol.encode(baseline))
        all[.provenanceMarker] = true; all[.punctuationTrace] = false
        let traceOff = TVProtocol.qualityFields(baseline,settings:all,origin:.packExact)
        XCTAssertNil(traceOff["quality_trace"]); XCTAssertEqual(traceOff["provenance"] as? String,"packExact")
    }
    func testCaptureConsentBoundsStopRetentionAndReplay() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:folder) }
        let capture = QualityCapture(folder:folder,byteLimit:1800,retention:60)
        let record = QualityCaptureRecord(eventID:"synthetic",lines:[CaptureLine(text:"Move now.",box:.dialogue,confidence:0.9)],parsed:"Move now.",engineInput:"Move now.",engineOutput:"تحرك الآن.",origin:.argosInference)
        try capture.start(consent:false); try capture.append(record)
        XCTAssertNil(capture.export())
        let now = Date(); try capture.start(consent:true,now:now)
        try capture.append(record,now:now)
        let data = try Data(contentsOf:capture.file)
        XCTAssertEqual(try QualityReplay.run(data,translate:{_ in "stub"}),["stub"])
        capture.stop(); try capture.append(record)
        XCTAssertEqual(try Data(contentsOf:capture.file),data)
        let afterTermination = QualityCapture(folder:folder,byteLimit:1800,retention:60)
        XCTAssertFalse(afterTermination.active)
        try capture.start(consent:true)
        for _ in 0..<100 { try capture.append(record) }
        XCTAssertFalse(capture.active)
        XCTAssertLessThanOrEqual(try Data(contentsOf:capture.file).count,1800)
        capture.prune(now:Date().addingTimeInterval(61)); XCTAssertNil(capture.export())
        try capture.start(consent:true); try capture.delete(); XCTAssertNil(capture.export())
    }
    func testCaptureStopsAfterThirtyMinutes() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:folder) }
        let capture = QualityCapture(folder:folder), now = Date()
        try capture.start(consent:true,now:now)
        try capture.append(QualityCaptureRecord(eventID:"1",lines:[],parsed:"",engineInput:"",engineOutput:"",origin:.rule),now:now.addingTimeInterval(1801))
        XCTAssertFalse(capture.active)
        XCTAssertEqual(try Data(contentsOf:capture.file).count,0)
    }
    func testDeterministicSyntheticJSONLReplayUsesExplicitStub() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource:"quality-replay",withExtension:"jsonl"))
        let data = try Data(contentsOf:url)
        let records = try data.split(separator:10).map { try JSONDecoder().decode(QualityCaptureRecord.self,from:Data($0)) }
        let authored = Dictionary(uniqueKeysWithValues:records.map{($0.engineInput,$0.engineOutput)})
        let first = try QualityReplay.run(data,translate:{authored[$0] ?? "MISSING STUB"})
        XCTAssertEqual(first,records.map(\.engineOutput))
        XCTAssertEqual(first,try QualityReplay.run(data,translate:{authored[$0] ?? "MISSING STUB"}))
        XCTAssertEqual(records.count,6)
    }
}
