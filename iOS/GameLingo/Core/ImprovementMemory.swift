import Foundation

struct ImprovementExample: Codable, Equatable, Identifiable {
    var id = UUID().uuidString
    var game: String, source: String, context: String
    var confidence: Double
    var observations = 1
    var trustedTarget: String?
    var authority: String?
    var created = Date()
    var model = "argos-en_ar-1.0"
    var evidence: LearningEvidence? = nil
    var valid: Bool { UserDataFile.validGame(game) && game != "general" && !source.isEmpty && source.count <= 1800 && context.count <= 4096 && confidence.isFinite && (0...1).contains(confidence) && (1...1000).contains(observations) && (trustedTarget?.count ?? 0) <= 2400 }
}
struct ImprovementProposal: Codable, Identifiable {
    var id: String
    var example: ImprovementExample
    var candidate: String
    var accepted: Bool
    var reason: String
    var version = 1
}
struct ApprovedMemoryEntry: Codable, Equatable, Identifiable {
    var id: String
    var game: String, source: String, context: String, target: String, authority: String, model: String
    var version = 1
    var created = Date()
    var valid: Bool { UUID(uuidString:id) != nil && UserDataFile.validGame(game) && game != "general" && !source.isEmpty && source.count <= 1800 && !context.isEmpty && context.count <= 4096 && !target.isEmpty && target.count <= 2400 && authority.hasPrefix("pack-exact:") && authority.count <= 120 && version == 1 }
}
struct ImprovedMemorySnapshot {
    var entries: [ApprovedMemoryEntry] = []
    var version = 0
    func lookup(game: String, source: String, context: String) -> String? {
        guard game != "general", !context.isEmpty else { return nil }
        let matches = entries.filter{$0.game == game && $0.source == source && $0.context == context}
        let targets = Set(matches.map(\.target))
        return targets.count == 1 ? targets.first : nil
    }
}
enum ImprovementGate {
    /// Independent authority is mandatory. A model agreeing with its prior output
    /// is not evidence. Exact reference equality is deliberately conservative.
    static func rejection(_ example: ImprovementExample, candidate: String, existing: [ApprovedMemoryEntry]) -> String? {
        guard example.valid, example.confidence >= 0.9, example.observations >= 2, !example.context.isEmpty else { return "OCR/context evidence insufficient" }
        guard let authority = example.authority, authority.hasPrefix("pack-exact:"), let reference = example.trustedTarget, !reference.isEmpty else { return "No independent exact-pack authority" }
        guard !candidate.isEmpty, candidate.count <= 2400, SubtitlePresentation.clean(candidate) == candidate,
              DialogueText.normalized(candidate) == DialogueText.normalized(reference) else { return "Candidate disagrees with independent reference" }
        let sourceNumbers = DialogueText.matches(example.source,"[0-9]+")
        let targetNumbers = DialogueText.matches(candidate,"[0-9]+")
        guard sourceNumbers == targetNumbers else { return "Number preservation failed" }
        let negatives = Set(["not","never","no","cannot","cant","dont","wont","without"])
        if !negatives.isDisjoint(with:DialogueText.exactWords(example.source)), !["لا","لم","لن","ليس","بدون","غير","ممنوع"].contains(where:{candidate.split(whereSeparator:\.isWhitespace).contains(Substring($0))}) { return "Negation evidence missing" }
        if existing.contains(where:{$0.game == example.game && $0.source == example.source && $0.context == example.context && $0.target != candidate}) { return "Conflicting approved context" }
        return nil
    }
}

