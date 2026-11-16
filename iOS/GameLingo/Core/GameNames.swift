import Foundation

enum GameNameType: String, Codable, CaseIterable { case person, place, term
    var title: String { self == .person ? "شخص" : self == .place ? "مكان" : "مصطلح" }
}
enum GameNameSource: String, Codable { case auto, pack, manual
    var title: String { self == .auto ? "متعلّم" : self == .pack ? "الحزمة" : "يدوي" }
    var priority: Int { self == .manual ? 3 : self == .pack ? 2 : 1 }
}
struct GameName: Codable, Equatable, Identifiable {
    var english: String, type: GameNameType, arabic: String, source: GameNameSource, count: Int
    var id: String { Self.key(english) }
    static func key(_ value: String) -> String { DialogueText.normalized(value).lowercased() }
    var valid: Bool {
        SpeakerEvidence.shape(english) && english.count <= 40 && !english.contains(",") &&
            !arabic.isEmpty && arabic.count <= 100 && !arabic.contains("\0") && SubtitlePresentation.clean(arabic) == arabic &&
            !arabic.unicodeScalars.contains { (0xfb50...0xfdff).contains($0.value) || (0xfe70...0xfefc).contains($0.value) } &&
            arabic.unicodeScalars.contains { (0x0600...0x06ff).contains($0.value) } && (0...1_000_000).contains(count)
    }
}
struct GameNamesSnapshot: Codable, Equatable {
    var schema = 1
    var game: String
    var general: Bool? = nil
    var version: UInt64 = 0
    var entries: [GameName] = []
    var blocked: [String] = []
    var userDeletions = 0
    private func dictionary(_ names: [GameName]) -> String { names.sorted { $0.source.priority == $1.source.priority ? $0.id < $1.id : $0.source.priority > $1.source.priority }.prefix(200).map(\.english).joined(separator:",") }
    var words: String { dictionary(entries) }
    var speakerWords: String { dictionary(entries.filter{$0.type == .person}) }
    var scopeKey: String { (general == true ? "general/" : "game/")+game }
    var outputKey: String { scopeKey+"/"+String(version) }
    func validate() throws {
        guard schema == 1, UserDataFile.validGame(game), general != true || game == "general", version < UInt64.max,
              entries.count <= 2000, entries.allSatisfy(\.valid), Set(entries.map(\.id)).count == entries.count,
              blocked.count <= 10000, Set(blocked).count == blocked.count,
              blocked.allSatisfy({SpeakerEvidence.shape($0) && $0 == GameName.key($0)}),
              Set(blocked).isDisjoint(with:entries.map(\.id)), (0...1_000_000).contains(userDeletions) else { throw LingoError.invalid("بنية ملف الأسماء غير صالحة") }
    }
}

