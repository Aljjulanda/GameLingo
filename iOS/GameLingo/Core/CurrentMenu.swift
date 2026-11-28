import Foundation

struct CurrentMenuReadout {
    var active = false
    var status = "افتح قائمة اللعبة ثم اطلب ترجمتها"
    var items: [MenuOverlayItem] = []
    var sources: [OCRLine] = []
    var pending = 0
    var withheld = 0
    var rejectedSources = Set<String>()
}

/// Ephemeral manual intent. Templates and game identity are not prerequisites.
/// Only fresh OCR observations advance stability; no bitmap hash counts as one.
struct CurrentMenuSession {
    static let maximumObservationAge = 1.5
    private(set) var ticket: UUID?
    private(set) var generation: UInt64 = 0
    private(set) var rows: [OCRLine] = []
    private(set) var region: SourceBox?
    private(set) var confirmations = 0
    private(set) var lastSeen = 0.0
    private var requestedAt = 0.0
    private var dimensions = ""
    private var hasInput = false
    private(set) var status = "القراءة مغلقة"
    var active: Bool { ticket != nil }
    var stable: Bool { active && confirmations >= 2 && !rows.isEmpty }
    mutating func request(_ ticket: UUID, now: Double) {
        close(); self.ticket = ticket; requestedAt = now; status = "بانتظار إطار جديد للقائمة…"
    }
    mutating func close(_ message: String = "أُغلقت القائمة؛ عاد مسار الحوار") {
        ticket = nil; generation &+= 1; rows = []; region = nil; confirmations = 0; lastSeen = 0; dimensions = ""; hasInput = false; status = message
    }
    @discardableResult mutating func expire(now: Double, sourceAge: Double? = nil) -> Bool {
        guard active else { return false }
        let age = hasInput ? (sourceAge ?? (now-(lastSeen > 0 ? lastSeen : requestedAt))) : now-requestedAt
        guard age > (hasInput ? Self.maximumObservationAge : 6) else { return false }
        close("توقفت إطارات القائمة؛ تحقق من بث PS5 وأعد الطلب"); return true
    }
    mutating func beginFrame() {
        guard active else { return }
        if !hasInput { status = "جارٍ قراءة إطار القائمة…" }
        hasInput = true
    }
    /// Cold OCR may be slow even while decoded frames keep arriving. Its old
    /// geometry can bound the next crop, but its text never counts as a fresh
    /// confirmation or becomes eligible for translation/publication.
    mutating func prepareFreshFrame(_ observations: [OCRLine], width: Int, height: Int) {
        guard active, width > 0, height > 0 else { return }
        beginFrame()
        let size = "\(width)x\(height)"
        guard dimensions.isEmpty || dimensions == size else { close("تغير مقاس المصدر؛ أعد طلب القائمة"); return }
        guard let candidate = CurrentMenuLayout.candidate(observations) else {
            close("لم تظهر قائمة واضحة؛ أعد الطلب أو استخدم قراءة النص"); return
        }
        dimensions = size; seedRegion(candidate)
        generation &+= 1; rows = []; confirmations = 0; lastSeen = 0
        status = "تأخرت القراءة؛ نتحقق من إطار حديث قبل العرض…"
    }
    /// Any semantic row change invalidates pending results immediately. Geometry
    /// jitter is tolerated, while current boxes always replace previous boxes.
    mutating func observe(_ observations: [OCRLine], width: Int, height: Int, now: Double) {
        guard active else { return }
        beginFrame()
        guard width > 0, height > 0 else { close("تعذر تحديد مقاس المصدر؛ أعد الطلب"); return }
        let size = "\(width)x\(height)"
        if !dimensions.isEmpty && dimensions != size { close("تغير مقاس المصدر؛ أعد طلب القائمة"); return }
        dimensions = size
        guard let candidate = CurrentMenuLayout.candidate(observations) else {
            close("لم تظهر قائمة واضحة أو كان النص كثيفًا؛ أعد الطلب أو استخدم قراءة النص"); return
        }
        let same = candidate.count == rows.count && zip(candidate,rows).allSatisfy { a,b in
            CurrentMenuLayout.key(a.text) == CurrentMenuLayout.key(b.text) &&
            abs(a.box.x-b.box.x) <= 0.018 && abs(a.box.y-b.box.y) <= 0.018 &&
            abs(a.box.w-b.box.w) <= 0.035 && abs(a.box.h-b.box.h) <= 0.018
        }
        if same { confirmations = min(3,confirmations+1) }
        else { generation &+= 1; confirmations = 1 }
        rows = candidate; lastSeen = now
        seedRegion(candidate)
        status = stable ? "القائمة الحالية · أغلِق القراءة عند العودة للعب" : "جارٍ تثبيت عناصر القائمة…"
    }
    func accepts(ticket: UUID, generation: UInt64, source: String, now: Double) -> Bool {
        stable && self.ticket == ticket && self.generation == generation && now-lastSeen < Self.maximumObservationAge &&
        rows.contains { CurrentMenuLayout.key($0.text) == CurrentMenuLayout.key(source) }
    }
    private mutating func seedRegion(_ candidate: [OCRLine]) {
        guard region == nil else { return }
        let union = StructuredDialogue.union(candidate)
        let x = max(0,union.x-0.08), y = max(0,union.y-0.06)
        region = SourceBox(x:x,y:y,w:min(1-x,union.w+0.16),h:min(1-y,union.h+0.12))
    }
}

