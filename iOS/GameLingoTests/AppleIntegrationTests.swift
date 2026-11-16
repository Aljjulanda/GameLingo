import XCTest
import UIKit
import CoreVideo
import VideoToolbox
import CryptoKit
import CoreImage
import Vision
import Network
import AVFAudio
@testable import GameLingo

final class AppleIntegrationTests: XCTestCase {
    private func visionFixture(_ draw: (UIGraphicsImageRendererContext) -> Void) throws -> CVPixelBuffer {
        let image = UIGraphicsImageRenderer(size:CGSize(width:1280,height:720)).image { context in
            UIColor.black.setFill();context.fill(CGRect(x:0,y:0,width:1280,height:720));draw(context)
        }
        var value: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault,1280,720,kCVPixelFormatType_32BGRA,[kCVPixelBufferCGImageCompatibilityKey:true,kCVPixelBufferCGBitmapContextCompatibilityKey:true] as CFDictionary,&value),kCVReturnSuccess)
        let buffer = try XCTUnwrap(value)
        CVPixelBufferLockBaseAddress(buffer,[]);defer { CVPixelBufferUnlockBaseAddress(buffer,[]) }
        let bitmap = try XCTUnwrap(CGContext(data:CVPixelBufferGetBaseAddress(buffer),width:1280,height:720,bitsPerComponent:8,bytesPerRow:CVPixelBufferGetBytesPerRow(buffer),space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedFirst.rawValue|CGBitmapInfo.byteOrder32Little.rawValue))
        bitmap.translateBy(x:0,y:720);bitmap.scaleBy(x:1,y:-1)
        UIGraphicsPushContext(bitmap);image.draw(in:CGRect(x:0,y:0,width:1280,height:720));UIGraphicsPopContext();bitmap.flush()
        // Match VideoDecoder's actual 420v/IOSurface input. BGRA-only synthetic
        // buffers repeatedly crashed MTLSimDriver while converting formats;
        // production already supplies video-range NV12. Keep foreground Vision.
        var video: CVPixelBuffer?
        let attributes: [String:Any] = [kCVPixelBufferMetalCompatibilityKey as String:true,kCVPixelBufferIOSurfacePropertiesKey as String:[:]]
        XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault,1280,720,kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,attributes as CFDictionary,&video),kCVReturnSuccess)
        let nv12 = try XCTUnwrap(video)
        CVPixelBufferLockBaseAddress(nv12,[]); defer { CVPixelBufferUnlockBaseAddress(nv12,[]) }
        let source = try XCTUnwrap(CVPixelBufferGetBaseAddress(buffer)).assumingMemoryBound(to:UInt8.self)
        let luma = try XCTUnwrap(CVPixelBufferGetBaseAddressOfPlane(nv12,0)).assumingMemoryBound(to:UInt8.self)
        let chroma = try XCTUnwrap(CVPixelBufferGetBaseAddressOfPlane(nv12,1))
        let sourceStride = CVPixelBufferGetBytesPerRow(buffer), yStride = CVPixelBufferGetBytesPerRowOfPlane(nv12,0)
        for y in 0..<720 { for x in 0..<1280 {
            let offset = y*sourceStride+x*4
            let gray = (29*Int(source[offset])+150*Int(source[offset+1])+77*Int(source[offset+2]))/256
            luma[y*yStride+x] = UInt8(16+(219*gray+127)/255)
        } }
        // Every fixture here is white text on black: neutral chroma is exact.
        memset(chroma,128,CVPixelBufferGetBytesPerRowOfPlane(nv12,1)*CVPixelBufferGetHeightOfPlane(nv12,1))
        XCTAssertEqual(CVPixelBufferGetPixelFormatType(nv12),kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)
        return nv12
    }
    func testVisionStructuredSpeakerAboveAndOnBothSides() throws {
        for layout in ["above","left","right"] {
            try autoreleasepool {
            let pixels = try visionFixture { _ in
                let body = "We need to leave now."
                let bodyX: CGFloat = layout == "left" ? 370 : 270
                (body as NSString).draw(at:CGPoint(x:bodyX,y:530),withAttributes:[.font:UIFont.systemFont(ofSize:34),.foregroundColor:UIColor.white])
                let point = layout == "above" ? CGPoint(x:420,y:485) : layout == "left" ? CGPoint(x:225,y:533) : CGPoint(x:770,y:533)
                ("Arthur" as NSString).draw(at:point,withAttributes:[.font:UIFont.systemFont(ofSize:25),.foregroundColor:UIColor.white])
            }
            let ocr = VisionDialogueOCR()
            _ = try ocr.recognize(pixels,roi:.dialogue,knownNames:"Arthur")
            XCTAssertEqual(ocr.content.speaker?.lowercased(),"arthur",layout+": "+ocr.content.text)
            XCTAssertTrue(ocr.content.text.lowercased().contains("we need to leave"),layout+": "+ocr.content.text)
            XCTAssertFalse(ocr.content.text.lowercased().contains("arthur"),layout)
            }
        }
    }
    func testVisionWrappedSpeakerIsExcludedFromEngineSource() throws {
        for label in ["(Arthur)","[Arthur]"] {
            try autoreleasepool {
            let pixels = try visionFixture { _ in
                (label+" We need to leave now." as NSString).draw(at:CGPoint(x:250,y:530),withAttributes:[.font:UIFont.systemFont(ofSize:32),.foregroundColor:UIColor.white])
            }
            let ocr = VisionDialogueOCR(); _ = try ocr.recognize(pixels,roi:.dialogue,knownNames:"Arthur")
            XCTAssertEqual(ocr.content.speaker?.lowercased(),"arthur")
            XCTAssertTrue(ocr.content.text.lowercased().contains("we need to leave"))
            XCTAssertFalse(ocr.content.text.lowercased().contains("arthur"))
            }
        }
    }
    func testQualityVisionNamesDictionaryDoesNotDegradeOrdinaryWords() throws {
        var nameCorrect = [0,0], ordinaryCorrect = [0,0]
        for source in ["Quillan: We should leave now.","The Stranger: We should leave now.","Wait: do not open the door.","Look: the river is deep."] {
            try autoreleasepool {
            let pixels = try visionFixture { _ in
                let font = UIFont.systemFont(ofSize:30)
                let width = (source as NSString).size(withAttributes:[.font:font]).width
                (source as NSString).draw(at:CGPoint(x:(1280-width)/2,y:530),withAttributes:[.font:font,.foregroundColor:UIColor.white])
            }
            for enabled in [false,true] {
                try autoreleasepool {
                let ocr = VisionDialogueOCR(); ocr.quality[.visionNames] = enabled
                ocr.quality[.speakerClassification] = true
                ocr.captureLines = true // Synthetic fixture observations only; no file recorder.
                let (text,_) = try ocr.recognize(pixels,roi:.dialogue,knownNames:"Quillan,The Stranger")
                XCTAssertEqual(DialogueText.exactWords(ocr.lastLines.map(\.text).joined(separator:" ")),DialogueText.exactWords(source),"Compare raw Vision output separately from dialogue-region selection")
                XCTAssertTrue(ocr.usesLanguageCorrection)
                XCTAssertEqual(ocr.configuredCustomWords,enabled ? ["Quillan","The Stranger"] : [])
                let index = enabled ? 1 : 0
                if source.hasPrefix("Quillan:") || source.hasPrefix("The Stranger:") {
                    let expected = String(source.split(separator:":")[0])
                    if ocr.content.speaker?.lowercased() == expected.lowercased() { nameCorrect[index] += 1 }
                    XCTAssertEqual(ocr.content.speaker,expected)
                } else {
                    if DialogueText.exactWords(text) == DialogueText.exactWords(source) { ordinaryCorrect[index] += 1 }
                    XCTAssertEqual(DialogueText.exactWords(text),DialogueText.exactWords(source))
                    XCTAssertNil(ocr.content.speaker,"Ordinary prefix must remain dialogue")
                }
                }
            }
            }
        }
        XCTAssertGreaterThanOrEqual(nameCorrect[1],nameCorrect[0]); XCTAssertEqual(nameCorrect[1],2)
        XCTAssertGreaterThanOrEqual(ordinaryCorrect[1],ordinaryCorrect[0]); XCTAssertEqual(ordinaryCorrect[1],2)
        print("SYNTHETIC_VISION_DICTIONARY name_correct=\(nameCorrect) ordinary_correct=\(ordinaryCorrect); clear synthetic glyphs, not game OCR quality")
    }
    func testQualityVisionRecognizedCueDoesNotEnterEngineInput() throws {
        let pixels = try visionFixture { _ in
            let source = "[laughs] We should leave now." as NSString, font = UIFont.systemFont(ofSize:31)
            let width = source.size(withAttributes:[.font:font]).width
            source.draw(at:CGPoint(x:(1280-width)/2,y:530),withAttributes:[.font:font,.foregroundColor:UIColor.white])
        }
        let ocr = VisionDialogueOCR(); ocr.quality[.stageCues] = true; ocr.quality[.speakerClassification] = true
        _ = try ocr.recognize(pixels,roi:.dialogue)
        XCTAssertEqual(ocr.content.engineText,"We should leave now.")
        XCTAssertEqual(ocr.content.cue,"(ضحك)"); XCTAssertNil(ocr.content.speaker)
    }
    func testQualityPipelineCueBypassAndBodyRuleWorkWithoutAModel() throws {
        for only in [false,true] {
            try autoreleasepool {
            let pixels = try visionFixture { _ in
                ((only ? "[laughs]" : "[laughs] We should leave now.") as NSString).draw(at:CGPoint(x:only ? 550 : 350,y:530),withAttributes:[.font:UIFont.systemFont(ofSize:31),.foregroundColor:UIColor.white])
            }
            let translator = OfflineTranslator(folder:FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
            // The production sample() already drains an autorelease pool per
            // OCR frame. Match that lifetime here; keep foreground/GPU settings.
            // Measure cold host initialization separately from the existing
            // 45-second publication assertion, as in the Smart Reading fixture.
            let cold = ProcessInfo.processInfo.systemUptime
            try autoreleasepool { _ = try VisionDialogueOCR().recognize(pixels,roi:.dialogue) }
            print("SYNTHETIC_VISION_COLD_HOST_MS \((ProcessInfo.processInfo.systemUptime-cold)*1000)")
            XCTAssertFalse(translator.installed)
            let published = expectation(description:"Cue and body bypass require no model")
            let pipeline = FramePipeline(translator:translator) { message in
                guard message["type"] as? String == "subtitle_show" else { return }
                XCTAssertEqual(message["translated"] as? String,only ? "(ضحك)" : "علينا المغادرة الآن.")
                XCTAssertEqual(message["cue"] as? String,"(ضحك)")
                XCTAssertEqual(message["cue_only"] as? Bool,only ? true : nil)
                published.fulfill()
            }
            var q = QualitySettings(); q[.stageCues] = true; q[.speakerClassification] = true
            pipeline.configureQuality(q)
            var advanced = AdvancedSettings(); advanced.terminology = "We should leave now.=علينا المغادرة الآن."
            pipeline.configureAdvanced(advanced); pipeline.start(roi:.dialogue,mode:.balanced)
            DispatchQueue.global().asyncAfter(deadline:.now()+0.5) { pipeline.offer(pixels) }
            wait(for:[published],timeout:45); pipeline.stop()
            }
        }
    }
    func testQualityPipelineExplicitCorrectionPrecedesBodyRuleAndRollsBack() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let store = try GameCorrectionsStore(root:root,game:"synthetic")
        try store.save(source:"We should leave now.",target:"حان وقت الرحيل.")
        for enabled in [true,false] {
            try autoreleasepool {
                let pixels = try visionFixture { _ in
                    let text = "[laughs] We should leave now." as NSString
                    let font = UIFont.systemFont(ofSize:31)
                    let width = text.size(withAttributes:[.font:font]).width
                    text.draw(at:CGPoint(x:(1280-width)/2,y:530),withAttributes:[.font:font,.foregroundColor:UIColor.white])
                }
                try autoreleasepool { _ = try VisionDialogueOCR().recognize(pixels,roi:.dialogue) }
                let translator = OfflineTranslator(folder:root.appendingPathComponent("no-model"))
                XCTAssertFalse(translator.installed)
                let shown = expectation(description:"Actual correction/rule pipeline without model")
                let pipeline = FramePipeline(translator:translator) { message in
                    guard message["type"] as? String == "subtitle_show" else { return }
                    XCTAssertEqual(message["translated"] as? String,enabled ? "حان وقت الرحيل." : "علينا المغادرة الآن.")
                    XCTAssertEqual(message["cue"] as? String,"(ضحك)")
                    XCTAssertEqual(message["provenance"] as? String,enabled ? "userCorrection" : "rule")
                    shown.fulfill()
                }
                var q = QualitySettings(); q[.corrections] = enabled; q[.stageCues] = true; q[.provenanceMarker] = true
                pipeline.configureQuality(q); pipeline.configureCorrections(store.snapshot)
                var advanced = AdvancedSettings(); advanced.terminology = "We should leave now.=علينا المغادرة الآن."
                pipeline.configureAdvanced(advanced); pipeline.start(roi:.dialogue,mode:.balanced)
                DispatchQueue.global().asyncAfter(deadline:.now()+0.5) { pipeline.offer(pixels) }
                wait(for:[shown],timeout:45); pipeline.stop()
            }
        }
    }
    func testQualityVisionStoredDictionaryRefreshAndRollback() throws {
        let source = "We should leave now."
        let pixels = try visionFixture { _ in
            let font = UIFont.systemFont(ofSize:31), text = source as NSString
            let width = text.size(withAttributes:[.font:font]).width
            text.draw(at:CGPoint(x:(1280-width)/2,y:530),withAttributes:[.font:font,.foregroundColor:UIColor.white])
        }
        let ocr = VisionDialogueOCR()
        for (enabled,word) in [(true,"Arthur"),(true,"John"),(false,"John")] {
            try autoreleasepool {
                ocr.quality[.visionNames] = enabled
                let (text,_) = try ocr.recognize(pixels,roi:.dialogue,knownNames:"",dictionaryNames:word)
                XCTAssertEqual(ocr.configuredCustomWords,enabled ? [word] : [])
                XCTAssertEqual(DialogueText.exactWords(text),DialogueText.exactWords(source))
                XCTAssertNil(ocr.content.speaker)
            }
        }
    }
    func testNativeArgosAndContextRuleBenchmarkOnSyntheticDialogue() throws {
        let folder = try XCTUnwrap(Bundle(for:Self.self).url(forResource:"en_ar",withExtension:nil))
        var error: NSError?
        let engine = try XCTUnwrap(GLTranslation(modelPath:folder.path,error:&error))
        var context = DialogueMemory()
        context.observe(DialogueJob(id:"river-fixture",text:"The river is deep",generation:1,correction:false,box:.dialogue,frameMilliseconds:0),now:0)
        let rules = "river | Wait near the bank. = انتظر قرب ضفة النهر.\nCollect 11 coins. = اجمع 11 قطعة نقدية."
        var records: [[String:Any]] = []
        for source in ["Wait near the bank.","Collect 11 coins.","We will not go to the camp."] {
            let start = ProcessInfo.processInfo.systemUptime
            let baseline = try XCTUnwrap(engine.translate(source,error:&error))
            let baselineMS = (ProcessInfo.processInfo.systemUptime-start)*1000
            let prepared = ProcessInfo.processInfo.systemUptime
            let assisted = Terminology.resolve(source,rules:rules,context:context.entries) ?? engine.translate(source,error:&error)
            let assistedMS = (ProcessInfo.processInfo.systemUptime-prepared)*1000
            XCTAssertNotNil(assisted)
            records.append(["source":source,"argos":baseline,"argos_ms":baselineMS,"configured_rules":assisted ?? "","configured_rules_ms":assistedMS,"rss_bytes":ResourceMonitor.residentBytes()])
        }
        let json = try JSONSerialization.data(withJSONObject:["environment":"iOS Simulator on CI Mac, not physical iPhone; synthetic dialogue and explicit hand-written rules","results":records],options:[.sortedKeys])
        print("SYNTHETIC_NATIVE_TRANSLATION_BENCHMARK "+String(decoding:json,as:UTF8.self))
    }
    func testNativeTranslationCanRetireImmediatelyAfterSynchronousResult() throws {
        let folder = try XCTUnwrap(Bundle(for:Self.self).url(forResource:"en_ar",withExtension:nil))
        for _ in 0..<10 {
            try autoreleasepool {
                var error: NSError?
                let engine = try XCTUnwrap(GLTranslation(modelPath:folder.path,error:&error))
                XCTAssertFalse(try XCTUnwrap(engine.translate("Wait near the gate.",error:&error)).isEmpty)
            }
        }
    }
    @MainActor
    func testAudioInterruptionRestorationCannotOverrideManualStop() async throws {
        let audio = BackgroundAudio()
        defer { audio.stop() }
        audio.start() // Simulator activation is not physical background validation.
        let interrupted = expectation(description:"audio interruption event handled")
        audio.onChange = { _,paused,_ in if paused { interrupted.fulfill() } }
        NotificationCenter.default.post(name:AVAudioSession.interruptionNotification,object:nil,userInfo:[AVAudioSessionInterruptionTypeKey:AVAudioSession.InterruptionType.began.rawValue])
        await fulfillment(of:[interrupted],timeout:3)
        XCTAssertTrue(audio.wanted); XCTAssertTrue(audio.interrupted)
        audio.onChange = nil; audio.stop()
        let resumed = expectation(description:"no recovery after manual stop"); resumed.isInverted = true
        audio.onRecovery = { resumed.fulfill() }
        audio.onChange = { active,_,_ in if active { resumed.fulfill() } }
        NotificationCenter.default.post(name:AVAudioSession.interruptionNotification,object:nil,userInfo:[AVAudioSessionInterruptionTypeKey:AVAudioSession.InterruptionType.ended.rawValue,AVAudioSessionInterruptionOptionKey:AVAudioSession.InterruptionOptions.shouldResume.rawValue])
        await fulfillment(of:[resumed],timeout:0.3)
        XCTAssertFalse(audio.wanted)
    }
    func testResourceMetricsReadCurrentProcess() {
        var monitor = ResourceMonitor()
        let sample = monitor.sample()
        XCTAssertGreaterThan(sample.residentBytes,0)
        XCTAssertTrue(sample.cpu.isFinite); XCTAssertGreaterThanOrEqual(sample.cpu,0)
    }
    func testManualSmartReadingUsesFreshFrameAndReturnsToDialogue() async throws {
        let folder = try XCTUnwrap(Bundle(for:Self.self).url(forResource:"en_ar",withExtension:nil))
        let translator = OfflineTranslator(folder:folder)
        let loaded = expectation(description:"existing offline model loaded")
        let loadStarted = ProcessInfo.processInfo.systemUptime
        var modelLoaded = false
        translator.load { result in
            print("SYNTHETIC_SMART_READING_COLD_MODEL_LOAD_MS \((ProcessInfo.processInfo.systemUptime-loadStarted)*1000)")
            if case .failure = result { XCTFail("Model load failed") } else { modelLoaded = true }
            loaded.fulfill()
        }
        // Cold model initialization is not the post-OCR latency assertion. The
        // Intel hosted Simulator can be heavily contended during its first run.
        // Retain all fresh-frame/page/negation/number/context checks below.
        await fulfillment(of:[loaded],timeout:90)
        guard modelLoaded else { return } // Avoid cascading unrelated assertions.
        let pipeline = FramePipeline(translator:translator,publish:{ _ in })
        var contextEntries = -1
        pipeline.onMetrics = { contextEntries = $0.contextEntries }
        defer { pipeline.stop() }
        let waiting = expectation(description:"manual request waits for a fresh decoded frame")
        let ready = expectation(description:"coherent document translated into pages")
        let closed = expectation(description:"document closes")
        let ticket = UUID()
        var translatedPages: [String] = []
        pipeline.onReading = { observed,active,pages,status in
            print("SYNTHETIC_READING_STATE active=\(active) pages=\(pages.count) status=\(status)")
            XCTAssertEqual(observed,ticket)
            if active && pages.isEmpty { waiting.fulfill() }
            else if active { translatedPages = pages; ready.fulfill() }
            else { closed.fulfill() }
        }
        let image = UIGraphicsImageRenderer(size:CGSize(width:1280,height:720)).image { context in
            UIColor.black.setFill(); context.fill(CGRect(x:0,y:0,width:1280,height:720))
            for (row,line) in ["Dear John,","We will not leave the camp.","Bring 11 coins before leaving."].enumerated() {
                (line as NSString).draw(at:CGPoint(x:140,y:CGFloat(100+row*70)),withAttributes:[.font:UIFont.systemFont(ofSize:36),.foregroundColor:UIColor.white])
            }
        }
        var buffer: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault,1280,720,kCVPixelFormatType_32BGRA,[kCVPixelBufferCGImageCompatibilityKey:true,kCVPixelBufferCGBitmapContextCompatibilityKey:true] as CFDictionary,&buffer),kCVReturnSuccess)
        let pixels = try XCTUnwrap(buffer)
        CVPixelBufferLockBaseAddress(pixels,[])
        let bitmap = try XCTUnwrap(CGContext(data:CVPixelBufferGetBaseAddress(pixels),width:1280,height:720,bitsPerComponent:8,bytesPerRow:CVPixelBufferGetBytesPerRow(pixels),space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedFirst.rawValue|CGBitmapInfo.byteOrder32Little.rawValue))
        bitmap.translateBy(x:0,y:720); bitmap.scaleBy(x:1,y:-1)
        UIGraphicsPushContext(bitmap); image.draw(in:CGRect(x:0,y:0,width:1280,height:720)); UIGraphicsPopContext(); bitmap.flush()
        CVPixelBufferUnlockBaseAddress(pixels,[])
        let source = try VisionDialogueOCR().document(pixels).joined(separator:" ")
        XCTAssertTrue(source.contains("11")); XCTAssertTrue(source.lowercased().contains("not leave"))
        // Construct and warm the synthetic fixture BEFORE the production
        // six-second fresh-frame deadline. Fixture generation is not Remote Play.
        pipeline.start(roi:.dialogue,mode:.balanced)
        pipeline.requestReading(ticket:ticket)
        await fulfillment(of:[waiting],timeout:5)
        pipeline.offer(pixels)
        await fulfillment(of:[ready],timeout:30)
        XCTAssertFalse(translatedPages.isEmpty)
        XCTAssertEqual(contextEntries,0,"Documents must not enter dialogue context memory")
        XCTAssertTrue(translatedPages.joined().range(of:"[\\u0600-\\u06FF]",options:.regularExpression) != nil)
        XCTAssertTrue(translatedPages.joined().contains("11") || translatedPages.joined().contains("١١"),"Document translation must retain the number")
        pipeline.closeReading()
        await fulfillment(of:[closed],timeout:5)
        pipeline.onReading = { _,active,pages,_ in XCTAssertFalse(active); XCTAssertTrue(pages.isEmpty) }
    }
    @MainActor
    func testBackgroundStopsTVAndExplicitForegroundRestart() async throws {
        let model = AppModel()
        defer { model.hub.stop() }
        model.connectTV()
        for _ in 0..<100 {
            if model.tvListening { break }
            try await Task.sleep(nanoseconds:100_000_000)
        }
        XCTAssertTrue(model.tvListening)
        XCTAssertTrue(UIApplication.shared.isIdleTimerDisabled,"Waiting for TV must prevent automatic screen lock")
        model.background()
        for _ in 0..<50 {
            if !model.tvListening { break }
            try await Task.sleep(nanoseconds:100_000_000)
        }
        XCTAssertFalse(model.tvListening)
        XCTAssertTrue(model.pairingCode.isEmpty)
        model.connectTV()
        for _ in 0..<100 {
            if model.tvListening { break }
            try await Task.sleep(nanoseconds:100_000_000)
        }
        XCTAssertTrue(model.tvListening)
        XCTAssertFalse(model.pairingCode.isEmpty)
    }
    func testPeerAddressUsesBytesIncludingMappedIPv4() throws {
        XCTAssertEqual(TVHub.peerIPv4(.ipv4(try XCTUnwrap(IPv4Address("192.168.3.138")))) ,"192.168.3.138")
        XCTAssertEqual(TVHub.peerIPv4(.ipv6(try XCTUnwrap(IPv6Address("::ffff:192.168.3.138")))) ,"192.168.3.138")
        XCTAssertNil(TVHub.peerIPv4(.ipv6(try XCTUnwrap(IPv6Address("2001:db8::1")))))
        XCTAssertNil(TVHub.peerIPv4(.name("192.168.3.138.attacker.example",nil)))
    }
    func testOkHttpLANPairingSecurityRestartAndInterruption() async throws {
        // This is a JVM OkHttp client -> simulator listener on its real en* IPv4,
        // not URLSession, not 127.0.0.1, and not physical iPhone/TCL validation.
        let hub = TVHub()
        defer { hub.stop() }
        let host = try XCTUnwrap(TVHub.localAddresses().first,"LAN interface required for this integration test")
        var diagnostics: [String] = []
        hub.onDiagnostics = { diagnostics = $0; if let last = $0.last { print("LAN fixture: " + last) } }
        func start() async throws -> String {
            let ready = expectation(description:"LAN listener bound to 38443")
            var code = ""
            hub.onPairing = { _,value in if !value.isEmpty { code = value; ready.fulfill() } }
            try hub.start(host:host,settings:TVSettings())
            await fulfillment(of:[ready],timeout:15)
            return try XCTUnwrap(code.isEmpty ? nil : code)
        }
        func probe(_ mode: String, code: String, token: String = "", abort: Bool = false, hold: Int = 0) async throws -> [String:Any] {
            var request = URLRequest(url:URL(string:"http://127.0.0.1:39999/run")!)
            request.httpMethod = "POST"; request.timeoutInterval = 40
            request.httpBody = try JSONSerialization.data(withJSONObject:["mode":mode,"host":host,"prefix":String(code.prefix(12)),"pin":String(code.suffix(6)),"token":token,"abort":abort,"hold_seconds":hold])
            let (data,response) = try await URLSession.shared.data(for:request)
            let result = try XCTUnwrap(JSONSerialization.jsonObject(with:data) as? [String:Any])
            XCTAssertEqual((response as? HTTPURLResponse)?.statusCode,200,result["error"] as? String ?? "probe HTTP failure")
            XCTAssertEqual(result["ok"] as? Bool,true,result["error"] as? String ?? "probe failed")
            try await Task.sleep(nanoseconds:250_000_000)
            return result
        }
        let code = try await start()
        let wrongPrefix = String(repeating:code.hasPrefix("0") ? "1" : "0",count:12) + "-" + code.suffix(6)
        let fingerprint = try await probe("bad-fingerprint",code:wrongPrefix)
        XCTAssertEqual(fingerprint["fingerprint_rejected"] as? Bool,true)
        let wrongPIN = String(code.prefix(12)) + "-" + (code.hasSuffix("000000") ? "111111" : "000000")
        let rejected = try await probe("bad-pin",code:wrongPIN)
        XCTAssertEqual(rejected["authentication_rejected"] as? Bool,true)
        let paired = try await probe("pair",code:code)
        XCTAssertTrue(["TLSv1.2","TLSv1.3"].contains(paired["tls"] as? String ?? ""))
        let token = try XCTUnwrap(paired["token"] as? String)
        XCTAssertEqual(paired["heartbeat"] as? Bool,true)
        XCTAssertTrue(diagnostics.contains { $0.contains("[settings.ack]") })
        hub.publish(TVProtocol.envelope("subtitle_clear")) // Must never queue for the next client.
        let reconnect = try await probe("hello",code:code,token:token,abort:true)
        XCTAssertEqual(reconnect["heartbeat"] as? Bool,true)
        // Abrupt network loss then a listener/app restart preserve the identity and token.
        let restartedCode = try await start()
        XCTAssertEqual(String(code.prefix(12)),String(restartedCode.prefix(12)))
        let restarted = try await probe("hello",code:restartedCode,token:token)
        XCTAssertEqual(restarted["heartbeat"] as? Bool,true)
        // A new explicit pairing replaces the old source's token without weakening pinning.
        let replacement = try await probe("pair",code:restartedCode)
        let newToken = try XCTUnwrap(replacement["token"] as? String)
        XCTAssertNotEqual(newToken,token)
        let stale = try await probe("bad-token",code:restartedCode,token:token)
        XCTAssertEqual(stale["authentication_rejected"] as? Bool,true)
        let finalConnection = try await probe("hello",code:restartedCode,token:newToken,hold:20)
        XCTAssertEqual(finalConnection["heartbeat"] as? Bool,true)
        let documentCode = try await start()
        let capabilities = expectation(description:"document receiver capability authenticated")
        hub.onCapabilities = { if $0.contains("document_v1") { capabilities.fulfill() } }
        hub.onConnected = { [weak hub] in hub?.publish(TVProtocol.envelope("document_show",fields:["translated":"هذه صفحة اختبار","page":1,"pages":2])) }
        let document = try await probe("document",code:documentCode)
        XCTAssertEqual(document["document"] as? Bool,true)
        await fulfillment(of:[capabilities],timeout:2)
        hub.onConnected = nil; hub.onCapabilities = nil
        // Diagnostics must not contain either issued token or either PIN.
        XCTAssertFalse(diagnostics.contains { $0.contains(token) || $0.contains(newToken) || $0.contains(String(restartedCode.suffix(6))) })
    }
    func testVideoToolboxDeliversDecodedFrameWithoutRenderer() throws {
        let fixture = EncodedFixture()
        var encoder: VTCompressionSession?
        XCTAssertEqual(VTCompressionSessionCreate(allocator:kCFAllocatorDefault,width:320,height:180,codecType:kCMVideoCodecType_H264,encoderSpecification:nil,imageBufferAttributes:nil,compressedDataAllocator:nil,outputCallback:{ user,_,status,_,sample in
            guard status == noErr, let user, let sample else { return }
            Unmanaged<EncodedFixture>.fromOpaque(user).takeUnretainedValue().capture(sample)
        },refcon:Unmanaged.passUnretained(fixture).toOpaque(),compressionSessionOut:&encoder),noErr)
        let session = try XCTUnwrap(encoder)
        defer { VTCompressionSessionInvalidate(session) }
        VTSessionSetProperty(session,key:kVTCompressionPropertyKey_RealTime,value:kCFBooleanTrue)
        VTSessionSetProperty(session,key:kVTCompressionPropertyKey_AllowFrameReordering,value:kCFBooleanFalse)
        var buffer: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault,320,180,kCVPixelFormatType_32BGRA,nil,&buffer),kCVReturnSuccess)
        let pixels = try XCTUnwrap(buffer)
        CVPixelBufferLockBaseAddress(pixels,[])
        memset(CVPixelBufferGetBaseAddress(pixels),0,CVPixelBufferGetBytesPerRow(pixels)*180)
        CVPixelBufferUnlockBaseAddress(pixels,[])
        XCTAssertEqual(VTCompressionSessionEncodeFrame(session,imageBuffer:pixels,presentationTimeStamp:.zero,duration:CMTime(value:1,timescale:30),frameProperties:[kVTEncodeFrameOptionKey_ForceKeyFrame:true] as CFDictionary,sourceFrameRefcon:nil,infoFlagsOut:nil),noErr)
        XCTAssertEqual(VTCompressionSessionCompleteFrames(session,untilPresentationTimeStamp:.invalid),noErr)
        let data = try XCTUnwrap(fixture.annexB)
        let decoded = expectation(description:"direct CVPixelBuffer callback")
        let decoder = VideoDecoder(hevc:false)
        defer { decoder.shutdown() }
        decoder.onFrame = { output in
            XCTAssertEqual(CVPixelBufferGetWidth(output),320)
            XCTAssertEqual(CVPixelBufferGetHeight(output),180)
            decoded.fulfill()
        }
        XCTAssertTrue(decoder.decode(data))
        wait(for:[decoded],timeout:10)
    }
    func testExistingTVWSSPairingAndReconnectDoNotReplayDialogue() async throws {
        let hub = TVHub(testingLoopback:true)
        defer { hub.stop() }
        let listening = expectation(description:"WSS listener ready")
        var pairingCode = ""
        hub.onStatus = { print("WSS fixture status: " + $0) }
        hub.onPairing = { _,code in pairingCode = code; listening.fulfill() }
        try hub.start(host:"127.0.0.1",settings:TVSettings())
        await fulfillment(of:[listening],timeout:15)
        guard !pairingCode.isEmpty else { return } // The expectation already records a failure.
        let pin = String(pairingCode.suffix(6))
        let delegate = FingerprintTrust(prefix:String(pairingCode.prefix(12)))
        let session = URLSession(configuration:.ephemeral,delegate:delegate,delegateQueue:nil)
        defer { session.invalidateAndCancel() }
        let url = URL(string:"wss://127.0.0.1:38443/")!
        let socket = session.webSocketTask(with:url); socket.resume()
        func receive(_ task: URLSessionWebSocketTask) async throws -> [String:Any] {
            switch try await task.receive() {
            case .string(let value): return try TVProtocol.decode(Data(value.utf8))
            case .data(let value): return try TVProtocol.decode(value)
            @unknown default: throw LingoError.invalid("Unexpected message")
            }
        }
        try await socket.send(.string(String(data:TVProtocol.encode(TVProtocol.envelope("pair",fields:["pin":pin])),encoding:.utf8)!))
        let paired = try await receive(socket)
        let token = try XCTUnwrap(paired["token"] as? String)
        XCTAssertEqual(paired["type"] as? String,"paired")
        let connected = try await receive(socket); XCTAssertEqual(connected["type"] as? String,"connection_status")
        let settings = try await receive(socket); XCTAssertEqual(settings["type"] as? String,"settings_sync")
        let job = DialogueJob(id:"fixture-event",text:"Follow me",generation:1,correction:false,box:.dialogue,frameMilliseconds:TVHub.now())
        hub.publish(TVProtocol.subtitle(job,arabic:"اتبعني",now:TVHub.now()))
        let subtitle = try await receive(socket); XCTAssertEqual(subtitle["id"] as? String,job.id)
        let disconnected = expectation(description:"disconnect")
        hub.onDisconnected = { disconnected.fulfill() }
        socket.cancel(with:.normalClosure,reason:nil)
        await fulfillment(of:[disconnected],timeout:10)
        hub.onDisconnected = nil
        let second = session.webSocketTask(with:url); second.resume()
        try await second.send(.string(String(data:TVProtocol.encode(TVProtocol.envelope("hello",fields:["token":token])),encoding:.utf8)!))
        let reconnected = try await receive(second)
        XCTAssertEqual(reconnected["type"] as? String,"connection_status")
        let reconfigured = try await receive(second)
        XCTAssertEqual(reconfigured["type"] as? String,"settings_sync")
        try await second.send(.string(#"{"v":1,"type":"heartbeat"}"#))
        let heartbeat = try await receive(second)
        XCTAssertEqual(heartbeat["type"] as? String,"heartbeat")
        second.cancel(with:.normalClosure,reason:nil)
    }
    func testNativePairingRejectsInvalidBufferSizes() {
        var error: Int32 = 0
        let registration = GLRegistrationCreate("192.168.1.1",nil,0,12345678,{ _,_,_,_,_ in },nil,&error)
        XCTAssertNil(registration); XCTAssertNotEqual(error,0)
        let session = GLSessionCreate("192.168.1.1",nil,0,nil,0,{ _,_,_ in },{ _,_,_ in true },nil,&error)
        XCTAssertNil(session); XCTAssertNotEqual(error,0)
    }
    func testMixedAnnexBStartCodes() {
        let bytes = Data([0,0,0,1,0x67,1,2,0,0,1,0x68,3,0,0,0,1,0x65,4])
        XCTAssertEqual(VideoDecoder.nalUnits(in:bytes),[Data([0x67,1,2]),Data([0x68,3]),Data([0x65,4])])
    }
    func testVisionReadsGeneratedEnglishDialogueDirectlyFromPixelBuffer() throws {
        let image = UIGraphicsImageRenderer(size:CGSize(width:1280,height:720)).image { context in
            UIColor.black.setFill(); context.fill(CGRect(x:0,y:0,width:1280,height:720))
            ("Follow me to the gate." as NSString).draw(at:CGPoint(x:280,y:510),withAttributes:[.font:UIFont.systemFont(ofSize:46),.foregroundColor:UIColor.white])
        }
        var buffer: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault,1280,720,kCVPixelFormatType_32BGRA,[kCVPixelBufferCGImageCompatibilityKey:true,kCVPixelBufferCGBitmapContextCompatibilityKey:true] as CFDictionary,&buffer),kCVReturnSuccess)
        let pixels = try XCTUnwrap(buffer)
        CVPixelBufferLockBaseAddress(pixels,[])
        let bitmap = try XCTUnwrap(CGContext(data:CVPixelBufferGetBaseAddress(pixels),width:1280,height:720,bitsPerComponent:8,bytesPerRow:CVPixelBufferGetBytesPerRow(pixels),space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedFirst.rawValue|CGBitmapInfo.byteOrder32Little.rawValue))
        // Draw through UIKit in its top-left coordinate system. Drawing the
        // CGImage directly under this transform vertically inverts its pixels.
        bitmap.translateBy(x:0,y:720)
        bitmap.scaleBy(x:1,y:-1)
        UIGraphicsPushContext(bitmap)
        image.draw(in:CGRect(x:0,y:0,width:1280,height:720))
        UIGraphicsPopContext()
        bitmap.flush()
        CVPixelBufferUnlockBaseAddress(pixels,[])
        let (text,box) = try VisionDialogueOCR().recognize(pixels,roi:.dialogue)
        if !text.lowercased().contains("follow me") {
            let raw = VNRecognizeTextRequest()
            raw.recognitionLevel = .accurate; raw.recognitionLanguages = ["en-US"]
            for region in [CGRect(x:0,y:0,width:1,height:1), CGRect(x:0.16,y:0.07,width:0.68,height:0.28)] {
                raw.regionOfInterest = region
                try VNImageRequestHandler(cvPixelBuffer:pixels,orientation:.up,options:[:]).perform([raw])
                for observation in raw.results ?? [] {
                    print("Vision fixture region=\(region) box=\(observation.boundingBox) candidates=\(observation.topCandidates(1).map { $0.string + ":" + String($0.confidence) })")
                }
                print("Vision fixture observation count=\(raw.results?.count ?? 0)")
            }
            let pixelsImage = CIImage(cvPixelBuffer:pixels)
            if let cg = CIContext().createCGImage(pixelsImage,from:pixelsImage.extent) {
                let attachment = XCTAttachment(image:UIImage(cgImage:cg))
                attachment.name = "Vision-pixel-buffer"; attachment.lifetime = .keepAlways; add(attachment)
            }
        }
        XCTAssertTrue(text.lowercased().contains("follow me"),text)
        XCTAssertTrue(box.isValid)
        XCTAssertGreaterThan(box.y,0.65)
        XCTAssertLessThan(box.y+box.h,0.93)
        XCTAssertGreaterThan(box.x,0.16)
        XCTAssertLessThan(box.x+box.w,0.84)
        // This glyph was actually drawn near x=280 in the full 1280px frame.
        // A range-only ROI assertion cannot detect applying the crop twice.
        XCTAssertEqual(box.x,280.0/1280,accuracy:0.05)
        XCTAssertEqual(box.y,510.0/720,accuracy:0.05)
    }
    func testOfflineArabicInferenceUsesVerifiedFixture() throws {
        let folder = try XCTUnwrap(Bundle(for:Self.self).url(forResource:"en_ar",withExtension:nil))
        var error: NSError?
        let translator = try XCTUnwrap(GLTranslation(modelPath:folder.path,error:&error),error?.localizedDescription ?? "Model failed")
        // No network/model download API is called in this test.
        let output = try XCTUnwrap(translator.translate("Where are you going?",error:&error))
        XCTAssertNotNil(output.range(of:"[\\u0600-\\u06FF]",options:.regularExpression),output)
        XCTAssertLessThan(output.count,2400)
    }
    func testKeychainRoundTripAndTLSIdentityFingerprintAreStable() throws {
        let account = "test."+UUID().uuidString
        defer { KeychainStore.delete(account) }
        let secret = try KeychainStore.random(32)
        try KeychainStore.write(secret,account:account)
        XCTAssertEqual(try KeychainStore.read(account),secret)
        let first = try TLSIdentity(), second = try TLSIdentity()
        XCTAssertEqual(first.fingerprint,second.fingerprint); XCTAssertEqual(first.fingerprint.count,64)
    }
}

