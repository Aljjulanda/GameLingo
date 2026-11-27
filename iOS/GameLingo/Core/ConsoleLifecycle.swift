import Foundation

/// Values come from our bridge, never from upstream Chiaki's enum ordering.
enum ConsoleDisconnect: Int, Codable {
    case unknown = 0, user = 1, network = 2, streaming = 3, shutdown = 4, rest = 5, decoder = 6, suspension = 7
    var terminal: Bool { [.unknown,.user,.shutdown,.rest].contains(self) }
}
struct ConsoleLifecycle {
    enum State: String { case stopped, connecting, active, waitingForConsole, recovering, suspended, requiresActivation }
    private(set) var state: State = .stopped
    private(set) var wanted = false
    private(set) var reason = ConsoleDisconnect.user
    private var readyAt: Double?
    private var disconnectedAt: Double?
    mutating func activate() { wanted = true; state = .connecting; readyAt = nil; disconnectedAt = nil }
    mutating func connected() { guard wanted else { return }; state = .active; disconnectedAt = nil }
    mutating func discovered(ready: Bool, standby: Bool, now: Double) {
        if standby && wanted { disconnect(.rest,now:now) }
        else if ready { readyAt = now }
    }
    mutating func disconnect(_ cause: ConsoleDisconnect, now: Double) {
        reason = cause
        if cause.terminal { wanted = false; state = .requiresActivation; readyAt = nil }
        else if cause == .suspension { state = .suspended; readyAt = nil }
        else { state = .waitingForConsole }
        disconnectedAt = now
    }
    mutating func stop() { wanted = false; state = .stopped; readyAt = nil; disconnectedAt = nil; reason = .user }
    /// Fresh READY received *after* interruption is required. Discovery never wakes.
    mutating func canRetry(now: Double, network: Bool) -> Bool {
        guard wanted, network, let readyAt, now-readyAt <= 4,
              disconnectedAt.map({readyAt >= $0}) ?? true else { return false }
        state = .recovering; return true
    }
    mutating func expireUnknown(now: Double, network: Bool) -> Bool {
        guard wanted, network, let disconnectedAt, now-disconnectedAt >= 45,
              state == .waitingForConsole || state == .suspended else { return false }
        disconnect(.unknown,now:now); return true
    }
}
