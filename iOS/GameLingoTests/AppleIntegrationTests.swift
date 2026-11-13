import XCTest
import UIKit
import CoreVideo
import VideoToolbox
import CryptoKit
@testable import GameLingo

final class AppleIntegrationTests: XCTestCase {
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
        hub.onStatus = { status in if status.hasPrefix("التلفزيون غير متصل") { disconnected.fulfill() } }
        socket.cancel(with:.normalClosure,reason:nil)
        await fulfillment(of:[disconnected],timeout:10)
        hub.onStatus = nil
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
        // Quartz bitmap coordinates are bottom-up; the production CVPixelBuffer
        // path is top-down. Preserve the renderer image's orientation in memory.
        bitmap.translateBy(x:0,y:720)
        bitmap.scaleBy(x:1,y:-1)
        bitmap.draw(try XCTUnwrap(image.cgImage),in:CGRect(x:0,y:0,width:1280,height:720))
        CVPixelBufferUnlockBaseAddress(pixels,[])
        let (text,box) = try VisionDialogueOCR().recognize(pixels,roi:.dialogue)
        XCTAssertTrue(text.lowercased().contains("follow me"),text)
        XCTAssertTrue(box.isValid)
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
