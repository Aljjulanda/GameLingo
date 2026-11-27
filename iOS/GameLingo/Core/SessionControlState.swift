import Foundation

/// Persist actual connection state with a short lease, never an independent toggle.
struct SessionControlSnapshot: Codable {
    enum Phase: String, Codable { case stopped, starting, active, recovering, suspended }
    var phase: Phase
    var updated: Date
    func isActive(now: Date = Date()) -> Bool { phase == .active && (0...12).contains(now.timeIntervalSince(updated)) }
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
    static func request(_ start: Bool) {
        let d = defaults; d.set(["start":start,"at":Date().timeIntervalSince1970] as [String:Any],forKey:"session.request.v1"); d.synchronize()
    }
    static func consumeRequest(now: Date = Date()) -> Bool? {
        let d = defaults; d.synchronize()
        guard let value = d.dictionary(forKey:"session.request.v1") else { return nil }
        d.removeObject(forKey:"session.request.v1"); d.synchronize()
        guard let at = value["at"] as? Double, (0...30).contains(now.timeIntervalSince1970-at) else { return nil }
        return value["start"] as? Bool
    }
}
