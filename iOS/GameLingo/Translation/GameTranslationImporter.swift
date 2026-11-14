import Foundation
import CryptoKit
import SQLite3
import ZIPFoundation

struct LocalizationInspection {
    var filename: String, bytes: Int64 = 0, format = "جارٍ الفحص"
    var localization: Bool?, supported: Bool?, mapping: Bool?, usable: Int?, rejected = 0
    var declaredUsable: Int?
    var progressDone: Int64?, progressTotal: Int64?
    var progressUnit = "بايت"
    var stage = "جارٍ فحص الملف", result = "", requirement = ""
}

/// Owns temporary copies only. Installation continues through the existing validator/store.
final class GameTranslationImporter {
    private let worker = DispatchQueue(label:"dev.gamelingo.localization-import",qos:.utility)
    private let temporaryRoot: URL
    init(temporaryRoot: URL = FileManager.default.temporaryDirectory.appendingPathComponent("GameLingo-Inspection",isDirectory:true)) { self.temporaryRoot = temporaryRoot }
    @discardableResult
    func start(_ external: URL, store: TranslationPackStore, update: @escaping (LocalizationInspection) -> Void,
               completion: @escaping (Result<Void,Error>,LocalizationInspection) -> Void) -> LocalizationImportControl {
        let control = LocalizationImportControl(), scoped = external.startAccessingSecurityScopedResource()
        worker.async { [self] in
            defer { if scoped { external.stopAccessingSecurityScopedResource() } }
            var report = LocalizationInspection(filename:String(external.lastPathComponent.prefix(240)))
            let stage = temporaryRoot.appendingPathComponent(UUID().uuidString,isDirectory:true)
            func publish(_ value: LocalizationInspection) { DispatchQueue.main.async { update(value) } }
            do {
                guard external.isFileURL else { throw LocalizationImportFailure.unsafe }
                try control.check(); try FileManager.default.createDirectory(at:stage,withIntermediateDirectories:true)
                let input = stage.appendingPathComponent("input")
                publish(report)
                var coordinationError: NSError?, copyError: Error?
                let coordinator = NSFileCoordinator()
                control.onCancellation { coordinator.cancel() }
                coordinator.coordinate(readingItemAt:external,options:.withoutChanges,error:&coordinationError) { source in
                    do {
                        let values = try source.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey])
                        guard values.isRegularFile == true, values.isSymbolicLink != true else { throw LocalizationImportFailure.unsafe }
                        guard let size = values.fileSize, size >= 0 else { throw LocalizationImportFailure.malformed }
                        report.bytes = Int64(size)
                        guard size <= 128*1024*1024 else { throw LocalizationImportFailure.limit }
                        report.stage = "جارٍ نسخ الملف للفحص"; report.progressDone = 0; report.progressTotal = Int64(size); publish(report)
                        let sourceHandle = try FileHandle(forReadingFrom:source); defer { try? sourceHandle.close() }
                        guard FileManager.default.createFile(atPath:input.path,contents:nil) else { throw PackFailure.unavailable }
                        let output = try FileHandle(forWritingTo:input); defer { try? output.close() }
                        var count = 0
                        while let chunk = try sourceHandle.read(upToCount:65536), !chunk.isEmpty {
                            try control.check(); count += chunk.count
                            guard count <= size, count <= 128*1024*1024 else { throw LocalizationImportFailure.limit }; try output.write(contentsOf:chunk)
                            if count % (1024*1024) == 0 || count == size { report.progressDone = Int64(count); publish(report) }
                        }
                        guard count == size else { throw LocalizationImportFailure.malformed }
                        report.bytes = Int64(count)
                    } catch { copyError = error }
                }
                control.onCancellation(nil); try control.check()
                if let error = coordinationError { throw error }; if let error = copyError { throw error }
                let package = try prepare(input,in:stage,depth:0,report:&report,control:control,publish:publish)
                try control.check(); report.stage = "جارٍ التحقق من حزمة الترجمة وتثبيتها"; report.progressDone = nil; report.progressTotal = nil; publish(report)
                let preparedReport = report
                DispatchQueue.main.async {
                    store.importPack(package,check:control.check) { result in
                        self.worker.async {
                            try? FileManager.default.removeItem(at:stage)
                            var final = preparedReport
                            switch result {
                            case .success: final.usable = final.usable ?? final.declaredUsable; final.result = "تم استيراد الترجمة بنجاح؛ اختر اللعبة لتفعيلها"; final.stage = "اكتمل الاستيراد"
                            case .failure(let error): final.result = Self.message(error); final.stage = "لم تُثبّت حزمة"
                            }
                            DispatchQueue.main.async { completion(result,final) }
                        }
                    }
                }
            } catch {
                try? FileManager.default.removeItem(at:stage)
                if report.format == "جارٍ الفحص" { report.format = "لم يكتمل الفحص" }
                report.result = Self.message(error); report.stage = "لم تُثبّت حزمة"
                let value = report; DispatchQueue.main.async { completion(.failure(error),value) }
            }
        }
        return control
    }
    private static func message(_ error: Error) -> String {
        if let error = error as? LocalizationImportFailure { return error.localizedDescription }
        if let error = error as? PackFailure { return error.localizedDescription }
        return "تعذر قراءة الملف أو التحقق منه؛ بقيت المكتبة السابقة محفوظة"
    }
    private func prefix(_ url: URL) throws -> Data {
        let handle = try FileHandle(forReadingFrom:url); defer { try? handle.close() }; return try handle.read(upToCount:65536) ?? Data()
    }
    private func prepare(_ file: URL, in stage: URL, depth: Int, report: inout LocalizationInspection,
                         control: LocalizationImportControl, publish: (LocalizationInspection) -> Void) throws -> URL {
        try control.check()
        let format = LocalizationFormatDetector.detect(try prefix(file))
        report.progressDone = nil; report.progressTotal = nil
        report.format = format.rawValue; report.stage = "تم التعرف على نوع الملف: "+format.rawValue
        publish(report)
        switch format {
        case .zip:
            guard depth <= 1 else { throw LocalizationImportFailure.limit }
            let archive: Archive
            do { archive = try Archive(url:file,accessMode:.read) } catch { throw LocalizationImportFailure.malformed }
            let entries = try checkedEntries(archive,control:control)
            let paths = Set(entries.map(\.path))
            if paths == Set(["manifest.json","translations.sqlite","checksums.json"]) {
                let entry = try required(archive["manifest.json"])
                let manifest = try PackManifest.decode(extractData(archive,entry:entry,limit:65536,control:control))
                report.format = LocalizationFileFormat.glpack.rawValue; report.localization = true; report.supported = true
                report.mapping = manifest.usableCount > 0; report.declaredUsable = manifest.usableCount
                return file
            }
            if paths.contains("translations.sqlite") || paths.contains("manifest.json") && paths.contains("checksums.json") { throw LocalizationImportFailure.malformed }
            guard entries.filter({$0.type == .file}).count == 1 else {
                throw LocalizationImportFailure.unsupported("أرشيف ZIP متعدد الملفات يحتاج المحوّل الخارجي للحفاظ على ملفات المصدر والترخيص وعدم خلط الألعاب؛ يدعم iPhone حاوية لملف تعريب واحد")
            }
            report.stage = "جارٍ استخراج ملفات التعريب بأمان"
            publish(report)
            var candidates: [(URL,LocalizationInspection)] = [], mappingMissing = false
            for entry in entries where entry.type == .file {
                try control.check()
                guard entry.uncompressedSize <= 16*1024*1024 else { throw LocalizationImportFailure.limit }
                let local = stage.appendingPathComponent(UUID().uuidString)
                try extractData(archive,entry:entry,limit:16*1024*1024,control:control).write(to:local,options:.atomic)
                let detected = LocalizationFormatDetector.detect(try prefix(local))
                guard LocalizationAdapters.all.contains(where:{$0.format == detected}) || detected == .zip else { if detected == .text || detected == .gxt2 { mappingMissing = true }; continue }
                var inner = report
                do {
                    let output = try prepare(local,in:stage,depth:depth+1,report:&inner,control:control,publish:publish)
                    candidates.append((output,inner))
                } catch LocalizationImportFailure.mapping { mappingMissing = true }
                // Malformed/unsafe recognized input aborts the archive; it is never silently skipped.
            }
            guard candidates.count == 1 else {
                if candidates.count > 1 { throw LocalizationImportFailure.unsupported("الأرشيف يحتوي عدة مصادر قابلة للتحويل؛ استخدم محوّل GameLingo لدمجها مع تحديد اللعبة دون خلط النصوص") }
                report.localization = nil; report.mapping = false; report.supported = false
                if mappingMissing { throw LocalizationImportFailure.mapping }
                throw LocalizationImportFailure.unsupported("أرشيف ZIP معروف، لكن محتواه لا يتضمن صيغة تعريب قابلة للتحويل حاليًا؛ استخدم المحوّل الخارجي")
            }
            report = candidates[0].1; report.format = "ZIP → "+report.format; return candidates[0].0
        case .json,.xml,.csv,.po:
            report.supported = true; report.stage = "جارٍ تحليل النصوص"
            publish(report)
            let size = try file.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? Int.max
            guard size <= 16*1024*1024 else { throw LocalizationImportFailure.limit }
            let parsed = try LocalizationAdapters.parse(Data(contentsOf:file),format:format,control:control)
            report.localization = parsed.records.isEmpty ? nil : true; report.rejected = parsed.rejected
            report.stage = "جارٍ مطابقة النصوص الإنجليزية والعربية"
            publish(report)
            let matched: ParsedLocalization
            do { matched = try EnglishArabicMatcher.match(parsed,control:control) }
            catch { report.mapping = false; report.requirement = "تحتاج نصوصًا إنجليزية وعربية متقابلة داخل الملف، أو تحويلًا خارجيًا يطابق معرفات النصوص"; throw error }
            report.mapping = true; report.usable = matched.records.count; report.rejected = matched.rejected
            report.stage = "جارٍ تجهيز حزمة الترجمة"
            publish(report)
            return try LocalizationPackBuilder.build(matched,sourceName:report.filename,sourceHash:TranslationPackStore.hash(file,check:control.check),in:stage,control:control) { done,total in
                report.progressDone = Int64(done); report.progressTotal = Int64(total); report.progressUnit = "مدخل"; publish(report)
            }
        case .pe:
            report.supported = false; report.mapping = false
            report.requirement = "يتطلب محوّل GameLingo الخارجي؛ لا يُنفّذ أي كود Windows على iPhone"
            let bytes = [UInt8](try prefix(file))
            guard bytes.count >= 64 else { throw LocalizationImportFailure.malformed }
            let offset = (0..<4).reduce(0) { $0 | Int(bytes[60+$1]) << (8*$1) }
            guard offset >= 64, offset <= Int(report.bytes)-4 else { throw LocalizationImportFailure.malformed }
            let handle = try FileHandle(forReadingFrom:file); defer { try? handle.close() }; try handle.seek(toOffset:UInt64(offset))
            guard try handle.read(upToCount:4) == Data([0x50,0x45,0,0]) else { throw LocalizationImportFailure.malformed }
            throw LocalizationImportFailure.unsupported("ملف PE/EXE معروف. لا يدعم iPhone استخراج هذا المثبّت حاليًا؛ استخدم محوّل GameLingo الخارجي لاستخراج الموارد ثابتًا ثم استورد الحزمة")
        case .rar,.sevenZip,.unity:
            report.supported = false; report.requirement = "فك الحاوية بمحوّل موثوق خارجيًا، ثم استورد البيانات أو GLPACK"
            throw LocalizationImportFailure.unsupported("تم التعرف على "+format.rawValue+"؛ استخراج هذه الحاوية غير مدعوم على iPhone حاليًا. استخدم محوّلًا خارجيًا")
        case .text,.gxt2:
            report.localization = nil; report.mapping = false; report.supported = false
            throw LocalizationImportFailure.mapping
        case .empty: report.supported = false; report.localization = false; throw LocalizationImportFailure.unsupported("الملف فارغ؛ لا توجد بيانات لفحصها")
        default: report.supported = false; throw LocalizationImportFailure.unsupported("صيغة الملف غير مدعومة حاليًا؛ لم تُستخرج بيانات تعريب ولم تُثبّت حزمة")
        }
    }
    private func required<T>(_ value: T?) throws -> T { guard let value else { throw LocalizationImportFailure.malformed }; return value }
    private func checkedEntries(_ archive: Archive, control: LocalizationImportControl) throws -> [Entry] {
        var entries: [Entry] = [], paths = Set<String>(), total: UInt64 = 0
        for entry in archive {
            try control.check(); let path = entry.path
            guard entries.count < 64, !path.hasPrefix("/"), !path.contains("\\"), !path.contains(":"), !path.contains("\0"),
                  !path.split(separator:"/").contains(where:{$0 == ".." || $0 == "."}), path.utf8.count <= 1024,
                  entry.type == .file || entry.type == .directory, paths.insert(path.lowercased()).inserted else { throw LocalizationImportFailure.unsafe }
            guard entry.uncompressedSize <= 256*1024*1024, total <= 256*1024*1024-entry.uncompressedSize,
                  max(1,entry.compressedSize) >= (entry.uncompressedSize+99)/100 else { throw LocalizationImportFailure.limit }
            total += entry.uncompressedSize; entries.append(entry)
        }
        guard !entries.isEmpty else { throw LocalizationImportFailure.malformed }
        let isPack = Set(entries.map(\.path)) == Set(["manifest.json","translations.sqlite","checksums.json"])
        if !isPack && total > 64*1024*1024 { throw LocalizationImportFailure.limit }
        return entries
    }
    private func extractData(_ archive: Archive, entry: Entry, limit: UInt64, control: LocalizationImportControl) throws -> Data {
        guard entry.type == .file, entry.uncompressedSize <= limit else { throw LocalizationImportFailure.limit }
        var output = Data()
        let crc = try archive.extract(entry,bufferSize:65536,skipCRC32:false) { chunk in
            try control.check(); guard UInt64(output.count)+UInt64(chunk.count) <= limit else { throw LocalizationImportFailure.limit }; output.append(chunk)
        }
        guard crc == entry.checksum, UInt64(output.count) == entry.uncompressedSize else { throw LocalizationImportFailure.malformed }; return output
    }
}

