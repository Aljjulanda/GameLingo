import Foundation

enum SpeakerLabelForm: String, Codable { case colon, bracket, separate }

enum StageDirections {
    // Whole metadata segments only: never replace words inside a sentence.
    private static let groups: [(String,String)] = [
        ("laugh laughs laughing laughter chuckle chuckles chuckling giggle giggles giggling","ضحك"),
        ("cough coughs coughing","سعال"), ("sigh sighs sighing","تنهّد"),
        ("groan groans groaning","أنين"), ("grunt grunts grunting","همهمة"),
        ("gasp gasps gasping","شهقة"), ("scream screams screaming shout shouts shouting","صراخ"),
        ("whisper whispers whispering","همس"), ("sob sobs sobbing cry cries crying","بكاء"),
        ("sniff sniffs sniffing","استنشاق"), ("pant pants panting","لهاث"),
        ("music","موسيقى"), ("gunshot gunshots","إطلاق نار"), ("footsteps","خطوات")
    ]
    static func arabic(_ value: String) -> String? {
        let key = DialogueText.normalized(DialogueContent.speakerLabel(value)).lowercased()
        if key == "door opens" || key == "door opening" { return "فتح باب" }
        if key == "music playing" { return "موسيقى" }
        return groups.first { $0.0.split(separator:" ").contains(Substring(key)) }?.1
    }
    static func leading(_ value: String) -> (raw:String,arabic:String,rest:String)? {
        guard let open = value.first, open == "(" || open == "[",
              let end = value.firstIndex(of:open == "(" ? ")" : "]"),
              let arabic = arabic(String(value[...end])) else { return nil }
        let tail = value[value.index(after:end)...]
        guard tail.isEmpty || tail.first?.isWhitespace == true || tail.first == ":" else { return nil }
        return (String(value[...end]),"("+arabic+")",tail.trimmingCharacters(in:.whitespacesAndNewlines).trimmingCharacters(in:CharacterSet(charactersIn:": ")))
    }
}

