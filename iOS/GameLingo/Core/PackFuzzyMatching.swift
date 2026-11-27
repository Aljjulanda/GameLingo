import Foundation

enum PackFuzzyMatching {
    struct Candidate { var source: String, target: String }
    private static let protected: Set<String> = ["no","not","never","cannot","cant","dont","wont","without","he","she","you","i","me","we","they","him","her","us","them","my","your","his","their","our","here","there","left","right","up","down","open","close","on","off","yes","go","stop","buy","sell","enter","exit","increase","decrease","enable","disable"]
    static func tokens(_ text: String) -> [String] { DialogueText.exactWords(text) }
    static func ocrKey(_ word: String) -> String {
        // Numeric values remain exact; only mixed alphanumeric OCR tokens qualify.
        guard word.contains(where:\.isLetter) else { return word }
        return word.replacingOccurrences(of:"0",with:"o").replacingOccurrences(of:"1",with:"l")
    }
    static func kind(source: String, reference: String) -> PackMatch.Kind? {
        let a = tokens(source), b = tokens(reference)
        guard a.count == b.count, a.count >= 4,
              DialogueText.matches(source,"[0-9]+") == DialogueText.matches(reference,"[0-9]+") ||
              (a.count == b.count && a.count >= 4 && a.filter{$0.allSatisfy(\.isNumber)} == b.filter{$0.allSatisfy(\.isNumber)}) else { return nil }
        guard a.filter({protected.contains($0)}) == b.filter({protected.contains($0)}) else { return nil }
        let namesA = DialogueText.matches(source,"\\b[A-Z][a-z]{2,}\\b").dropFirst()
        let namesB = DialogueText.matches(reference,"\\b[A-Z][a-z]{2,}\\b").dropFirst()
        guard Array(namesA) == Array(namesB) else { return nil }
        if a == b { return .fuzzy }
        let changed = zip(a,b).filter{$0 != $1}
        guard changed.count == 1, let pair = changed.first, pair.0.count >= 5,
              !protected.contains(pair.0), !protected.contains(pair.1), ocrKey(pair.0) == ocrKey(pair.1),
              pair.0.contains(where:\.isNumber) else { return nil }
        return .ocrTolerant
    }
    static func choose(source: String, candidates: [Candidate]) -> PackMatch {
        let eligible = candidates.compactMap { c -> (Candidate,PackMatch.Kind)? in kind(source:source,reference:c.source).map{(c,$0)} }
        let targets = Set(eligible.map{$0.0.target})
        guard targets.count <= 1 else { return PackMatch(text:nil,kind:.ambiguous) }
        guard let match = eligible.first else { return PackMatch(text:nil,kind:.missing) }
        return PackMatch(text:match.0.target,kind:match.1)
    }
}
