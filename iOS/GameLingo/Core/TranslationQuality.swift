import Foundation

struct PunctuationRepairResult: Equatable {
    var text: String, repairs: Int = 0, unbalanced = false
}

enum SourceGuidedPunctuation {
    private static let terminals = Set(".!?؟…")
    private static let closingQuotes = Set("\"'»”’")
    private static let quotes = Set("\"'«»“”‘’")
    private static let bracketMarks = Set("()[]")
    static func terminalRun(_ text: String) -> String {
        var chars = Array(text.trimmingCharacters(in:.whitespacesAndNewlines))
        while let last = chars.last, closingQuotes.contains(last) { chars.removeLast() }
        return String(chars.reversed().prefix(while:{terminals.contains($0)}).reversed())
    }
    static func unbalanced(_ text: String) -> Bool {
        var stack: [Character] = []
        for c in text {
            if c == "(" { stack.append(")") }
            else if c == "[" { stack.append("]") }
            else if c == ")" || c == "]" { if stack.popLast() != c { return true } }
        }
        return !stack.isEmpty
    }
    private static func arabicLetter(_ c: Character) -> Bool {
        c.isLetter && c.unicodeScalars.contains{(0x0600...0x06ff).contains($0.value)}
    }
    static func repair(_ output: String, source: String, enabled: Bool = true) -> PunctuationRepairResult {
        guard enabled else { return PunctuationRepairResult(text:output) }
        var body = output.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !body.isEmpty else { return PunctuationRepairResult(text:output) }
        let leading = String(output.prefix(while:\.isWhitespace))
        let trailing = String(output.reversed().prefix(while:\.isWhitespace).reversed())
        let sourceTail = terminalRun(source)
        let question = sourceTail.contains("?") || sourceTail.contains("؟")
        var repairs = 0
        let quoted = body.contains(where:{quotes.contains($0)})
        if !quoted, !sourceTail.isEmpty, terminalRun(body).isEmpty, let first = body.first, terminals.contains(first) {
            let prefix = first == "." ? String(body.prefix(while:{$0 == "."})) : String(first)
            let rest = String(body.dropFirst(prefix.count)).trimmingCharacters(in:.whitespacesAndNewlines)
            // A decimal (.5) or mixed-script identifier (.NET) is not a
            // misplaced sentence terminator. No words or marks are invented.
            if prefix.count <= 3, let next = rest.first, arabicLetter(next) {
                body = rest+prefix; repairs += 1
            }
        }
        if !quoted, question && body.last == "?" { body.removeLast(); body.append("؟"); repairs += 1 }
        // Only one witnessed pair, outside quotations. More complex or
        // unbalanced strings stay unchanged and are reported, never guessed.
        if !quoted, body.contains(where:arabicLetter), !body.contains(where:{$0.isASCII && $0.isLetter}),
           source.filter({bracketMarks.contains($0)}).count == 2,
           body.filter({bracketMarks.contains($0)}).count == 2 {
            let pairs: [(Character,Character)] = [("(",")"),("[","]")]
            for (open,close) in pairs {
                let sourceMarks = source.filter{$0 == open || $0 == close}
                var chars = Array(body)
                if sourceMarks == String([open,close]), let left = chars.firstIndex(of:close), let right = chars.firstIndex(of:open), left < right {
                    chars[left] = open; chars[right] = close; body = String(chars); repairs += 1
                }
            }
        }
        return PunctuationRepairResult(text:repairs == 0 ? output : leading+body+trailing,repairs:repairs,unbalanced:unbalanced(body))
    }
}