/// Three separate, bounded local files. No images, uploader, recursive training,
/// auto-generated menu templates, or changes to explicit user corrections.
final class ImprovementMemoryStore {
    private let root: URL
    private(set) var raw: [ImprovementExample] = []
    private(set) var proposals: [ImprovementProposal] = []
    private(set) var approved: [ApprovedMemoryEntry] = []
    init(root: URL) throws {
        self.root = root
        func read<T: Decodable>(_ name: String, _ type: T.Type) throws -> T? {
            let file = root.appendingPathComponent(name+".json")
            return FileManager.default.fileExists(atPath:file.path) ? try JSONDecoder().decode(type,from:UserDataFile.read(file)) : nil
        }
        raw = try read("raw",[ImprovementExample].self) ?? []; proposals = try read("proposals",[ImprovementProposal].self) ?? []; approved = try read("approved",[ApprovedMemoryEntry].self) ?? []
        guard raw.count <= 200, proposals.count <= 200, approved.count <= 500, raw.allSatisfy(\.valid), approved.allSatisfy(\.valid), proposals.allSatisfy({$0.example.valid && $0.candidate.count <= 2400 && $0.reason.count <= 200}) else { throw LingoError.invalid("ذاكرة التحسين غير صالحة؛ لم يُعدل الأصل") }
        try prune()
    }
    private func save<T: Encodable>(_ name: String, _ value: T) throws { try UserDataFile.write(JSONEncoder().encode(value),to:root.appendingPathComponent(name+".json")) }
    func observe(_ example: ImprovementExample, consent: Bool) throws {
        guard consent, example.valid, !TextPrivacy.excluded(example.source) else { return }
        try prune()
        if let index = raw.firstIndex(where:{$0.game == example.game && PackLookupKey.normalized($0.source) == PackLookupKey.normalized(example.source) && $0.context == example.context}) {
            if example.trustedTarget == nil { raw[index].observations = min(1000,raw[index].observations+1) }
            raw[index].confidence = min(raw[index].confidence,example.confidence)
            if let evidence = example.evidence { raw[index].evidence = evidence }
            if let target = example.trustedTarget { raw[index].trustedTarget = target; raw[index].authority = example.authority }
        } else { raw.append(example); raw = Array(raw.suffix(200)) }
        try save("raw",raw)
    }
    /// Continuous reference-backed memory updates. No model inference/training,
    /// no approval dialog, and repeated Argos output cannot enter this path.
    @discardableResult func approveAutomatic() throws -> Int {
        var count = 0
        for sample in raw where LearningSafety.trusted(sample) && !proposals.contains(where:{$0.id == sample.id}) {
            if try record(sample,candidate:sample.trustedTarget!) { count += 1 }
        }
        return count
    }
    func record(_ example: ImprovementExample, candidate: String) throws -> Bool {
        guard raw.contains(where:{$0.id == example.id}), !proposals.contains(where:{$0.id == example.id}) else { return false }
        let reason = ImprovementGate.rejection(example,candidate:candidate,existing:approved)
        var next = approved
        if reason == nil { next.append(ApprovedMemoryEntry(id:example.id,game:example.game,source:example.source,context:example.context,target:candidate,authority:example.authority!,model:example.model)); next = Array(next.suffix(500)); try save("approved",next); approved = next }
        proposals.append(ImprovementProposal(id:example.id,example:example,candidate:String(candidate.prefix(2400)),accepted:reason == nil,reason:reason ?? "Exact independent reference + context + structural gates passed"))
        proposals = Array(proposals.suffix(200)); try save("proposals",proposals); return reason == nil
    }
    func prune(now: Date = Date()) throws {
        raw.removeAll { TextPrivacy.excluded($0.source) || ($0.evidence == nil && LearningSafety.confidence(source:$0.source,speaker:nil,speakerConfidence:0,ocr:$0.confidence,ui:false) == nil) }
        proposals.removeAll { TextPrivacy.excluded($0.example.source) }
        approved.removeAll { TextPrivacy.excluded($0.source) }
        raw.removeAll { now.timeIntervalSince($0.created) > 7*86400 }; proposals.removeAll { now.timeIntervalSince($0.example.created) > 7*86400 }
        try save("raw",raw); try save("proposals",proposals); try save("approved",approved)
        let exported = root.appendingPathComponent("export.json")
        if let modified = try? exported.resourceValues(forKeys:[.contentModificationDateKey]).contentModificationDate,
           now.timeIntervalSince(modified) > 900 { try? FileManager.default.removeItem(at:exported) }
    }
    func deleteCollected() throws { raw = []; proposals = []; try save("raw",raw); try save("proposals",proposals); try? FileManager.default.removeItem(at:root.appendingPathComponent("export.json")) }
    func rollbackApproved() throws { approved = []; try save("approved",approved); try? FileManager.default.removeItem(at:root.appendingPathComponent("export.json")) }
    func export() throws -> URL {
        try prune()
        let file = root.appendingPathComponent("export.json")
        let validated = raw.filter { $0.evidence?.dialogue ?? 0 >= 0.9 && $0.observations >= 3 }
        let references = raw.filter { $0.trustedTarget != nil && $0.authority?.hasPrefix("pack-exact:") == true }
        let data = try JSONSerialization.data(withJSONObject:["schema_version":2,"raw":JSONSerialization.jsonObject(with:JSONEncoder().encode(raw)),"validated_dialogue":JSONSerialization.jsonObject(with:JSONEncoder().encode(validated)),"ocr_corrections":[],"trusted_references":JSONSerialization.jsonObject(with:JSONEncoder().encode(references)),"unverified_candidates":JSONSerialization.jsonObject(with:JSONEncoder().encode(proposals.filter{!$0.accepted})),"quarantined":JSONSerialization.jsonObject(with:JSONEncoder().encode(proposals.filter{!$0.accepted})),"proposals":JSONSerialization.jsonObject(with:JSONEncoder().encode(proposals)),"approved":JSONSerialization.jsonObject(with:JSONEncoder().encode(approved))],options:[.sortedKeys])
        guard data.count <= 12*1024*1024 else { throw LingoError.invalid("التصدير يتجاوز الحد المسموح") }
        #if os(iOS)
        try data.write(to:file,options:[.atomic,.completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to:file,options:.atomic)
        #endif
        return file
    }
}
