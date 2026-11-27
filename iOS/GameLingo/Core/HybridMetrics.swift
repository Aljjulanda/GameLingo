import Foundation

enum TranslationOrigin: String, Codable, CaseIterable {
    case userCorrection, rule, packExact, packNormalized, packPunctuationless
    case reuse, argosCache, argosInference, command, apple, packOCR, packFuzzy, learningMemory
    var isPack: Bool { [.packExact,.packNormalized,.packPunctuationless,.packOCR,.packFuzzy].contains(self) }
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
        case .packOCR: return "الحزمة · تصحيح OCR محمي"
        case .packFuzzy: return "الحزمة · مطابقة محمية"
        case .learningMemory: return "ذاكرة التعلم المعتمدة"
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
    var basis: TranslationOrigin? = nil
    // Present only for opt-in capture/trace; stripped before the RAM reuse cache.
    var engineInput: String? = nil
    var rawOutput: String? = nil
    var punctuationUnbalanced = false
    var withoutEngineTrace: Self { var copy = self; copy.engineInput = nil; copy.rawOutput = nil; return copy }
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
    var basis: TranslationOrigin? = nil
    var isPackBacked: Bool { pack != nil && (origin.isPack || (origin == .reuse && basis?.isPack == true)) }
}
struct HybridMetrics {
    // Retain legacy attempt counters for comparison; none is the denominator Y.
    var dialogueEvents = 0, lookups = 0, matches = 0, fallbacks = 0, ambiguous = 0
    var argos = 0, exact = 0, normalized = 0, punctuationless = 0, approximate = 0
    var ocrTolerant = 0, contextResolved = 0, misses = 0
    var lookupTotal = 0.0
    var samples = LatencySamples()
    private(set) var published = 0, publishedPack = 0
    private(set) var origins: [TranslationOrigin:Int] = [:]
    private(set) var attemptOrigins: [TranslationOrigin:Int] = [:]
    private(set) var attemptFallbackReasons: [TranslationFallback:Int] = [:]
    private(set) var fallbackReasons: [TranslationFallback:Int] = [:]
    private(set) var lastEvent: PublishedTranslation?
    private var events: [String:PublishedTranslation] = [:]
    private(set) var saturated = false
    var average: Double { lookups == 0 ? 0 : lookupTotal/Double(lookups) }
    mutating func recordAttempt(_ origin: TranslationOrigin, fallback: TranslationFallback? = nil) {
        attemptOrigins[origin,default:0] += 1
        if let fallback { attemptFallbackReasons[fallback,default:0] += 1 }
    }
    /// Y = first accepted publication of each stable dialogue ID, in the current
    /// selected game/pack activation or explicit measurement reset. Corrections/retries never increment Y.
    mutating func recordPublished(_ event: PublishedTranslation) {
        if let old = events[event.eventID] {
            origins[old.origin,default:0] -= 1
            if old.isPackBacked { publishedPack -= 1 }
            if let reason = old.fallback { fallbackReasons[reason,default:0] -= 1 }
        } else {
            guard events.count < 50000 else { saturated = true; return }
            published += 1
        }
        events[event.eventID] = event; lastEvent = event
        origins[event.origin,default:0] += 1
        if event.isPackBacked { publishedPack += 1 }
        if let reason = event.fallback { fallbackReasons[reason,default:0] += 1 }
    }
    func status(active: Bool, damaged: Bool, threshold: Int = 20) -> String {
        if damaged { return "تالفة" }
        guard active else { return "غير مفعّلة (اختر اللعبة)" }
        if publishedPack > 0 { return "تعمل · \(publishedPack) من \(published) من الحزمة" }
        if published >= max(1,threshold) {
            let top = fallbackReasons.filter{$0.value > 0}.sorted { $0.value == $1.value ? $0.key.rawValue < $1.key.rawValue : $0.value > $1.value }.first?.key.title ?? "اختيرت قواعد أو مصادر أخرى قبل الحزمة"
            return "مفعّلة · لا تطابق بعد \(published) حوار · السبب الأغلب: \(top)"
        }
        return "مفعّلة · بانتظار حوارات منشورة (\(published))"
    }
    var summary: String {
        let identity = lastEvent.map { "last id=\($0.eventID) game=\($0.game ?? "general") pack=\($0.pack ?? "none") origin=\($0.origin.rawValue) basis=\($0.basis?.rawValue ?? "none")" } ?? "last event=none"
        return "Attempts: \(lookups); matches: \(matches); exact/normalized/punctuation/OCR/fuzzy/context: \(exact)/\(normalized)/\(punctuationless)/\(ocrTolerant)/\(approximate)/\(contextResolved); ambiguous/misses: \(ambiguous)/\(misses); learned attempts/published: \(attemptOrigins[.learningMemory,default:0])/\(origins[.learningMemory,default:0]); Argos requests: \(argos); published unique IDs Y: \(published); published pack X: \(publishedPack); saturated: \(saturated); lookup avg/p95 ms: \(NumericInput.format(average))/\(NumericInput.format(samples.p95)); \(identity)"
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
