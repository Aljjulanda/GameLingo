import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

enum LocalizationImportFailure: LocalizedError {
    case cancelled, limit, malformed, mapping, unsupported(String), unsafe
    var errorDescription: String? {
        switch self {
        case .cancelled: return "أُلغي الاستيراد؛ بقيت المكتبة السابقة محفوظة"
        case .limit: return "تجاوز الملف حدود الحجم أو عدد السجلات أو وقت المعالجة"
        case .malformed: return "بنية الملف أو ترميزه غير صالحين؛ لم تُثبّت حزمة"
        case .mapping: return "لم تُستخرج أزواج إنجليزية/عربية موثوقة؛ أضف النص الإنجليزي الأصلي أو استخدم محوّل GameLingo الخارجي"
        case .unsupported(let detail): return detail
        case .unsafe: return "رُفض محتوى غير آمن أو مسار استخراج غير صالح"
        }
    }
}

final class LocalizationImportControl {
    private let lock = NSLock()
    private var cancelled = false
    private var cancellation: (() -> Void)?
    private let deadline: Double
    init(seconds: Double = 120) { deadline = ProcessInfo.processInfo.systemUptime+seconds }
    func cancel() {
        lock.lock(); let action = cancelled ? nil : cancellation; cancelled = true; lock.unlock(); action?()
    }
    func onCancellation(_ action: (() -> Void)?) {
        lock.lock(); cancellation = action; let run = cancelled; lock.unlock(); if run { action?() }
    }
    func check() throws {
        lock.lock(); let value = cancelled; lock.unlock()
        if value { throw LocalizationImportFailure.cancelled }
        if ProcessInfo.processInfo.systemUptime > deadline { throw LocalizationImportFailure.limit }
    }
}

enum LocalizationFileFormat: String {
    case glpack = "GLPACK", zip = "ZIP", rar = "RAR", sevenZip = "7Z", pe = "PE / EXE"
    case xml = "XML", json = "JSON", csv = "CSV / TSV", po = "PO", gxt2 = "GXT / GXT2"
    case unity = "Unity Bundle", text = "نص", binary = "بيانات ثنائية غير معروفة", empty = "ملف فارغ"
}

enum LocalizationFormatDetector {
    static func detect(_ data: Data) -> LocalizationFileFormat {
        let bytes = [UInt8](data.prefix(16))
        if bytes.isEmpty { return .empty }
        if bytes.starts(with:[0x50,0x4b,3,4]) || bytes.starts(with:[0x50,0x4b,5,6]) { return .zip }
        if bytes.starts(with:[0x52,0x61,0x72,0x21,0x1a,7]) { return .rar }
        if bytes.starts(with:[0x37,0x7a,0xbc,0xaf,0x27,0x1c]) { return .sevenZip }
        if bytes.starts(with:[0x4d,0x5a]) { return .pe }
        if bytes.starts(with:Array("UnityFS\0".utf8)) { return .unity }
        if bytes.starts(with:Array("TKEY".utf8)) { return .gxt2 }
        // Inspection uses a bounded prefix, which may end inside a UTF-8/16 scalar.
        let text = (0...min(3,data.count)).lazy.compactMap { try? decodeText(data.dropLast($0)) }.first
        guard let text, !text.isEmpty else { return .binary }
        let prefix = text.trimmingCharacters(in:.whitespacesAndNewlines)
        if prefix.hasPrefix("{") || prefix.hasPrefix("[") { return .json }
        if prefix.hasPrefix("<") { return .xml }
        if prefix.hasPrefix("msgid ") || prefix.hasPrefix("#") && prefix.contains("msgid ") { return .po }
        if prefix.range(of:"(?m)^\\s*(?:0x[0-9a-fA-F]{8}|[A-Z][A-Z0-9_]{3,})\\s*=",options:.regularExpression) != nil { return .gxt2 }
        if prefix.contains("\t") || prefix.contains(",") || prefix.contains(";") { return .csv }
        return .text
    }
    static func decodeText(_ data: Data) throws -> String {
        let encoding: String.Encoding
        let offset: Int
        if data.starts(with:[0xff,0xfe]) { encoding = .utf16LittleEndian; offset = 2 }
        else if data.starts(with:[0xfe,0xff]) { encoding = .utf16BigEndian; offset = 2 }
        else { encoding = .utf8; offset = data.starts(with:[0xef,0xbb,0xbf]) ? 3 : 0 }
        guard let text = String(data:data.dropFirst(offset),encoding:encoding), !text.contains("\0") else { throw LocalizationImportFailure.malformed }
        return text
    }
}

