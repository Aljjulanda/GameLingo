import Foundation

struct LearningEvidence: Codable, Equatable {
    var ocr: Double, dialogue: Double, speaker: Double, translation: Double
    var speakerName: String?
    var observations = 1
    var valid: Bool { [ocr,dialogue,speaker,translation].allSatisfy{$0.isFinite && (0...1).contains($0)} }
}
enum LearningSafety {
    static func confidence(source: String, speaker: String?, speakerConfidence: Double, ocr: Double, ui: Bool) -> LearningEvidence? {
        guard !ui, !TextPrivacy.excluded(source), (8...500).contains(source.count), ocr >= 0.9,
              source.range(of:"[a-zA-Z]{4,}",options:.regularExpression) != nil else { return nil }
        let s = source.lowercased(), words = DialogueText.exactWords(source)
        guard words.count >= 3, words.count <= 70,
              !["trophy","achievement","unlocked","inventory","ammo","damage","armor","outfit","clothing","jacket","shirt","trousers","weapon stats","settings","notification","press ","hold ","tap "].contains(where:s.contains),
              source.filter({$0 == ":"}).count <= (speaker == nil ? 0 : 1),
              source.range(of:"(?:^|\\s)[A-Z][A-Za-z]{1,20}:.*(?:[A-Z][A-Za-z]{1,20}):",options:.regularExpression) == nil,
              source.range(of:"[A-Za-z][0-9][A-Za-z]|(.)\\1{3,}|[|~_{}<>]",options:.regularExpression) == nil,
              Double(source.filter(\.isLetter).count)/Double(max(1,source.count)) >= 0.65 else { return nil }
        // A proper name plus a sentence or clear conversational pronouns is
        // evidence; OCR's numeric score alone is never dialogue confidence.
        let pronouns: Set<String> = ["i","you","we","he","she","they","me","my","your","our","us","let's","don't","can't"]
        let named = speaker != nil && speakerConfidence >= 0.9
        guard named || !pronouns.isDisjoint(with:words) else { return nil }
        return LearningEvidence(ocr:min(0.99,ocr),dialogue:named ? 0.97 : 0.92,speaker:named ? min(0.99,speakerConfidence) : 0,translation:0,speakerName:speaker)
    }
    /// Reliable local Arabic semantic inference isn't bundled. Approve the
    /// independent reference itself, never require generated Arabic equality.
    static func trusted(_ example: ImprovementExample) -> Bool {
        guard let evidence = example.evidence, evidence.valid, evidence.ocr >= 0.9, evidence.dialogue >= 0.9,
              example.observations >= 3, let target = example.trustedTarget,
              example.authority?.hasPrefix("pack-exact:") == true else { return false }
        return SpatialTarget.valid(source:example.source,target:target)
    }
}
