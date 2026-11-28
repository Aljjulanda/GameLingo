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

/// Bounded command receipts; no game text, credentials or independent session state.
enum ControlCommandReceipt {
    static func record(_ stage: String, detail: String = "", extensionProcess: Bool = false) {
        let key = extensionProcess ? "control.extension.receipt.v1" : "control.app.receipt.v1"
        let value = ["stage":stage,"detail":String(detail.prefix(240)),"at":ISO8601DateFormatter().string(from:Date())]
        for d in [UserDefaults.standard, UserDefaults(suiteName:SessionControlStore.group)].compactMap({$0}) {
            d.set(value,forKey:key); d.synchronize()
        }
    }
    static func summary() -> String {
        let shared = UserDefaults(suiteName:SessionControlStore.group); shared?.synchronize()
        return ["control.extension.receipt.v1","control.app.receipt.v1"].compactMap { key in
            let value = (key.contains("extension") ? shared?.dictionary(forKey:key) : UserDefaults.standard.dictionary(forKey:key))
            guard let value else { return nil }
            return ["at","stage","detail"].compactMap{value[$0] as? String}.filter{!$0.isEmpty}.joined(separator:" · ")
        }.joined(separator:"\n")
    }
}
