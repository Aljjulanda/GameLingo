import Foundation

struct CaptureLine: Codable {
    var text: String, box: SourceBox, confidence: Double
}
struct QualityCaptureRecord: Codable {
    var eventID: String
    var lines: [CaptureLine]
    var parsed: String
    var engineInput: String
    var engineOutput: String
    var origin: TranslationOrigin
}
/// Explicit local consent only. Fixed filename, bounded session, no uploader.
/// All methods confined to the pipeline queue (UI actions use that queue too).
final class QualityCapture {
    let folder: URL
    var file: URL { folder.appendingPathComponent("session.jsonl") }
    private(set) var active = false
    private var bytes = 0
    private var deadline = Date.distantPast
    let byteLimit: Int, retention: TimeInterval
    init(folder: URL, byteLimit: Int = 4*1024*1024, retention: TimeInterval = 86400) {
        self.folder = folder; self.byteLimit = max(256,byteLimit); self.retention = max(60,retention)
        // A terminated session is never automatically resumed. Old material is
        // pruned on launch, before export, and before a new recording.
        prune()
    }
    func prune(now: Date = Date()) {
        guard let values = try? file.resourceValues(forKeys:[.contentModificationDateKey,.fileSizeKey]) else { return }
        if (values.fileSize ?? 0) > byteLimit || now.timeIntervalSince(values.contentModificationDate ?? .distantPast) > retention { try? FileManager.default.removeItem(at:file) }
    }
    func start(consent: Bool, now: Date = Date()) throws {
        guard consent else { return }
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        var url = folder; var values = URLResourceValues(); values.isExcludedFromBackup = true; try url.setResourceValues(values)
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey:FileProtectionType.complete],ofItemAtPath:folder.path)
        try Data().write(to:file,options:[.atomic,.completeFileProtection])
        #else
        try Data().write(to:file,options:.atomic)
        #endif
        bytes = 0; deadline = now.addingTimeInterval(30*60); active = true
    }
    func append(_ record: QualityCaptureRecord, now: Date = Date()) throws {
        guard active else { return }
        guard now < deadline else { stop(); return }
        var data = try JSONEncoder().encode(record); data.append(10)
        guard data.count <= byteLimit-bytes else { stop(); return }
        let handle = try FileHandle(forWritingTo:file); defer { try? handle.close() }
        try handle.seekToEnd(); try handle.write(contentsOf:data); bytes += data.count
    }
    func stop() { active = false }
    func delete() throws { stop(); if FileManager.default.fileExists(atPath:file.path) { try FileManager.default.removeItem(at:file) } }
    func export() -> URL? { prune(); return FileManager.default.fileExists(atPath:file.path) ? file : nil }
}

/// Deterministic post-OCR replay. It intentionally does not claim OCR/model or
/// hardware coverage; native integration tests exercise those separately.
enum QualityReplay {
    static func run(_ data: Data, translate: (String) -> String) throws -> [String] {
        guard data.count <= 4*1024*1024 else { throw LingoError.invalid("ملف الاختبار كبير") }
        var selector = DialogueSelection(), tracker = DialogueTracker(), stability = PublicationStability()
        var result: [String] = [], clock = 0.0
        for line in data.split(separator:10) {
            clock += 0.6
            let record = try JSONDecoder().decode(QualityCaptureRecord.self,from:Data(line))
            let lines = record.lines.map{OCRLine(text:$0.text,box:$0.box,confidence:$0.confidence)}
            let reading = DialogueObservation.resolve(lines,roi:.dialogue,knownNames:"",selector:&selector)
            if case .dialogue(let job,_) = tracker.observe(text:reading.content.text,box:reading.box,now:clock,frameMilliseconds:Int64(clock*1000),speaker:reading.content.speaker,confidence:reading.confidence), stability.shouldPublish(job) {
                result.append(translate(job.text)); stability.didPublish(job)
            }
        }
        return result
    }
}
