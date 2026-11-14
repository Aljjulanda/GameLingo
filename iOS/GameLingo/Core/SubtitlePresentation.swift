import Foundation

enum SubtitlePresentation {
    /// Remove untrusted directional formatting, never meaningful punctuation.
    /// The TV owns presentation isolates and paragraph direction.
    static func clean(_ text: String) -> String {
        String(text.unicodeScalars.filter { ![0x061c,0x200e,0x200f,0x202a,0x202b,0x202c,0x202d,0x202e,0x2066,0x2067,0x2068,0x2069].contains($0.value) }.map(Character.init))
    }
    /// Content-free stage trace: diagnose bracket origin without logging dialogue.
    static func punctuation(_ text: String) -> String {
        "()[]:\"؟?".map { mark in "\(mark)=\(text.filter{$0==mark}.count)" }.joined(separator:" ")
    }
}
