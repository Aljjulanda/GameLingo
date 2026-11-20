import Foundation

struct OCRLine: Equatable {
    var text: String
    var box: SourceBox
    var confidence: Double = 1
}

/// Same-request observations only. No extra OCR pass or expanded scanning area.
enum StructuredDialogue {
    struct Reading {
        let content: DialogueContent
        let box: SourceBox
        let confidence: Double
    }
    static func union(_ lines: [OCRLine]) -> SourceBox {
        if lines.count == 1 { return lines[0].box }
        let x = lines.map(\.box.x).min()!, y = lines.map(\.box.y).min()!
        return SourceBox(x:x,y:y,w:lines.map { $0.box.x+$0.box.w }.max()!-x,h:lines.map { $0.box.y+$0.box.h }.max()!-y)
    }
    static func resolve(_ lines: [OCRLine], roi: SourceBox, knownNames: String, quality: QualitySettings = QualitySettings()) -> Reading? {
        guard !lines.isEmpty, lines.count <= 8 else { return nil }
        let menu = Set(["settings","options","inventory","resume game","main menu","objectives","equipment","skills","map"])
        guard lines.filter({menu.contains(DialogueText.normalized($0.text).lowercased())}).count < 2 else { return nil }
        let safe = lines.filter {
            let key = DialogueText.normalized($0.text).lowercased()
            return $0.box.isValid && $0.confidence >= 0.2 && !key.isEmpty && !menu.contains(key) && !key.hasPrefix("press ") && !key.hasPrefix("hold ") && !key.hasPrefix("tap ")
        }
        func group(_ anchor: OCRLine, excluding: OCRLine?) -> [OCRLine] {
            safe.filter { line in
                if line == excluding { return false }
                if line == anchor { return true }
                let b = line.box, a = anchor.box
                let gap = max(b.y-a.y-a.h,a.y-b.y-b.h,0)
                let overlap = min(b.x+b.w,a.x+a.w)-max(b.x,a.x)
                return abs(b.y-a.y)>min(a.h,b.h)*0.45 && gap <= 1.4*max(a.h,b.h) && overlap>min(a.w,b.w)*0.3 && !DialogueContent.isName(line.text,knownNames:knownNames,confidence:line.confidence,quality:quality)
            }.sorted { $0.box.y < $1.box.y }.prefix(quality[.lineLimits] ? max(3,min(5,quality.anchoredLineCap)) : 3).map { $0 }
        }
        for line in safe {
            let parsed = DialogueContent.parse(line.text,knownNames:knownNames,confidence:line.confidence,quality:quality)
            if let speaker = parsed.speaker, !parsed.text.isEmpty {
                let body = group(line,excluding:nil)
                let text = body.map { $0 == line ? parsed.text : $0.text }.joined(separator:" ")
                var content = parsed
                content = DialogueContent(text:DialogueText.normalized(text),speaker:speaker,uncertainSpeaker:parsed.uncertainSpeaker,engineText:parsed.engineText.map { _ in ([parsed.engineText ?? ""]+body.filter{$0 != line}.map(\.text)).joined(separator:" ") },cue:parsed.cue,speakerHidden:parsed.speakerHidden,labelForm:parsed.labelForm,speakerConfidence:parsed.speakerConfidence)
                return Reading(content:content,box:union(body),confidence:body.map(\.confidence).min() ?? 0)
            }
        }
        for label in safe where DialogueContent.isName(label.text,knownNames:knownNames,confidence:label.confidence,quality:quality) || (quality[.speakerClassification] && SpeakerEvidence.shape(label.text) && !SpeakerEvidence.excluded(label.text) && label.text.first?.isUppercase == true) {
            let known = knownNames.split(separator:",").contains { $0.trimmingCharacters(in:.whitespacesAndNewlines).lowercased() == label.text.lowercased() }
            let matches = safe.filter { line in
                guard line != label, DialogueText.words(line.text).count >= 2,
                      !DialogueContent.isName(line.text,knownNames:knownNames,confidence:line.confidence,quality:quality) else { return false }
                let a = label.box, b = line.box
                let verticalGap = b.y-a.y-a.h
                let overlap = min(a.x+a.w,b.x+b.w)-max(a.x,b.x)
                let expanded = quality[.speakerGeometry]
                let height = expanded ? quality.nameHeightRatio : 1.2
                let aligned = overlap > min(a.w,b.w)*(expanded ? quality.nameOverlap : 0.25)
                let offset = expanded && abs(a.x-b.x) <= quality.nameLeftOffset*roi.w && a.x+a.w >= b.x-0.04*roi.w
                let above = verticalGap >= -0.2*min(a.h,b.h) && verticalGap <= max(0.05*roi.h,(expanded ? quality.nameGapRatio : 1.8)*max(a.h,b.h)) && (aligned || offset) && a.h <= b.h*height && (a.w <= b.w*0.7 || a.h <= b.h*0.8)
                let horizontalGap = max(a.x-b.x-b.w,b.x-a.x-a.w,0)
                let side = abs(a.y+a.h/2-b.y-b.h/2)<=0.6*max(a.h,b.h) && horizontalGap<=(known ? 0.2 : 0.12)*roi.w && a.w<=b.w*0.55 && a.h<=b.h*height && overlap<=0
                return above || side
            }
            guard let anchor = matches.max(by: { $0.box.w < $1.box.w }) else { continue }
            let body = group(anchor,excluding:label)
            guard !body.isEmpty else { continue }
            var content: DialogueContent
            if quality[.speakerClassification] || quality[.stageCues] {
                content = DialogueContent.parse(label.text+"\n"+body.map(\.text).joined(separator:" "),knownNames:knownNames,separateLabel:true,confidence:min(label.confidence,body.map(\.confidence).min() ?? 0),quality:quality)
            } else { content = DialogueContent(text:DialogueText.normalized(body.map(\.text).joined(separator:" ")),speaker:DialogueContent.speakerLabel(label.text),labelForm:.separate) }
            content.speakerConfidence = label.confidence
            return Reading(content:content,box:union(body),confidence:body.map(\.confidence).min() ?? 0)
        }
        return nil
    }
}