/// Serialized internally; the pipeline can approve a name before submitting
/// the current inference. Pending evidence/IDs are RAM only, never dialogue.
final class GameNamesStore {
    let game: String, file: URL
    private let lock = NSLock()
    private var state: GameNamesSnapshot
    private var evidence = BoundedLRU<String,Set<String>>(capacity:256)
    var onChange: (() -> Void)?
    init(root: URL, game: String, general: Bool = false) throws {
        self.game = game; file = try UserDataFile.url(root:root,game:game)
        if FileManager.default.fileExists(atPath:file.path) {
            state = try JSONDecoder().decode(GameNamesSnapshot.self,from:UserDataFile.read(file))
            try state.validate(); guard state.game == game, (state.general == true) == general else { throw LingoError.invalid("ملف أسماء لعبة مختلفة") }
        } else { state = GameNamesSnapshot(game:game,general:general ? true : nil); try state.validate() }
    }
    var snapshot: GameNamesSnapshot { lock.lock(); defer { lock.unlock() }; return state }
    private func change(_ operation: (inout GameNamesSnapshot) throws -> Void) throws {
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
    func upsert(_ name: GameName, explicit: Bool = false) throws {
        guard name.valid else { throw LingoError.invalid("أدخل اسمًا إنجليزيًا وتهجئة عربية صحيحة") }
        try change { next in
            let key = name.id
            if next.blocked.contains(key) {
                guard explicit && name.source == .manual else { return }
                next.blocked.removeAll { $0 == key }
            }
            var incoming = name
            if let index = next.entries.firstIndex(where:{$0.id == key}) {
                let old = next.entries[index]
                guard incoming.source.priority >= old.source.priority else { return }
                incoming.count = max(old.count,incoming.count)
                if old.english != incoming.english || old.arabic != incoming.arabic || old.type != incoming.type || old.source != incoming.source { next.version += 1 }
                next.entries[index] = incoming
            } else { guard next.entries.count < 2000 else { throw LingoError.invalid("وصلت قائمة الأسماء إلى حدها") }; next.entries.append(incoming); next.version += 1 }
        }
    }
    func remove(_ english: String) throws {
        try change { next in
            let key = GameName.key(english)
            guard next.entries.contains(where:{$0.id == key}) else { return }
            next.entries.removeAll { $0.id == key }; next.blocked.append(key)
            next.userDeletions = min(1_000_000,next.userDeletions+1); next.version += 1
        }
    }
    @discardableResult
    func learn(_ english: String, form: SpeakerLabelForm, confidence: Double, eventID: String, colonThreshold: Int = 1, otherThreshold: Int = 2) throws -> Bool {
        guard confidence >= 0.8, eventID.count <= 160, !eventID.isEmpty,
              SpeakerEvidence.isName(english,knownNames:"",confidence:confidence) else { return false }
        let key = GameName.key(english)
        lock.lock()
        if state.blocked.contains(key) { lock.unlock(); return false }
        var ids = evidence.get(key) ?? []
        guard !ids.contains(eventID) else { lock.unlock(); return false }
        ids.insert(eventID); if ids.count > 32 { ids = [eventID] }; evidence.put(ids,for:key)
        let count = ids.count
        let existing = state.entries.first(where:{$0.id == key})
        lock.unlock()
        let threshold = max(1,min(10,form == .colon ? colonThreshold : otherThreshold))
        guard existing != nil || count >= threshold else { return false }
        if existing != nil {
            try change { next in
                if let index = next.entries.firstIndex(where:{$0.id == key}) { next.entries[index].count = min(1_000_000,next.entries[index].count+1) }
            }
            return true
        }
        try upsert(GameName(english:english,type:.person,arabic:NameTransliteration.arabic(english),source:.auto,count:count)); return true
    }
    func importData(_ data: Data) throws {
        guard data.count <= UserDataFile.limit else { throw LingoError.invalid("ملف الأسماء كبير جدًا") }
        let imported = try JSONDecoder().decode(GameNamesSnapshot.self,from:data)
        try imported.validate(); guard imported.game == game, (imported.general == true) == (snapshot.general == true) else { throw LingoError.invalid("اختر اللعبة المطابقة لملف الأسماء") }
        // Preserve every existing manual spelling and every local deletion.
        try change { next in
            for name in imported.entries where !next.blocked.contains(name.id) {
                if let index = next.entries.firstIndex(where:{$0.id == name.id}) {
                    guard next.entries[index].source != .manual, name.source.priority >= next.entries[index].source.priority else { continue }
                    next.entries[index] = name
                } else { next.entries.append(name) }
            }
            for key in imported.blocked where !next.entries.contains(where:{$0.id == key && $0.source == .manual}) {
                next.entries.removeAll {$0.id == key}; if !next.blocked.contains(key) { next.blocked.append(key) }
            }
            next.userDeletions = max(next.userDeletions,imported.userDeletions); next.version += 1
        }
    }
    func export() throws -> URL {
        lock.lock(); defer { lock.unlock() }
        // An empty new store has no file until explicitly exported.
        if !FileManager.default.fileExists(atPath:file.path) { try UserDataFile.write(JSONEncoder().encode(state),to:file) }
        return file
    }
}

enum NameTransliteration {
    // Deterministic editable approximation, NOT authoritative pronunciation.
    // A small explicit conventional-name table precedes the digraph/vowel rules.
    private static let conventional = ["arthur":"آرثر","john":"جون","bill":"بيل","grace":"غريس","dutch":"داتش","morgan":"مورغان","47":"٤٧","2b":"٢ بي","9s":"٩ إس","bt-7274":"بي تي-٧٢٧٤"]
    static func arabic(_ input: String) -> String {
        let input = input.folding(options:.diacriticInsensitive,locale:Locale(identifier:"en_US_POSIX")).lowercased()
        if let known = conventional[input] { return known }
        let digraphs = ["th":"ث","sh":"ش","ch":"تش","ph":"ف","ck":"ك","ee":"ي","oo":"و","ea":"ي","ai":"اي","ay":"اي","ou":"او"]
        let letters: [Character:String] = ["a":"ا","b":"ب","c":"ك","d":"د","e":"ي","f":"ف","g":"غ","h":"ه","i":"ي","j":"ج","k":"ك","l":"ل","m":"م","n":"ن","o":"و","p":"ب","q":"ك","r":"ر","s":"س","t":"ت","u":"و","v":"ف","w":"و","x":"كس","y":"ي","z":"ز"]
        var result = "", cursor = input.startIndex
        while cursor < input.endIndex {
            let next = input.index(after:cursor)
            if next < input.endIndex, let value = digraphs[String(input[cursor...next])] { result += value; cursor = input.index(after:next); continue }
            let letter = input[cursor]
            if letter == "e", next == input.endIndex { cursor = next; continue }
            result += letters[letter] ?? String(letter); cursor = next
        }
        return result
    }
}
