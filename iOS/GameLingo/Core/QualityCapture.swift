import Foundation

struct CaptureLine: Codable {
    var text: String, box: SourceBox, confidence: Double
}
enum CaptureStage: String, Codable { case observation, published }
struct QualityCaptureRecord: Codable {
    var eventID: String
    var lines: [CaptureLine]
    var parsed: String
    var engineInput: String
    var engineOutput: String
    var origin: TranslationOrigin?
    var stage: CaptureStage? = nil
    var timestamp: Double? = nil
    var segments: [CaptureLine]? = nil
    var basis: TranslationOrigin? = nil
    var finalOutput: String? = nil
    var rawEngineTraceAvailable: Bool? = nil
}
/// Explicit local consent only. Fixed filename, bounded session, no uploader.
/// All methods confined to the pipeline queue (UI actions use that queue too).
final class QualityCapture {
    let folder: URL
    var file: URL { folder.appendingPathComponent("session.jsonl") }
    private(set) var active = false
    private var bytes = 0
    private var deadline = Date.distantPast
    private var startClock = 0.0
    private var observationSerial: UInt64 = 0
    var elapsed: Double { max(0,ProcessInfo.processInfo.systemUptime-startClock) }
    func observationID() -> String { observationSerial &+= 1; return "observation-\(observationSerial)" }
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
        active = false
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        var url = folder; var values = URLResourceValues(); values.isExcludedFromBackup = true; try url.setResourceValues(values)
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey:FileProtectionType.complete],ofItemAtPath:folder.path)
        try Data().write(to:file,options:[.atomic,.completeFileProtection])
        try FileManager.default.setAttributes([.protectionKey:FileProtectionType.complete],ofItemAtPath:file.path)
        #if !targetEnvironment(simulator)
        guard Self.permitsProtectedRecording(protectionClass) else {
            throw LingoError.invalid("تعذر تأكيد حماية ملف التسجيل؛ لن تُسجل النصوص")
        }
        #endif
        #else
        try Data().write(to:file,options:.atomic)
        #endif
        bytes = 0; deadline = now.addingTimeInterval(30*60)
        startClock = ProcessInfo.processInfo.systemUptime; observationSerial = 0; active = true
    }
    static func permitsProtectedRecording(_ reportedClass: String?) -> Bool {
        reportedClass == "NSFileProtectionComplete"
    }
    var protectionClass: String? {
        #if os(iOS)
        guard let value = try? FileManager.default.attributesOfItem(atPath:file.path)[.protectionKey] else { return nil }
        // attributesOfItem is an untyped Objective-C dictionary. Foundation
        // may return the NSString raw value rather than the imported newtype.
        return (value as? FileProtectionType)?.rawValue ?? value as? String
        #else
        return nil
        #endif
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
    static func run(_ data: Data, quality: QualitySettings = QualitySettings(), game: String? = nil, translate: (String) -> String) throws -> [String] {
        guard data.count <= 4*1024*1024 else { throw LingoError.invalid("ملف الاختبار كبير") }
        var selector = DialogueSelection(), tracker = DialogueTracker(), stability = PublicationStability()
        var typewriter = TypewriterPublication(knownTypewriter:game.map{quality.typewriterGames.contains($0)} ?? false)
        var held: (job:DialogueJob,text:String)?
        var result: [String] = [], clock = 0.0
        let records = try data.split(separator:10).map { try JSONDecoder().decode(QualityCaptureRecord.self,from:Data($0)) }
        // A real capture contains raw candidates AND publication outcomes.
        // Replay candidates once; never count its publication record as a new
        // OCR read. Legacy/synthetic publication-only files remain readable.
        let rawStream = records.contains{$0.stage == .observation}
        for record in records where !rawStream || record.stage == .observation {
            clock = record.timestamp.map{max(clock,$0)} ?? clock+0.6
            let lines = (record.segments ?? record.lines).map{OCRLine(text:$0.text,box:$0.box,confidence:$0.confidence)}
            let reading = DialogueObservation.resolve(lines,roi:.dialogue,knownNames:"",selector:&selector,quality:quality)
            if quality[.typewriter] {
                let observed = TypewriterReading(text:reading.content.text,speaker:reading.content.speaker,box:reading.box,confidence:reading.confidence)
                let ready = typewriter.observe(observed,now:clock,enabled:!(reading.content.engineText == "" && reading.content.cue != nil),maxWait:quality.settleSeconds,window:quality.typewriterWindow)
                if let previous = held, TypewriterPublication.canFlush(previous.job,ready:ready,current:observed), tracker.accepts(previous.job), stability.shouldPublish(previous.job) {
                    result.append(previous.text); stability.didPublish(previous.job); held = nil
                }
            }
            if case .dialogue(let job,_) = tracker.observe(text:reading.content.text,box:reading.box,now:clock,frameMilliseconds:Int64(clock*1000),speaker:reading.content.speaker,confidence:reading.confidence), stability.shouldPublish(job) {
                let input = reading.content.engineText ?? job.text
                let value = input.isEmpty && reading.content.cue != nil ? reading.content.cue! : translate(input)
                // Synchronous stub completion; shares the production publication
                // gate, not asynchronous worker timing or real model latency.
                if quality[.typewriter] && !typewriter.canPublish(job) { held = (job,value) }
                else { result.append(value); stability.didPublish(job) }
            }
            if let previous = held, tracker.current?.id != previous.job.id { held = nil }
        }
        return result
    }
}
