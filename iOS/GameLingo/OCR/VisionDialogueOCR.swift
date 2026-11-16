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
    var qualityTrace = false
    var captureLines = false
    var quality = QualitySettings()
    private(set) var nameConfidence = NameConfidenceCounts()
    var configuredCustomWords: [String] { request.customWords }
    var usesLanguageCorrection: Bool { request.usesLanguageCorrection }
    private var selector = DialogueSelection()
    private(set) var lastLines: [OCRLine] = []
    private(set) var lastSegments: [OCRLine] = []
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
        if DialogueContent.parse(text,knownNames:knownNames,confidence:confidence,quality:quality).speaker != nil { return [original] }
        let words = text.split(whereSeparator:\.isWhitespace)
        guard words.count >= 3 else { return [original] }
        for leading in [true,false] {
            for count in (1...min(3,words.count-2)).reversed() {
                let names = leading ? Array(words.prefix(count)) : Array(words.suffix(count))
                let body = leading ? Array(words.dropFirst(count)) : Array(words.dropLast(count))
                let nameRange = names.first!.startIndex..<names.last!.endIndex
                let label = String(text[nameRange])
                let classified = DialogueContent.isName(label,knownNames:knownNames,confidence:confidence,quality:quality)
                let possibleLabel = quality[.speakerClassification] && SpeakerEvidence.shape(label) && !SpeakerEvidence.excluded(label) && label.first?.isUppercase == true
                guard classified || possibleLabel else { continue }
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
        request.customWords = quality[.visionNames] ? VisionNameDictionary.words([knownNames]) : []
        try VNImageRequestHandler(cvPixelBuffer:buffer,orientation:.up,options:[:]).perform([request])
        var lines: [OCRLine] = [], raw: [OCRLine] = []
        for observation in request.results ?? [] {
            guard let candidate = observation.topCandidates(1).first else { continue }
            let b = observation.boundingBox
            if captureLines || qualityTrace {
                raw.append(OCRLine(text:candidate.string,box:project(b,roi:roi),confidence:Double(candidate.confidence)))
            }
            guard candidate.confidence >= 0.2 else { continue }
            // Preserve the original eligibility and glyph-gap segmentation;
            // debug raw observations are recorded before those transformations.
            lines.append(contentsOf:visualLines(candidate,box:b,roi:roi,knownNames:knownNames))
        }
        lastLines = captureLines ? Array(raw.prefix(150)) : []
        lastSegments = captureLines ? Array(lines.prefix(150)) : []
        punctuationTrace = qualityTrace ? SubtitlePresentation.punctuation(raw.map(\.text).joined(separator:" ")) : ""
        if quality[.speakerClassification] || quality[.visionNames] { nameConfidence.observe(lines) }
        let reading = DialogueObservation.resolve(lines,roi:roi,knownNames:knownNames,selector:&selector,quality:quality)
        confidence = reading.confidence; content = reading.content; separateSpeakerLabel = reading.separateSpeakerLabel
        return (reading.rawText,reading.box)
    }
    func select(_ lines: [OCRLine], roi: SourceBox) -> [OCRLine] { selector.select(lines,roi:roi) }
}
