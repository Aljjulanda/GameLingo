import Foundation

struct SourceBox: Codable, Equatable {
    var x: Double, y: Double, w: Double, h: Double
    static let dialogue = SourceBox(x: 0.16, y: 0.65, w: 0.68, h: 0.28)
    var isValid: Bool {
        [x,y,w,h].allSatisfy(\.isFinite) && x >= 0 && y >= 0 && w > 0 && h > 0 && x+w <= 1.000001 && y+h <= 1.000001
    }
    func isAdjacent(to other: SourceBox) -> Bool {
        abs(x+w/2-other.x-other.w/2) < 0.2 && abs(y-other.y) < 0.12
    }
}

enum DialogueText {
    static func normalized(_ text: String) -> String {
        SubtitlePresentation.clean(text).precomposedStringWithCompatibilityMapping.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
    static func matches(_ text: String, _ pattern: String) -> [String] {
        let regex = try! NSRegularExpression(pattern: pattern)
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
            Range($0.range, in: text).map { String(text[$0]) }
        }
    }
    static func words(_ text: String) -> [String] {
        let plain = normalized(text).lowercased().replacingOccurrences(of: "['’`]", with: "", options: .regularExpression)
        return matches(plain, "[+-]?\\d+(?:[.,]\\d+)+|[+-]\\d+|[\\p{L}\\p{N}_]+").map {
            $0.count >= 4 && $0.allSatisfy(\.isLetter) ? $0.replacingOccurrences(of: "l", with: "i") : $0
        }
    }
    static func prefix(_ before: String, _ after: String) -> Bool {
        let a = words(before), b = words(after)
        return a.count >= 2 && b.count > a.count && Array(b.prefix(a.count)) == a
    }
    static func similarity(_ a: String, _ b: String) -> Double {
        guard a.count <= 512 && b.count <= 512 else { return a == b ? 1 : 0 }
        let x = Array(a), y = Array(b)
        guard !x.isEmpty || !y.isEmpty else { return 1 }
        var row = Array(repeating: 0, count: y.count+1)
        for c in x {
            var diagonal = 0
            for j in y.indices {
                let previous = row[j+1]
                row[j+1] = c == y[j] ? diagonal+1 : max(row[j], row[j+1])
                diagonal = previous
            }
        }
        return 2 * Double(row[y.count]) / Double(x.count+y.count)
    }
    static func same(_ before: String, _ after: String) -> Bool {
        let a = words(before), b = words(after)
        guard !a.isEmpty && !b.isEmpty else { return false }
        func names(_ text: String) -> [String] {
            matches(text,"[A-Za-z]+").dropFirst().filter { $0.count >= 3 && $0.first?.isUppercase == true && $0.dropFirst().allSatisfy(\.isLowercase) }
        }
        guard names(before) == names(after) else { return false }
        let destinationsA = destination(before), destinationsB = destination(after)
        if !destinationsA.isEmpty && !destinationsB.isEmpty && destinationsA != destinationsB && !prefix(before,after) && !prefix(after,before) { return false }
        let locations: Set<String> = ["here","there"]
        let locationA = matches(before.lowercased(),"[a-z]+").filter { locations.contains($0) }
        let locationB = matches(after.lowercased(),"[a-z]+").filter { locations.contains($0) }
        if !locationA.isEmpty && !locationB.isEmpty && locationA != locationB { return false }
        if a == b || a.joined() == b.joined() { return true }
        guard semanticMarkers(before) == semanticMarkers(after) else { return false }
        guard matches(before, "[+-]?\\d+(?:[.,]\\d+)*") == matches(after, "[+-]?\\d+(?:[.,]\\d+)*") else { return false }
        if prefix(before, after) || prefix(after, before) { return true }
        let short = a.count < b.count ? a : b, long = a.count < b.count ? b : a
        if short.count >= 3 && long.count > short.count && long.count-short.count <= 2 && Double(short.count)/Double(long.count) >= 0.72 {
            var index = 0, missing: [String] = []
            for word in long {
                if index < short.count && word == short[index] { index += 1 } else { missing.append(word) }
            }
            let negations: Set<String> = ["no","not","never","dont","cannot","cant","wont","without"]
            if index == short.count && negations.isDisjoint(with: missing) { return true }
        }
        guard a.count == b.count else { return false }
        let changed = zip(a,b).filter { pair in pair.0 != pair.1 }
        guard changed.count == 1, let (x,y) = changed.first else { return false }
        return min(x.count,y.count) >= 4 && similarity(x,y) >= 0.8 && similarity(a.joined(),b.joined()) >= 0.88
    }
    static func semanticMarkers(_ text: String) -> [String] {
        let plain = text.lowercased().replacingOccurrences(of:"['’`]",with:"",options:.regularExpression)
        let protected: Set<String> = ["no","not","never","dont","cannot","cant","wont","without","isnt","wasnt","didnt","shouldnt","wouldnt","couldnt","he","she","they","we","you","i","left","right","north","south","east","west","open","close","enter","exit","attack","defend","take","drop","give","keep","stop","start","push","pull","save","kill","follow","stay","leave","collect"]
        return matches(plain,"[+-]?\\d+(?:[.,]\\d+)*|[a-z]+").filter { protected.contains($0) || $0.contains(where:\.isNumber) }
    }
    static func destination(_ text: String) -> [String] {
        let tokens = matches(text.lowercased(),"[a-z]+")
        let anchors: Set<String> = ["to","toward","towards","at","near","through","into","inside","outside","behind","follow","reach","find","visit","enter","exit","open","close"]
        guard let at = tokens.lastIndex(where:{ anchors.contains($0) }) else { return [] }
        let ignored: Set<String> = ["the","a","an","me","him","her","us","them"]
        return Array(tokens.dropFirst(at+1).filter { !ignored.contains($0) }.prefix(12))
    }
}