struct LocalizationRecord: Equatable {
    var id: String, source: String, target: String, category: String = "general"
}
struct ParsedLocalization {
    var records: [LocalizationRecord] = []
    var metadata: [String:String] = [:]
    var rejected = 0
}
protocol LocalizationFormatAdapter {
    var format: LocalizationFileFormat { get }
    func parse(_ text: String, control: LocalizationImportControl) throws -> ParsedLocalization
}
enum LocalizationAdapters {
    static let metadataKeys = ["game_id","game_title","pack_version","attribution","author","copyright","permission","license","source_language","target_language","arabic_order"]
    static let creditKeys: Set<String> = ["attribution","author","copyright","permission","license"]
    static func metadata(_ object: [String:Any], into result: inout ParsedLocalization) throws {
        for key in metadataKeys {
            guard let raw = object[key], !(raw is NSNull) else { continue }
            guard let value = raw as? String else { throw LocalizationImportFailure.malformed }
            if value.isEmpty { continue }
            if let old = result.metadata[key], old != value {
                guard creditKeys.contains(key) else { throw LocalizationImportFailure.malformed }
                result.metadata[key] = old+"\n"+value
            } else { result.metadata[key] = value }
            guard (result.metadata[key]?.count ?? 0) <= 4096 else { throw LocalizationImportFailure.limit }
        }
    }
    static let all: [LocalizationFormatAdapter] = [JSONLocalizationAdapter(),XMLLocalizationAdapter(),CSVLocalizationAdapter(),POLocalizationAdapter()]
    static func parse(_ data: Data, format: LocalizationFileFormat, control: LocalizationImportControl) throws -> ParsedLocalization {
        guard data.count <= 16*1024*1024 else { throw LocalizationImportFailure.limit }
        try control.check()
        guard let adapter = all.first(where:{$0.format == format}) else { throw LocalizationImportFailure.mapping }
        return try adapter.parse(LocalizationFormatDetector.decodeText(data),control:control)
    }
    static func record(_ value: [String:Any], index: Int) -> LocalizationRecord? {
        func field(_ keys: [String]) -> String? { keys.compactMap { value[$0] as? String }.first }
        guard let source = field(["source","english","en","msgid"]), let target = field(["target","arabic","ar","msgstr"]) else { return nil }
        return LocalizationRecord(id:field(["id","identifier"]) ?? String(index),source:source,target:target,category:field(["category"]) ?? "general")
    }
}

struct JSONLocalizationAdapter: LocalizationFormatAdapter {
    let format = LocalizationFileFormat.json
    func parse(_ text: String, control: LocalizationImportControl) throws -> ParsedLocalization {
        // Bound depth before Foundation allocates a deeply nested object graph.
        var depth = 0, nodes = 0, quoted = false, escaped = false
        for byte in text.utf8 {
            if quoted { if escaped { escaped = false } else if byte == 92 { escaped = true } else if byte == 34 { quoted = false }; continue }
            if byte == 34 { quoted = true; nodes += 1 }
            else if byte == 123 || byte == 91 { depth += 1; guard depth <= 32 else { throw LocalizationImportFailure.limit } }
            else if byte == 125 || byte == 93 { depth -= 1; guard depth >= 0 else { throw LocalizationImportFailure.malformed } }
            else if byte == 44 { nodes += 1 }
            guard nodes <= 300000 else { throw LocalizationImportFailure.limit }
        }
        guard depth == 0, !quoted else { throw LocalizationImportFailure.malformed }
        let object: Any
        do { object = try JSONSerialization.jsonObject(with:Data(text.utf8)) } catch { throw LocalizationImportFailure.malformed }
        var result = ParsedLocalization(), rows: [[String:Any]] = []
        if let root = object as? [String:Any] {
            try LocalizationAdapters.metadata(root,into:&result)
            if let metadata = root["metadata"] {
                guard let metadata = metadata as? [String:Any] else { throw LocalizationImportFailure.malformed }
                try LocalizationAdapters.metadata(metadata,into:&result)
            }
            if let entries = root["entries"] as? [[String:Any]] { rows = entries }
            else if let en = root["en"] as? [String:String], let ar = root["ar"] as? [String:String] {
                guard en.count <= 50000, ar.count <= 50000 else { throw LocalizationImportFailure.limit }
                for id in en.keys.sorted() { try control.check(); if let target = ar[id], let source = en[id] { rows.append(["id":id,"source":source,"target":target]) } else { result.rejected += 1 } }
            } else if result.metadata["source_language"] == "en", result.metadata["target_language"] == "ar", let entries = root["translations"] as? [String:String] {
                rows = entries.keys.sorted().map { ["source":$0,"target":entries[$0]!] }
            }
        } else if let array = object as? [[String:Any]] { rows = array }
        guard rows.count <= 50000 else { throw LocalizationImportFailure.limit }
        for (index,row) in rows.enumerated() { try control.check(); try LocalizationAdapters.metadata(row,into:&result); if let record = LocalizationAdapters.record(row,index:index) { result.records.append(record) } else { result.rejected += 1 } }
        return result
    }
}

