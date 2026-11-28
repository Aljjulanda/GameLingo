import Foundation
#if canImport(SQLite3)
import SQLite3
#else
import CSQLite
#endif

enum ScreenCategory: String, Codable { case gameplay, menu, settings, inventory, tutorial, objective, phone, map, shop }
enum TextPrivacy {
    /// Applied before persistence in either pipeline. Conservative when identity is unclear.
    static func excluded(_ text: String) -> Bool {
        let s = text.lowercased()
        return s.range(of:"[a-z0-9._%+-]+@[a-z0-9.-]+\\.[a-z]{2,}|https?://|www\\.",options:.regularExpression) != nil ||
            ["playstation network","psn id","online id","signed in","signed out","account","trophy earned","trophy unlocked","friend request","party invitation","joined your party","microphone","broadcast started","payment","password","verification code"].contains(where:s.contains)
    }
}
enum SpatialRecognition {
    static func key(_ s: String) -> String { PackLookupKey.normalized(s) }
    static func category(_ lines: [OCRLine]) -> ScreenCategory {
        let keys = lines.map { key($0.text) }, words = Set(keys)
        if keys.contains(where: { $0.contains("messages") || $0 == "contacts" || $0 == "inbox" }), lines.count >= 2 { return .phone }
        if keys.contains(where: { $0.hasPrefix("press ") || $0.hasPrefix("hold ") || $0.hasPrefix("tap ") }) { return .tutorial }
        if !words.isDisjoint(with:["graphics","audio","accessibility","display","controls","brightness","settings"]), lines.count >= 3 { return .settings }
        if !words.isDisjoint(with:["inventory","weapons","equipment","items"]), lines.count >= 3 { return .inventory }
        if !words.isDisjoint(with:["shop","buy","sell","purchase"]), lines.count >= 3 { return .shop }
        if words.contains("map"), keys.contains(where:{$0.contains("waypoint") || $0.contains("legend")}) { return .map }
        if !words.isDisjoint(with:["resume","resume game","new game","load game","main menu","options","save game","pause"]), lines.count >= 3 { return .menu }
        // A submenu often has only two selectable rows. Require both known UI
        // labels AND shared column geometry; one sign/word is never a menu.
        let labels: Set<String> = ["back","continue","resume","resume game","settings","options","graphics","audio","display","controls","accessibility","brightness","subtitles","language","on","off","apply","cancel","confirm","new game","load game","save game","quit","quit game"]
        let ui = lines.filter { labels.contains(key($0.text)) && $0.confidence >= 0.8 }
        if ui.contains(where:{ a in ui.contains { b in a != b && abs(a.box.x-b.box.x)<0.04 && abs(a.box.y-b.box.y)>max(a.box.h,b.box.h) && abs(a.box.y-b.box.y)<0.45 } }) { return .menu }
        // Generic lists need geometric and textual evidence; environmental signs alone aren't menus.
        let aligned = lines.filter { l in lines.filter { abs($0.box.x-l.box.x)<0.03 && $0.box.y != l.box.y }.count >= 3 }
        if aligned.count >= 4, keys.contains(where:{["back","select","confirm","cancel"].contains($0)}) { return .menu }
        if lines.contains(where:isObjective) || keys.contains(where:{$0.hasPrefix("mission:") || $0.hasPrefix("mission objective")}) { return .objective }
        return .gameplay
    }
    static func isObjective(_ line: OCRLine) -> Bool {
        let text = key(line.text)
        guard line.confidence >= 0.8, line.box.isValid, line.box.y < 0.55,
              line.box.h <= 0.12, (2...24).contains(text.split(separator:" ").count), !TextPrivacy.excluded(text) else { return false }
        return ["escape ","lose the ","evade ","reach ","return to ","go to ","find ","follow ","protect ","defend ","collect ","deliver ","meet ","steal ","destroy "].contains(where:text.hasPrefix)
    }
    static func sameObservation(_ a: [OCRLine], _ b: [OCRLine]) -> Bool {
        a.count == b.count && a.allSatisfy { row in b.contains { key($0.text) == key(row.text) && abs($0.box.x-row.box.x)<0.035 && abs($0.box.y-row.box.y)<0.035 } }
    }
    static func rows(_ lines: [OCRLine], dialogue: SourceBox, category: ScreenCategory) -> [OCRLine] {
        let safe = rows(lines,dialogue:dialogue)
        if category == .objective {
            // A HUD objective does not authorize translating the surrounding
            // world. Each selected row needs its own instruction evidence.
            return safe.filter { isObjective($0) || key($0.text).hasPrefix("mission:") || key($0.text).hasPrefix("mission objective") }
        }
        if category == .tutorial {
            return safe.filter { let s = key($0.text); return s.hasPrefix("press ") || s.hasPrefix("hold ") || s.hasPrefix("tap ") }
        }
        return safe
    }
    static func dynamic(_ text: String, category: ScreenCategory) -> Bool {
        text.contains(where:\.isNumber) || [.phone,.objective,.tutorial].contains(category)
    }
    static func rows(_ lines: [OCRLine], dialogue: SourceBox) -> [OCRLine] {
        Array(lines.filter { l in
            l.box.isValid && l.confidence >= 0.8 && (1...320).contains(l.text.count) && !TextPrivacy.excluded(l.text) &&
            l.text.unicodeScalars.contains(where:CharacterSet.letters.contains) &&
            // Spoken lines can coexist with menus; don't put them in spatial memory.
            !(dialogue.contains(l.box) && l.text.split(separator:" ").count >= 6 && l.text.last.map { ".!?".contains($0) } == true)
        }.prefix(24))
    }
    static func hash(_ text: String) -> String {
        var h: UInt64 = 14695981039346656037
        for byte in text.utf8 { h = (h ^ UInt64(byte)) &* 1099511628211 }
        return String(h,radix:16)
    }
    static func fingerprint(_ rows: [OCRLine], category: ScreenCategory) -> String {
        hash(category.rawValue+"|"+rows.map { key($0.text)+"@\(Int($0.box.x*32)),\(Int($0.box.y*32))" }.sorted().joined(separator:"|"))
    }
    static func layoutScore(_ saved: [SpatialElement], observed: [OCRLine]) -> Double {
        guard !saved.isEmpty, !observed.isEmpty else { return 0 }
        let anchors = saved.filter{!$0.dynamic}
        guard anchors.count >= 2 else { return 0 }
        let matched = anchors.filter { a in observed.contains { key($0.text) == a.normalized && abs($0.box.x-a.box.x)<0.04 && abs($0.box.y-a.box.y)<0.04 && abs($0.box.h-a.box.h)<0.025 } }.count
        return Double(matched)/Double(max(anchors.count,observed.filter{!$0.text.contains(where:\.isNumber)}.count))
    }
}
struct SpatialElement: Codable {
    var source: String, normalized: String, translated: String
    var box: SourceBox
    var alignment = "right"
    var scale: Double
    var dynamic: Bool
    var origin: String
    var confidence: Double
}
struct SpatialScreen: Codable {
    var game: String, gameVersion: String, id: String, fingerprint: String, category: ScreenCategory
    var visualHash: String
    var elements: [SpatialElement]
    var observed: Double
    var uses = 1
    var cacheVersion = 1
}
struct SpatialMetrics {
    var scans = 0, recognized = 0, discoveries = 0, cacheHits = 0, misses = 0, dynamicUpdates = 0, rejected = 0, published = 0
    var observedRows = 0, selectedRows = 0
    var category = "gameplay"
    var recall = LatencySamples()
    var summary: String { "Spatial scans/discoveries/recognized: \(scans)/\(discoveries)/\(recognized); category/observed/selected: \(category)/\(observedRows)/\(selectedRows); hits/misses/dynamic/rejected/published: \(cacheHits)/\(misses)/\(dynamicUpdates)/\(rejected)/\(published); recall p95 ms: \(recall.p95)" }
}
enum SpatialTarget {
    static func valid(source: String, target: String) -> Bool {
        guard !target.isEmpty, target.count <= 400, target.unicodeScalars.contains(where:{(0x0600...0x06ff).contains($0.value)}) else { return false }
        func numbers(_ text: String) -> [String] {
            DialogueText.matches(text,"[0-9٠-٩]+(?:[.,][0-9٠-٩]+)*").map { String($0.map { c in c.wholeNumberValue.map{Character(String($0))} ?? c }) }
        }
        return numbers(source) == numbers(target) && ["%","$","€","£","△","□","✕","○","L1","L2","R1","R2"].allSatisfy { !source.contains($0) || target.contains($0) }
    }
}

