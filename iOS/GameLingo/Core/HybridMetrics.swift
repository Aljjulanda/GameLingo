import Foundation

enum TranslationOrigin: String, Codable, CaseIterable {
    case userCorrection, rule, packExact, packNormalized, packPunctuationless
    case reuse, argosCache, argosInference, command, apple
    var isPack: Bool { self == .packExact || self == .packNormalized || self == .packPunctuationless }
    var title: String {
        switch self {
        case .userCorrection: return "تصحيحك المحفوظ"
        case .rule: return "قاعدة مصطلحات"
        case .packExact: return "الحزمة · حرفي"
        case .packNormalized: return "الحزمة · بعد توحيد المسافات"
        case .packPunctuationless: return "الحزمة · دون ترقيم"
        case .reuse: return "إعادة استخدام السطر نفسه"
        case .argosCache: return "Argos · نتيجة مؤقتة"
        case .argosInference: return "Argos · ترجمة جديدة"
        case .command: return "أمر قصير"
        case .apple: return "Apple · تجريبي"
        }
    }
}
enum TranslationFallback: String, Codable, CaseIterable {
    case noDatabase, missing, ambiguous, unsupported, notDialogue
    var title: String {
        switch self {
        case .noDatabase: return "لا توجد قاعدة نشطة"
        case .missing: return "النص غير موجود"
        case .ambiguous: return "مطابقة غامضة"
        case .unsupported: return "مدخل غير مدعوم"
        case .notDialogue: return "ليس حوارًا"
        }
    }
}
struct TranslationDecision {
    var text: String
    var origin: TranslationOrigin
    var fallback: TranslationFallback?
    var game: String?
    var pack: String?
}
struct PackLookupOutcome {
    var text: String?
    var origin: TranslationOrigin = .argosInference
    var fallback: TranslationFallback?
    var game: String?
    var pack: String?
}
/// RAM-only content-free identity. Never contains English or Arabic dialogue.
struct PublishedTranslation: Codable {
    var eventID: String, game: String?, pack: String?
    var origin: TranslationOrigin
    var fallback: TranslationFallback?
}
struct HybridMetrics {
    // Retain legacy attempt counters for comparison; none is the denominator Y.
    var dialogueEvents = 0, lookups = 0, matches = 0, fallbacks = 0, ambiguous = 0
    var argos = 0, exact = 0, normalized = 0, approximate = 0
    var lookupTotal = 0.0
    var samples = LatencySamples()
    private(set) var published = 0, publishedPack = 0
    private(set) var origins: [TranslationOrigin:Int] = [:]
    private(set) var attemptOrigins: [TranslationOrigin:Int] = [:]
    private(set) var fallbackReasons: [TranslationFallback:Int] = [:]
    private(set) var lastEvent: PublishedTranslation?
    private var seen = Set<String>()
    private(set) var saturated = false
    var average: Double { lookups == 0 ? 0 : lookupTotal/Double(lookups) }
    mutating func recordAttempt(_ origin: TranslationOrigin) { attemptOrigins[origin,default:0] += 1 }
    /// Y = first accepted publication of each stable dialogue ID, in the current
    /// selected game/pack activation. Corrections/retries never increment Y.
    mutating func recordPublished(_ event: PublishedTranslation) {
        guard !seen.contains(event.eventID) else { return }
        guard seen.count < 50000 else { saturated = true; return }
        seen.insert(event.eventID); published += 1; lastEvent = event
        origins[event.origin,default:0] += 1
        if event.origin.isPack { publishedPack += 1 }
        if let reason = event.fallback { fallbackReasons[reason,default:0] += 1 }
    }
    func status(active: Bool, damaged: Bool, threshold: Int = 20) -> String {
        if damaged { return "تالفة" }
        guard active else { return "غير مفعّلة (اختر اللعبة)" }
        if publishedPack > 0 { return "تعمل · \(publishedPack) من \(published) من الحزمة" }
        if published >= max(1,threshold) {
            let top = fallbackReasons.sorted { $0.value == $1.value ? $0.key.rawValue < $1.key.rawValue : $0.value > $1.value }.first?.key.title ?? "لا مطابقة"
            return "مفعّلة · لا تطابق بعد \(published) حوار · السبب الأغلب: \(top)"
        }
        return "مفعّلة · بانتظار حوارات منشورة (\(published))"
    }
    var summary: String {
        "Attempts: \(lookups); matches: \(matches); Argos requests: \(argos); published unique IDs Y: \(published); published pack X: \(publishedPack); saturated: \(saturated); lookup avg/p95 ms: \(NumericInput.format(average))/\(NumericInput.format(samples.p95))"
    }
}

struct PackSelfTest {
    var count = 0, matched = 0, usablePairs = 0
    var active = false
    var reasons: [String:Int] = [:]
    var summary: String {
        let outcome = count == 0 ? "لا توجد أزواج حوار صالحة للاختبار" : "طابقت \(matched) من \(count)"
        let details = reasons.sorted{$0.key < $1.key}.map { item -> String in
            let title = TranslationFallback(rawValue:item.key)?.title ?? (item.key == "damaged" ? "تعذر قراءة الحزمة" : "لا أزواج حوار")
            return "\(title): \(item.value)"
        }.joined(separator:"، ")
        return "اختبار اصطناعي فقط: \(outcome) · أزواج صالحة: \(usablePairs) · نشطة: \(active ? "نعم" : "لا") · \(details)"
    }
}
