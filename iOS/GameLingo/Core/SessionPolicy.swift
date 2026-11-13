import Foundation

/// User intent is never inferred from a socket failure or a scene transition.
struct SessionPolicy {
    private(set) var wanted = false
    private(set) var epoch: UInt64 = 0
    var foreground = true
    var network = true
    var experimentalAudio = false
    var audioActive = false
    var interrupted = false
    var canExecute: Bool { foreground || (experimentalAudio && audioActive && !interrupted) }
    var canRecover: Bool { wanted && network && canExecute }
    mutating func start() { wanted = true; epoch &+= 1 }
    mutating func stop() { wanted = false; epoch &+= 1 }
    func accepts(_ scheduledEpoch: UInt64) -> Bool { wanted && epoch == scheduledEpoch }
    static func retryDelay(_ attempt: Int, jitter: Double = 0) -> Double {
        let delays: [Double] = [2,4,8,15,30]
        return delays[max(0,min(delays.count-1,attempt))] + max(0,min(1,jitter))
    }
}

struct AdvancedSettings: Codable, Equatable {
    var backgroundAudio = false
    var contextEnabled = true
    var contextCapacity = 5
    var showSpeakers = true
    var speakerColor = "#A6C7D8"
    /// Explicit, user-supplied name dictionary. No automatic name guessing.
    var speakerNames = ""
    /// Exact whole-sentence translations, one English = Arabic pair per line.
    var terminology = ""
    mutating func validate() {
        contextCapacity = max(1,min(20,contextCapacity))
        speakerNames = String(speakerNames.prefix(2000)); terminology = String(terminology.prefix(8000))
        if speakerColor.range(of:"^#[0-9A-Fa-f]{6}$",options:.regularExpression) == nil { speakerColor = "#A6C7D8" }
    }
}