/// One payload contract for the TV receiver and the phone's Codable decoder.
enum SpatialPresentation {
    static func snapshot(_ screen: SpatialScreen, rows: [OCRLine], aspect: Double) -> [String:Any]? {
        guard aspect.isFinite, (0.5...4).contains(aspect) else { return nil }
        let items = screen.elements.compactMap { element -> [String:Any]? in
            guard let row = rows.first(where:{SpatialRecognition.key($0.text) == element.normalized && abs($0.box.x-element.box.x)<0.035 && abs($0.box.y-element.box.y)<0.035}) else { return nil }
            return ["id":SpatialRecognition.hash(element.normalized+"@\(Int(row.box.x*100)),\(Int(row.box.y*100))"),"source":row.text,"translated":SubtitlePresentation.clean(element.translated),
                    "box":["x":row.box.x,"y":row.box.y,"w":row.box.w,"h":row.box.h],"alignment":element.alignment,"scale":element.scale,"dynamic":element.dynamic]
        }
        var appearance = MenuAppearance(); appearance.shadow = false
        guard let data = try? JSONEncoder().encode(appearance), let style = try? JSONSerialization.jsonObject(with:data) else { return nil }
        var bounded = Array(items.prefix(24))
        while true {
            let message = TVProtocol.envelope("menu_snapshot",fields:["menu_id":"spatial-"+screen.id,"items":bounded,"appearance":style,"spatial":true,"category":screen.category.rawValue,"frame_aspect":aspect,"lease_ms":1800])
            if let data = try? TVProtocol.encode(message), data.count <= 14000 { return message }
            if bounded.isEmpty { return nil }; bounded.removeLast()
        }
    }
}

