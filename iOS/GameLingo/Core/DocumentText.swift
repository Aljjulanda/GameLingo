import Foundation

struct DocumentLine {
    let text: String, box: SourceBox
    var confidence: Double = 1
}

enum DocumentText {
    private static let sentenceBreak = try! NSRegularExpression(pattern:"[.!?]\\s")
    static func paragraphs(_ input: [DocumentLine]) -> [String] {
        let lines = Array(input.filter { $0.confidence >= 0.35 && $0.box.isValid && !$0.text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty }.prefix(150))
        var columns = [lines]
        // Split only an unambiguous two-column layout, never interleave rows.
        let centers = lines.sorted { $0.box.x+$0.box.w/2 < $1.box.x+$1.box.w/2 }
        if centers.count >= 8 {
            for index in 3..<(centers.count-3) {
                let left = Array(centers.prefix(index)), right = Array(centers.suffix(from:index))
                if let end = left.map({ $0.box.x+$0.box.w }).max(), let start = right.map({ $0.box.x }).min(), start-end > 0.06 {
                    columns = [left,right]; break
                }
            }
        }
        var paragraphs: [String] = []
        for column in columns {
            let ordered = column.sorted { abs($0.box.y-$1.box.y) < 0.008 ? $0.box.x < $1.box.x : $0.box.y < $1.box.y }
            var paragraph = "", previous: DocumentLine?
            for line in ordered {
                let text = DialogueText.normalized(line.text)
                let gap = previous.map { line.box.y-$0.box.y-$0.box.h } ?? 0
                let numbered = text.range(of:"^\\d+[.)]\\s",options:.regularExpression) != nil
                if !paragraph.isEmpty && (numbered || gap > max(0.012,(previous?.box.h ?? 0.02)*0.8)) {
                    paragraphs.append(paragraph); paragraph = ""
                }
                if paragraph.hasSuffix("-") { paragraph.removeLast(); paragraph += text }
                else { paragraph += (paragraph.isEmpty ? "" : " ")+text }
                previous = line
            }
            if !paragraph.isEmpty { paragraphs.append(paragraph) }
        }
        return paragraphs
    }
    static func chunks(_ paragraphs: [String], limit: Int = 600, maximumCharacters: Int = 16000, maximumChunks: Int = 192) -> [String] {
        var result: [String] = [], total = 0
        for paragraph in paragraphs {
            var remaining = paragraph.trimmingCharacters(in:.whitespacesAndNewlines)
            while !remaining.isEmpty && total < maximumCharacters && result.count < maximumChunks {
                let bound = min(limit,maximumCharacters-total)
                let prefix = String(remaining.prefix(bound))
                // Backwards search is not supported consistently with regular
                // expressions. Select the last actual match explicitly.
                let match = sentenceBreak.matches(in:prefix,range:NSRange(prefix.startIndex...,in:prefix)).last
                let sentenceEnd = match.flatMap { Range($0.range,in:prefix)?.upperBound }
                let end = remaining.count <= bound ? prefix.endIndex : (sentenceEnd ?? prefix.lastIndex(of:" ") ?? prefix.endIndex)
                let text = String(prefix[..<end]).trimmingCharacters(in:.whitespacesAndNewlines)
                guard !text.isEmpty else { break }
                result.append(text); total += text.count
                remaining = String(remaining.dropFirst(prefix.distance(from:prefix.startIndex,to:end))).trimmingCharacters(in:.whitespacesAndNewlines)
            }
        }
        return result
    }
    static func pages(_ paragraphs: [String], limit: Int = 600) -> [String] {
        let chunks = self.chunks(paragraphs,limit:limit,maximumCharacters:57600,maximumChunks:192)
        var pages: [String] = [], page = ""
        for text in chunks {
            if !page.isEmpty && page.count+text.count+2 > limit { pages.append(page); page = "" }
            page += (page.isEmpty ? "" : "\n\n")+text
        }
        if !page.isEmpty { pages.append(page) }
        return pages.count <= 64 ? pages : []
    }
}
