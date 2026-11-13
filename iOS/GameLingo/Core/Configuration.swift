import Foundation

enum LingoError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case .invalid(let text) = self { return text }; return nil }
}

enum LAN {
    static func isPrivateIPv4(_ host: String) -> Bool {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        let a = parts.compactMap { Int($0) }
        guard a.count == 4, a.allSatisfy({ (0...255).contains($0) }), parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) else { return false }
        return a[0] == 10 || (a[0] == 192 && a[1] == 168) || (a[0] == 172 && (16...31).contains(a[1]))
    }
}

struct ConsoleCredentials: Codable, Identifiable {
    var id: String
    var name: String
    var host: String
    var registrationKey: Data
    var key: Data
    func validate() throws {
        guard !id.isEmpty, LAN.isPrivateIPv4(host), registrationKey.count == 16, key.count == 16 else {
            throw LingoError.invalid("بيانات تسجيل PS5 غير صالحة")
        }
    }
    static func accountID(_ base64: String, pin: String) throws -> Data {
        guard let id = Data(base64Encoded: base64.trimmingCharacters(in: .whitespacesAndNewlines)), id.count == 8,
              pin.count == 8, pin.utf8.allSatisfy({ (48...57).contains($0) }) else {
            throw LingoError.invalid("أدخل Account ID بصيغة Base64 من 8 بايت ورمز ربط من 8 أرقام")
        }
        return id
    }
}

enum PerformanceMode: String, Codable, CaseIterable, Hashable {
    case economy, balanced, performance
    var rate: Double { switch self { case .economy: return 2; case .balanced: return 4; case .performance: return 8 } }
    var title: String { switch self { case .economy: return "اقتصادي"; case .balanced: return "متوازن"; case .performance: return "أداء" } }
    func samplingRate(thermal: Int, lowPower: Bool) -> Double {
        if thermal >= 3 { return 0 }
        return min(rate, thermal >= 2 || lowPower ? 2 : rate)
    }
}

enum JSONValue: Codable, Equatable {
    case number(Double), bool(Bool), string(String)
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let value = try? c.decode(Bool.self) { self = .bool(value) }
        else if let value = try? c.decode(Double.self) { self = .number(value) }
        else { self = .string(try c.decode(String.self)) }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self { case .number(let v): try c.encode(v); case .bool(let v): try c.encode(v); case .string(let v): try c.encode(v) }
    }
    var object: Any { switch self { case .number(let v): return v; case .bool(let v): return v; case .string(let v): return v } }
}

struct DisplaySchema: Decodable {
    var defaults: [String: JSONValue]
    var bounds: [String: [Double]]
    static let shared: DisplaySchema = {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        return try! JSONDecoder().decode(DisplaySchema.self, from: Data(contentsOf: bundle.url(forResource: "tv-display-schema", withExtension: "json")!))
    }()
}

struct TVSettings: Codable, Equatable {
    var values = DisplaySchema.shared.defaults
    var revision: Int64 = 0
    func number(_ key: String) -> Double { if case .number(let v) = values[key] { return v }; return 0 }
    func bool(_ key: String) -> Bool { if case .bool(let v) = values[key] { return v }; return false }
    func string(_ key: String) -> String { if case .string(let v) = values[key] { return v }; return "" }
    mutating func set(_ key: String, _ value: JSONValue) {
        guard let original = DisplaySchema.shared.defaults[key] else { return }
        switch (original,value) {
        case (.number, .number(let n)):
            guard n.isFinite, let bounds = DisplaySchema.shared.bounds[key] else { return }
            values[key] = .number(max(bounds[0],min(bounds[1],n)))
        case (.bool, .bool): values[key] = value
        case (.string, .string(let s)):
            if key.hasSuffix("color") && s.range(of: "^#[0-9A-Fa-f]{6}$", options: .regularExpression) == nil { return }
            values[key] = .string(String(s.prefix(80)))
        default: return
        }
        values["max_seconds"] = .number(max(number("min_seconds"),number("max_seconds")))
        values["hard_seconds"] = .number(max(number("min_seconds"),number("hard_seconds")))
        revision = max(revision+1,Int64(Date().timeIntervalSince1970*1000))
    }
    var wire: [String: Any] { var result = values.mapValues(\.object); result["revision"] = revision; return result }
    static func importWire(_ data: Data) throws -> TVSettings {
        guard data.count <= 1_048_576, let object = try JSONSerialization.jsonObject(with:data) as? [String:Any] else { throw LingoError.invalid("ملف إعدادات غير صالح") }
        let raw = object["display"] as? [String:Any] ?? object["settings"] as? [String:Any] ?? object
        let known = raw.filter { DisplaySchema.shared.defaults[$0.key] != nil }
        guard !known.isEmpty else { throw LingoError.invalid("لا يحتوي الملف على مظهر ترجمة محفوظ") }
        let decoded = try JSONDecoder().decode([String:JSONValue].self,from:JSONSerialization.data(withJSONObject:known))
        var settings = TVSettings()
        for (key,value) in decoded { settings.set(key,value) }
        let incoming = (raw["revision"] as? NSNumber)?.int64Value ?? 0
        settings.revision = max(settings.revision,incoming+1)
        return settings
    }
    mutating func preset(_ name: String) {
        values = DisplaySchema.shared.defaults
        switch name {
        case "Classic": set("background",.bool(false)); set("outline",.bool(true))
        case "Cinema": set("outline",.bool(false))
        case "Gaming": set("bold",.bool(true)); set("outline_width",.number(3)); set("background_opacity",.number(75))
        case "Minimal": set("background",.bool(false)); set("outline",.bool(false))
        default: break
        }
        revision = max(revision+1,Int64(Date().timeIntervalSince1970*1000))
    }
}

struct AppSettings: Codable {
    var display = TVSettings()
    var roi = SourceBox.dialogue
    var mode = PerformanceMode.balanced
    var selectedConsoleID: String?
    var localIP = ""
    var dimScreen = false
    static func load(from defaults: UserDefaults = .standard) -> AppSettings {
        guard let data = defaults.data(forKey: "GameLingo.settings.v1"), var value = try? JSONDecoder().decode(Self.self,from: data) else { return Self() }
        if !value.roi.isValid { value.roi = .dialogue }
        var validated = TVSettings()
        for (key,item) in value.display.values { validated.set(key,item) }
        validated.revision = max(value.display.revision,validated.revision)
        value.display = validated
        return value
    }
    func save(to defaults: UserDefaults = .standard) throws {
        defaults.set(try JSONEncoder().encode(self),forKey: "GameLingo.settings.v1")
    }
}
