import Foundation

struct LocalSubtitle: Identifiable {
    var id: String, text: String
    var until: Double, minimumUntil: Double
}

/// Presentation clock only. Never translates and never replays an expired entry.
struct LocalSubtitleState {
    static let sample = "هذه تجربة لعرض الترجمة العربية داخل الألعاب"
    private(set) var entries: [LocalSubtitle] = []
    private(set) var preview = false
    private var seen: [String] = []
    var document: String?
    mutating func clear() { entries.removeAll(); document = nil }
    mutating func expire(now: Double) { entries.removeAll { $0.until <= now } }
    mutating func apply(_ message: [String:Any], settings: TVSettings, now: Double) {
        expire(now:now)
        switch message["type"] as? String {
        case "subtitle_preview_show": preview = true
        case "subtitle_preview_hide": preview = false; clear()
        case "subtitle_clear", "subtitle_hide": clear()
        case "document_show": document = message["translated"] as? String
        case "document_hide": document = nil
        case "subtitle_source_gone":
            if let id = message["id"] as? String, let i = entries.firstIndex(where:{$0.id == id}) { entries[i].until = min(entries[i].until,max(entries[i].minimumUntil,now+settings.number("disappearance_grace"))) }
        case "subtitle_show", "subtitle_update":
            guard let id = message["id"] as? String, let text = message["translated"] as? String, !text.isEmpty, text.count <= 2400 else { return }
            let clean = SubtitlePresentation.clean(text)
            if let index = entries.firstIndex(where:{$0.id == id}) { entries[index].text = clean; return }
            guard !seen.contains(id) else { return }
            seen.append(id); seen = Array(seen.suffix(128))
            let duration = settings.bool("adaptive") ? max(settings.number("min_seconds"),min(settings.number("max_seconds"),Double(clean.count)/max(1,settings.number("reading_speed")))) : settings.number("fixed_seconds")
            entries.append(LocalSubtitle(id:id,text:clean,until:now+min(duration,settings.number("hard_seconds")),minimumUntil:now+settings.number("min_seconds")))
            entries = Array(entries.suffix(max(1,min(3,Int(settings.number("max_entries"))))))
        default: break
        }
    }
}