private final class EncodedFixture {
    var annexB: Data?
    func capture(_ sample: CMSampleBuffer) {
        guard let format = CMSampleBufferGetFormatDescription(sample), let block = CMSampleBufferGetDataBuffer(sample) else { return }
        var output = Data()
        for index in 0..<2 {
            var pointer: UnsafePointer<UInt8>?, size = 0, count = 0
            guard CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format,parameterSetIndex:index,parameterSetPointerOut:&pointer,parameterSetSizeOut:&size,parameterSetCountOut:&count,nalUnitHeaderLengthOut:nil) == noErr, let pointer else { return }
            output.append(contentsOf:[0,0,0,1]); output.append(pointer,count:size)
        }
        let length = CMBlockBufferGetDataLength(block)
        var bytes = [UInt8](repeating:0,count:length)
        guard CMBlockBufferCopyDataBytes(block,atOffset:0,dataLength:length,destination:&bytes) == noErr else { return }
        var offset = 0
        while offset+4 <= bytes.count {
            let size = bytes[offset..<offset+4].reduce(0) { ($0 << 8)|Int($1) }; offset += 4
            guard size > 0, offset+size <= bytes.count else { return }
            output.append(contentsOf:[0,0,0,1]); output.append(contentsOf:bytes[offset..<offset+size]); offset += size
        }
        annexB = output
    }
}

private final class FingerprintTrust: NSObject,URLSessionDelegate {
    let prefix: String
    init(prefix: String) { self.prefix = prefix }
    func urlSession(_ session: URLSession,didReceive challenge: URLAuthenticationChallenge,completionHandler: @escaping (URLSession.AuthChallengeDisposition,URLCredential?) -> Void) {
        guard let trust = challenge.protectionSpace.serverTrust, let certificate = SecTrustGetCertificateAtIndex(trust,0) else { completionHandler(.cancelAuthenticationChallenge,nil); return }
        let digest = SHA256.hash(data:SecCertificateCopyData(certificate) as Data).map { String(format:"%02x",$0) }.joined()
        if digest.hasPrefix(prefix) { completionHandler(.useCredential,URLCredential(trust:trust)) }
        else { completionHandler(.cancelAuthenticationChallenge,nil) }
    }
}
