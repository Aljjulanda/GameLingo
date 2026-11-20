import Foundation

/// The existing command map. Sharing its exact lookup prevents cached commands
/// from being incorrectly reported as Argos model output.
enum DialogueCommands {
    static let legacy = ["go":"انطلق!","run":"اركض!","wait":"انتظر!","no":"لا!"]
    static func key(_ normalized: String) -> String {
        normalized.lowercased().trimmingCharacters(in:CharacterSet(charactersIn:".?!"))
    }
    static func cachedOrigin(_ normalized: String) -> TranslationOrigin {
        legacy[key(normalized)] == nil ? .argosCache : .command
    }
    static func value(_ normalized: String, sourcePunctuation: Bool) -> String? {
        guard let value = legacy[key(normalized)] else { return nil }
        guard sourcePunctuation else { return value }
        let tail = SourceGuidedPunctuation.terminalRun(normalized).replacingOccurrences(of:"?",with:"؟")
        return String(value.dropLast())+tail
    }
}