enum CurrentMenuLayout {
    static func key(_ text: String) -> String { text.precomposedStringWithCanonicalMapping.split(whereSeparator:\.isWhitespace).joined(separator:" ") }
    /// Explicit intent permits an unfamiliar vocabulary, but never a single
    /// dialogue line, dense document, or scattered HUD counters. No fuzzy text.
    static func candidate(_ input: [OCRLine]) -> [OCRLine]? {
        guard input.count <= 40 else { return nil }
        let visible = input.filter { $0.box.isValid && $0.confidence >= 0.8 && !$0.text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty }
        guard !visible.isEmpty, visible.allSatisfy({$0.text.count <= 600}) else { return nil }
        let rows = MenuItemGrouping.rows(visible,maximumCharacters:600,minimumWrapLength:12)
        guard (2...20).contains(rows.count), rows.reduce(0,{$0+$1.text.count}) <= 4000,
              rows.allSatisfy({$0.box.h <= 0.18 && $0.text.count <= 600}) else { return nil }
        let hud: Set<String> = ["hp","health","ammo","fps","score","xp"]
        if rows.allSatisfy({ line in line.text.contains(where:\.isNumber) && !hud.isDisjoint(with:DialogueText.exactWords(line.text)) }) { return nil }
        // At least two short labels in a column with a real vertical gap.
        let labels = rows.filter { $0.text.count <= 100 && $0.text.contains(where:\.isLetter) }
        let aligned = labels.contains { a in labels.contains { b in
            abs(a.box.x-b.box.x) <= 0.035 && abs(a.box.y-b.box.y) >= max(a.box.h,b.box.h)+0.012
        } }
        guard aligned else { return nil }
        return rows
    }
    /// The legacy receivers use a fixed quarter-width overlay. Withhold rows
    /// that cannot fit beside the source, or might overlap. The complete text
    /// remains in the phone's scrollable readout, never silently clipped.
    static func overlay(_ items: [MenuOverlayItem], appearance: MenuAppearance, aspect: Double, sourceBoxes: [SourceBox]? = nil) -> [MenuOverlayItem] {
        guard aspect.isFinite, aspect > 0, appearance.valid else { return [] }
        var occupied: [SourceBox] = [], accepted: [MenuOverlayItem] = []
        for item in items {
            guard item.translated.count <= 240, item.translated.utf16.count <= 400 else { continue }
            let x = appearance.side == "left" ? item.box.x-appearance.gap-0.26 : item.box.x+item.box.w+appearance.gap
            guard x >= 0.006, x+0.26 <= 0.994 else { continue }
            // Bound using the larger phone renderer, not optimistic TV metrics.
            let font = appearance.fontSize/1000
            let lines = max(1,ceil(Double(item.translated.count)*font/0.23))
            let height = lines*font*aspect*1.6+0.012
            let top = min(item.box.y-0.008,item.box.y+item.box.h/2-height/2-0.008)
            let rect = SourceBox(x:x,y:top,w:0.26,h:item.box.y+height+0.008-top)
            guard rect.y >= 0, rect.y+rect.h <= 0.99,
                  !occupied.contains(where:{ abs(($0.x+$0.w/2)-(rect.x+rect.w/2)) < ($0.w+rect.w)/2 && abs(($0.y+$0.h/2)-(rect.y+rect.h/2)) < ($0.h+rect.h)/2 }),
                  !(sourceBoxes ?? items.map(\.box)).contains(where:{ other in rect.x < other.x+other.w && rect.x+rect.w > other.x && rect.y < other.y+other.h && rect.y+rect.h > other.y }) else { continue }
            occupied.append(rect); accepted.append(item)
        }
        return accepted
    }
}

