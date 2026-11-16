import Foundation

struct UserCorrection: Codable, Equatable, Identifiable {
    var id: String, source: String, normalized: String, target: String
    var valid: Bool {
        UUID(uuidString:id) != nil && !source.isEmpty && source.count <= 4096 && source.utf8.count <= 16384 &&
        !source.contains("\0") && SubtitlePresentation.clean(source) == source &&
        normalized == PackLookupKey.normalized(source) && !normalized.isEmpty &&
        !target.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty && target.count <= 2400 && target.utf8.count <= 7200 &&
        !target.contains("\0") && SubtitlePresentation.clean(target) == target
    }
}
struct CorrectionsSnapshot: Codable, Equatable {
    var schema = 1
    var game: String
    var general: Bool? = nil
    var version: UInt64 = 0
    var entries: [UserCorrection] = []
    var scopeKey: String { (general == true ? "general/" : "game/")+game }
    var outputKey: String { scopeKey+"/"+String(version) }
    func validate() throws {
        guard schema == 1, UserDataFile.validGame(game), general != true || game == "general", version < UInt64.max,
              entries.count <= 1000, entries.allSatisfy(\.valid), Set(entries.map(\.id)).count == entries.count,
              Set(entries.map(\.source)).count == entries.count else { throw LingoError.invalid("بنية ملف التصحيحات غير صالحة") }
    }
}
struct CorrectionLookup {
    private var exact: [String:String] = [:]
    private var normalized: [String:Set<String>] = [:]
    init(_ snapshot: CorrectionsSnapshot) {
        for entry in snapshot.entries { exact[entry.source] = entry.target; normalized[entry.normalized,default:[]].insert(entry.target) }
    }
    func lookup(_ source: String) -> String? {
        if let value = exact[source] { return value }
        let values = normalized[PackLookupKey.normalized(source)]
        return values?.count == 1 ? values?.first : nil
    }
}
final class GameCorrectionsStore {
    let file: URL
    private let lock = NSLock()
    private var state: CorrectionsSnapshot
    var onChange: (() -> Void)?
    init(root: URL, game: String, general: Bool = false) throws {
        file = try UserDataFile.url(root:root,game:game)
        if FileManager.default.fileExists(atPath:file.path) {
            state = try JSONDecoder().decode(CorrectionsSnapshot.self,from:UserDataFile.read(file))
            try state.validate(); guard state.game == game, (state.general == true) == general else { throw LingoError.invalid("ملف تصحيحات لعبة مختلفة") }
        } else { state = CorrectionsSnapshot(game:game,general:general ? true : nil); try state.validate() }
    }
    var snapshot: CorrectionsSnapshot { lock.lock(); defer { lock.unlock() }; return state }
    private func change(_ operation: (inout CorrectionsSnapshot) throws -> Void) throws {
        lock.lock()
        do {
            var next = state; try operation(&next); try next.validate()
            if next != state {
                let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys,.prettyPrinted]
                try UserDataFile.write(encoder.encode(next),to:file); state = next
            }
            lock.unlock(); onChange?()
        } catch { lock.unlock(); throw error }
    }
    // Called ONLY from explicit UI editing/import. Never from inference/publication.
    func save(source: String, target: String, id: String? = nil) throws {
        try change { next in
            let existing: Int?
            if let id {
                guard let index = next.entries.firstIndex(where:{$0.id == id}) else { throw LingoError.invalid("التصحيح تغير أو حُذف؛ افتحه مجددًا") }
                existing = index
            } else { existing = next.entries.firstIndex{$0.source == source} }
            let identifier = existing.map{next.entries[$0].id} ?? UUID().uuidString
            let entry = UserCorrection(id:identifier,source:source,normalized:PackLookupKey.normalized(source),target:target)
            guard entry.valid, !next.entries.contains(where:{$0.source == source && $0.id != identifier}) else { throw LingoError.invalid("أدخل نصًا وتصحيحًا صالحين؛ لا تكرر مصدرًا محفوظًا") }
            if let existing {
                guard next.entries[existing] != entry else { return }
                next.entries[existing] = entry
            } else { next.entries.append(entry) }
            next.version += 1
        }
    }
    func remove(_ id: String) throws { try change { next in if next.entries.contains(where:{$0.id == id}) { next.entries.removeAll{$0.id == id}; next.version += 1 } } }
    func importData(_ data: Data) throws {
        guard data.count <= UserDataFile.limit else { throw LingoError.invalid("ملف التصحيحات كبير جدًا") }
        let incoming = try JSONDecoder().decode(CorrectionsSnapshot.self,from:data); try incoming.validate()
        let current = snapshot
        guard incoming.scopeKey == current.scopeKey else { throw LingoError.invalid("اختر اللعبة المطابقة لملف التصحيحات") }
        try change { next in
            // Explicit import can update an exact source; preserve its existing ID.
            for entry in incoming.entries {
                if let index = next.entries.firstIndex(where:{$0.source == entry.source}) { next.entries[index].target = entry.target }
                else { var added = entry; added.id = UUID().uuidString; next.entries.append(added) }
            }
            next.version += 1
        }
    }
    func export() throws -> URL {
        lock.lock(); defer { lock.unlock() }
        try UserDataFile.write(JSONEncoder().encode(state),to:file)
        return file
    }
}
struct RecentPublishedLine: Identifiable, Equatable {
    let id: String, scope: String, source: String, target: String
    let origin: TranslationOrigin
}
struct RecentPublishedLines {
    private(set) var entries: [RecentPublishedLine] = []
    private var scope = ""
    mutating func select(_ value: String) { if scope != value { scope = value; entries.removeAll() } }
    mutating func published(_ line: RecentPublishedLine) {
        guard line.scope == scope, !line.source.isEmpty, line.source.count <= 4096, line.target.count <= 2400 else { return }
        if let index = entries.firstIndex(where:{$0.id == line.id}) { entries[index] = line }
        else { entries.append(line) }
        entries = Array(entries.suffix(20))
    }
    mutating func clear() { entries.removeAll() }
}