/// Queue-confined SQLite, small page cache, indexed candidate retrieval, no screenshots.
/// New additive database; old pack/profile/correction/learning files aren't rewritten.
final class SpatialMemoryStore {
    private var db: OpaquePointer?
    init(url: URL) throws {
        try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
        guard sqlite3_open_v2(url.path,&db,SQLITE_OPEN_READWRITE|SQLITE_OPEN_CREATE|SQLITE_OPEN_NOMUTEX,nil) == SQLITE_OK else { sqlite3_close_v2(db); db = nil; throw PackFailure.unavailable }
        do {
            sqlite3_busy_timeout(db,100)
            try execute("PRAGMA journal_mode=WAL"); try execute("PRAGMA cache_size=-1024"); try execute("PRAGMA mmap_size=0")
            try execute("PRAGMA max_page_count=16384")
            let v = try statement("PRAGMA user_version"); defer{sqlite3_finalize(v)}
            guard sqlite3_step(v) == SQLITE_ROW, sqlite3_column_int(v,0) <= 1 else { throw PackFailure.unsupported }
            try execute("BEGIN IMMEDIATE")
            do {
                try execute("CREATE TABLE IF NOT EXISTS screens(game TEXT NOT NULL, version TEXT NOT NULL, id TEXT NOT NULL, category TEXT NOT NULL, observed REAL NOT NULL, payload BLOB NOT NULL, PRIMARY KEY(game,version,id))")
                try execute("CREATE TABLE IF NOT EXISTS anchors(game TEXT NOT NULL, version TEXT NOT NULL, text TEXT NOT NULL, screen TEXT NOT NULL, PRIMARY KEY(game,version,text,screen))")
                try execute("CREATE TABLE IF NOT EXISTS translations(game TEXT NOT NULL, version TEXT NOT NULL, source TEXT NOT NULL, target TEXT NOT NULL, origin TEXT NOT NULL, observed REAL NOT NULL, PRIMARY KEY(game,version,source))")
                try execute("CREATE INDEX IF NOT EXISTS screens_age ON screens(observed)")
                try execute("CREATE INDEX IF NOT EXISTS translations_age ON translations(observed)")
                try execute("PRAGMA user_version=1"); try execute("COMMIT")
            } catch { try? execute("ROLLBACK"); throw error }
        } catch { sqlite3_close_v2(db); db = nil; throw error }
    }
    deinit { sqlite3_close_v2(db) }
    private func statement(_ sql: String) throws -> OpaquePointer {
        var s: OpaquePointer?
        guard sqlite3_prepare_v2(db,sql,-1,&s,nil) == SQLITE_OK, let s else { throw PackFailure.damaged }; return s
    }
    private func execute(_ sql: String) throws {
        let s = try statement(sql); defer{sqlite3_finalize(s)}
        var rc = sqlite3_step(s); while rc == SQLITE_ROW { rc = sqlite3_step(s) }
        guard rc == SQLITE_DONE else { throw PackFailure.damaged }
    }
    private func bind(_ values: [String], to s: OpaquePointer) throws {
        for (i,v) in values.enumerated() {
            guard v.withCString({sqlite3_bind_text(s,Int32(i+1),$0,-1,unsafeBitCast(-1,to:sqlite3_destructor_type.self))}) == SQLITE_OK else { throw PackFailure.damaged }
        }
    }
    private func text(_ s: OpaquePointer, _ col: Int32) -> String { sqlite3_column_text(s,col).map{String(cString:$0)} ?? "" }
    func translation(game: String, version: String, source: String) throws -> (String,String)? {
        let s = try statement("SELECT target,origin FROM translations WHERE game=? AND version=? AND source=?"); defer{sqlite3_finalize(s)}
        try bind([game,version,SpatialRecognition.key(source)],to:s)
        return sqlite3_step(s) == SQLITE_ROW ? (text(s,0),text(s,1)) : nil
    }
    func saveTranslation(game: String, version: String, source: String, target: String, origin: String, now: Double) throws {
        guard UserDataFile.validGame(game), !TextPrivacy.excluded(source), (1...320).contains(source.count), (1...400).contains(target.count) else { return }
        let s = try statement("INSERT OR REPLACE INTO translations VALUES(?,?,?,?,?,?)"); defer{sqlite3_finalize(s)}
        try bind([game,version,SpatialRecognition.key(source),target,origin],to:s); sqlite3_bind_double(s,6,now)
        guard sqlite3_step(s) == SQLITE_DONE else { throw PackFailure.damaged }
    }
    func recognize(game: String, version: String, rows: [OCRLine], category: ScreenCategory) throws -> SpatialScreen? {
        let s = try statement("SELECT s.payload FROM anchors a JOIN screens s ON s.game=a.game AND s.version=a.version AND s.id=a.screen WHERE a.game=? AND a.version=? AND a.text=? AND s.category=? ORDER BY s.observed DESC LIMIT 8")
        defer{sqlite3_finalize(s)}
        var seen = Set<String>(), candidates: [(Double,SpatialScreen)] = []
        for row in rows.prefix(8) {
            sqlite3_reset(s); sqlite3_clear_bindings(s); try bind([game,version,SpatialRecognition.key(row.text),category.rawValue],to:s)
            while sqlite3_step(s) == SQLITE_ROW {
                guard let bytes = sqlite3_column_blob(s,0), sqlite3_column_bytes(s,0) <= 65536 else { continue }
                let data = Data(bytes:bytes,count:Int(sqlite3_column_bytes(s,0)))
                guard let screen = try? JSONDecoder().decode(SpatialScreen.self,from:data), seen.insert(screen.id).inserted else { continue }
                let score = SpatialRecognition.layoutScore(screen.elements,observed:rows)
                if score >= 0.75 { candidates.append((score,screen)) }
            }
        }
        let ranked = candidates.sorted{$0.0 > $1.0}
        guard let best = ranked.first, ranked.count == 1 || best.0-ranked[1].0 >= 0.15 else { return nil }
        return best.1
    }
    func save(_ screen: SpatialScreen, version: String) throws {
        guard screen.elements.count <= 24, screen.elements.allSatisfy({!TextPrivacy.excluded($0.source) && $0.box.isValid}) else { return }
        let payload = try JSONEncoder().encode(screen); guard payload.count <= 65536 else { return }
        try execute("BEGIN IMMEDIATE")
        do {
            let s = try statement("INSERT OR REPLACE INTO screens VALUES(?,?,?,?,?,?)"); defer{sqlite3_finalize(s)}
            try bind([screen.game,version,screen.id,screen.category.rawValue],to:s); sqlite3_bind_double(s,5,screen.observed)
            _ = payload.withUnsafeBytes { sqlite3_bind_blob(s,6,$0.baseAddress,Int32(payload.count),unsafeBitCast(-1,to:sqlite3_destructor_type.self)) }
            guard sqlite3_step(s) == SQLITE_DONE else { throw PackFailure.damaged }
            let a = try statement("INSERT OR IGNORE INTO anchors VALUES(?,?,?,?)"); defer{sqlite3_finalize(a)}
            for element in screen.elements.filter({!$0.dynamic}).prefix(12) {
                sqlite3_reset(a); sqlite3_clear_bindings(a); try bind([screen.game,version,element.normalized,screen.id],to:a)
                guard sqlite3_step(a) == SQLITE_DONE else { throw PackFailure.damaged }
            }
            try execute("DELETE FROM screens WHERE rowid IN (SELECT rowid FROM screens ORDER BY observed DESC LIMIT -1 OFFSET 1000)")
            try execute("DELETE FROM anchors WHERE NOT EXISTS (SELECT 1 FROM screens s WHERE s.game=anchors.game AND s.version=anchors.version AND s.id=anchors.screen)")
            try execute("DELETE FROM translations WHERE rowid IN (SELECT rowid FROM translations ORDER BY observed DESC LIMIT -1 OFFSET 20000)")
            try execute("COMMIT")
        } catch { try? execute("ROLLBACK"); throw error }
    }
    func releaseMemory() { sqlite3_db_release_memory(db) }
}
