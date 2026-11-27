import Foundation

struct SessionNotice: Identifiable, Equatable {
    enum Kind: Equatable { case starting, active, recovering, stopped, suspended, failed }
    let id = UUID()
    let kind: Kind
    let title: String
    let body: String
    var symbol: String {
        switch kind {
        case .starting, .recovering: return "arrow.triangle.2.circlepath"
        case .active: return "checkmark.circle.fill"
        case .stopped: return "stop.circle.fill"
        case .suspended: return "pause.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }
}

/// Observes actual session phases; a requested start is never a success notice.
struct SessionFeedbackState {
    private var phase: SessionControlSnapshot.Phase = .stopped
    mutating func observe(_ next: SessionControlSnapshot.Phase, detail: String = "") -> SessionNotice? {
        guard phase != next else { return nil }
        let before = phase; phase = next
        switch next {
        case .starting:
            return SessionNotice(kind:.starting,title:"جارٍ تشغيل المترجم",body:"جارٍ تجهيز نموذج الترجمة والاتصال بـPS5.")
        case .recovering:
            let recovering = before == .active || before == .suspended
            return SessionNotice(kind:recovering ? .recovering : .starting,title:recovering ? "جارٍ استعادة الاتصال" : "جارٍ تشغيل المترجم",body:"بانتظار اتصال بث PS5؛ لم يبدأ البث بعد.")
        case .active:
            return SessionNotice(kind:.active,title:"تم تشغيل المترجم",body:"اتصل بث PS5 وأصبحت جلسة الترجمة نشطة.")
        case .stopped:
            return SessionNotice(kind:.stopped,title:"تم إيقاف المترجم",body:String(detail.prefix(180)))
        case .suspended:
            return SessionNotice(kind:.suspended,title:"الترجمة متوقفة مؤقتًا",body:"التنفيذ في الخلفية غير متاح حاليًا. افتح GameLingo للاستئناف.")
        }
    }
    mutating func failure(_ message: String) -> SessionNotice {
        phase = .stopped
        return SessionNotice(kind:.failed,title:"تعذّر تشغيل المترجم",body:String(message.prefix(180)))
    }
}