struct CSVLocalizationAdapter: LocalizationFormatAdapter {
    let format = LocalizationFileFormat.csv
    func parse(_ text: String, control: LocalizationImportControl) throws -> ParsedLocalization {
        let first = String(text.prefix(4096).split(separator:"\n",maxSplits:1).first ?? "")
        // Select using header separators, independently of the filename.
        let choices: [UInt8] = [9,44,59]
        let separator = choices.max { a,b in first.utf8.filter{$0 == a}.count < first.utf8.filter{$0 == b}.count } ?? 44
        var rows: [[String]] = [], row: [String] = [], field: [UInt8] = [], quoted = false, closed = false
        let chars = Array(text.utf8); var i = 0
        func finishField() throws {
            guard let value = String(bytes:field,encoding:.utf8) else { throw LocalizationImportFailure.malformed }
            guard value.count <= 16000, row.count < 32 else { throw LocalizationImportFailure.limit }
            row.append(value); field.removeAll(keepingCapacity:true); closed = false
        }
        func finishRow() throws { try finishField(); if row.contains(where:{!$0.isEmpty}) { rows.append(row) }; row = []; guard rows.count <= 50001 else { throw LocalizationImportFailure.limit } }
        while i < chars.count {
            if i % 4096 == 0 { try control.check() }; let c = chars[i]
            if quoted {
                if c == 34 { if i+1 < chars.count && chars[i+1] == 34 { field.append(c); i += 1 } else { quoted = false; closed = true } }
                else { field.append(c) }
            } else if c == 34 { guard field.isEmpty, !closed else { throw LocalizationImportFailure.malformed }; quoted = true }
            else if c == separator { try finishField() }
            else if c == 10 || c == 13 { try finishRow(); if c == 13 && i+1 < chars.count && chars[i+1] == 10 { i += 1 } }
            else { guard !closed else { throw LocalizationImportFailure.malformed }; field.append(c) }
            guard field.count <= 64000 else { throw LocalizationImportFailure.limit }; i += 1
        }
        guard !quoted else { throw LocalizationImportFailure.malformed }
        if !field.isEmpty || !row.isEmpty || closed { try finishRow() }
        guard let header = rows.first else { return ParsedLocalization() }
        let keys = header.map { $0.trimmingCharacters(in:.whitespaces).lowercased() }
        guard Set(keys).count == keys.count else { throw LocalizationImportFailure.malformed }
        var result = ParsedLocalization()
        for (index,fields) in rows.dropFirst().enumerated() {
            try control.check(); guard fields.count == keys.count else { throw LocalizationImportFailure.malformed }
            let value = Dictionary(uniqueKeysWithValues:zip(keys,fields.map{$0 as Any}))
            try LocalizationAdapters.metadata(value,into:&result)
            if let record = LocalizationAdapters.record(value,index:index) { result.records.append(record) } else { result.rejected += 1 }
        }
        return result
    }
}

