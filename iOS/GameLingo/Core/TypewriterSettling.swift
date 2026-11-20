import Foundation

/// RAM-only observations, not dialogue history or a second identity/duplicate
/// system. Publication can settle while the existing worker translates early.
struct TypewriterReading: Equatable {
    var text: String, speaker: String?
    var box: SourceBox
    var confidence: Double = 1
}

/// Translation is allowed to start immediately. Only publication is held, so a
/// fast interrupted line whose result is ready can be delivered BEFORE the
/// existing tracker moves to the next source. No new IDs or TV clocks are made.
struct TypewriterPublication {
    private var settling: TypewriterSettling
    private var permitted: TypewriterReading?
    private(set) var active = false
    var needsConfirmation: Bool { active && settling.needsConfirmation }
    var detected: Bool { settling.detected }
    init(knownTypewriter: Bool = false) { settling = TypewriterSettling(knownTypewriter:knownTypewriter) }
    mutating func observe(_ reading: TypewriterReading, now: Double, enabled: Bool, maxWait: Double = 3, window: Int = 5) -> [TypewriterReading] {
        active = enabled && maxWait > 0
        let result = settling.observe(reading,now:now,enabled:enabled,maxWait:maxWait,window:window)
        if let last = result.ready.last, last.text == reading.text, last.box.isAdjacent(to:reading.box) { permitted = reading }
        else { permitted = nil }
        return result.ready
    }
    private static func compatible(_ job: DialogueJob, _ reading: TypewriterReading) -> Bool {
        job.box.isAdjacent(to:reading.box) && (job.speaker == nil || reading.speaker == nil || job.speaker == reading.speaker)
    }
    func canPublish(_ job: DialogueJob) -> Bool {
        !active || permitted.map { $0.text == job.text && Self.compatible(job,$0) } == true
    }
    static func canFlush(_ job: DialogueJob, ready: [TypewriterReading]) -> Bool {
        ready.contains { Self.compatible(job,$0) && ($0.text == job.text || $0.text.hasPrefix(job.text)) }
    }
}

struct TypewriterDecision {
    var ready: [TypewriterReading]
    var detected: Bool
    var waiting: Bool
}

struct TypewriterSettling {
    private(set) var detected = false
    private var previous: TypewriterReading?
    private var growth: [Int] = []
    private var pending: TypewriterReading?
    private var released: TypewriterReading?
    private var started = 0.0
    private var lastRead: Double?
    var needsConfirmation: Bool { pending != nil }
    init(knownTypewriter: Bool = false) { detected = knownTypewriter }
    mutating func reset(knownTypewriter: Bool = false) { self = Self(knownTypewriter:knownTypewriter) }
    private func sameRegion(_ a: TypewriterReading, _ b: TypewriterReading) -> Bool {
        a.box.isAdjacent(to:b.box) && a.speaker == b.speaker
    }
    private func extending(_ a: TypewriterReading, _ b: TypewriterReading) -> Int {
        guard sameRegion(a,b), a.confidence >= 0.75, b.confidence >= 0.75,
              a.text.filter(\.isLetter).count >= 3, b.text.hasPrefix(a.text), b.text.count > a.text.count else { return 0 }
        return b.text.dropFirst(a.text.count).filter(\.isLetter).count
    }
    private mutating func emit(_ readings: [TypewriterReading], waiting: Bool) -> TypewriterDecision {
        if let last = readings.last { released = last }
        return TypewriterDecision(ready:readings,detected:detected,waiting:waiting)
    }
    mutating func observe(_ reading: TypewriterReading, now: Double, enabled: Bool, maxWait: Double = 3, window: Int = 5) -> TypewriterDecision {
        let limit = maxWait.isFinite ? max(0,min(3,maxWait)) : 3
        guard enabled && limit > 0 else {
            pending = nil; previous = nil; growth = []; lastRead = nil
            return emit([reading],waiting:false)
        }
        if let lastRead, now-lastRead > 2 { growth = [] }
        lastRead = now
        if let previous {
            let amount = extending(previous,reading)
            // Identical real OCR reads settle a candidate; punctuation-only
            // changes, shrinking/case jitter and unrelated lines reset evidence.
            if amount > 0 { growth.append(amount) }
            else if previous.text != reading.text || !sameRegion(previous,reading) { growth = [] }
            else { growth.append(0) }
            growth = Array(growth.suffix(max(3,min(20,window))))
            if growth.filter({$0 > 0}).count >= 2 && growth.reduce(0,+) >= 4 { detected = true }
        }
        previous = reading
        var interrupted: [TypewriterReading] = []
        if let pending, !(pending.text == reading.text && sameRegion(pending,reading)), extending(pending,reading) == 0 {
            interrupted = [pending]; self.pending = nil
        }
        if reading.text.isEmpty || !detected || !SourceGuidedPunctuation.terminalRun(reading.text).isEmpty {
            pending = nil
            return emit(interrupted+[reading],waiting:false)
        }
        if let released, released.text == reading.text, sameRegion(released,reading), pending == nil { return emit([reading],waiting:false) }
        if let pending, pending.text == reading.text && sameRegion(pending,reading) {
            self.pending = nil
            return emit([reading],waiting:false)
        }
        if pending == nil { started = now }
        pending = reading
        if now-started >= limit {
            pending = nil
            return emit(interrupted+[reading],waiting:false)
        }
        return emit(interrupted,waiting:true)
    }
}
