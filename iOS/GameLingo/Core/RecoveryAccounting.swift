import Foundation

struct RemoteMetrics {
    var attempts = 0, successes = 0, failures = 0, starvations = 0, decoderRequests = 0
    var lastRecoverySeconds = 0.0, uptime = 0.0
    var decodedFrameAge: Double?, encodedFrameAge: Double?
}

/// Mirrors actual native events, not requests from lifecycle/network callbacks.
/// The serial remote-service queue owns this state and the only retry timer.
struct RecoveryAccounting {
    enum Phase { case idle, connecting, connected, waiting, login }
    private(set) var phase = Phase.idle
    private(set) var retryPending = false
    private(set) var metrics = RemoteMetrics()
    private var reconnecting = false
    private var attemptAt = 0.0, connectedAt = 0.0
    mutating func initial(now: Double) { self = RecoveryAccounting(); phase = .connecting; attemptAt = now }
    mutating func reserveRecovery(hasSession: Bool, stalled: Bool, age: Double, now: Double) -> Bool {
        guard !retryPending, phase != .connecting, phase != .login else { return false }
        guard !hasSession || (stalled && age > 12) else { return false }
        if hasSession { metrics.starvations += 1 }
        beginReplacement(now:now); return true
    }
    private mutating func beginReplacement(now: Double) {
        metrics.attempts += 1; reconnecting = true; phase = .connecting; attemptAt = now
    }
    mutating func scheduleRetry() { retryPending = true; phase = .waiting }
    mutating func beginRetry(now: Double) -> Bool {
        guard retryPending else { return false }
        retryPending = false; beginReplacement(now:now); return true
    }
    @discardableResult mutating func established(now: Double) -> Bool {
        guard phase == .connecting || phase == .login else { return false }
        if reconnecting { metrics.successes += 1; metrics.lastRecoverySeconds = max(0,now-attemptAt) }
        reconnecting = false; phase = .connected; connectedAt = now; return true
    }
    mutating func ended() {
        if reconnecting && (phase == .connecting || phase == .login) { metrics.failures += 1 }
        reconnecting = false; phase = .idle
    }
    mutating func loginRequired() { phase = .login }
    mutating func loginSubmitted() { if phase == .login { phase = .connecting } }
    mutating func decoderRequested() { metrics.decoderRequests += 1 }
    mutating func stop() { retryPending = false; reconnecting = false; phase = .idle }
    func snapshot(now: Double) -> RemoteMetrics {
        var value = metrics; value.uptime = phase == .connected ? max(0,now-connectedAt) : 0; return value
    }
}

struct SessionDiagnostics {
    private(set) var lines: [String] = []
    mutating func record(_ stage: String, detail: String, now: Double, foreground: Bool, network: Bool, interrupted: Bool) {
        let safe = String(detail.replacingOccurrences(of:"\n",with:" ").prefix(180))
        lines.append(String(format:"%.2f",now)+" ["+stage+"] "+safe+" fg=\(foreground) net=\(network) audioInterrupted=\(interrupted)")
        if lines.count > 80 { lines.removeFirst(lines.count-80) }
    }
}
