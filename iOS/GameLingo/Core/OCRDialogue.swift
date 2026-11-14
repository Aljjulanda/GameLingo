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
    static func resolve(_ lines: [OCRLine], roi: SourceBox, knownNames: String) -> Reading? {
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
                return abs(b.y-a.y)>min(a.h,b.h)*0.45 && gap <= 1.4*max(a.h,b.h) && overlap>min(a.w,b.w)*0.3 && !DialogueContent.isName(line.text,knownNames:knownNames,confidence:line.confidence)
            }.sorted { $0.box.y < $1.box.y }.prefix(3).map { $0 }
        }
        for line in safe {
            let parsed = DialogueContent.parse(line.text,knownNames:knownNames,confidence:line.confidence)
            if let speaker = parsed.speaker, !parsed.text.isEmpty {
                let body = group(line,excluding:nil)
                let text = body.map { $0 == line ? parsed.text : $0.text }.joined(separator:" ")
                return Reading(content:DialogueContent(text:DialogueText.normalized(text),speaker:speaker),box:union(body),confidence:body.map(\.confidence).min() ?? 0)
            }
        }
        for label in safe where DialogueContent.isName(label.text,knownNames:knownNames,confidence:label.confidence) {
            let known = knownNames.split(separator:",").contains { $0.trimmingCharacters(in:.whitespacesAndNewlines).lowercased() == label.text.lowercased() }
            let matches = safe.filter { line in
                guard line != label, DialogueText.words(line.text).count >= 2,
                      !DialogueContent.isName(line.text,knownNames:knownNames,confidence:line.confidence) else { return false }
                let a = label.box, b = line.box
                let verticalGap = b.y-a.y-a.h
                let overlap = min(a.x+a.w,b.x+b.w)-max(a.x,b.x)
                let above = verticalGap >= -0.2*min(a.h,b.h) && verticalGap <= max(0.05*roi.h,1.8*max(a.h,b.h)) && overlap > min(a.w,b.w)*0.25 && a.h <= b.h*1.2 && (a.w <= b.w*0.7 || a.h <= b.h*0.8)
                let horizontalGap = max(a.x-b.x-b.w,b.x-a.x-a.w,0)
                let side = abs(a.y+a.h/2-b.y-b.h/2)<=0.6*max(a.h,b.h) && horizontalGap<=(known ? 0.2 : 0.12)*roi.w && a.w<=b.w*0.55 && a.h<=b.h*1.2 && overlap<=0
                return above || side
            }
            guard let anchor = matches.max(by: { $0.box.w < $1.box.w }) else { continue }
            let body = group(anchor,excluding:label)
            guard !body.isEmpty else { continue }
            return Reading(content:DialogueContent(text:DialogueText.normalized(body.map(\.text).joined(separator:" ")),speaker:DialogueContent.speakerLabel(label.text)),box:union(body),confidence:body.map(\.confidence).min() ?? 0)
        }
        return nil
    }
}
