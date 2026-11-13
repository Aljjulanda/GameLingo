import Foundation

enum NumericInput {
    static func parse(_ text: String, range: ClosedRange<Double>, integer: Bool = false) -> Double? {
        var value = ""
        for character in text.trimmingCharacters(in:.whitespacesAndNewlines) {
            if let digit = character.wholeNumberValue, (0...9).contains(digit) { value += String(digit) }
            else if character == "٫" { value += "." }
            else if "0123456789.-+".contains(character) { value.append(character) }
            else { return nil }
        }
        guard let number = Double(value), number.isFinite else { return nil }
        return min(range.upperBound,max(range.lowerBound,integer ? number.rounded() : number))
    }
    static func format(_ value: Double) -> String { String(format:"%.2f",locale:Locale(identifier:"en_US_POSIX"),value).replacingOccurrences(of:"\\.?0+$",with:"",options:.regularExpression) }
}

struct LatencySamples {
    private(set) var values: [Double] = []
    mutating func record(_ value: Double) {
        guard value.isFinite, value >= 0 else { return }
        values.append(value); if values.count > 120 { values.removeFirst(values.count-120) }
    }
    var p95: Double {
        guard !values.isEmpty else { return 0 }
        return values.sorted()[max(0,Int(ceil(Double(values.count)*0.95))-1)]
    }
}

enum SessionIntentStore {
    private static let key = "GameLingo.sessionWanted.v1"
    static func load(_ defaults: UserDefaults = .standard) -> Bool { defaults.bool(forKey:key) }
    static func save(_ wanted: Bool, to defaults: UserDefaults = .standard) { defaults.set(wanted,forKey:key) }
}
