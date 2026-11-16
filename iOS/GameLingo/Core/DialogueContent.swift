import Foundation

struct DialogueContent {
    let text: String
    let speaker: String?
    var uncertainSpeaker = false
    var engineText: String? = nil
    var cue: String? = nil
    var speakerHidden = false
    var labelForm: SpeakerLabelForm? = nil
    static let ordinary: Set<String> = ["warning","note","objective","mission","quest","hint","tip","chapter","attention","remember","listen","look","yes","no","hello","inventory","options","settings","item","message","journal","letter","press","hold","system","dialogue","go","run","wait","stop","help","come","follow","leave","hey","okay","sure","please","thanks","we","you","they","he","she","it","the","i","left","right","up","down","forward","back","attack","block","jump","reload","fire","aim","interact","move","get","out","open","close","collect","save","load","exit","enter","new","game"]
    static func isName(_ value: String, knownNames: String, confidence: Double, quality: QualitySettings = QualitySettings()) -> Bool {
        if quality[.speakerClassification] { return SpeakerEvidence.isName(value,knownNames:knownNames,confidence:confidence) }
        let label = speakerLabel(value)
        let key = label.lowercased().trimmingCharacters(in:CharacterSet(charactersIn:".:!"))
        let words = label.split(separator:" ")
        let effects: Set<String> = ["laughing","laughter","gunshots","gunshot","sighs","sighing","music","music playing","door opens","footsteps","screaming","whispering","grunts","grunting","gasps","applause","sobbing"]
        guard !effects.contains(key), label.allSatisfy({ $0.isLetter || $0.isNumber || " '’-.".contains($0) }), label.count <= 40, (1...3).contains(words.count), !ordinary.contains(key),
              words.allSatisfy({ !ordinary.contains($0.lowercased().trimmingCharacters(in:CharacterSet(charactersIn:".:!"))) }) else { return false }
        let known = knownNames.split(separator:",").contains { $0.trimmingCharacters(in:.whitespacesAndNewlines).lowercased() == label.lowercased() }
        if known { return confidence >= 0.35 }
        return confidence >= 0.65 && words.allSatisfy { word in
            word.first?.isUppercase == true && word.filter(\.isLetter).count >= 2 && word.allSatisfy { $0.isLetter || $0.isNumber || "'’-.".contains($0) }
        }
    }
    static func speakerLabel(_ value: String) -> String {
        let label = value.trimmingCharacters(in:.whitespacesAndNewlines)
        if (label.first == "(" && label.last == ")") || (label.first == "[" && label.last == "]") {
            return String(label.dropFirst().dropLast()).trimmingCharacters(in:.whitespaces)
        }
        return label
    }
    static func parse(_ text: String, knownNames: String, separateLabel: Bool = false, confidence: Double = 1, quality: QualitySettings = QualitySettings()) -> DialogueContent {
        if quality[.stageCues] || quality[.speakerClassification] {
            return SpeakerEvidence.parse(text,knownNames:knownNames,separateLabel:separateLabel,confidence:confidence,quality:quality)
        }
        let lines = SubtitlePresentation.clean(text).components(separatedBy:.newlines).filter { !$0.trimmingCharacters(in:.whitespaces).isEmpty }
        guard let first = lines.first else { return DialogueContent(text:"",speaker:nil) }
        if let opening = first.first, opening == "(" || opening == "[", let end = first.firstIndex(of:opening == "(" ? ")" : "]") {
            let label = String(first[...end])
            let suffix = first[first.index(after:end)...]
            if suffix.isEmpty || suffix.first?.isWhitespace == true || suffix.first == ":" {
                let rest = suffix.trimmingCharacters(in:.whitespaces).trimmingCharacters(in:CharacterSet(charactersIn:":")).trimmingCharacters(in:.whitespaces)
                let body = ([rest]+Array(lines.dropFirst())).joined(separator:" ")
                if !body.trimmingCharacters(in:.whitespaces).isEmpty && isName(label,knownNames:knownNames,confidence:confidence) {
                    return DialogueContent(text:DialogueText.normalized(body),speaker:speakerLabel(label))
                }
            }
        }
        if let colon = first.firstIndex(of:":") {
            let label = first[..<colon].trimmingCharacters(in:.whitespaces)
            if isName(label,knownNames:knownNames,confidence:confidence) {
                let rest = String(first[first.index(after:colon)...])
                return DialogueContent(text:DialogueText.normalized(([rest]+Array(lines.dropFirst())).joined(separator:" ")),speaker:speakerLabel(label))
            }
        }
        let known = knownNames.split(separator:",").contains { $0.trimmingCharacters(in:.whitespacesAndNewlines).lowercased() == first.trimmingCharacters(in:.whitespaces).lowercased() }
        if lines.count > 1 && (known || separateLabel) && isName(first,knownNames:knownNames,confidence:confidence) && DialogueText.words(lines.dropFirst().joined(separator:" ")).count >= 2 {
            return DialogueContent(text:DialogueText.normalized(lines.dropFirst().joined(separator:" ")),speaker:speakerLabel(first))
        }
        // An ordinary word, uncertain OCR or uppercase alone is not a speaker.
        return DialogueContent(text:DialogueText.normalized(text),speaker:nil,uncertainSpeaker:(first.contains(":") && first.prefix(while:{$0 != ":"}).count <= 40) || (separateLabel && lines.count > 1 && first.count <= 40))
    }
}

