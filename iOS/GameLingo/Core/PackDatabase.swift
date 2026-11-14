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
    static let categories: Set<String> = ["dialogue","menu","document","general"]
    func validate() throws {
        guard formatVersion == 1, schemaVersion == 1, sourceLanguage == "en", targetLanguage == "ar", arabicOrder == "logical" else { throw PackFailure.unsupported }
        guard gameId.range(of:"^[a-z0-9][a-z0-9._-]{0,63}$",options:.regularExpression) != nil,
              !gameTitle.isEmpty, gameTitle.count <= 100, !packVersion.isEmpty, packVersion.count <= 32,
              (1...500_000).contains(recordCount), (0...recordCount).contains(usableCount),
              !categories.isEmpty, categories.count <= 4, Set(categories).isSubset(of:Self.categories), Set(categories).count == categories.count,
              attribution.count <= 4096, permission.count <= 2000, builtAt.count <= 64,
              databaseSha256.range(of:"^[0-9a-f]{64}$",options:.regularExpression) != nil,
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
    enum Kind: String { case exact, normalized, missing, ambiguous, unsupported, unavailable }
    var text: String?
    var kind: Kind
}

/// One read-only connection, two prepared lookup statements, bounded page cache.
/// Confined to its owner's serial queue. No caller-supplied SQL is accepted.
final class PackDatabase {
    static let table = "CREATE TABLE entries (identifier TEXT NOT NULL, original_id TEXT NOT NULL, source TEXT NOT NULL, normalized TEXT NOT NULL, target TEXT NOT NULL, category TEXT NOT NULL, source_file TEXT NOT NULL, flags TEXT NOT NULL, usable INTEGER NOT NULL)"
    static let indexes = ["by_exact":"CREATE INDEX by_exact ON entries(source, category)","by_normalized":"CREATE INDEX by_normalized ON entries(normalized, category)","by_identifier":"CREATE INDEX by_identifier ON entries(identifier)"]
    private var db: OpaquePointer?
    private var exact: OpaquePointer?, normalized: OpaquePointer?
    private let deadline = UnsafeMutablePointer<Double>.allocate(capacity:1)
    private var cache = BoundedLRU<String,PackMatch>(capacity:32)
    init(url: URL) throws {
        deadline.initialize(to:ProcessInfo.processInfo.systemUptime+30)
        var ready = false
        defer {
            if !ready {
                sqlite3_finalize(exact); sqlite3_finalize(normalized); sqlite3_close_v2(db)
                deadline.deinitialize(count:1); deadline.deallocate()
            }
        }
        let encoded = url.path.addingPercentEncoding(withAllowedCharacters:.urlPathAllowed)!
        guard sqlite3_open_v2("file:"+encoded+"?mode=ro&immutable=1",&db,SQLITE_OPEN_READONLY|SQLITE_OPEN_URI|SQLITE_OPEN_NOMUTEX,nil) == SQLITE_OK else { throw PackFailure.damaged }
        sqlite3_limit(db,SQLITE_LIMIT_LENGTH,65536); sqlite3_limit(db,SQLITE_LIMIT_SQL_LENGTH,4096)
        sqlite3_limit(db,SQLITE_LIMIT_COLUMN,32); sqlite3_limit(db,SQLITE_LIMIT_ATTACHED,0)
        sqlite3_limit(db,SQLITE_LIMIT_EXPR_DEPTH,20); sqlite3_limit(db,SQLITE_LIMIT_VARIABLE_NUMBER,8)
        sqlite3_progress_handler(db,1000,{ pointer in
            guard let pointer else { return 1 }
            return ProcessInfo.processInfo.systemUptime > pointer.assumingMemoryBound(to:Double.self).pointee ? 1 : 0
        },deadline)
        try execute("PRAGMA trusted_schema=OFF"); try execute("PRAGMA query_only=ON")
        try execute("PRAGMA mmap_size=0"); try execute("PRAGMA cache_size=-2048")
        try validateSchema()
        exact = try prepare("SELECT target, usable FROM entries WHERE source=? AND category IN (?, 'general') LIMIT 33")
        normalized = try prepare("SELECT target, usable FROM entries WHERE normalized=? AND category IN (?, 'general') LIMIT 33")
        ready = true
    }
    deinit {
        sqlite3_finalize(exact); sqlite3_finalize(normalized); sqlite3_close_v2(db)
        deadline.deinitialize(count:1); deadline.deallocate()
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
        let statement = try prepare("SELECT type, name, sql FROM sqlite_master WHERE name NOT LIKE 'sqlite_%'")
        defer { sqlite3_finalize(statement) }
        var found = Set<String>(), code = sqlite3_step(statement)
        while code == SQLITE_ROW {
            let type = try string(statement,0), name = try string(statement,1), sql = try string(statement,2)
            guard (name == "entries" && type == "table" && sql == Self.table) || (type == "index" && Self.indexes[name] == sql), !found.contains(name) else { throw PackFailure.invalid }
            found.insert(name); code = sqlite3_step(statement)
        }
        guard code == SQLITE_DONE, found == Set(["entries"]+Array(Self.indexes.keys)) else { throw PackFailure.invalid }
        let version = try prepare("PRAGMA user_version"); defer { sqlite3_finalize(version) }
        guard sqlite3_step(version) == SQLITE_ROW, sqlite3_column_int(version,0) == 1 else { throw PackFailure.unsupported }
    }
    func validateContents(manifest: PackManifest) throws {
        deadline.pointee = ProcessInfo.processInfo.systemUptime+60
        let check = try prepare("PRAGMA integrity_check(1)"); defer { sqlite3_finalize(check) }
        guard sqlite3_step(check) == SQLITE_ROW, try string(check,0) == "ok" else { throw PackFailure.damaged }
        let statement = try prepare("SELECT identifier, original_id, source, normalized, target, category, source_file, flags, usable FROM entries")
        defer { sqlite3_finalize(statement) }
        var count = 0, usable = 0, code = sqlite3_step(statement)
        while code == SQLITE_ROW {
            count += 1; guard count <= 500000, ProcessInfo.processInfo.systemUptime <= deadline.pointee else { throw PackFailure.size }
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
        guard code == SQLITE_DONE, count == manifest.recordCount, usable == manifest.usableCount else { throw PackFailure.damaged }
    }
    private func query(_ statement: OpaquePointer, key: String, category: String, kind: PackMatch.Kind) throws -> PackMatch {
        sqlite3_reset(statement); sqlite3_clear_bindings(statement)
        defer { sqlite3_reset(statement); sqlite3_clear_bindings(statement) }
        try bind(key,statement,1); try bind(category,statement,2)
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
    func lookup(_ source: String, category: String) throws -> PackMatch {
        guard source.count <= 4096, !source.contains("\0"), PackManifest.categories.contains(category) else { return PackMatch(text:nil,kind:.unsupported) }
        let key = category+"/"+source
        if let result = cache.get(key) { return result }
        deadline.pointee = ProcessInfo.processInfo.systemUptime+0.05
        var result = try query(exact!,key:source,category:category,kind:.exact)
        if result.kind == .missing { result = try query(normalized!,key:PackLookupKey.normalized(source),category:category,kind:.normalized) }
        cache.put(result,for:key); return result
    }
    func lookupIdentifier(_ identifier: String) throws -> [String] {
        deadline.pointee = ProcessInfo.processInfo.systemUptime+0.05
        let statement = try prepare("SELECT target FROM entries WHERE identifier=? LIMIT 33"); defer { sqlite3_finalize(statement) }
        try bind(identifier,statement,1); var result: [String] = [], code = sqlite3_step(statement)
        while code == SQLITE_ROW { result.append(try string(statement,0)); code = sqlite3_step(statement) }
        guard code == SQLITE_DONE else { throw PackFailure.damaged }; return result
    }
}
