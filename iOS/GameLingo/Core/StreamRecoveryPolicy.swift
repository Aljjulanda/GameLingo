import Foundation

/// Frame silence is evidence about the video path, never permission to wake a console.
/// Call on the serial native queue. Require two observations and a cooldown before
/// replacing an established session; a single delayed UI callback is insufficient.
struct StreamRecoveryPolicy {
    private var silenceObservedAt: Double?
    private var lastReplacementAt: Double?
    mutating func replacementNeeded(encodedAge: Double?, decodedAge: Double?, sessionAge: Double, now: Double) -> Bool {
        guard sessionAge >= 20, let encodedAge, let decodedAge,
              encodedAge.isFinite, decodedAge.isFinite,
              encodedAge > 20, decodedAge > 20 else { silenceObservedAt = nil; return false }
        guard let observed = silenceObservedAt else { silenceObservedAt = now; return false }
        guard now-observed >= 4, lastReplacementAt.map({ now-$0 >= 60 }) ?? true else { return false }
        lastReplacementAt = now; silenceObservedAt = nil; return true
    }
    mutating func resetObservation() { silenceObservedAt = nil }
    static func delay(_ failures: Int) -> Double {
        let delays: [Double] = [2,4,8,15,30,60]
        return delays[max(0,min(delays.count-1,failures-1))]
    }
}
