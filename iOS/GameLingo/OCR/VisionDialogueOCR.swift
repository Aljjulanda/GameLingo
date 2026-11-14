import Foundation
import CoreVideo
import Vision
import ImageIO

final class VisionDialogueOCR {
    private let request: VNRecognizeTextRequest = {
        let request = VNRecognizeTextRequest()
        request.recognitionLanguages = ["en-US"]; request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true; request.minimumTextHeight = 0.012
        return request
    }()
    private var previousSignature: [String] = []
    private(set) var confidence: Double = 0
    private(set) var separateSpeakerLabel = false
    private(set) var content = DialogueContent(text:"",speaker:nil)
    private(set) var punctuationTrace = ""
    private func project(_ b: CGRect, roi: SourceBox) -> SourceBox {
        SourceBox(x:roi.x+Double(b.minX)*roi.w,y:roi.y+Double(1-b.maxY)*roi.h,w:Double(b.width)*roi.w,h:Double(b.height)*roi.h)
    }
    /// Vision may merge a side label and dialogue into one observation. Split
    /// only when character boxes prove a gap much larger than a normal space.
    private func visualLines(_ candidate: VNRecognizedText, box: CGRect, roi: SourceBox, knownNames: String) -> [OCRLine] {
        let text = candidate.string, confidence = Double(candidate.confidence)
        let original = OCRLine(text:text,box:project(box,roi:roi),confidence:confidence)
        if DialogueContent.parse(text,knownNames:knownNames,confidence:confidence).speaker != nil { return [original] }
        let words = text.split(whereSeparator:\.isWhitespace)
        guard words.count >= 3 else { return [original] }
        for leading in [true,false] {
            for count in (1...min(3,words.count-2)).reversed() {
                let names = leading ? Array(words.prefix(count)) : Array(words.suffix(count))
                let body = leading ? Array(words.dropFirst(count)) : Array(words.dropLast(count))
                let nameRange = names.first!.startIndex..<names.last!.endIndex
                guard DialogueContent.isName(String(text[nameRange]),knownNames:knownNames,confidence:confidence) else { continue }
                let bodyRange = body.first!.startIndex..<body.last!.endIndex
                guard let a = try? candidate.boundingBox(for:nameRange), let b = try? candidate.boundingBox(for:bodyRange) else { continue }
                let gap = max(a.boundingBox.minX-b.boundingBox.maxX,b.boundingBox.minX-a.boundingBox.maxX)
                guard gap > max(0.012,0.6*max(a.boundingBox.height,b.boundingBox.height)) else { continue }
                return [OCRLine(text:String(text[nameRange]),box:project(a.boundingBox,roi:roi),confidence:confidence),
                        OCRLine(text:String(text[bodyRange]),box:project(b.boundingBox,roi:roi),confidence:confidence)]
            }
        }
        return [original]
    }
    func setBackground(_ background: Bool) { request.usesCPUOnly = background }
    func document(_ buffer: CVPixelBuffer) throws -> [String] {
        let document = VNRecognizeTextRequest()
        document.recognitionLanguages = ["en-US"]; document.recognitionLevel = .accurate
        document.usesLanguageCorrection = true; document.minimumTextHeight = 0.008
        document.usesCPUOnly = request.usesCPUOnly
        try VNImageRequestHandler(cvPixelBuffer:buffer,orientation:.up,options:[:]).perform([document])
        guard (document.results?.count ?? 0) <= 150 else { throw LingoError.invalid("قسّم المستند إلى صفحات أصغر") }
        let lines = (document.results ?? []).compactMap { observation -> DocumentLine? in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let b = observation.boundingBox
            return DocumentLine(text:candidate.string,box:SourceBox(x:Double(b.minX),y:Double(1-b.maxY),w:Double(b.width),h:Double(b.height)),confidence:Double(candidate.confidence))
        }
        return DocumentText.paragraphs(lines)
    }
    func recognize(_ buffer: CVPixelBuffer, roi: SourceBox, knownNames: String = "") throws -> (String,SourceBox) {
        guard roi.isValid else { throw LingoError.invalid("منطقة الحوار غير صالحة") }
        // Vision's ROI is lower-left origin. The shared TV protocol uses top-left origin.
        request.regionOfInterest = CGRect(x:roi.x,y:1-roi.y-roi.h,width:roi.w,height:roi.h)
        try VNImageRequestHandler(cvPixelBuffer:buffer,orientation:.up,options:[:]).perform([request])
        let lines: [OCRLine] = (request.results ?? []).flatMap { observation -> [OCRLine] in
            guard let candidate = observation.topCandidates(1).first, candidate.confidence >= 0.2 else { return [] }
            let b = observation.boundingBox
            // Vision reports observations relative to the request's ROI. Project
            // into the full frame before applying dialogue geometry or event IDs.
            return visualLines(candidate,box:b,roi:roi,knownNames:knownNames)
        }
        punctuationTrace = SubtitlePresentation.punctuation(lines.map(\.text).joined(separator:" "))
        if let reading = StructuredDialogue.resolve(lines,roi:roi,knownNames:knownNames) {
            confidence = reading.confidence; content = reading.content; separateSpeakerLabel = reading.content.speaker != nil
            return (content.text,reading.box)
        }
        let selected = select(lines,roi:roi)
        confidence = selected.map(\.confidence).min() ?? 0
        let ordered = selected.sorted { $0.box.y < $1.box.y }
        separateSpeakerLabel = ordered.count >= 2 && ordered[0].box.w < ordered[1].box.w*0.5 && ordered[0].box.h <= ordered[1].box.h*1.1
        guard !selected.isEmpty else { content = DialogueContent(text:"",speaker:nil); return ("",roi) }
        let x = selected.map(\.box.x).min()!, y = selected.map(\.box.y).min()!
        let right = selected.map { $0.box.x+$0.box.w }.max()!, bottom = selected.map { $0.box.y+$0.box.h }.max()!
        let text = String(selected.map(\.text).joined(separator:"\n").prefix(1800))
        content = DialogueContent.parse(text,knownNames:knownNames,separateLabel:separateSpeakerLabel,confidence:confidence)
        return (text,SourceBox(x:x,y:y,w:right-x,h:bottom-y))
    }
    /// Port the desktop's structural gate; this is not semantic game/menu classification.
    func select(_ lines: [OCRLine], roi: SourceBox) -> [OCRLine] {
        let menus: Set<String> = ["settings","options","inventory","resume","resume game","load game","save game","new game","quit","quit game","main menu","graphics","audio","controls","objectives","equipment","skills","map"]
        let context: Set<String> = ["search","interact","pick up","open","talk","examine","use","climb"]
        func term(_ text: String) -> String { DialogueText.matches(text.lowercased(),"[\\p{L}\\p{N}_]+").joined(separator:" ") }
        guard lines.count < 5, lines.filter({ menus.contains(term($0.text)) }).count < 2 else { previousSignature = []; return [] }
        let candidates = lines.filter { line in
            let key = term(line.text), center = (line.box.x+line.box.w/2-roi.x)/roi.w
            return !menus.contains(key) && !context.contains(key) && !key.hasPrefix("press ") && !key.hasPrefix("hold ") && !key.hasPrefix("tap ") && key.range(of:"^(hp|ammo|fps|xp|level)\\s*\\d",options:.regularExpression) == nil && (0.12...0.88).contains(center) && (0.018...0.55).contains(line.box.h/roi.h) && line.text.filter(\.isLetter).count >= 2
        }
        guard let anchor = candidates.min(by:{ abs($0.box.x+$0.box.w/2-0.5) < abs($1.box.x+$1.box.w/2-0.5) }) else { previousSignature = []; return [] }
        var group = [anchor]
        for line in candidates.sorted(by:{ abs($0.box.y-anchor.box.y) < abs($1.box.y-anchor.box.y) }) where group.count < 4 {
            if line.box == anchor.box { continue }
            if group.contains(where: { near in
                let gap = max(line.box.y-near.box.y-near.box.h,near.box.y-line.box.y-line.box.h,0)
                let separate = abs(line.box.y+line.box.h/2-near.box.y-near.box.h/2) > 0.45*min(line.box.h,near.box.h)
                let aligned = abs(line.box.x+line.box.w/2-near.box.x-near.box.w/2) <= 0.15*roi.w || abs(line.box.x-near.box.x) <= 0.07*roi.w
                let overlap = min(line.box.x+line.box.w,near.box.x+near.box.w)-max(line.box.x,near.box.x) > 0.25*min(line.box.w,near.box.w)
                return separate && aligned && overlap && gap <= max(0.035*roi.h,1.35*max(line.box.h,near.box.h))
            }) { group.append(line) }
        }
        let signature = DialogueText.words(group.map(\.text).joined(separator:" "))
        let reliable = group.allSatisfy { abs(($0.box.x+$0.box.w/2-roi.x)/roi.w-0.5) <= 0.22 }
        let accepted = reliable || signature == previousSignature
        previousSignature = signature
        return accepted ? group.sorted(by:{ $0.box.y < $1.box.y }) : []
    }
}
