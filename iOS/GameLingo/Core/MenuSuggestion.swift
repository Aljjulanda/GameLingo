import Foundation

/// Advisory only: evidence from existing dialogue OCR, never another scan or
/// permission to render a menu. The explicit menu request still owns that path.
struct MenuSuggestionSession {
    private(set) var visible = false
    private var rows: [OCRLine] = []
    private var confirmations = 0
    private var lastFrame = 0.0
    static let lifetime = 1.5
    var expiresAt: Double { lastFrame+Self.lifetime }

    mutating func clear() { self = MenuSuggestionSession() }
    mutating func expire(now: Double) {
        if now-lastFrame >= Self.lifetime { clear() }
    }
    mutating func observe(_ lines: [OCRLine], frameAt: Double, now: Double) {
        guard frameAt <= now, now-frameAt < Self.lifetime,
              frameAt > lastFrame, let candidate = Self.candidate(lines) else { clear(); return }
        let same = frameAt-lastFrame < Self.lifetime && candidate.count == rows.count && zip(candidate,rows).allSatisfy { a,b in
            CurrentMenuLayout.key(a.text) == CurrentMenuLayout.key(b.text) &&
            abs(a.box.x-b.box.x) <= 0.018 && abs(a.box.y-b.box.y) <= 0.018 &&
            abs(a.box.w-b.box.w) <= 0.035 && abs(a.box.h-b.box.h) <= 0.018
        }
        confirmations = same ? min(2,confirmations+1) : 1
        rows = candidate; lastFrame = frameAt; visible = confirmations >= 2
    }
    static func candidate(_ lines: [OCRLine]) -> [OCRLine]? {
        // Three exact, distinct navigation labels in one compact column. A
        // vocabulary miss is intentionally left to the manual menu action.
        let labels: Set<String> = ["resume","continue","settings","options","save","save game","load","load game",
            "new game","back","exit","quit","inventory","map","objectives","controls","audio","video","graphics",
            "language","subtitles","brightness","difficulty","apply","cancel","default"]
        guard (3...8).contains(lines.count), lines.allSatisfy({
            $0.confidence >= 0.9 && (0.012...0.09).contains($0.box.h) &&
            $0.text.count <= 40 && $0.text.split(whereSeparator:\.isWhitespace).count <= 4 &&
            $0.text.rangeOfCharacter(from:CharacterSet(charactersIn:".!?;:؟")) == nil
        }), let rows = CurrentMenuLayout.candidate(lines), rows.count == lines.count,
           let first = rows.first, rows.allSatisfy({abs($0.box.x-first.box.x) <= 0.035}) else { return nil }
        let exact = Set(rows.map{CurrentMenuLayout.key($0.text).lowercased()}).intersection(labels)
        guard exact.count >= 3, Double(exact.count)/Double(rows.count) >= 0.6 else { return nil }
        return rows
    }
}
