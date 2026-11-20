import Foundation
#if canImport(SQLite3)
import SQLite3
#else
import CSQLite
#endif

struct PackQualitySummary: Codable, Equatable {
    var rawUsable = 0, markupUsable = 0, labelsUsable = 0, combinedUsable = 0
    var cleaned = 0, excluded = 0, labels = 0
    var possibleVisualOrder = false
    var speakerNames: [String] = []
    func usable(profile: Int) -> Int { profile == 1 ? markupUsable : profile == 2 ? labelsUsable : profile == 3 ? combinedUsable : rawUsable }
    func valid(recordCount: Int) -> Bool {
        [rawUsable,markupUsable,labelsUsable,combinedUsable,cleaned,excluded,labels].allSatisfy{(0...max(0,recordCount)).contains($0)} &&
            speakerNames.count <= 64 && Set(speakerNames).count == speakerNames.count && speakerNames == speakerNames.sorted() &&
            speakerNames.allSatisfy{SpeakerEvidence.isName($0,knownNames:"",confidence:1)}
    }
}

struct PackRawRow {
    var fields: [String], usable: Bool
    var source: String { fields[2] }
    var target: String { fields[4] }
    var original: PackQualityText { PackQualityText(source:source,target:target,flags:fields[7],usable:usable) }
    func variants(alignedArabic: (String) throws -> String?) rethrows -> [(Int32,PackQualityText)] {
        try (1...3).compactMap { profile in
            let candidate = profile & 1 != 0 ? PackQualityPolicy.cleanMarkup(source) : source
            let name = profile & 2 != 0 ? PackQualityPolicy.label(candidate)?.name : nil
            let arabic = try name.flatMap { try alignedArabic($0) }
            let value = PackQualityPolicy.transform(source:source,target:target,flags:fields[7],usable:usable,
                options:PackQualityOptions(markup:profile & 1 != 0,labels:profile & 2 != 0),alignedArabicName:arabic)
            return value == original ? nil : (Int32(profile),value)
        }
    }
}

struct PackQualityAccumulator {
    private var value = PackQualitySummary(), names = Set<String>(), order = PackArabicOrderEvidence()
    mutating func observe(_ row: PackRawRow, variants: [(Int32,PackQualityText)]) {
        // Avoid older Swift's optional tuple-element inference with `?.1 ??`.
        func selected(_ profile: Int32) -> PackQualityText {
            for (key,value) in variants where key == profile { return value }
            return row.original
        }
        let markup = selected(1), labels = selected(2), both = selected(3)
        value.rawUsable += row.usable ? 1 : 0
        value.markupUsable += markup.usable ? 1 : 0; value.labelsUsable += labels.usable ? 1 : 0
        value.combinedUsable += both.usable ? 1 : 0
        value.cleaned += markup.source != row.source || markup.target != row.target ? 1 : 0
        value.excluded += row.usable && !markup.usable ? 1 : 0
        if let speaker = both.speaker, both.usable, ["dialogue","general"].contains(row.fields[5]) {
            value.labels += 1; names.insert(speaker)
            if names.count > 64, let last = names.max() { names.remove(last) }
        }
        order.observe(row.target)
    }
    var summary: PackQualitySummary {
        var result = value; result.speakerNames = names.sorted(); result.possibleVisualOrder = order.warning; return result
    }
}