enum SpeakerEvidence {
    static let hud: Set<String> = ["health","ammo","fps","xp","level","score","money","wanted","dead eye","stamina","weapon","damage","online","continue","back","apply","brightness","subtitles","language","volume","music","chapter","mission","objective","main menu","resume game","load game","save game","new game"]
    static func known(_ value: String, _ names: String) -> Bool {
        names.split(separator:",").contains { $0.trimmingCharacters(in:.whitespacesAndNewlines).lowercased() == DialogueContent.speakerLabel(value).lowercased() }
    }
    static func shape(_ value: String) -> Bool {
        let label = DialogueContent.speakerLabel(value), words = label.split(separator:" ")
        return !label.isEmpty && label.count <= 40 && (1...3).contains(words.count) &&
            label.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || " '’-.".contains($0)) }
    }
    static func excluded(_ value: String) -> Bool {
        let key = DialogueContent.speakerLabel(value).lowercased()
        let words = key.split(separator:" ").map(String.init)
        return StageDirections.arabic(key) != nil || hud.contains(key) ||
            (!words.isEmpty && words.allSatisfy { DialogueContent.ordinary.contains($0) || hud.contains($0) }) ||
            key.range(of:"^(hp|ammo|fps|xp|level|score)\\s*\\d",options:.regularExpression) != nil
    }
    static func digitName(_ word: String) -> Bool {
        word == "47" || word.range(of:"^(?:[0-9][A-Z]|BT-[0-9]{4})$",options:.regularExpression) != nil
    }
    static func isName(_ value: String, knownNames: String, confidence: Double) -> Bool {
        let label = DialogueContent.speakerLabel(value), words = label.split(separator:" ").map(String.init)
        guard shape(label), !excluded(label) else { return false }
        if known(label,knownNames) { return confidence >= 0.35 }
        guard confidence >= 0.65 else { return false }
        var distinctive = false
        for word in words {
            if digitName(word) { distinctive = true; continue }
            if word.contains(where:\.isNumber) { return false }
            if DialogueContent.ordinary.contains(word.lowercased()) { continue }
            guard word.first?.isUppercase == true, word.filter(\.isLetter).count >= 2 else { return false }
            distinctive = true
        }
        return distinctive
    }
    static func parse(_ input: String, knownNames: String, separateLabel: Bool, confidence: Double, quality: QualitySettings) -> DialogueContent {
        var text = SubtitlePresentation.clean(input), cues: [(String,String)] = []
        func takeCue() {
            guard quality[.stageCues], let cue = StageDirections.leading(text) else { return }
            cues.append((cue.raw,cue.arabic)); text = cue.rest
        }
        takeCue()
        if quality[.stageCues], cues.isEmpty, let arabic = StageDirections.arabic(text),
           !["music","music playing","footsteps","door opens"].contains(text.lowercased()) {
            cues.append((text,"("+arabic+")")); text = ""
        }
        var content: DialogueContent
        if quality[.speakerClassification] {
            let lines = text.components(separatedBy:.newlines).filter { !$0.trimmingCharacters(in:.whitespaces).isEmpty }
            let first = lines.first ?? ""
            var candidate: (String,String,SpeakerLabelForm)?
            if let open = first.first, open == "(" || open == "[", let end = first.firstIndex(of:open == "(" ? ")" : "]") {
                let tail = first[first.index(after:end)...]
                if tail.isEmpty || tail.first?.isWhitespace == true || tail.first == ":" {
                    candidate = (String(first[...end]),([tail.trimmingCharacters(in:CharacterSet(charactersIn:": "))]+Array(lines.dropFirst())).joined(separator:" "),.bracket)
                }
            } else if let colon = first.firstIndex(of:":") {
                candidate = (String(first[..<colon]),([String(first[first.index(after:colon)...])]+Array(lines.dropFirst())).joined(separator:" "),.colon)
            } else if lines.count > 1 && separateLabel {
                candidate = (first,lines.dropFirst().joined(separator:" "),.separate)
            }
            if let (label,body,form) = candidate, !body.trimmingCharacters(in:.whitespaces).isEmpty,
               shape(label), !excluded(label),
               // Shape alone is insufficient: accepted identity, or spatial
               // evidence plus capitalized/known label and a real body.
               isName(label,knownNames:knownNames,confidence:confidence) ||
               (separateLabel && confidence >= 0.35 && DialogueText.words(body).count >= 2 &&
                (known(label,knownNames) || DialogueContent.speakerLabel(label).first?.isUppercase == true)) {
                let confident = isName(label,knownNames:knownNames,confidence:confidence)
                content = DialogueContent(text:DialogueText.normalized(body),speaker:confident ? DialogueContent.speakerLabel(label) : nil,uncertainSpeaker:!confident,speakerHidden:!confident,labelForm:form)
            } else { content = DialogueContent(text:DialogueText.normalized(text),speaker:nil,uncertainSpeaker:candidate != nil) }
        } else {
            content = DialogueContent.parse(text,knownNames:knownNames,separateLabel:separateLabel,confidence:confidence)
        }
        // A cue may follow the one accepted speaker. Never recursively consume
        // a second colon label from the actual dialogue.
        text = content.text; takeCue()
        if !cues.isEmpty {
            content.engineText = DialogueText.normalized(text)
            content.cue = cues.map(\.1).joined(separator:" ")
            content = DialogueContent(text:DialogueText.normalized(cues.map(\.0).joined(separator:" ")+" "+text),speaker:content.speaker,uncertainSpeaker:content.uncertainSpeaker,engineText:content.engineText,cue:content.cue,speakerHidden:content.speakerHidden,labelForm:content.labelForm)
        }
        return content
    }
}

struct NameConfidenceCounts {
    private(set) var low = 0, medium = 0, high = 0
    mutating func observe(_ lines: [OCRLine]) {
        for line in lines where SpeakerEvidence.shape(line.text) && !SpeakerEvidence.excluded(line.text) {
            if line.confidence < 0.5 { low += 1 } else if line.confidence < 0.8 { medium += 1 } else { high += 1 }
        }
    }
    var summary: String { "name confidence <.5=\(low) .5–.8=\(medium) ≥.8=\(high)" }
}

enum VisionNameDictionary {
    static func words(_ groups: [String]) -> [String] {
        var seen = Set<String>()
        return groups.flatMap { $0.split(separator:",").map { $0.trimmingCharacters(in:.whitespacesAndNewlines) } }
            .filter { SpeakerEvidence.shape($0) && !SpeakerEvidence.excluded($0) && seen.insert($0.lowercased()).inserted }.prefix(200).map { $0 }
    }
}