struct POLocalizationAdapter: LocalizationFormatAdapter {
    let format = LocalizationFileFormat.po
    func parse(_ text: String, control: LocalizationImportControl) throws -> ParsedLocalization {
        var result = ParsedLocalization(), source = "", target = "", active = "", blocked = false, context = "", started = false
        guard text.utf8.filter({$0 == 10 || $0 == 13}).count <= 200000 else { throw LocalizationImportFailure.limit }
        var attribution: [String] = []
        func flush() throws {
            if started && !blocked && !source.isEmpty { result.records.append(.init(id:context.isEmpty ? String(result.records.count) : String(result.records.count)+":"+String(context.prefix(80)),source:source,target:target)) }
            else if started && !source.isEmpty { result.rejected += 1 }
            else if started && source.isEmpty {
                attribution.append(target)
                for line in target.components(separatedBy:.newlines) {
                    let pair = line.split(separator:":",maxSplits:1).map{String($0).trimmingCharacters(in:.whitespaces)}
                    if pair.count == 2 && pair[0].lowercased() == "language" { result.metadata["target_language"] = pair[1] }
                }
            }
            guard result.records.count <= 50000 else { throw LocalizationImportFailure.limit }
            source = ""; target = ""; context = ""; active = ""; blocked = false; started = false
        }
        func unquote(_ raw: String) throws -> String {
            guard let data = raw.data(using:.utf8), let value = try? JSONSerialization.jsonObject(with:data,options:.fragmentsAllowed) as? String else { throw LocalizationImportFailure.malformed }; return value
        }
        for raw in text.components(separatedBy:.newlines) {
            try control.check(); let line = raw.trimmingCharacters(in:.whitespaces)
            if line.isEmpty { try flush(); continue }
            if line.hasPrefix("#") {
                if line.contains("fuzzy") || line.hasPrefix("#~") { blocked = true }
                if ["copyright","license","translator","author"].contains(where:{line.lowercased().contains($0)}) { attribution.append(line) }
                guard attribution.reduce(0,{$0+$1.count}) <= 4096 else { throw LocalizationImportFailure.limit }; continue
            }
            if line.hasPrefix("msgctxt ") { if started { try flush() }; context = try unquote(String(line.dropFirst(8))); active = "context" }
            else if line.hasPrefix("msgid_plural ") || line.hasPrefix("msgstr[") { blocked = true; active = "" }
            else if line.hasPrefix("msgid ") { if started { try flush() }; source = try unquote(String(line.dropFirst(6))); started = true; active = "source" }
            else if line.hasPrefix("msgstr ") { target = try unquote(String(line.dropFirst(7))); active = "target" }
            else if line.hasPrefix("\"") { let value = try unquote(line); if active == "source" { source += value } else if active == "target" { target += value } else if active == "context" { context += value } else if !blocked { throw LocalizationImportFailure.malformed } }
            else { throw LocalizationImportFailure.malformed }
            guard source.count <= 4096, target.count <= 16000, context.count <= 128 else { throw LocalizationImportFailure.limit }
        }
        try flush(); let credit = attribution.joined(separator:"\n")
        guard credit.count <= 4096 else { throw LocalizationImportFailure.limit }; result.metadata["attribution"] = credit; return result
    }
}

private final class LocalizationXMLDelegate: NSObject, XMLParserDelegate {
    var result = ParsedLocalization(), stack: [String] = [], values: [String:String] = [:], attributes: [String:String] = [:]
    var text = "", failure: Error?, nodes = 0, inEntry = false, entryDepth = 0
    let control: LocalizationImportControl
    init(control: LocalizationImportControl) { self.control = control }
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes attributesDict: [String:String]) {
        do { try control.check(); nodes += 1; guard nodes <= 300000, stack.count < 32 else { throw LocalizationImportFailure.limit }; stack.append(name); text = ""
            if stack.count > 1 && LocalizationAdapters.metadataKeys.contains(name) { throw LocalizationImportFailure.unsupported("بيانات المصدر والترخيص في XML مدعومة كسمات؛ استخدم المحوّل الخارجي للبنية المتداخلة دون فقد بياناتها") }
            if stack.count == 1 || name == "entry" || name == "string" { try LocalizationAdapters.metadata(attributesDict.mapValues{$0 as Any},into:&result) }
            if name == "entry" || name == "string" { guard !inEntry else { throw LocalizationImportFailure.malformed }; inEntry = true; entryDepth = stack.count; values = [:]; attributes = attributesDict }
            if inEntry && stack.count > entryDepth+1 { throw LocalizationImportFailure.malformed }
        } catch { failure = error; parser.abortParsing() }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string; if text.count > 16000 { failure = LocalizationImportFailure.limit; parser.abortParsing() }
    }
    func parser(_ parser: XMLParser, foundCDATA block: Data) {
        guard let value = String(data:block,encoding:.utf8) else { failure = LocalizationImportFailure.malformed; parser.abortParsing(); return }
        self.parser(parser,foundCharacters:value)
    }
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        if inEntry && stack.count == entryDepth+1 {
            if values[name] != nil { failure = LocalizationImportFailure.malformed; parser.abortParsing(); return }
            values[name] = text.trimmingCharacters(in:.whitespacesAndNewlines)
        }
        if name == "entry" || name == "string" {
            values["id"] = attributes["id"] ?? attributes["name"] ?? String(result.records.count)
            if let record = LocalizationAdapters.record(values,index:result.records.count) { result.records.append(record) } else { result.rejected += 1 }
            inEntry = false; if result.records.count > 50000 { failure = LocalizationImportFailure.limit; parser.abortParsing() }
        }
        if !stack.isEmpty { stack.removeLast() }; text = ""
    }
    func parser(_ parser: XMLParser, resolveExternalEntityName name: String, systemID: String?) -> Data? { failure = LocalizationImportFailure.unsafe; parser.abortParsing(); return nil }
}
struct XMLLocalizationAdapter: LocalizationFormatAdapter {
    let format = LocalizationFileFormat.xml
    func parse(_ text: String, control: LocalizationImportControl) throws -> ParsedLocalization {
        let upper = text.uppercased()
        guard !upper.contains("<!DOCTYPE"), !upper.contains("<!ENTITY") else { throw LocalizationImportFailure.unsafe }
        let delegate = LocalizationXMLDelegate(control:control), parser = XMLParser(data:Data(text.utf8))
        parser.delegate = delegate; parser.shouldResolveExternalEntities = false
        let valid = parser.parse()
        if let failure = delegate.failure { throw failure }
        guard valid else { throw LocalizationImportFailure.malformed }
        return delegate.result
    }
}

