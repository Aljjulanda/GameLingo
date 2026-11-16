import Foundation

enum TVProtocol {
    static let port: UInt16 = 38443
    static let maximumBytes = 16384
    static func envelope(_ type: String, fields: [String: Any] = [:]) -> [String: Any] {
        var result = fields; result["v"] = 1; result["type"] = type; return result
    }
    static func encode(_ message: [String: Any]) throws -> Data {
        let data = try JSONSerialization.data(withJSONObject: message,options: [.sortedKeys])
        guard data.count <= maximumBytes else { throw LingoError.invalid("رسالة التلفزيون تتجاوز الحد المسموح") }
        return data
    }
    static func decode(_ data: Data) throws -> [String: Any] {
        guard data.count <= maximumBytes,
              let value = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let version = value["v"] as? Int, version == 1, value["type"] is String else {
            throw LingoError.invalid("رسالة تلفزيون غير صالحة")
        }
        return value
    }
    static func subtitle(_ job: DialogueJob, arabic: String, now: Int64) -> [String: Any] {
        var fields: [String:Any] = [
            "id":job.id,"source":job.text,"translated":String(SubtitlePresentation.clean(arabic).prefix(2400)),"source_lang":"en","target_lang":"ar",
            "update_type":job.correction ? "correction" : "new","frame_ms":job.frameMilliseconds,"translation_ms":now,
            "x":job.box.x,"y":job.box.y,"w":job.box.w,"h":job.box.h,"category":"text","confidence":NSNull(),"font_sp":25,
            "duration_ms":8000,"expires_at":now+8000
        ]
        fields["event_fresh"] = !job.correction
        fields["meaningful_correction"] = job.meaningfulCorrection
        if !job.eventBoundary.isEmpty { fields["event_boundary"] = job.eventBoundary; fields["source_gap_ms"] = job.sourceGapMilliseconds }
        if let speaker = job.speaker {
            var label = ["name":String(speaker.prefix(40))]
            if let arabic = job.speakerArabic { label["arabic"] = String(arabic.prefix(100)) }
            fields["speaker"] = label
        }
        return envelope(job.correction ? "subtitle_update" : "subtitle_show",fields:fields)
    }
    static func qualityFields(_ message: [String:Any], settings: QualitySettings, origin: TranslationOrigin, basis: TranslationOrigin? = nil) -> [String:Any] {
        var message = message
        if settings[.provenanceMarker] { message["provenance"] = origin.rawValue }
        if settings[.provenanceMarker], let basis { message["provenance_basis"] = basis.rawValue }
        if settings[.punctuationTrace] { message["quality_trace"] = true }
        if settings[.arabicParagraphDirection] { message["arabic_paragraph_direction"] = true }
        return message
    }
}

struct TVSequence {
    let session = UUID().uuidString
    private(set) var sequence: UInt64 = 0
    mutating func stamp(_ raw: [String: Any]) -> [String: Any] {
        sequence &+= 1
        var value = raw; value["session"] = session; value["seq"] = sequence; return value
    }
}
