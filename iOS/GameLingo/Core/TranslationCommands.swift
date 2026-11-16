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
}

