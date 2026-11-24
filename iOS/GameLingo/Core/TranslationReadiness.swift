import Foundation

/// Presentation only. Never changes session intent, profiles, or credentials.
struct TranslationReadiness {
    enum NextStep: Equatable { case model, console, region, importing, pairing, ready }
    var modelReady: Bool
    var hasConsole: Bool
    var validRegion: Bool
    var importing: Bool
    var pairing: Bool
    var destination: DisplayDestination
    var tvConnected: Bool

    var nextStep: NextStep {
        if pairing { return .pairing }
        if importing { return .importing }
        if !modelReady { return .model }
        if !hasConsole { return .console }
        if !validRegion { return .region }
        return .ready
    }
    // Starting the existing session also starts the TV listener when needed.
    // TV connectivity must never block phone output or PS5 connection setup.
    var canStart: Bool { nextStep == .ready }
    var waitingForTV: Bool { destination.tvEnabled && !tvConnected }
    var title: String {
        switch nextStep {
        case .model: return "جهّز نموذج الترجمة"
        case .console: return "اختر جهاز PS5"
        case .region: return "اضبط منطقة الحوار"
        case .importing: return "جارٍ استيراد الحزمة"
        case .pairing: return "جارٍ تسجيل PS5"
        case .ready:
            if waitingForTV { return destination.phoneEnabled ? "جاهز على الآيفون؛ التلفزيون غير متصل" : "جاهز لبدء البث؛ التلفزيون غير متصل" }
            return "جاهز لبدء الترجمة"
        }
    }
}
