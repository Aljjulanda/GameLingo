import Foundation

/// Import-time profiles retain the raw v1 row for independent rollback. These
/// policies never mutate the external file or the legacy normalized key.
struct PackQualityOptions: Equatable {
    var markup = false, labels = false, punctuation = false
    var profile: Int { (markup ? 1 : 0) | (labels ? 2 : 0) }
    var key: String { "\(profile)/\(punctuation ? 1 : 0)" }
    init(markup: Bool = false, labels: Bool = false, punctuation: Bool = false) {
        self.markup = markup; self.labels = labels; self.punctuation = punctuation
    }
    init(_ quality: QualitySettings) {
        self.init(markup:quality[.packMarkup],labels:quality[.packLabels],punctuation:quality[.packPunctuation])
    }
}

struct PackQualityText: Equatable {
    var source: String, target: String, flags: String, usable: Bool
    var speaker: String?
}

enum PackQualityPolicy {
    private static let controls = try! NSRegularExpression(pattern:"~[zns]~",options:.caseInsensitive)
    private static let color = try! NSRegularExpression(pattern:"</?C>",options:.caseInsensitive)
    private static let unresolved = try! NSRegularExpression(pattern:"~[A-Za-z][A-Za-z0-9_]{0,20}~|</?[A-Za-z][A-Za-z0-9]*(?:\\s[^<>]{0,128})?>")
    private static let placeholder = try! NSRegularExpression(pattern:"\\{[0-9]+(?::[^{}\\r\\n]{0,32})?\\}|(?<!%)%(?!%)(?:[0-9]+\\$)?[-+0 #]*[0-9]*(?:\\.[0-9]+)?[sdifuxX@]")
    private static func matches(_ regex: NSRegularExpression, _ text: String) -> [NSTextCheckingResult] {
        regex.matches(in:text,range:NSRange(text.startIndex...,in:text))
    }
    static func hasPlaceholder(_ text: String) -> Bool { !matches(placeholder,text).isEmpty }
    static func cleanMarkup(_ text: String) -> String {
        // Only ~z~, ~n~, ~s~ and balanced <C> wrappers are documented here.
        // A newline token separates words; color/state controls do not add words.
        var value = text
        for match in matches(controls,text).reversed() {
            guard let range = Range(match.range,in:value) else { continue }
            let replacement = String(value[range]).lowercased() == "~n~" ? " " : ""
            value.replaceSubrange(range,with:replacement)
        }
        let tags = matches(color,value)
        var depth = 0, balanced = true
        for tag in tags {
            guard let range = Range(tag.range,in:value) else { balanced = false; break }
            depth += value[range].hasPrefix("</") ? -1 : 1
            if depth < 0 || depth > 8 { balanced = false; break }
        }
        if balanced && depth == 0 {
            for tag in tags.reversed() { if let range = Range(tag.range,in:value) { value.removeSubrange(range) } }
        }
        return SubtitlePresentation.clean(value).split(whereSeparator:\.isWhitespace).joined(separator:" ")
    }
    static func label(_ text: String) -> (name:String,body:String)? {
        guard let colon = text.firstIndex(of:":"), text.distance(from:text.startIndex,to:colon) <= 40 else { return nil }
        let name = String(text[..<colon]).trimmingCharacters(in:.whitespacesAndNewlines)
        let body = String(text[text.index(after:colon)...]).trimmingCharacters(in:.whitespacesAndNewlines)
        guard !body.isEmpty, name.range(of:"[\\p{Latin}]",options:.regularExpression) != nil,
              SpeakerEvidence.isName(name,knownNames:"",confidence:1) else { return nil }
        return (name,body)
    }
    static func transform(source: String, target: String, flags: String, usable: Bool, options: PackQualityOptions) -> PackQualityText {
        var result = PackQualityText(source:source,target:target,flags:flags,usable:usable)
        guard options.profile != 0 else { return result }
        let originalFlags = (try? JSONSerialization.jsonObject(with:Data(flags.utf8))) as? [String]
        var added: [String] = []
        if options.markup {
            result.source = cleanMarkup(source); result.target = cleanMarkup(target)
            if result.source != source || result.target != target { added.append("quality_markup_cleaned") }
        }
        if options.labels, let label = label(result.source) {
            result.source = label.body; result.speaker = label.name
            added.append("speaker:"+label.name)
            // Only remove a demonstrably identical English label from the target.
            // An unverified Arabic prefix remains visible; it is never guessed.
            if let colon = result.target.firstIndex(of:":"),
               String(result.target[..<colon]).trimmingCharacters(in:.whitespacesAndNewlines).lowercased() == label.name.lowercased() {
                result.target = String(result.target[result.target.index(after:colon)...]).trimmingCharacters(in:.whitespacesAndNewlines)
            }
        }
        if options.markup {
            let blocked = hasPlaceholder(result.source) || hasPlaceholder(result.target) ||
                !matches(unresolved,result.source).isEmpty || !matches(unresolved,result.target).isEmpty
            if hasPlaceholder(result.source) || hasPlaceholder(result.target) { added.append("quality_placeholder") }
            if blocked { result.usable = false }
            else if !usable, let old = originalFlags,
                    old.contains("unresolved_markup_or_placeholder"),
                    Set(old).isSubset(of:["unresolved_markup_or_placeholder","presentation_forms_converted"]) {
                result.usable = true
            }
        }
        if result.source.isEmpty || result.target.isEmpty || PackLookupKey.normalized(result.source).isEmpty ||
            !result.target.unicodeScalars.contains(where:{(0x0600...0x06ff).contains($0.value)}) ||
            result.target.unicodeScalars.contains(where:{(0xfb50...0xfdff).contains($0.value) || (0xfe70...0xfefc).contains($0.value)}) {
            result.usable = false
        }
        if !added.isEmpty {
            // Unknown legacy flag encodings are retained verbatim as one value;
            // they can never qualify a previously unusable row for recovery.
            let combined = (originalFlags ?? [flags])+added
            if let data = try? JSONSerialization.data(withJSONObject:combined,options:.sortedKeys), let value = String(data:data,encoding:.utf8), value.count <= 2048 {
                result.flags = value
            } else { result.usable = false; result.flags = flags }
        }
        return result
    }
    static func punctuationless(_ text: String) -> String {
        var folded = text.precomposedStringWithCompatibilityMapping.lowercased()
        for quote in ["’","‘"] { folded = folded.replacingOccurrences(of:quote,with:"'") }
        let chars = Array(folded)
        var words: [String] = [], token = ""
        func flush() { if !token.isEmpty { words.append(token); token = "" } }
        for (index,c) in chars.enumerated() {
            let before: Character? = index > 0 ? chars[index-1] : nil
            let after: Character? = index+1 < chars.count ? chars[index+1] : nil
            if c.isLetter || c.isNumber || c.unicodeScalars.allSatisfy({CharacterSet.nonBaseCharacters.contains($0)}) { token.append(c) }
            else if c == "'", before?.isLetter == true, after?.isLetter == true { token.append(c) }
            else if c == ".", before?.isNumber == true, after?.isNumber == true { token.append(c) }
            else if (c == "-" || c == "+"), after?.isNumber == true, before?.isLetter != true, before?.isNumber != true {
                flush(); token.append(c)
            } else { flush() }
        }
        flush(); return words.joined(separator:" ")
    }
}

/// Statistical warning only, never an Arabic reversal or a validity claim.
struct PackArabicOrderEvidence {
    private(set) var words = 0, reversed = 0, logical = 0
    private var distinct = Set<String>()
    mutating func observe(_ target: String) {
        let reverse: Set<String> = ["نم","يف","ىلع","اذه","كلذ","انأ","وه","يه"]
        let normal: Set<String> = ["من","في","على","هذا","ذلك","أنا","هو","هي"]
        for word in target.split(whereSeparator:{!$0.isLetter}) {
            guard word.unicodeScalars.contains(where:{(0x0600...0x06ff).contains($0.value)}) else { continue }
            words += 1
            if reverse.contains(String(word)) { reversed += 1; distinct.insert(String(word)) }
            if normal.contains(String(word)) { logical += 1 }
        }
    }
    var warning: Bool { words >= 12 && reversed >= 4 && distinct.count >= 3 && reversed > logical*3 }
}
