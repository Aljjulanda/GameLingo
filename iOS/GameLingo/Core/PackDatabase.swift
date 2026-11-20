import Foundation
#if canImport(SQLite3)
import SQLite3
#else
import CSQLite
#endif

enum PackFailure: LocalizedError {
    case invalid, unsupported, damaged, size, unavailable
    var errorDescription: String? {
        switch self {
        case .invalid: return "بنية حزمة الترجمة غير صالحة"
        case .unsupported: return "إصدار الحزمة أو محتواها غير مدعوم"
        case .damaged: return "فشل التحقق من سلامة حزمة الترجمة"
        case .size: return "حزمة الترجمة تتجاوز الحدود المسموحة"
        case .unavailable: return "الحزمة غير متاحة؛ يستمر استخدام Argos"
        }
    }
}

struct PackManifest: Codable, Equatable {
    var formatVersion: Int, schemaVersion: Int
    var gameId: String, gameTitle: String, sourceLanguage: String, targetLanguage: String
    var packVersion: String, recordCount: Int, usableCount: Int, categories: [String]
    var attribution: String, permission: String, builtAt: String, arabicOrder: String, databaseSha256: String
    var speakerNames: [String]?
    var coverage: String?
    var quality: PackQualitySummary? = nil
    static let categories: Set<String> = ["dialogue","menu","document","general"]
    func validate() throws {
        guard formatVersion == 1, [1,2].contains(schemaVersion), sourceLanguage == "en", targetLanguage == "ar", arabicOrder == "logical" else { throw PackFailure.unsupported }
        guard schemaVersion == 2 ? quality?.valid(recordCount:recordCount) == true : quality == nil else { throw PackFailure.invalid }
        guard gameId.range(of:"^[a-z0-9][a-z0-9._-]{0,63}$",options:.regularExpression) != nil,
              !gameTitle.isEmpty, gameTitle.count <= 100, !packVersion.isEmpty, packVersion.count <= 32,
              (1...500_000).contains(recordCount), (0...recordCount).contains(usableCount),
              !categories.isEmpty, categories.count <= 4, Set(categories).isSubset(of:Self.categories), Set(categories).count == categories.count,
              attribution.count <= 4096, permission.count <= 2000, builtAt.count <= 64,
              databaseSha256.range(of:"^[0-9a-f]{64}$",options:.regularExpression) != nil,
              coverage == nil || coverage == "partial" || coverage == "unspecified",
              (speakerNames?.count ?? 0) <= 64,
              speakerNames?.allSatisfy({ !$0.isEmpty && $0.count <= 40 && !$0.contains(",") && !$0.contains("\n") }) != false else { throw PackFailure.invalid }
    }
    static func decode(_ data: Data) throws -> PackManifest {
        guard data.count <= 65536, String(data:data,encoding:.utf8) != nil else { throw PackFailure.size }
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        let value = try decoder.decode(Self.self,from:data); try value.validate(); return value
    }
}

enum PackLookupKey {
    static func normalized(_ text: String) -> String {
        var value = SubtitlePresentation.clean(text).precomposedStringWithCompatibilityMapping
        for (a,b) in [("’","'"),("‘","'"),("“","\""),("”","\"")] { value = value.replacingOccurrences(of:a,with:b) }
        value = value.split(whereSeparator:\.isWhitespace).joined(separator:" ").lowercased()
        while value.last == "." || value.last == "!" { value.removeLast() }
        return value.trimmingCharacters(in:.whitespacesAndNewlines)
    }
}

struct PackMatch {
    enum Kind: String { case exact, normalized, punctuationless, missing, ambiguous, unsupported, unavailable }
    var text: String?
    var kind: Kind
}

/// One read-only connection, two prepared lookup statements, bounded page cache.
/// Confined to its owner's serial queue. No caller-supplied SQL is accepted.
private final class PackSQLiteProgress {
    var deadline = ProcessInfo.processInfo.systemUptime+30
    var check: (() throws -> Void)?
    func interrupted() -> Int32 {
        do { try check?(); return ProcessInfo.processInfo.systemUptime > deadline ? 1 : 0 }
        catch { return 1 }
    }
}