enum EnglishArabicMatcher {
    static func match(_ parsed: ParsedLocalization, control: LocalizationImportControl) throws -> ParsedLocalization {
        func base(_ value: String) -> String { value.trimmingCharacters(in:.whitespaces).lowercased().split(whereSeparator:{$0 == "-" || $0 == "_"}).first.map(String.init) ?? "" }
        guard parsed.metadata["source_language"].map({base($0) == "en"}) ?? true,
              parsed.metadata["target_language"].map({base($0) == "ar"}) ?? true else {
            throw LocalizationImportFailure.unsupported("المحوّل المحلي يدعم نصوصًا إنجليزية إلى عربية؛ لغات الملف المعلنة مختلفة")
        }
        guard parsed.metadata["arabic_order"].map({$0 == "logical"}) ?? true else {
            throw LocalizationImportFailure.unsupported("الملف يعلن ترتيبًا بصريًا للعربية؛ استخدم المحوّل الخارجي لإنتاج ترتيب منطقي صحيح")
        }
        var result = parsed; result.records = []
        var targets: [String:Set<String>] = [:], candidates: [LocalizationRecord] = [], ids: [String:LocalizationRecord] = [:]
        for var record in parsed.records {
            try control.check()
            record.source = record.source.trimmingCharacters(in:.whitespacesAndNewlines)
            record.target = SubtitlePresentation.clean(record.target)
            guard record.id.count <= 128, record.source.count <= 4096, record.target.count <= 16000,
                  !record.source.contains("\0"), !record.target.contains("\0"),
                  record.source.range(of:"[A-Za-z]",options:.regularExpression) != nil,
                  record.target.unicodeScalars.contains(where:{(0x0600...0x06ff).contains($0.value)}),
                  !record.target.unicodeScalars.contains(where:{(0xfb50...0xfdff).contains($0.value) || (0xfe70...0xfefc).contains($0.value)}) else { result.rejected += 1; continue }
            if !PackManifest.categories.contains(record.category) { record.category = "general" }
            if let old = ids[record.id] { guard old == record else { throw LocalizationImportFailure.malformed }; result.rejected += 1; continue }
            ids[record.id] = record
            let key = PackLookupKey.normalized(record.source); guard !key.isEmpty else { result.rejected += 1; continue }
            targets[key,default:[]].insert(record.target); candidates.append(record)
        }
        var seen = Set<String>()
        for record in candidates {
            let normalized = PackLookupKey.normalized(record.source)
            if targets[normalized]?.count == 1 && seen.insert(normalized+"\0"+record.category).inserted { result.records.append(record) }
            else { result.rejected += 1 }
        }
        guard !result.records.isEmpty else { throw LocalizationImportFailure.mapping }
        return result
    }
}