/// The existing selection gate, shared by Vision and deterministic post-OCR
/// replay. Kept verbatim during extraction; no sampling/ROI/layout change.
struct DialogueSelection {
    private var previousSignature: [String] = []
    /// Port the desktop's structural gate; this is not semantic game/menu classification.
    mutating func select(_ lines: [OCRLine], roi: SourceBox, quality: QualitySettings = QualitySettings()) -> [OCRLine] {
        let menus: Set<String> = ["settings","options","inventory","resume","resume game","load game","save game","new game","quit","quit game","main menu","graphics","audio","controls","objectives","equipment","skills","map"]
        let context: Set<String> = ["search","interact","pick up","open","talk","examine","use","climb"]
        func term(_ text: String) -> String { DialogueText.matches(text.lowercased(),"[\\p{L}\\p{N}_]+").joined(separator:" ") }
        let cap = quality[.lineLimits] ? max(4,min(6,quality.fallbackLineCap)) : 4
        guard lines.count <= cap, lines.filter({ menus.contains(term($0.text)) }).count < 2 else { previousSignature = []; return [] }
        let candidates = lines.filter { line in
            let key = term(line.text), center = (line.box.x+line.box.w/2-roi.x)/roi.w
            return !menus.contains(key) && !context.contains(key) && !key.hasPrefix("press ") && !key.hasPrefix("hold ") && !key.hasPrefix("tap ") && key.range(of:"^(hp|ammo|fps|xp|level)\\s*\\d",options:.regularExpression) == nil && (0.12...0.88).contains(center) && (0.018...0.55).contains(line.box.h/roi.h) && line.text.filter(\.isLetter).count >= 2
        }
        guard let anchor = candidates.min(by:{ abs($0.box.x+$0.box.w/2-0.5) < abs($1.box.x+$1.box.w/2-0.5) }) else { previousSignature = []; return [] }
        var group = [anchor]
        for line in candidates.sorted(by:{ abs($0.box.y-anchor.box.y) < abs($1.box.y-anchor.box.y) }) where group.count < cap {
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
        var accepted = reliable || signature == previousSignature
        if quality[.lineLimits], group.count > 4 {
            // New unanchored 5/6-line regions need BOTH compact dialogue layout
            // and a repeated real OCR observation. Short lines alone never mean
            // menu; they remain eligible with a genuine sentence anchor. The
            // pre-existing menu/HUD filters above are retained.
            let bounds = StructuredDialogue.union(group)
            let sentence = group.contains { DialogueText.words($0.text).count >= 5 }
            let compact = bounds.h <= 0.85*roi.h && group.count == candidates.count
            accepted = reliable && compact && sentence && signature == previousSignature
        }
        previousSignature = signature
        return accepted ? group.sorted(by:{ $0.box.y < $1.box.y }) : []
    }
}

struct PostOCRReading {
    let content: DialogueContent
    let rawText: String
    let box: SourceBox
    let confidence: Double
    let separateSpeakerLabel: Bool
}

enum DialogueObservation {
    static func resolve(_ lines: [OCRLine], roi: SourceBox, knownNames: String, selector: inout DialogueSelection, quality: QualitySettings = QualitySettings()) -> PostOCRReading {
        if let reading = StructuredDialogue.resolve(lines,roi:roi,knownNames:knownNames,quality:quality) {
            return PostOCRReading(content:reading.content,rawText:reading.content.text,box:reading.box,confidence:reading.confidence,separateSpeakerLabel:reading.content.speaker != nil)
        }
        let selected = selector.select(lines,roi:roi,quality:quality)
        let confidence = selected.map(\.confidence).min() ?? 0
        let ordered = selected.sorted { $0.box.y < $1.box.y }
        let separate = ordered.count >= 2 && ordered[0].box.w < ordered[1].box.w*0.5 && ordered[0].box.h <= ordered[1].box.h*1.1
        guard !selected.isEmpty else { return PostOCRReading(content:DialogueContent(text:"",speaker:nil),rawText:"",box:roi,confidence:0,separateSpeakerLabel:false) }
        let text = String(selected.map(\.text).joined(separator:"\n").prefix(1800))
        let content = DialogueContent.parse(text,knownNames:knownNames,separateLabel:separate,confidence:confidence,quality:quality)
        let x = selected.map(\.box.x).min()!, y = selected.map(\.box.y).min()!
        let right = selected.map { $0.box.x+$0.box.w }.max()!, bottom = selected.map { $0.box.y+$0.box.h }.max()!
        return PostOCRReading(content:content,rawText:text,box:SourceBox(x:x,y:y,w:right-x,h:bottom-y),confidence:confidence,separateSpeakerLabel:separate)
    }
}