enum LocalizationPackBuilder {
    static func build(_ parsed: ParsedLocalization, sourceName: String, sourceHash: String, in stage: URL, control: LocalizationImportControl, progress: (Int,Int) -> Void = {_,_ in}) throws -> URL {
        let folder = stage.appendingPathComponent(UUID().uuidString,isDirectory:true)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        let database = folder.appendingPathComponent("translations.sqlite")
        var db: OpaquePointer?, statement: OpaquePointer?
        guard sqlite3_open(database.path,&db) == SQLITE_OK else { sqlite3_close(db); throw PackFailure.unavailable }
        defer { sqlite3_finalize(statement); sqlite3_close(db) }
        for sql in [PackDatabase.table]+PackDatabase.indexes.values.sorted()+["PRAGMA user_version=1","BEGIN"] {
            guard sqlite3_exec(db,sql,nil,nil,nil) == SQLITE_OK else { throw PackFailure.damaged }
        }
        guard sqlite3_prepare_v2(db,"INSERT INTO entries VALUES (?,?,?,?,?,?,?,?,1)",-1,&statement,nil) == SQLITE_OK else { throw PackFailure.damaged }
        for (index,record) in parsed.records.enumerated() {
            if index % 1024 == 0 { progress(index,parsed.records.count) }
            try control.check(); sqlite3_reset(statement); sqlite3_clear_bindings(statement)
            let fields = ["raw-\(index)",record.id,record.source,PackLookupKey.normalized(record.source),record.target,record.category,sourceName,"[]"]
            for (column,value) in fields.enumerated() { guard value.withCString({sqlite3_bind_text(statement,Int32(column+1),$0,Int32(value.utf8.count),unsafeBitCast(-1,to:sqlite3_destructor_type.self))}) == SQLITE_OK else { throw PackFailure.damaged } }
            guard sqlite3_step(statement) == SQLITE_DONE else { throw PackFailure.damaged }
        }
        guard sqlite3_exec(db,"COMMIT",nil,nil,nil) == SQLITE_OK else { throw PackFailure.damaged }
        progress(parsed.records.count,parsed.records.count)
        sqlite3_finalize(statement); statement = nil
        guard sqlite3_close(db) == SQLITE_OK else { throw PackFailure.damaged }; db = nil
        let metadata = parsed.metadata
        let credit = ["attribution","author","copyright"].compactMap{metadata[$0]}.filter{!$0.isEmpty}.joined(separator:"\n")
        let terms = ["permission","license"].compactMap{metadata[$0]}.filter{!$0.isEmpty}.joined(separator:"\n")
        let manifest = PackManifest(formatVersion:1,schemaVersion:1,gameId:metadata["game_id"] ?? "local-"+String(sourceHash.prefix(20)),
            gameTitle:metadata["game_title"] ?? String((sourceName as NSString).deletingPathExtension.prefix(100)),sourceLanguage:"en",targetLanguage:"ar",
            packVersion:metadata["pack_version"] ?? "1",recordCount:parsed.records.count,usableCount:parsed.records.count,categories:Array(Set(parsed.records.map(\.category))).sorted(),
            attribution:credit.isEmpty ? "استيراد محلي من: "+sourceName : credit,
            permission:terms.isEmpty ? "لم تُرفق بيانات ترخيص؛ لم يتحقق التطبيق من حقوق إعادة التوزيع" : terms,
            builtAt:ISO8601DateFormatter().string(from:Date()),arabicOrder:"logical",databaseSha256:try TranslationPackStore.hash(database),speakerNames:[],coverage:"partial")
        try manifest.validate()
        let encoder = JSONEncoder(); encoder.keyEncodingStrategy = .convertToSnakeCase; encoder.outputFormatting = .sortedKeys
        let raw = try encoder.encode(manifest); try raw.write(to:folder.appendingPathComponent("manifest.json"))
        let checksums = ["manifest.json":SHA256.hash(data:raw).map{String(format:"%02x",$0)}.joined(),"translations.sqlite":manifest.databaseSha256]
        try JSONEncoder().encode(checksums).write(to:folder.appendingPathComponent("checksums.json"))
        let output = stage.appendingPathComponent(UUID().uuidString+".glpack"), archive = try Archive(url:output,accessMode:.create)
        for name in ["manifest.json","translations.sqlite","checksums.json"] { try control.check(); try archive.addEntry(with:name,relativeTo:folder,compressionMethod:.none) }
        return output
    }
}