struct DialogueMemoryEntry {
    let id: String, source: String
    let speaker: String?
    let timestamp: TimeInterval, confidence: Double
}

struct DialogueMemory {
    private(set) var entries: [DialogueMemoryEntry] = []
    var capacity = 5
    var enabled = true
    mutating func prune(now: TimeInterval) {
        entries.removeAll { now-$0.timestamp > 90 }
        entries = Array(entries.suffix(max(1,min(20,capacity))))
        if !enabled { entries.removeAll() }
    }
    mutating func observe(_ job: DialogueJob, now: TimeInterval) {
        prune(now:now); guard enabled, job.confidence >= 0.45 else { return }
        let entry = DialogueMemoryEntry(id:job.id,source:job.text,speaker:job.speaker,timestamp:now,confidence:job.confidence)
        if let index = entries.firstIndex(where:{ $0.id == job.id }) { entries[index] = entry }
        else { entries.append(entry) }
        prune(now:now)
    }
    mutating func clear() { entries.removeAll(keepingCapacity:false) }
}

/// Explicit whole-sentence rules, optionally scoped by a recent source trigger.
/// This is context-assisted terminology, not a conversational neural model.
enum Terminology {
    static func resolve(_ source: String, rules: String, context: [DialogueMemoryEntry]) -> String? {
        func key(_ value: String) -> String { DialogueText.normalized(value).lowercased() }
        for line in rules.split(separator:"\n").prefix(100) {
            let parts = line.split(separator:"=",maxSplits:1).map { String($0).trimmingCharacters(in:.whitespaces) }
            guard parts.count == 2, !parts[1].isEmpty, parts[1].count <= 2400 else { continue }
            let condition = parts[0].split(separator:"|",maxSplits:1).map(String.init)
            let input = condition.last ?? ""
            guard key(input) == key(source) else { continue }
            if condition.count == 2 {
                let trigger = key(condition[0]); guard !trigger.isEmpty,
                    context.contains(where:{ key(($0.speaker ?? "")+" "+$0.source).range(of:"(?<![\\p{L}\\p{N}_])"+NSRegularExpression.escapedPattern(for:trigger)+"(?![\\p{L}\\p{N}_])",options:.regularExpression) != nil }) else { continue }
            }
            return parts[1]
        }
        return nil
    }
}

struct PublicationStability {
    private struct Published { let text: String, speaker: String? }
    private var sources = BoundedLRU<String,Published>(capacity:8)
    mutating func shouldPublish(_ job: DialogueJob) -> Bool {
        guard let old = sources.get(job.id) else { return true }
        return job.meaningfulCorrection || (old.speaker == nil && job.speaker != nil) || (DialogueText.prefix(old.text,job.text) && DialogueText.words(old.text) != DialogueText.words(job.text))
    }
    mutating func didPublish(_ job: DialogueJob) { sources.put(Published(text:job.text,speaker:job.speaker),for:job.id) }
    mutating func clear() { sources = BoundedLRU(capacity:8) }
}
