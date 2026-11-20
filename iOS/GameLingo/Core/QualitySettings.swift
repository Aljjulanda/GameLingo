import Foundation

/// Each behavior can be independently reverted. Absence of a saved key never
/// enables a new behavior. Recording consent is deliberately NOT persisted.
enum QualityFlag: String, CaseIterable, Codable {
    case measurement, provenanceMarker, punctuationTrace, sessionCapture
    case stageCues, speakerClassification, speakerGeometry, visionNames
    case learnNames, corrections, packMarkup, packPunctuation
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
    var typewriterWindow = 5
    private(set) var typewriterGames = Set<String>()
    var anchoredLineCap = 5, fallbackLineCap = 6
    var nameHeightRatio = 1.4, nameGapRatio = 2.0, nameOverlap = 0.15
    var nameLeftOffset = 0.18
    var colonNameThreshold = 1, otherNameThreshold = 2
    subscript(_ flag: QualityFlag) -> Bool {
        get { enabled.contains(flag) }
        set { if newValue { enabled.insert(flag) } else { enabled.remove(flag) } }
    }
    var outputKey: String { enabled.map(\.rawValue).sorted().joined(separator:",") }
    @discardableResult mutating func rememberTypewriter(game: String) -> Bool {
        guard game.range(of:"^[a-z0-9][a-z0-9._-]{0,63}$",options:.regularExpression) != nil,
              typewriterGames.count < 256 || typewriterGames.contains(game) else { return false }
        return typewriterGames.insert(game).inserted
    }
    static func load(_ defaults: UserDefaults = .standard) -> Self {
        var value = Self()
        for flag in QualityFlag.allCases { value[flag] = defaults.bool(forKey:"quality."+flag.rawValue) }
        if let n = defaults.object(forKey:"quality.noHitThreshold") as? Int { value.noHitThreshold = max(1,min(1000,n)) }
        if defaults.object(forKey:"quality.settleSeconds") != nil {
            let duration = defaults.double(forKey:"quality.settleSeconds")
            value.settleSeconds = duration.isFinite ? max(0,min(3,duration)) : 3
        }
        if let n = defaults.object(forKey:"quality.typewriterWindow") as? Int { value.typewriterWindow = max(3,min(20,n)) }
        for game in (defaults.stringArray(forKey:"quality.typewriterGames") ?? []).prefix(256) { value.rememberTypewriter(game:game) }
        if let n = defaults.object(forKey:"quality.anchoredLineCap") as? Int { value.anchoredLineCap = max(3,min(5,n)) }
        if let n = defaults.object(forKey:"quality.fallbackLineCap") as? Int { value.fallbackLineCap = max(4,min(6,n)) }
        func bounded(_ key: String, _ fallback: Double, _ range: ClosedRange<Double>) -> Double {
            guard defaults.object(forKey:key) != nil else { return fallback }
            let n = defaults.double(forKey:key)
            return n.isFinite ? max(range.lowerBound,min(range.upperBound,n)) : fallback
        }
        value.nameHeightRatio = bounded("quality.nameHeightRatio",1.4,0.8...2)
        value.nameGapRatio = bounded("quality.nameGapRatio",2,0.5...3)
        value.nameOverlap = bounded("quality.nameOverlap",0.15,0...0.75)
        value.nameLeftOffset = bounded("quality.nameLeftOffset",0.18,0...0.3)
        if let n = defaults.object(forKey:"quality.colonNameThreshold") as? Int { value.colonNameThreshold = max(1,min(10,n)) }
        if let n = defaults.object(forKey:"quality.otherNameThreshold") as? Int { value.otherNameThreshold = max(1,min(10,n)) }
        return value
    }
    func save(_ defaults: UserDefaults = .standard) {
        for flag in QualityFlag.allCases { defaults.set(self[flag],forKey:"quality."+flag.rawValue) }
        defaults.set(noHitThreshold,forKey:"quality.noHitThreshold")
        defaults.set(settleSeconds,forKey:"quality.settleSeconds")
        defaults.set(typewriterWindow,forKey:"quality.typewriterWindow")
        defaults.set(typewriterGames.sorted(),forKey:"quality.typewriterGames")
        defaults.set(anchoredLineCap,forKey:"quality.anchoredLineCap"); defaults.set(fallbackLineCap,forKey:"quality.fallbackLineCap")
        defaults.set(nameHeightRatio,forKey:"quality.nameHeightRatio"); defaults.set(nameGapRatio,forKey:"quality.nameGapRatio")
        defaults.set(nameOverlap,forKey:"quality.nameOverlap"); defaults.set(nameLeftOffset,forKey:"quality.nameLeftOffset")
        defaults.set(colonNameThreshold,forKey:"quality.colonNameThreshold"); defaults.set(otherNameThreshold,forKey:"quality.otherNameThreshold")
    }
}