enum MenuTerminology {
    private static let terms = ["resume":"متابعة اللعب","continue":"متابعة","settings":"الإعدادات","options":"الخيارات",
        "save":"حفظ","save game":"حفظ اللعبة","load":"تحميل","load game":"تحميل اللعبة","new game":"لعبة جديدة",
        "back":"رجوع","exit":"خروج","quit":"إنهاء","inventory":"المخزون","map":"الخريطة","objectives":"الأهداف",
        "controls":"التحكم","audio":"الصوت","video":"الفيديو","graphics":"الرسوم","language":"اللغة",
        "subtitles":"الترجمة النصية","brightness":"السطوع","difficulty":"الصعوبة","apply":"تطبيق","cancel":"إلغاء",
        "yes":"نعم","no":"لا","on":"تشغيل","off":"إيقاف","enabled":"مفعّل","disabled":"معطّل","default":"افتراضي",
        "escape the police":"اهرب من الشرطة"]
    static func translation(_ source: String) -> String? { terms[CurrentMenuLayout.key(source).lowercased()] }
}

enum MenuTranslationGuard {
    static func safe(_ target: String, source: String, names: [String:String] = [:]) -> Bool {
        guard !target.isEmpty, target.count <= 1800 else { return false }
        func canonical(_ value: String) -> String {
            String(value.map { c in
                if let digit = c.wholeNumberValue, (0...9).contains(digit) { return Character(String(digit)) }
                return c
            })
                .replacingOccurrences(of:"٫",with:".").replacingOccurrences(of:"٬",with:",")
                .replacingOccurrences(of:"٪",with:"%").replacingOccurrences(of:"−",with:"-")
        }
        let a = canonical(source), b = canonical(target)
        let numeric = #"[+-]?\d+(?:[.,]\d+)*(?:%)?"#
        guard DialogueText.matches(a,numeric) == DialogueText.matches(b,numeric) else { return false }
        let variables = #"\$?\{[^{}\s]{1,64}\}|%[0-9]*\$?[a-zA-Z]|\[[A-Z0-9_]+\]"#
        guard DialogueText.matches(source,variables).sorted() == DialogueText.matches(target,variables).sorted() else { return false }
        let symbols = Set("△◯○✕×□▢")
        guard source.filter({symbols.contains($0)}).sorted() == target.filter({symbols.contains($0)}).sorted() else { return false }
        let negatives: Set<String> = ["no","not","never","without","cannot","cant","dont","wont","disabled","off"]
        let arabic: Set<String> = ["لا","لم","لن","ليس","ليست","بدون","غير","عدم","معطل","معطّل","إيقاف","ايقاف"]
        let targetWords = DialogueText.exactWords(target.components(separatedBy:.nonBaseCharacters).joined())
        if !negatives.isDisjoint(with:DialogueText.exactWords(source)) {
            guard !arabic.isDisjoint(with:targetWords) else { return false }
        }
        if ["yes","on","enabled"].contains(CurrentMenuLayout.key(source).lowercased()), !arabic.isDisjoint(with:targetWords) { return false }
        for (english,arabic) in names where !english.isEmpty {
            let pattern = "\\b"+NSRegularExpression.escapedPattern(for:english)+"\\b"
            if source.range(of:pattern,options:[.regularExpression,.caseInsensitive]) != nil,
               target.range(of:english,options:.caseInsensitive) == nil, !target.contains(arabic) { return false }
        }
        return true
    }
}
