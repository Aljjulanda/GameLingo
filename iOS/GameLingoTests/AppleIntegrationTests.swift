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
        translator.load { result in if case .failure = result { XCTFail("Model load failed") }; loaded.fulfill() }
        await fulfillment(of:[loaded],timeout:20)
        let pipeline = FramePipeline(translator:translator,publish:{ _ in })
        var contextEntries = -1
        pipeline.onMetrics = { contextEntries = $0.contextEntries }
        defer { pipeline.stop() }
        let waiting = expectation(description:"manual request waits for a fresh decoded frame")
        let ready = expectation(description:"coherent document translated into pages")
        let closed = expectation(description:"document closes")
        let ticket = UUID()
        var translatedPages: [String] = []
        pipeline.onReading = { observed,active,pages,_ in
            XCTAssertEqual(observed,ticket)
            if active && pages.isEmpty { waiting.fulfill() }
            else if active { translatedPages = pages; ready.fulfill() }
            else { closed.fulfill() }
        }
        pipeline.start(roi:.dialogue,mode:.balanced)
        pipeline.requestReading(ticket:ticket)
        await fulfillment(of:[waiting],timeout:5)
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
        func probe(_ mode: String, code: String, token: String = "", abort: Bool = false) async throws -> [String:Any] {
            var request = URLRequest(url:URL(string:"http://127.0.0.1:39999/run")!)
            request.httpMethod = "POST"; request.timeoutInterval = 40
            request.httpBody = try JSONSerialization.data(withJSONObject:["mode":mode,"host":host,"prefix":String(code.prefix(12)),"pin":String(code.suffix(6)),"token":token,"abort":abort])
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
        let finalConnection = try await probe("hello",code:restartedCode,token:newToken)
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
