import Foundation

/// Persist actual connection state with a short lease, never an independent toggle.
struct SessionControlSnapshot: Codable {
    enum Phase: String, Codable { case stopped, starting, active, recovering, suspended }
    var phase: Phase
    var updated: Date
    func isActive(now: Date = Date()) -> Bool { phase == .active && (0...12).contains(now.timeIntervalSince(updated)) }
    // Pending/recovering sessions must also be switchable OFF. Enabled does
    // not claim that the PS5 has connected or translated frames are arriving.
    func isEnabled(now: Date = Date()) -> Bool { enabledValue(now:now) == true }
    func enabledValue(now: Date = Date()) -> Bool? {
        guard (0...12).contains(now.timeIntervalSince(updated)) else { return nil }
        return phase != .stopped
    }
}
enum SessionControlStore {
    static let group = "group.dev.gamelingo.ios"
    static let kind = "dev.gamelingo.ios.translation"
    private static var defaults: UserDefaults { UserDefaults(suiteName:group) ?? .standard }
    static func snapshot() -> SessionControlSnapshot {
        let d = defaults; d.synchronize()
        return d.data(forKey:"session.actual.v1").flatMap{try? JSONDecoder().decode(SessionControlSnapshot.self,from:$0)} ?? SessionControlSnapshot(phase:.stopped,updated:Date(timeIntervalSince1970:0))
    }
    static func save(_ phase: SessionControlSnapshot.Phase) {
        let d = defaults
        d.set(try? JSONEncoder().encode(SessionControlSnapshot(phase:phase,updated:Date())),forKey:"session.actual.v1"); d.synchronize()
    }
}