struct DialogueJob: Equatable {
    let id: String, text: String, generation: UInt64, correction: Bool, box: SourceBox, frameMilliseconds: Int64
    var speaker: String? = nil
    var confidence: Double = 1
    var meaningfulCorrection = false
    var eventBoundary = ""
    var sourceGapMilliseconds: Int64 = 0
}

enum Observation {
    case unchanged
    case gone(String)
    case dialogue(DialogueJob, previousID: String?)
}

/// Confined to the OCR serial queue. Identity is independent of translation completion.
struct DialogueTracker {
    private let namespace = UUID().uuidString
    private var serial: UInt64 = 0
    private(set) var generation: UInt64 = 0
    private(set) var current: DialogueJob?
    private var lastSeen: TimeInterval = 0
    private var empty = 0
    private var suppressContinuingCurrent = false
    private var firstSeen: TimeInterval = 0
    private var confirmedGap: Int64 = 0
    private(set) var duplicatesSuppressed = 0
    private(set) var correctionsMerged = 0
    static let dropoutGrace: TimeInterval = 0.75
    mutating func markInterrupted() { suppressContinuingCurrent = current != nil }
    mutating func observe(text raw: String, box: SourceBox, now: TimeInterval, frameMilliseconds: Int64, speaker: String? = nil, confidence: Double = 1) -> Observation {
        let text = String(DialogueText.normalized(raw).prefix(1800))
        guard !text.isEmpty else {
            empty += 1
            guard empty >= 2, let old = current, now-lastSeen >= Self.dropoutGrace else { return .unchanged }
            confirmedGap = Int64((now-lastSeen)*1000)
            current = nil; generation &+= 1
            return .gone(old.id)
        }
        empty = 0
        if let old = current, (speaker == nil || speaker == old.speaker), DialogueText.words(text) == DialogueText.words(old.text), box.isAdjacent(to: old.box) {
            lastSeen = now
            duplicatesSuppressed += 1
            return .unchanged
        }
        let old = current
        suppressContinuingCurrent = false
        let adjacent = old.map { box.isAdjacent(to:$0.box) && (speaker == nil || $0.speaker == nil || speaker == $0.speaker) } ?? false
        let equivalent = old.map { DialogueText.same($0.text,text) } ?? false
        // A high-overlap semantic correction during initial OCR acquisition can
        // repair the same event. Later changes remain fresh dialogue events.
        let important = old.map { !equivalent && adjacent && now-firstSeen <= 0.8 && $0.confidence < 0.65 && confidence >= 0.8 && confidence-$0.confidence >= 0.2 && DialogueText.similarity($0.text.lowercased(),text.lowercased()) >= 0.72 } ?? false
        let correction = adjacent && (equivalent || important)
        if let old, correction && equivalent && confidence <= old.confidence && !DialogueText.prefix(old.text,text) && (speaker == nil || speaker == old.speaker) {
            // Keep the best bounded reference, instead of allowing a chain of
            // successively worse OCR variants to drift into a new event.
            lastSeen = now; correctionsMerged += 1; duplicatesSuppressed += 1
            return .unchanged
        }
        if !correction { serial &+= 1; firstSeen = now }
        generation &+= 1
        let removedLabel = old.map { prior in
            guard prior.speaker == nil, let speaker else { return false }
            let prefix = DialogueText.words(speaker), words = DialogueText.words(prior.text)
            return words.starts(with:prefix) && Array(words.dropFirst(prefix.count)) == DialogueText.words(text)
        } ?? false
        if correction { correctionsMerged += 1 }
        let boundary = correction ? "continuity" : old == nil ? (confirmedGap > 0 ? "source_gap" : "initial") : old!.speaker != nil && speaker != nil && old!.speaker != speaker ? "speaker_change" : !box.isAdjacent(to:old!.box) ? "spatial_change" : "dialogue_change"
        let job = DialogueJob(id: correction ? old!.id : "\(namespace)-\(serial)", text: text, generation: generation, correction: correction, box: box, frameMilliseconds: frameMilliseconds,speaker:speaker ?? (correction ? old?.speaker : nil),confidence:confidence,meaningfulCorrection:correction && (!equivalent || removedLabel),eventBoundary:boundary,sourceGapMilliseconds:confirmedGap)
        confirmedGap = 0
        current = job; lastSeen = now
        return .dialogue(job, previousID: correction ? nil : old?.id)
    }
    func accepts(_ result: DialogueJob) -> Bool {
        guard let current, current.id == result.id else { return false }
        return current.generation == result.generation || (DialogueText.semanticMarkers(result.text) == DialogueText.semanticMarkers(current.text) && (DialogueText.words(result.text) == DialogueText.words(current.text) || DialogueText.prefix(result.text,current.text)))
    }
    mutating func reset() { current = nil; empty = 0; suppressContinuingCurrent = false; confirmedGap = 0; duplicatesSuppressed = 0; correctionsMerged = 0; generation &+= 1 }
}

/// All access must be serialized by the owner. There is never a dialogue history.
struct BoundedLRU<Key: Hashable, Value> {
    private(set) var values: [Key: Value] = [:]
    private var order: [Key] = []
    let capacity: Int
    init(capacity: Int) { self.capacity = max(1,capacity) }
    mutating func get(_ key: Key) -> Value? {
        guard let value = values[key] else { return nil }
        order.removeAll { $0 == key }; order.append(key)
        return value
    }
    mutating func put(_ value: Value, for key: Key) {
        values[key] = value; order.removeAll { $0 == key }; order.append(key)
        while order.count > max(1,capacity) { values.removeValue(forKey: order.removeFirst()) }
    }
}