/// Called only on an already validated staging database. The original remains
/// read-only, and a failed/cancelled write removes only its newly created output.
enum PackV2Builder {
    static func build(from source: PackDatabase, to output: URL, check: @escaping () throws -> Void = {}) throws -> PackQualitySummary {
        guard source.schemaVersion == 1, output.isFileURL, !FileManager.default.fileExists(atPath:output.path) else { throw PackFailure.invalid }
        var db: OpaquePointer?, raw: OpaquePointer?, variant: OpaquePointer?, success = false
        guard sqlite3_open_v2(output.path,&db,SQLITE_OPEN_READWRITE|SQLITE_OPEN_CREATE|SQLITE_OPEN_EXCLUSIVE,nil) == SQLITE_OK else { sqlite3_close(db); throw PackFailure.unavailable }
        defer {
            sqlite3_finalize(raw); sqlite3_finalize(variant); sqlite3_close(db)
            if !success { try? FileManager.default.removeItem(at:output) }
        }
        func execute(_ sql: String) throws { guard sqlite3_exec(db,sql,nil,nil,nil) == SQLITE_OK else { throw PackFailure.damaged } }
        func prepare(_ sql: String) throws -> OpaquePointer {
            var result: OpaquePointer?
            guard sqlite3_prepare_v2(db,sql,-1,&result,nil) == SQLITE_OK, let result else { throw PackFailure.damaged }; return result
        }
        func bind(_ value: String, to statement: OpaquePointer, at index: Int32) throws {
            guard value.withCString({sqlite3_bind_text(statement,index,$0,Int32(value.utf8.count),unsafeBitCast(-1,to:sqlite3_destructor_type.self))}) == SQLITE_OK else { throw PackFailure.damaged }
        }
        func reset(_ statement: OpaquePointer) { sqlite3_reset(statement); sqlite3_clear_bindings(statement) }
        try execute("PRAGMA page_size=4096"); try execute("PRAGMA max_page_count=65536")
        try execute("PRAGMA journal_mode=DELETE"); try execute("PRAGMA cache_size=-8192")
        try execute("BEGIN IMMEDIATE"); try execute(PackDatabase.tableV2); try execute(PackDatabase.qualityTable)
        raw = try prepare("INSERT INTO entries VALUES (?,?,?,?,?,?,?,?,?,?)")
        variant = try prepare("INSERT INTO quality_variants VALUES (?,?,?,?,?,?,?,?)")
        var totals = PackQualityAccumulator(), rowID: Int64 = 0
        try source.forEachRawRow(check:check) { _,row,_ in
            rowID += 1; let statement = raw!
            reset(statement)
            for (index,value) in row.fields.enumerated() { try bind(value,to:statement,at:Int32(index+1)) }
            sqlite3_bind_int(statement,9,row.usable ? 1 : 0)
            try bind(PackQualityPolicy.punctuationless(row.source),to:statement,at:10)
            guard sqlite3_step(statement) == SQLITE_DONE else { throw PackFailure.damaged }
            let variants = try source.qualityVariants(row); totals.observe(row,variants:variants)
            for (profile,value) in variants {
                let statement = variant!; reset(statement)
                sqlite3_bind_int64(statement,1,rowID); sqlite3_bind_int(statement,2,profile)
                for (index,text) in [value.source,PackLookupKey.normalized(value.source),value.target,value.flags].enumerated() { try bind(text,to:statement,at:Int32(index+3)) }
                sqlite3_bind_int(statement,7,value.usable ? 1 : 0)
                try bind(PackQualityPolicy.punctuationless(value.source),to:statement,at:8)
                guard sqlite3_step(statement) == SQLITE_DONE else { throw PackFailure.damaged }
            }
            if rowID % 1024 == 0 { try check(); try checkSize() }
        }
        func checkSize() throws {
            let pages = try prepare("PRAGMA page_count"); defer { sqlite3_finalize(pages) }
            let size = try prepare("PRAGMA page_size"); defer { sqlite3_finalize(size) }
            guard sqlite3_step(pages) == SQLITE_ROW, sqlite3_step(size) == SQLITE_ROW,
                  sqlite3_column_int64(pages,0)*sqlite3_column_int64(size,0) <= 256*1024*1024 else { throw PackFailure.size }
        }
        for sql in PackDatabase.indexes.values.sorted()+PackDatabase.qualityIndexes.values.sorted() { try check(); try execute(sql) }
        try checkSize(); try check(); try execute("PRAGMA user_version=2"); try execute("COMMIT")
        success = true; return totals.summary
    }
}
