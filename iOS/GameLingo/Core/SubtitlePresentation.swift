import Foundation

enum SubtitlePresentation {
    /// Remove untrusted directional formatting, never meaningful punctuation.
    /// The TV owns presentation isolates and paragraph direction.
    static func clean(_ text: String) -> String {
        String(text.unicodeScalars.filter { ![0x061c,0x200e,0x200f,0x202a,0x202b,0x202c,0x202d,0x202e,0x2066,0x2067,0x2068,0x2069].contains($0.value) }.map(Character.init))
    }
    /// Content-free stage trace: diagnose bracket origin without logging dialogue.
    static func punctuation(_ text: String) -> String {
        let marks = Set("()[]:\"'?؟!.…،؛«»-—")
        let characters = Array(text)
        let first = text.unicodeScalars.first { CharacterSet.letters.contains($0) }
        let direction: String
        if let first { direction = (0x0590...0x08ff).contains(first.value) ? "R" : "L" } else { direction = "none" }
        let positions = characters.enumerated().compactMap { index, mark -> String? in
            guard marks.contains(mark) else { return nil }
            let location = index == 0 ? "start" : index == characters.count-1 ? "end" : "middle"
            return "\(mark):\(location)"
        }
        return "logical first=\(direction); " + positions.joined(separator:" ")
    }
}
