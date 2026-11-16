import Foundation

/// Each behavior can be independently reverted. Absence of a saved key never
/// enables a new behavior. Recording consent is deliberately NOT persisted.
enum QualityFlag: String, CaseIterable, Codable {
    case measurement, provenanceMarker, punctuationTrace, sessionCapture
    case stageCues, speakerClassification, speakerGeometry, visionNames
    case learnNames, protectNames, corrections, packMarkup, packPunctuation
    case packLabels, punctuationRepair, commandPunctuation, typewriter, lineLimits
    case arabicParagraphDirection
    var title: String {
        switch self {
        case .measurement: return "قياس مصدر الحوارات المنشورة"
        case .provenanceMarker: return "علامة مصدر الترجمة على التلفزيون"
        case .sessionCapture: return "إتاحة تسجيل الاختبار المحلي · بموافقة منفصلة"
        case .punctuationTrace: return "تشخيص مواضع الترقيم بلا نصوص"
        case .stageCues: return "الأصوات والوصف بين الأقواس"
        case .speakerClassification: return "تحسين تمييز أسماء المتحدثين"
        case .speakerGeometry: return "تسمية المتحدث المنفصلة"
        case .visionNames: return "قاموس الأسماء للتعرف البصري"
        case .learnNames: return "تعلّم أسماء اللعبة"
        case .protectNames: return "حماية الأسماء أثناء الترجمة · تجريبي"
        case .corrections: return "تصحيحاتي قبل الترجمة"
        case .packMarkup: return "تنظيف علامات اللعبة عند الاستيراد"
        case .packPunctuation: return "مطابقة كلمات الحزمة دون ترقيم"
        case .packLabels: return "فصل أسماء المتحدثين عند الاستيراد"
        case .punctuationRepair: return "إصلاح الترقيم بدليل من الإنجليزية"
        case .commandPunctuation: return "ترقيم الأوامر حسب النص الأصلي"
        case .typewriter: return "اكتشاف النص المتدرج"
        case .lineLimits: return "الحوارات متعددة الأسطر"
        case .arabicParagraphDirection: return "اتجاه الفقرة العربية على التلفزيون"
        }
    }
}

struct QualitySettings: Equatable {
    private var enabled = Set<QualityFlag>()
    var noHitThreshold = 20
    var settleSeconds = 3.0
    var nameHeightRatio = 1.4, nameGapRatio = 2.0, nameOverlap = 0.15
    subscript(_ flag: QualityFlag) -> Bool {
        get { enabled.contains(flag) }
        set { if newValue { enabled.insert(flag) } else { enabled.remove(flag) } }
    }
    var outputKey: String { enabled.map(\.rawValue).sorted().joined(separator:",") }
    static func load(_ defaults: UserDefaults = .standard) -> Self {
        var value = Self()
        for flag in QualityFlag.allCases { value[flag] = defaults.bool(forKey:"quality."+flag.rawValue) }
        if let n = defaults.object(forKey:"quality.noHitThreshold") as? Int { value.noHitThreshold = max(1,min(1000,n)) }
        if defaults.object(forKey:"quality.settleSeconds") != nil { value.settleSeconds = max(0,min(3,defaults.double(forKey:"quality.settleSeconds"))) }
        return value
    }
    func save(_ defaults: UserDefaults = .standard) {
        for flag in QualityFlag.allCases { defaults.set(self[flag],forKey:"quality."+flag.rawValue) }
        defaults.set(noHitThreshold,forKey:"quality.noHitThreshold")
        defaults.set(settleSeconds,forKey:"quality.settleSeconds")
    }
}
