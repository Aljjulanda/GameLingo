import Foundation

enum NamePlaceholderForm: String, CaseIterable {
    case underscores, letters, brackets, guillemets
    func marker(_ index: Int) -> String {
        switch self {
        case .underscores: return "__GLNAME_\(index)__"
        case .letters: return "ZXQNAME\(index)ZXQ"
        case .brackets: return "[GLNAME\(index)]"
        case .guillemets: return "«GLNAME\(index)»"
        }
    }
}
enum NameProtectionPolicy {
    // Select only after the four-form native Argos/control experiment. A nil
    // policy offers no dead setting and leaves the proven Argos route intact.
    static let form: NamePlaceholderForm? = nil
}
enum ProtectedNameTranslation {
    static func run(_ source: String, names: [GameName], form: NamePlaceholderForm?, translate: (String) throws -> String) rethrows -> String {
        guard let form, let plan = NameProtectionPlan.make(source,names:names,form:form) else { return try translate(source) }
        let output = try translate(plan.input)
        if let restored = plan.restore(output) { return restored }
        return try translate(source)
    }
}
struct NameProtectionPlan {
    struct Replacement { let marker: String, english: String, arabic: String }
    let input: String
    let replacements: [Replacement]
    private static let common: Set<String> = ["bill","grace","will","may","mark","rose","faith","hope","chase","hunter"]
    private static func pattern(_ name: String) -> String { "(?<![\\p{L}\\p{N}_])"+NSRegularExpression.escapedPattern(for:name)+"(?![\\p{L}\\p{N}_])" }
    static func make(_ source: String, names: [GameName], form: NamePlaceholderForm) -> Self? {
        guard source.count <= 4096, !source.contains("GLNAME"), !source.contains("ZXQNAME") else { return nil }
        var matches: [(Range<String.Index>,GameName)] = []
        for name in names.filter({source.range(of:$0.english,options:.caseInsensitive) != nil}).sorted(by:{$0.english.count > $1.english.count}) {
            guard name.valid, let regex = try? NSRegularExpression(pattern:pattern(name.english),options:.caseInsensitive) else { continue }
            for match in regex.matches(in:source,range:NSRange(source.startIndex...,in:source)) {
                guard let range = Range(match.range,in:source), !matches.contains(where:{$0.0.overlaps(range)}) else { continue }
                if common.contains(name.id) {
                    let spelling = source[range]
                    let prefix = source[..<range.lowerBound].trimmingCharacters(in:.whitespacesAndNewlines.union(CharacterSet(charactersIn:"\"'“”‘’([{")))
                    let midSentence = prefix.contains(where:\.isLetter) && !prefix.hasSuffix(".") && !prefix.hasSuffix("?") && !prefix.hasSuffix("!") && !prefix.hasSuffix("…")
                    let next = source[range.upperBound...].drop(while:\.isWhitespace).first
                    let vocative = next == "," || next == "!" || next == ":"
                    guard spelling.first?.isUppercase == true, midSentence || vocative else { continue }
                }
                matches.append((range,name))
            }
        }
        matches.sort { $0.0.lowerBound < $1.0.lowerBound }
        guard !matches.isEmpty, matches.count <= 16 else { return nil }
        let replacements = matches.enumerated().map { Replacement(marker:form.marker($0.offset),english:$0.element.1.english,arabic:$0.element.1.arabic) }
        let input = NSMutableString(string:source)
        for index in matches.indices.reversed() { input.replaceCharacters(in:NSRange(matches[index].0,in:source),with:replacements[index].marker) }
        return Self(input:input as String,replacements:replacements)
    }
    func restore(_ output: String) -> String? {
        guard output.count <= 16000 else { return nil }
        var previous = output.startIndex
        for replacement in replacements {
            let ranges = output.exactRanges(of:replacement.marker)
            guard ranges.count == 1, let range = ranges.first, range.lowerBound >= previous else { return nil }
            if range.lowerBound > output.startIndex {
                let before = output[output.index(before:range.lowerBound)]
                guard !(before.isLetter || before.isNumber || before == "_") && before != replacement.marker.first else { return nil }
            }
            if range.upperBound < output.endIndex {
                let after = output[range.upperBound]
                guard !(after.isLetter || after.isNumber || after == "_") && after != replacement.marker.last else { return nil }
            }
            previous = range.upperBound
        }
        var restored = output
        for replacement in replacements { restored = restored.replacingOccurrences(of:replacement.marker,with:replacement.arabic) }
        guard !restored.contains("GLNAME"), !restored.contains("ZXQNAME") else { return nil }
        return restored
    }
    /// Native fixture control: surviving markers alone are not evidence that
    /// the model preserved the surrounding words. Compare that separately.
    func contextUnchanged(_ output: String, baseline: String) -> Bool {
        guard restore(output) != nil else { return false }
        var masked = baseline
        for replacement in replacements {
            var found = false
            for spelling in [replacement.arabic,replacement.english] {
                guard let regex = try? NSRegularExpression(pattern:Self.pattern(spelling),options:.caseInsensitive),
                      let match = regex.firstMatch(in:masked,range:NSRange(masked.startIndex...,in:masked)), let range = Range(match.range,in:masked) else { continue }
                masked.replaceSubrange(range,with:replacement.marker); found = true; break
            }
            guard found else { return false }
        }
        func normalized(_ value: String) -> String { value.split(whereSeparator:\.isWhitespace).joined(separator:" ") }
        return normalized(masked) == normalized(output)
    }
}

private extension String {
    func exactRanges(of needle: String) -> [Range<String.Index>] {
        var result: [Range<String.Index>] = [], start = startIndex
        while start < endIndex, let range = range(of:needle,range:start..<endIndex) { result.append(range); start = range.upperBound }
        return result
    }
}
