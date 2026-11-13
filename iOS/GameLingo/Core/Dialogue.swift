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
        text.precomposedStringWithCompatibilityMapping.split(whereSeparator: \.isWhitespace).joined(separator: " ")
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
    private static func similarity(_ a: String, _ b: String) -> Double {
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
        if a == b || a.joined() == b.joined() { return true }
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
        return min(x.count,y.count) >= 5 && x.first == y.first && x.last == y.last && similarity(x,y) >= 0.8 && similarity(a.joined(),b.joined()) >= 0.9
    }
}

struct DialogueJob: Equatable {
    let id: String, text: String, generation: UInt64, correction: Bool, box: SourceBox, frameMilliseconds: Int64
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
    mutating func observe(text raw: String, box: SourceBox, now: TimeInterval, frameMilliseconds: Int64) -> Observation {
        let text = String(DialogueText.normalized(raw).prefix(1800))
        guard !text.isEmpty else {
            empty += 1
            guard empty >= 2, let old = current else { return .unchanged }
            current = nil; generation &+= 1
            return .gone(old.id)
        }
        empty = 0
        if let old = current, DialogueText.words(text) == DialogueText.words(old.text), now-lastSeen <= 1.5, box.isAdjacent(to: old.box) {
            lastSeen = now
            return .unchanged
        }
        let old = current
        let correction = old.map { now-lastSeen <= 1.5 && box.isAdjacent(to: $0.box) && DialogueText.same($0.text,text) } ?? false
        if !correction { serial &+= 1 }
        generation &+= 1
        let job = DialogueJob(id: correction ? old!.id : "\(namespace)-\(serial)", text: text, generation: generation, correction: correction, box: box, frameMilliseconds: frameMilliseconds)
        current = job; lastSeen = now
        return .dialogue(job, previousID: correction ? nil : old?.id)
    }
    func accepts(_ result: DialogueJob) -> Bool {
        guard let current, current.id == result.id else { return false }
        return current.generation == result.generation || DialogueText.prefix(result.text,current.text)
    }
    mutating func reset() { current = nil; empty = 0; generation &+= 1 }
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
