import XCTest
import UIKit
import CoreVideo
import CoreImage
@testable import GameLingo

final class PlayExperienceIntegrationTests: XCTestCase {
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
        let ocr = VisionDialogueOCR(); ocr.strictRegion = true; ocr.setBackground(true)
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
        let ocr = VisionDialogueOCR();ocr.setBackground(true)
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
        var rows: [[String:String]] = []
        for (id,source) in cases {
            let pixels = try frame([(source,CGPoint(x:160,y:520),.white)])
            let ocr = VisionDialogueOCR();ocr.setBackground(true)
            let lines = try ocr.menuLines(pixels,roi:SourceBox(x:0.08,y:0.65,w:0.87,h:0.25))
            let text = lines.map(\.text).joined(separator:" ")
            XCTAssertFalse(text.isEmpty)
            rows.append(["id":id,"correct_source":source,"vision_ocr":text])
        }
        let data = try JSONSerialization.data(withJSONObject:rows,options:[.sortedKeys,.prettyPrinted])
        let attachment = XCTAttachment(data:data,uniformTypeIdentifier:"public.json");attachment.name = "play-vision-ocr-corpus";attachment.lifetime = .keepAlways;add(attachment)
    }
}
