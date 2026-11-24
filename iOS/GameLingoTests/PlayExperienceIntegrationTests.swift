import XCTest
import UIKit
import CoreVideo
import CoreImage
import Vision
@testable import GameLingo

final class PlayExperienceIntegrationTests: XCTestCase {
    /// Investigation only; not included in the release acceptance selection.
    func testDiagnoseFirstCorpusFrameAndRawVisionConfidence() throws {
        let source = "Do not open that door."
        let pixels = try frame([(source,CGPoint(x:160,y:520),.white)])
        let region = SourceBox(x:0.08,y:0.65,w:0.87,h:0.25)
        let ocr = VisionDialogueOCR(softwareImageContext:true);ocr.setBackground(true)
        let first = try ocr.menuLines(pixels,roi:region)
        let context = CIContext(options:[.useSoftwareRenderer:true,.cacheIntermediates:false])
        let image = CIImage(cvPixelBuffer:pixels)
        let full = try XCTUnwrap(context.createCGImage(image,from:image.extent))
        let rect = CGRect(x:ceil(region.x*1280),y:ceil((1-region.y-region.h)*720),width:floor((region.x+region.w)*1280)-ceil(region.x*1280),height:floor((1-region.y)*720)-ceil((1-region.y-region.h)*720))
        let cropped = try XCTUnwrap(context.createCGImage(image.cropped(to:rect),from:rect))
        let raw = VNRecognizeTextRequest();raw.recognitionLanguages = ["en-US"];raw.recognitionLevel = .accurate
        raw.usesLanguageCorrection = false;raw.minimumTextHeight = 0.008;raw.usesCPUOnly = true
        try VNImageRequestHandler(cgImage:cropped,orientation:.up,options:[:]).perform([raw])
        let observations = (raw.results ?? []).compactMap { observation -> [String:Any]? in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let b = observation.boundingBox
            return ["text":candidate.string,"confidence":Double(candidate.confidence),"box":["x":Double(b.minX),"y":Double(b.minY),"w":Double(b.width),"h":Double(b.height)]]
        }
        let repeated = try ocr.menuLines(pixels,roi:region)
        ocr.strictRegion = true;ocr.captureLines = true
        let dialogue = try ocr.recognize(pixels,roi:region)
        let data = try JSONSerialization.data(withJSONObject:["source":source,"first_menu":first.map(\.text),"raw_menu_observations":observations,"repeated_menu":repeated.map(\.text),"dialogue":dialogue.0,"raw_dialogue":ocr.lastLines.map{["text":$0.text,"confidence":$0.confidence]}],options:[.prettyPrinted,.sortedKeys])
        let result = XCTAttachment(data:data,uniformTypeIdentifier:"public.json");result.name = "failed-corpus-first-frame-diagnosis";result.lifetime = .keepAlways;add(result)
        for (name,cg) in [("failed-corpus-full-frame",full),("failed-corpus-cropped-frame",cropped)] {
            let attachment = XCTAttachment(image:UIImage(cgImage:cg));attachment.name = name;attachment.lifetime = .keepAlways;add(attachment)
        }
    }
    func testMenuConfigurationDoesNotCancelIndependentDialogueInference() throws {
        let folder = try XCTUnwrap(Bundle(for:Self.self).url(forResource:"en_ar",withExtension:nil))
        let translator = OfflineTranslator(folder:folder)
        let loaded = expectation(description:"Shared inference worker loaded")
        translator.load { result in if case .failure(let error) = result { XCTFail(error.localizedDescription) }; loaded.fulfill() }
        wait(for:[loaded],timeout:20)
        let pipeline = FramePipeline(translator:translator) { _ in }
        let finished = expectation(description:"Dialogue survives unrelated menu configuration")
        translator.translateDetailed("We must not leave John behind.") { result,_ in
            switch result { case .success(let decision): XCTAssertFalse(decision.text.isEmpty); case .failure(let error): XCTFail(error.localizedDescription) }
            finished.fulfill()
        }
        var options = GameOptions();options.menusEnabled = true
        pipeline.configureMenus(options)
        wait(for:[finished],timeout:20)
        let stopped = expectation(description:"Idle pipeline drained")
        pipeline.stop { stopped.fulfill() };wait(for:[stopped],timeout:5)
    }
    func testIdleWorkerActuallyInfersAndCannotApproveItsOwnUnreferencedOutput() throws {
        let folder = try XCTUnwrap(Bundle(for:Self.self).url(forResource:"en_ar",withExtension:nil))
        let translator = OfflineTranslator(folder:folder)
        let loaded = expectation(description:"Native idle worker model loaded")
        translator.load { result in if case .failure(let error) = result { XCTFail(error.localizedDescription) }; loaded.fulfill() }
        wait(for:[loaded],timeout:20)
        let generated = expectation(description:"Actual unassisted proposal")
        translator.propose("Do not open that door.") { result in
            switch result {
            case .failure(let error): XCTFail(error.localizedDescription)
            case .success(let candidate):
                XCTAssertFalse(candidate.isEmpty)
                var example = ImprovementExample(game:"synthetic-idle",source:"Do not open that door.",context:"Arthur|We must stay here.",confidence:0.95,observations:2,trustedTarget:candidate,authority:"model-self")
                XCTAssertNotNil(ImprovementGate.rejection(example,candidate:candidate,existing:[]))
                example.authority = "pack-exact:synthetic-independent"; example.trustedTarget = "افتح الباب فورًا."
                XCTAssertNotNil(ImprovementGate.rejection(example,candidate:candidate,existing:[]))
            }
            generated.fulfill()
        }
        wait(for:[generated],timeout:20)
        translator.cancel()
    }
    @MainActor
    func testPhoneDestinationSurvivesTVLossAndProfileApplicationCannotReenter() async throws {
        let originalQuality = QualitySettings.load()
        defer { originalQuality.save() }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let model = AppModel(profileRoot:root)
        for _ in 0..<100 {
            if !model.gameProfiles.isEmpty { break }
            try await Task.sleep(nanoseconds:50_000_000)
        }
        XCTAssertFalse(model.gameProfiles.isEmpty)
        let game = model.currentGame
        model.quality[.measurement] = true
        XCTAssertEqual(model.currentGame,game)
        XCTAssertEqual(model.gameProfiles.count,1,"Applying quality must not recursively create a profile")
        model.gameOptions.destination = .phone; model.running = true
        model.route(TVProtocol.envelope("subtitle_show",fields:["id":"one-result","translated":"لا تغادر بدونها."]))
        XCTAssertEqual(model.localSubtitles.entries.count,1)
        model.hub.onDisconnected?()
        try await Task.sleep(nanoseconds:100_000_000)
        XCTAssertEqual(model.localSubtitles.entries.first?.text,"لا تغادر بدونها.")
        model.route(TVProtocol.envelope("subtitle_update",fields:["id":"one-result","translated":"لا تغادر بدونها! "]))
        XCTAssertEqual(model.localSubtitles.entries.count,1)
        model.preview(true); model.stop()
        XCTAssertTrue(model.localSubtitles.preview)
        XCTAssertTrue(model.localSubtitles.entries.isEmpty)
        model.preview(false)
        model.route(TVProtocol.envelope("subtitle_show",fields:["id":"late-result","translated":"متأخر"]))
        XCTAssertTrue(model.localSubtitles.entries.isEmpty)
    }
    @MainActor
    func testUnregisteredMenuUsesFreshVisionFramesAndReturnsToDialogue() async throws {
        let folder = try XCTUnwrap(Bundle(for:Self.self).url(forResource:"en_ar",withExtension:nil))
        let translator = OfflineTranslator(folder:folder)
        let loaded = expectation(description:"Actual local model reused")
        translator.load { result in if case .failure(let error) = result { XCTFail(error.localizedDescription) }; loaded.fulfill() }
        await fulfillment(of:[loaded],timeout:20)
        let menuRead = expectation(description:"Unregistered synthetic menu translated")
        let submenuRead = expectation(description:"Changed synthetic submenu replaces old items")
        let dialogueRead = expectation(description:"Fresh dialogue returns after explicit menu close")
        var first = false, second = false, dialogue = false
        var trace: [[String:Any]] = []
        let diagnosticStarted = ProcessInfo.processInfo.systemUptime
        func observation(_ line: OCRLine) -> [String:Any] {
            ["text":line.text,"confidence":line.confidence,"box":["x":line.box.x,"y":line.box.y,"w":line.box.w,"h":line.box.h]]
        }
        let pipeline = FramePipeline(translator:translator,softwareImageContext:true) { message in
            DispatchQueue.main.async {
                if message["type"] as? String == "subtitle_show", let source = message["source"] as? String,
                   ["Follow me to the gate.","Follow me to the gate"].contains(source),
                   let text = message["translated"] as? String, text.unicodeScalars.contains(where:{(0x0600...0x06ff).contains($0.value)}), !dialogue {
                    dialogue = true; dialogueRead.fulfill()
                }
            }
        }
        defer { pipeline.stop() }
        pipeline.onCurrentMenu = { _,state in
            trace.append(["stage":"state","seconds":ProcessInfo.processInfo.systemUptime-diagnosticStarted,
                "active":state.active,"status":state.status,"sources":state.sources.map(observation),
                "translated_sources":state.items.map(\.source),"pending":state.pending,"rejected":state.rejectedSources.sorted()])
            trace = Array(trace.suffix(60))
            let sources = Set(state.items.map(\.source))
            if sources == Set(["Settings","Audio","Back"]), !first { first = true; menuRead.fulfill() }
            if sources == Set(["Graphics","Language","Exit"]), !second { second = true; submenuRead.fulfill() }
            if second { XCTAssertFalse(sources.contains("Audio")) }
        }
#if DEBUG
        pipeline.onCurrentMenuObservation = { lines,region,milliseconds,arrivalAge in
            trace.append(["stage":"ocr","seconds":ProcessInfo.processInfo.systemUptime-diagnosticStarted,
                "milliseconds":milliseconds,"arrival_age":arrivalAge,
                "region":["x":region.x,"y":region.y,"w":region.w,"h":region.h],"observations":lines.map(observation)])
            trace = Array(trace.suffix(60))
        }
#endif
        pipeline.start(roi:.dialogue,mode:.balanced); pipeline.setBackground(true)
        pipeline.requestCurrentMenu(ticket:UUID())
        let initial = try frame([("Settings",CGPoint(x:140,y:170),.white),("Audio",CGPoint(x:140,y:290),.white),("Back",CGPoint(x:140,y:410),.white)])
        for _ in 0..<35 { pipeline.offer(initial); try await Task.sleep(nanoseconds:100_000_000) }
        await fulfillment(of:[menuRead],timeout:10)
        let changed = try frame([("Graphics",CGPoint(x:140,y:170),.white),("Language",CGPoint(x:140,y:290),.white),("Exit",CGPoint(x:140,y:410),.white)])
        for _ in 0..<35 { pipeline.offer(changed); try await Task.sleep(nanoseconds:100_000_000) }
        await fulfillment(of:[submenuRead],timeout:10)
        pipeline.closeCurrentMenu()
        let pixels = try frame([("Follow me to the gate.",CGPoint(x:260,y:530),.white)])
        for _ in 0..<35 { pipeline.offer(pixels); try await Task.sleep(nanoseconds:100_000_000) }
        await fulfillment(of:[dialogueRead],timeout:10)
        let payload = try JSONSerialization.data(withJSONObject:["source":"Authored synthetic menu lifecycle; not gameplay","trace":trace],options:[.prettyPrinted,.sortedKeys])
        let diagnostic = XCTAttachment(data:payload,uniformTypeIdentifier:"public.json")
        diagnostic.name = "synthetic-current-menu-lifecycle"; diagnostic.lifetime = .keepAlways; add(diagnostic)
        let stopped = expectation(description:"Menu and dialogue pipeline drained")
        pipeline.stop { stopped.fulfill() }; await fulfillment(of:[stopped],timeout:5)
    }
    private func frame(_ text: [(String,CGPoint,UIColor)]) throws -> CVPixelBuffer {
        let image = UIGraphicsImageRenderer(size:CGSize(width:1280,height:720)).image { context in
            UIColor.black.setFill(); context.fill(CGRect(x:0,y:0,width:1280,height:720))
            for (value,point,color) in text { (value as NSString).draw(at:point,withAttributes:[.font:UIFont.systemFont(ofSize:32),.foregroundColor:color]) }
        }
        var value: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault,1280,720,kCVPixelFormatType_32BGRA,[kCVPixelBufferCGImageCompatibilityKey:true,kCVPixelBufferCGBitmapContextCompatibilityKey:true] as CFDictionary,&value),kCVReturnSuccess)
        let buffer = try XCTUnwrap(value)
        CVPixelBufferLockBaseAddress(buffer,[]); defer { CVPixelBufferUnlockBaseAddress(buffer,[]) }
        let context = try XCTUnwrap(CGContext(data:CVPixelBufferGetBaseAddress(buffer),width:1280,height:720,bitsPerComponent:8,bytesPerRow:CVPixelBufferGetBytesPerRow(buffer),space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedFirst.rawValue|CGBitmapInfo.byteOrder32Little.rawValue))
        context.translateBy(x:0,y:720); context.scaleBy(x:1,y:-1)
        UIGraphicsPushContext(context);image.draw(at:.zero);UIGraphicsPopContext();context.flush()
        return buffer
    }
    func testManualCropReadsWholeSelectedTextAndExcludesOutsideRegion() throws {
        let pixels = try frame([("OUTSIDE SECRET HUD",CGPoint(x:200,y:100),.white),("We must not leave John behind.",CGPoint(x:200,y:520),.white)])
        let ocr = VisionDialogueOCR(softwareImageContext:true); ocr.strictRegion = true; ocr.setBackground(true)
        let region = SourceBox(x:0.1,y:0.65,w:0.8,h:0.25)
        let lines = try ocr.menuLines(pixels,roi:region)
        XCTAssertTrue(lines.contains{$0.text.contains("John behind")},"Selected line must not be clipped")
        XCTAssertFalse(lines.contains{$0.text.contains("OUTSIDE")})
        XCTAssertTrue(lines.allSatisfy{region.contains($0.box,tolerance:0.004)})
        let (text,box) = try ocr.recognize(pixels,roi:region)
        XCTAssertTrue(text.contains("John")); XCTAssertFalse(text.contains("SECRET"));XCTAssertTrue(region.contains(box,tolerance:0.004))
    }
    func testCurrentMenuOCRKeepsDynamicValuesAndMeasuresDecodedGlyphColor() throws {
        let pixels = try frame([("Moonlight Lodge",CGPoint(x:150,y:180),.white),("Save game",CGPoint(x:150,y:250),.yellow),("Return to camp",CGPoint(x:150,y:320),.white),("Coins 137",CGPoint(x:150,y:390),.white)])
        let ocr = VisionDialogueOCR(softwareImageContext:true);ocr.setBackground(true)
        let region = SourceBox(x:0.05,y:0.15,w:0.7,h:0.65)
        let lines = try ocr.menuLines(pixels,roi:region)
        XCTAssertTrue(lines.contains{$0.text.contains("137")})
        let selected = try XCTUnwrap(lines.first{$0.text.lowercased().contains("save game")})
        let color = try XCTUnwrap(GlyphColorSampler.sample(pixels,box:selected.box,context:CIContext(options:[.useSoftwareRenderer:true])))
        let numeric = try XCTUnwrap(Int(color.dropFirst(),radix:16))
        XCTAssertGreaterThan((numeric>>16)&255,160);XCTAssertGreaterThan((numeric>>8)&255,160);XCTAssertLessThan(numeric&255,100)
    }
    func testActualVisionOCRComparisonCorpusIsExportedWithoutPrivateImages() throws {
        let cases: [(String,String)] = [
            ("negation","Do not open that door."),("pronouns","She gave him the map."),("name","John will meet Arthur at dawn."),
            ("idiom","We are running out of time."),("cut","If you see him, tell him that"),("number","Collect 11 coins before leaving."),
            ("negation-heldout","I never said she stole the key."),("pronouns-heldout","They told us to wait here.")]
        var rows: [[String:Any]] = []
        for (id,source) in cases {
            let pixels = try frame([(source,CGPoint(x:160,y:520),.white)])
            let ocr = VisionDialogueOCR(softwareImageContext:true);ocr.setBackground(true);ocr.strictRegion = true
            let region = SourceBox(x:0.08,y:0.65,w:0.87,h:0.25)
            // Measure the dialogue path used by these source sentences. The
            // menu reader deliberately disables correction and rejects <0.7;
            // Vision gives the first fixture 0.5 there, versus 1.0 for dialogue.
            // Off-centre dialogue needs two consecutive observations under the
            // unchanged structural gate. This is stabilization, not test retry.
            let first = try ocr.recognize(pixels,roi:region).0
            let text = try ocr.recognize(pixels,roi:region).0
            XCTAssertFalse(text.isEmpty,"Dialogue OCR returned no accepted text for \(id)")
            rows.append(["id":id,"correct_source":source,"vision_ocr":text,"ocr_path":"dialogue-strict-region","first_dialogue_read":first,"observations":2,"confidence":ocr.confidence])
        }
        let data = try JSONSerialization.data(withJSONObject:rows,options:[.sortedKeys,.prettyPrinted])
        let attachment = XCTAttachment(data:data,uniformTypeIdentifier:"public.json");attachment.name = "play-vision-ocr-corpus";attachment.lifetime = .keepAlways;add(attachment)
    }
}