final class PackDatabase {
    static let table = "CREATE TABLE entries (identifier TEXT NOT NULL, original_id TEXT NOT NULL, source TEXT NOT NULL, normalized TEXT NOT NULL, target TEXT NOT NULL, category TEXT NOT NULL, source_file TEXT NOT NULL, flags TEXT NOT NULL, usable INTEGER NOT NULL)"
    static let indexes = ["by_exact":"CREATE INDEX by_exact ON entries(source, category)","by_normalized":"CREATE INDEX by_normalized ON entries(normalized, category)","by_identifier":"CREATE INDEX by_identifier ON entries(identifier)"]
    static let tableV2 = String(table.dropLast())+", punctuationless TEXT NOT NULL)"
    static let qualityTable = "CREATE TABLE quality_variants (entry_id INTEGER NOT NULL, profile INTEGER NOT NULL, source TEXT NOT NULL, normalized TEXT NOT NULL, target TEXT NOT NULL, flags TEXT NOT NULL, usable INTEGER NOT NULL, punctuationless TEXT NOT NULL)"
    static let qualityIndexes = [
        "by_punctuationless":"CREATE INDEX by_punctuationless ON entries(punctuationless, category)",
        "quality_profile":"CREATE UNIQUE INDEX quality_profile ON quality_variants(entry_id, profile)",
        "quality_exact":"CREATE INDEX quality_exact ON quality_variants(source, profile)",
        "quality_normalized":"CREATE INDEX quality_normalized ON quality_variants(normalized, profile)",
        "quality_punctuationless":"CREATE INDEX quality_punctuationless ON quality_variants(punctuationless, profile)"
    ]
    private(set) var schemaVersion = 1
    private var db: OpaquePointer?
    private var exact: OpaquePointer?, normalized: OpaquePointer?
    private var punctuationless: OpaquePointer?
    private var qualityStatements: [OpaquePointer] = []
    private let progress = PackSQLiteProgress()
    private var cache = BoundedLRU<String,PackMatch>(capacity:32)
    init(url: URL) throws {
        let encoded = url.path.addingPercentEncoding(withAllowedCharacters:.urlPathAllowed)!
        guard sqlite3_open_v2("file:"+encoded+"?mode=ro&immutable=1",&db,SQLITE_OPEN_READONLY|SQLITE_OPEN_URI|SQLITE_OPEN_NOMUTEX,nil) == SQLITE_OK else { sqlite3_close_v2(db); db = nil; throw PackFailure.damaged }
        do {
        sqlite3_limit(db,SQLITE_LIMIT_LENGTH,65536); sqlite3_limit(db,SQLITE_LIMIT_SQL_LENGTH,4096)
        sqlite3_limit(db,SQLITE_LIMIT_COLUMN,32); sqlite3_limit(db,SQLITE_LIMIT_ATTACHED,0)
        sqlite3_limit(db,SQLITE_LIMIT_EXPR_DEPTH,20); sqlite3_limit(db,SQLITE_LIMIT_VARIABLE_NUMBER,8)
        sqlite3_progress_handler(db,1000,{ pointer in
            guard let pointer else { return 1 }
            return Unmanaged<PackSQLiteProgress>.fromOpaque(pointer).takeUnretainedValue().interrupted()
        },Unmanaged.passUnretained(progress).toOpaque())
        try execute("PRAGMA trusted_schema=OFF"); try execute("PRAGMA query_only=ON")
        try execute("PRAGMA mmap_size=0"); try execute("PRAGMA cache_size=-2048")
        try validateSchema()
        exact = try prepare("SELECT target, usable FROM entries WHERE source=? AND category IN (?, ?, 'general') LIMIT 33")
        normalized = try prepare("SELECT target, usable FROM entries WHERE normalized=? AND category IN (?, ?, 'general') LIMIT 33")
        if schemaVersion == 2 {
            punctuationless = try prepare("SELECT target, usable FROM entries WHERE punctuationless=? AND category IN (?, ?, 'general') LIMIT 33")
            for column in ["source","normalized","punctuationless"] {
                qualityStatements.append(try prepare("SELECT r.target, r.usable FROM entries r WHERE r.\(column)=?1 AND r.category IN (?2, ?3, 'general') AND NOT EXISTS (SELECT 1 FROM quality_variants q WHERE q.entry_id=r.rowid AND q.profile=?4) UNION ALL SELECT q.target, q.usable FROM quality_variants q JOIN entries r ON r.rowid=q.entry_id WHERE q.\(column)=?1 AND q.profile=?4 AND r.category IN (?2, ?3, 'general') LIMIT 33"))
            }
        }
        } catch {
            sqlite3_finalize(exact); sqlite3_finalize(normalized)
            sqlite3_finalize(punctuationless); qualityStatements.forEach { sqlite3_finalize($0) }; qualityStatements = []
            exact = nil; normalized = nil
            sqlite3_progress_handler(db,0,nil,nil); sqlite3_close_v2(db); db = nil
            throw error
        }
    }
    deinit {
        sqlite3_finalize(exact); sqlite3_finalize(normalized); sqlite3_finalize(punctuationless)
        qualityStatements.forEach { sqlite3_finalize($0) }; sqlite3_close_v2(db)
    }
    private func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db,sql,-1,&statement,nil) == SQLITE_OK, let statement else { throw PackFailure.damaged }
        return statement
    }
    private func execute(_ sql: String) throws {
        let statement = try prepare(sql); defer { sqlite3_finalize(statement) }
        var code = sqlite3_step(statement)
        while code == SQLITE_ROW { code = sqlite3_step(statement) }
        guard code == SQLITE_DONE else { throw PackFailure.damaged }
    }
    private func string(_ statement: OpaquePointer, _ column: Int32) throws -> String {
        guard sqlite3_column_type(statement,column) == SQLITE_TEXT, let pointer = sqlite3_column_text(statement,column),
              let text = String(bytes:UnsafeBufferPointer(start:pointer,count:Int(sqlite3_column_bytes(statement,column))),encoding:.utf8) else { throw PackFailure.damaged }
        return text
    }
    private func bind(_ value: String, _ statement: OpaquePointer, _ column: Int32) throws {
        guard value.withCString({ sqlite3_bind_text(statement,column,$0,-1,unsafeBitCast(-1,to:sqlite3_destructor_type.self)) }) == SQLITE_OK else { throw PackFailure.damaged }
    }
    private func validateSchema() throws {
        let version = try prepare("PRAGMA user_version"); defer { sqlite3_finalize(version) }
        guard sqlite3_step(version) == SQLITE_ROW else { throw PackFailure.damaged }
        schemaVersion = Int(sqlite3_column_int(version,0))
        guard [1,2].contains(schemaVersion) else { throw PackFailure.unsupported }
        var tables = ["entries":schemaVersion == 1 ? Self.table : Self.tableV2]
        var indexes = Self.indexes
        if schemaVersion == 2 { tables["quality_variants"] = Self.qualityTable; indexes.merge(Self.qualityIndexes) {_,b in b} }
        let statement = try prepare("SELECT type, name, sql FROM sqlite_master")
        defer { sqlite3_finalize(statement) }
        var found = Set<String>(), code = sqlite3_step(statement)
        while code == SQLITE_ROW {
            let type = try string(statement,0), name = try string(statement,1), sql = try string(statement,2)
            guard (type == "table" && tables[name] == sql) || (type == "index" && indexes[name] == sql), !found.contains(name) else { throw PackFailure.invalid }
            found.insert(name); code = sqlite3_step(statement)
        }
        guard code == SQLITE_DONE, found == Set(Array(tables.keys)+Array(indexes.keys)) else { throw PackFailure.invalid }
    }
    func validateContents(manifest: PackManifest, check: @escaping () throws -> Void = {}) throws {
        guard manifest.schemaVersion == schemaVersion else { throw PackFailure.invalid }
        progress.deadline = ProcessInfo.processInfo.systemUptime+60; progress.check = check
        defer { progress.check = nil }
        let integrity = try prepare("PRAGMA integrity_check(1)"); defer { sqlite3_finalize(integrity) }
        let integrityCode = sqlite3_step(integrity); try check()
        guard integrityCode == SQLITE_ROW, try string(integrity,0) == "ok" else { throw PackFailure.damaged }
        let statement = try prepare("SELECT identifier, original_id, source, normalized, target, category, source_file, flags, usable FROM entries")
        defer { sqlite3_finalize(statement) }
        var count = 0, usable = 0, code = sqlite3_step(statement)
        while code == SQLITE_ROW {
            if count % 256 == 0 { try check() }
            count += 1; guard count <= 500000, ProcessInfo.processInfo.systemUptime <= progress.deadline else { throw PackFailure.size }
            let fields = try (0..<8).map { try string(statement,Int32($0)) }
            guard fields[0].count <= 128, fields[1].count <= 128, fields[2].count <= 4096,
                  fields[3] == PackLookupKey.normalized(fields[2]), fields[4].count <= 16000,
                  PackManifest.categories.contains(fields[5]), manifest.categories.contains(fields[5]),
                  fields[6].count <= 8192, fields[7].count <= 2048,
                  fields.allSatisfy({ !$0.contains("\0") }), sqlite3_column_type(statement,8) == SQLITE_INTEGER,
                  [0,1].contains(sqlite3_column_int(statement,8)) else { throw PackFailure.invalid }
            if sqlite3_column_int(statement,8) == 1 {
                guard !fields[2].isEmpty, !fields[3].isEmpty, !fields[4].isEmpty,
                      SubtitlePresentation.clean(fields[4]) == fields[4],
                      !fields[4].unicodeScalars.contains(where:{ (0xfb50...0xfdff).contains($0.value) || (0xfe70...0xfefc).contains($0.value) }),
                      fields[4].unicodeScalars.contains(where:{ (0x0600...0x06ff).contains($0.value) }) else { throw PackFailure.invalid }
                usable += 1
            }
            code = sqlite3_step(statement)
        }
        try check()
        guard code == SQLITE_DONE, count == manifest.recordCount, usable == manifest.usableCount else { throw PackFailure.damaged }
        if schemaVersion == 2 { try validateQuality(manifest:manifest,check:check) }
    }
    private func query(_ statement: OpaquePointer, key: String, category: String, kind: PackMatch.Kind, profile: Int = 0) throws -> PackMatch {
        sqlite3_reset(statement); sqlite3_clear_bindings(statement)
        defer { sqlite3_reset(statement); sqlite3_clear_bindings(statement) }
        try bind(key,statement,1); try bind(category,statement,2)
        try bind(category == "document" ? "menu" : category,statement,3)
        if profile != 0 { guard sqlite3_bind_int(statement,4,Int32(profile)) == SQLITE_OK else { throw PackFailure.damaged } }
        var values = Set<String>(), count = 0, blocked = false, code = sqlite3_step(statement)
        while code == SQLITE_ROW {
            count += 1; values.insert(try string(statement,0)); blocked = blocked || sqlite3_column_int(statement,1) != 1
            code = sqlite3_step(statement)
        }
        guard code == SQLITE_DONE else { throw PackFailure.damaged }
        if count == 0 { return PackMatch(text:nil,kind:.missing) }
        if count > 32 || values.count != 1 { return PackMatch(text:nil,kind:.ambiguous) }
        if blocked { return PackMatch(text:nil,kind:.unsupported) }
        return PackMatch(text:values.first,kind:kind)
    }
    func lookup(_ source: String, category: String, quality: PackQualityOptions = PackQualityOptions()) throws -> PackMatch {
        guard source.count <= 4096, !source.contains("\0"), PackManifest.categories.contains(category) else { return PackMatch(text:nil,kind:.unsupported) }
        let key = quality.key+"/"+category+"/"+source
        if let result = cache.get(key) { return result }
        progress.deadline = ProcessInfo.processInfo.systemUptime+0.05
        let profile = schemaVersion == 2 ? quality.profile : 0
        let exactStatement = profile == 0 ? exact! : qualityStatements[0]
        let normalizedStatement = profile == 0 ? normalized! : qualityStatements[1]
        var result = try query(exactStatement,key:source,category:category,kind:.exact,profile:profile)
        if result.kind == .missing { result = try query(normalizedStatement,key:PackLookupKey.normalized(source),category:category,kind:.normalized,profile:profile) }
        if result.kind == .missing, quality.punctuation, schemaVersion == 2 {
            let punctuationKey = PackQualityPolicy.punctuationless(source)
            if !punctuationKey.isEmpty { result = try query(profile == 0 ? punctuationless! : qualityStatements[2],key:punctuationKey,category:category,kind:.punctuationless,profile:profile) }
        }
        cache.put(result,for:key); return result
    }
    /// Shared bounded stream for the writer and derived-content validation.
    func forEachRawRow(check: @escaping () throws -> Void = {}, _ body: (Int64,PackRawRow,String?) throws -> Void) throws {
        progress.deadline = ProcessInfo.processInfo.systemUptime+120; progress.check = check
        defer { progress.check = nil }
        let sql = "SELECT rowid, identifier, original_id, source, normalized, target, category, source_file, flags, usable"+(schemaVersion == 2 ? ", punctuationless" : "")+" FROM entries ORDER BY rowid"
        let statement = try prepare(sql); defer { sqlite3_finalize(statement) }
        var count = 0, code = sqlite3_step(statement)
        while code == SQLITE_ROW {
            if count % 256 == 0 { try check() }; count += 1
            guard count <= 500000 else { throw PackFailure.size }
            let row = PackRawRow(fields:try (1...8).map { try string(statement,Int32($0)) },usable:sqlite3_column_int(statement,9) == 1)
            try body(sqlite3_column_int64(statement,0),row,schemaVersion == 2 ? try string(statement,10) : nil)
            code = sqlite3_step(statement)
        }
        try check(); guard code == SQLITE_DONE else { throw PackFailure.damaged }
    }
    private func validateQuality(manifest: PackManifest, check: @escaping () throws -> Void) throws {
        let statement = try prepare("SELECT entry_id, profile, source, normalized, target, flags, usable, punctuationless FROM quality_variants ORDER BY entry_id, profile")
        defer { sqlite3_finalize(statement) }
        var code = sqlite3_step(statement), count: Int64 = 0, totals = PackQualityAccumulator()
        try forEachRawRow(check:check) { id,row,key in
            count += 1
            guard id == count, key == PackQualityPolicy.punctuationless(row.source) else { throw PackFailure.invalid }
            let variants = row.variants
            totals.observe(row,variants:variants)
            for (profile,value) in variants {
                guard code == SQLITE_ROW, sqlite3_column_type(statement,0) == SQLITE_INTEGER, sqlite3_column_int64(statement,0) == id,
                      sqlite3_column_type(statement,1) == SQLITE_INTEGER, sqlite3_column_int(statement,1) == profile,
                      try string(statement,2) == value.source, try string(statement,3) == PackLookupKey.normalized(value.source),
                      try string(statement,4) == value.target, try string(statement,5) == value.flags,
                      sqlite3_column_type(statement,6) == SQLITE_INTEGER, sqlite3_column_int(statement,6) == (value.usable ? 1 : 0),
                      try string(statement,7) == PackQualityPolicy.punctuationless(value.source) else { throw PackFailure.invalid }
                code = sqlite3_step(statement)
            }
        }
        guard code == SQLITE_DONE, totals.summary == manifest.quality else { throw PackFailure.invalid }
    }
    func lookupIdentifier(_ identifier: String) throws -> [String] {
        progress.deadline = ProcessInfo.processInfo.systemUptime+0.05
        let statement = try prepare("SELECT target FROM entries WHERE identifier=? LIMIT 33"); defer { sqlite3_finalize(statement) }
        try bind(identifier,statement,1); var result: [String] = [], code = sqlite3_step(statement)
        while code == SQLITE_ROW { result.append(try string(statement,0)); code = sqlite3_step(statement) }
        guard code == SQLITE_DONE else { throw PackFailure.damaged }; return result
    }
    /// Explicit synthetic compatibility check only, not gameplay provenance.
    func sampleSources(seed: UInt64 = 0x474c, limit: Int = 20) throws -> [String] {
        progress.deadline = ProcessInfo.processInfo.systemUptime+2
        let statement = try prepare("SELECT source FROM entries WHERE usable=1 AND category IN ('dialogue','general') ORDER BY identifier LIMIT 20")
        defer { sqlite3_finalize(statement) }
        var result: [String] = [], code = sqlite3_step(statement)
        while code == SQLITE_ROW { result.append(try string(statement,0)); code = sqlite3_step(statement) }
        guard code == SQLITE_DONE else { throw PackFailure.damaged }
        var state = seed
        if result.count > 1 { for i in stride(from:result.count-1,through:1,by:-1) {
            state = state &* 6364136223846793005 &+ 1
            result.swapAt(i,Int(state % UInt64(i+1)))
        } }
        return Array(result.prefix(max(0,min(20,limit))))
    }
}
