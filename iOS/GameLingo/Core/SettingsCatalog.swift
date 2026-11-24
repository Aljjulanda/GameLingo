import Foundation

enum SettingsPage: String, CaseIterable, Identifiable {
    case devices, appearance, translation, menus, model, advanced, experiments, improvement, diagnostics, help
    var id: String { rawValue }
    var title: String {
        switch self {
        case .devices: return "الأجهزة والاتصال"
        case .appearance: return "مظهر الترجمة"
        case .translation: return "الترجمة واللغة"
        case .menus: return "القوائم والقراءة"
        case .model: return "النموذج المحلي"
        case .advanced: return "إعدادات متقدمة"
        case .experiments: return "تجارب اختيارية"
        case .improvement: return "التحسين المحلي خارج اللعب"
        case .diagnostics: return "التشخيص والقياسات"
        case .help: return "المساعدة والتراخيص"
        }
    }
    var symbol: String {
        switch self {
        case .devices: return "antenna.radiowaves.left.and.right"
        case .appearance: return "textformat.size"
        case .translation: return "character.bubble"
        case .menus: return "list.bullet.rectangle"
        case .model: return "arrow.down.circle"
        case .advanced: return "slider.horizontal.3"
        case .experiments: return "testtube.2"
        case .improvement: return "wand.and.stars"
        case .diagnostics: return "gauge"
        case .help: return "questionmark.circle"
        }
    }
    var keywords: String {
        switch self {
        case .devices: return "اقتران تسجيل شبكة واي فاي تلفزيون ايفون PS5 TV QR IP"
        case .appearance: return "خط لون خلفية ظل حدود حجم موضع محاذاة توقيت معاينة"
        case .translation: return "عربي العربية انجليزي English لغات أداء اقتصادي تعتيم شاشة"
        case .menus: return "قائمة منيو menu قوائم اقتراح تلقائي قراءة محاذاة جهة فجوة"
        case .model: return "تنزيل تحميل استيراد حذف اوفلاين offline Argos"
        case .advanced: return "جودة OCR سياق ذاكرة مصطلحات منطقة حوار أرقام نفي متحدث"
        case .experiments: return "خلفية قفل صوت صامت تجريبي"
        case .improvement: return "جمع أمثلة موافقة تصدير حذف تعلم تراجع"
        case .diagnostics: return "سرعة بطارية حرارة ذاكرة قياس تأخير سجل تسجيل اختبار"
        case .help: return "تعليمات مساعدة مصادر خصوصية تراخيص إعداد أول استخدام خطوات"
        }
    }
    func matches(_ query: String) -> Bool {
        let words = Self.normalized(query).split(whereSeparator: { $0.isWhitespace })
        let index = Self.normalized(title+" "+keywords)
        return words.allSatisfy { index.contains($0) }
    }
    private static func normalized(_ value: String) -> String {
        value.folding(options:[.diacriticInsensitive,.caseInsensitive],locale:Locale(identifier:"ar"))
            // Foundation's diacritic folding retains Arabic vowel marks on
            // some runtimes. Remove combining marks explicitly for search.
            .components(separatedBy:CharacterSet.nonBaseCharacters).joined()
            .replacingOccurrences(of:"ـ",with:"")
            .replacingOccurrences(of:"أ",with:"ا").replacingOccurrences(of:"إ",with:"ا").replacingOccurrences(of:"آ",with:"ا")
    }
}
