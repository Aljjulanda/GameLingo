import Foundation
import CryptoKit
import ZIPFoundation

struct InstalledGamePack: Codable, Identifiable {
    var id: String, manifest: PackManifest, bytes: Int64, enabled: Bool
}
struct GamePackRegistry: Codable {
    var packs: [InstalledGamePack] = []
    var selectedGame: String?
}
struct GamePackState {
    var registry = GamePackRegistry()
    var loaded = false
    var error: String?
}
/// Import validation never owns the runtime lookup queue. All paths are generated.
final class TranslationPackStore {
    let root: URL
    var onChange: ((GamePackState) -> Void)?
    private let queue = DispatchQueue(label:"dev.gamelingo.pack.lookup",qos:.userInitiated)
    private let importer = DispatchQueue(label:"dev.gamelingo.pack.import",qos:.utility)
    private var state = GamePackState()
    private var database: PackDatabase?
    private var activation = 0
    private var metrics = HybridMetrics()
    private var eventIDs = BoundedLRU<String,Bool>(capacity:64)
    init(root: URL? = nil) {
        self.root = root ?? FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("GameTranslationLibrary",isDirectory:true)
        queue.async { [self] in
            do {
                try FileManager.default.createDirectory(at:self.root,withIntermediateDirectories:true)
                var folder = self.root; var values = URLResourceValues(); values.isExcludedFromBackup = true; try folder.setResourceValues(values)
                try FileManager.default.setAttributes([.protectionKey:FileProtectionType.completeUntilFirstUserAuthentication],ofItemAtPath:self.root.path)
                let file = self.root.appendingPathComponent("library.json")
                if FileManager.default.fileExists(atPath:file.path) {
                    let data = try Data(contentsOf:file); guard data.count <= 262144 else { throw PackFailure.size }
                    let registry = try JSONDecoder().decode(GamePackRegistry.self,from:data)
                    guard registry.packs.count <= 32, Set(registry.packs.map(\.id)).count == registry.packs.count,
                          Set(registry.packs.map { $0.manifest.gameId }).count == registry.packs.count else { throw PackFailure.invalid }
                    for item in registry.packs { guard UUID(uuidString:item.id) != nil else { throw PackFailure.invalid }; try item.manifest.validate() }
                    state.registry = registry
                }
                activate()
            } catch { state.error = "تعذر تحميل المكتبة؛ يستمر استخدام Argos"; notify() }
        }
    }
    private func notify() { let value = state; DispatchQueue.main.async { self.onChange?(value) } }
    private func save(_ registry: GamePackRegistry) throws {
        let url = root.appendingPathComponent("library.json")
        try JSONEncoder().encode(registry).write(to:url,options:[.atomic,.completeFileProtectionUntilFirstUserAuthentication])
    }
    static func hash(_ url: URL, check: () throws -> Void = {}) throws -> String {
        let file = try FileHandle(forReadingFrom:url); defer { try? file.close() }
        var hash = SHA256()
        while let data = try file.read(upToCount:1024*1024), !data.isEmpty { try check(); hash.update(data:data) }
        return hash.finalize().map { String(format:"%02x",$0) }.joined()
    }
    private func activate() {
        activation += 1; let epoch = activation
        metrics = HybridMetrics(); eventIDs = BoundedLRU(capacity:64)
        database = nil; state.loaded = false; state.error = nil; notify()
        guard let game = state.registry.selectedGame, let item = state.registry.packs.first(where:{ $0.manifest.gameId == game && $0.enabled }) else { return }
        importer.async { [self] in
            let result = Result { () throws -> PackDatabase in
                let url = root.appendingPathComponent(item.id).appendingPathComponent("translations.sqlite")
                guard try Self.hash(url) == item.manifest.databaseSha256 else { throw PackFailure.damaged }
                return try PackDatabase(url:url)
            }
            queue.async { [self] in
                guard epoch == activation else { return }
                switch result {
                case .success(let value): database = value; state.loaded = true
                case .failure: state.error = "الحزمة المختارة تالفة أو غير متاحة؛ يستمر استخدام Argos"
                }
                notify()
            }
        }
    }
    func changeSelection(game: String?) {
        queue.async { [self] in
            do {
                guard game == nil || state.registry.packs.contains(where:{ $0.manifest.gameId == game }) else { throw PackFailure.invalid }
                if state.registry.selectedGame == game && (state.loaded || game == nil) { return }
                var next = state.registry; next.selectedGame = game; try save(next); state.registry = next; activate()
            } catch { state.error = "تعذر حفظ اختيار اللعبة"; notify() }
        }
    }
    func enable(_ id: String, _ enabled: Bool) {
        queue.async { [self] in
            do {
                guard let at = state.registry.packs.firstIndex(where:{ $0.id == id }) else { return }
                var next = state.registry; next.packs[at].enabled = enabled; try save(next); state.registry = next
                if next.selectedGame == next.packs[at].manifest.gameId { activate() } else { notify() }
            } catch { state.error = "تعذر حفظ إعداد الحزمة"; notify() }
        }
    }
    func remove(_ id: String) {
        queue.async { [self] in
            do {
                guard let item = state.registry.packs.first(where:{ $0.id == id }) else { return }
                var next = state.registry; next.packs.removeAll { $0.id == id }
                let wasSelected = next.selectedGame == item.manifest.gameId
                if wasSelected { next.selectedGame = nil }
                try save(next); state.registry = next
                if wasSelected { activate() } else { notify() }
                let folder = root.appendingPathComponent(item.id)
                importer.async { try? FileManager.default.removeItem(at:folder) }
            } catch { state.error = "تعذر حذف الحزمة"; notify() }
        }
    }
    func resetMetrics() { queue.async { self.metrics = HybridMetrics(); self.eventIDs = BoundedLRU(capacity:64) } }
    func sampleMetrics(_ completion: @escaping (HybridMetrics) -> Void) {
        queue.async { let value = self.metrics; DispatchQueue.main.async { completion(value) } }
    }
    func sampleState(_ completion: @escaping (GamePackState) -> Void) { queue.async { let value = self.state; DispatchQueue.main.async { completion(value) } } }
    func recordArgos() { queue.async { self.metrics.argos += 1 } }
    func recordDialogue(_ id: String) {
        queue.async { [self] in if eventIDs.get(id) == nil { eventIDs.put(true,for:id); metrics.dialogueEvents += 1 } }
    }
    func recordPublished(_ event: PublishedTranslation) {
        queue.async { [self] in
            // A completed request from an earlier selection cannot contaminate
            // this game's denominator or display a false active-pack status.
            guard event.game == state.registry.selectedGame else { return }
            metrics.recordPublished(event)
        }
    }
    func recordAttempt(_ origin: TranslationOrigin) { queue.async { self.metrics.recordAttempt(origin) } }
    func publication(_ id: String, origin: TranslationOrigin, fallback: TranslationFallback? = nil) -> PublishedTranslation {
        queue.sync { PublishedTranslation(eventID:id,game:state.registry.selectedGame,
            pack:state.loaded ? state.registry.packs.first{$0.manifest.gameId == state.registry.selectedGame && $0.enabled}?.id : nil,
            origin:origin,fallback:fallback) }
    }
    func lookup(_ source: String, category: String, eventID: String?) -> String? {
        lookupDetailed(source,category:category,eventID:eventID).text
    }
    func lookupDetailed(_ source: String, category: String, eventID: String?) -> PackLookupOutcome {
        queue.sync { [self] in
            if category == "dialogue", let eventID, eventIDs.get(eventID) == nil { eventIDs.put(true,for:eventID); metrics.dialogueEvents += 1 }
            var outcome = PackLookupOutcome(game:state.registry.selectedGame,
                pack:state.loaded ? state.registry.packs.first{$0.manifest.gameId == state.registry.selectedGame && $0.enabled}?.id : nil)
            guard let database else { outcome.fallback = .noDatabase; return outcome }
            let start = ProcessInfo.processInfo.systemUptime; metrics.lookups += 1
            defer { let ms = (ProcessInfo.processInfo.systemUptime-start)*1000; metrics.lookupTotal += ms; metrics.samples.record(ms) }
            do {
                let result = try database.lookup(source,category:category)
                if let text = result.text {
                    metrics.matches += 1
                    if result.kind == .exact { metrics.exact += 1 } else { metrics.normalized += 1 }
                    outcome.text = text; outcome.origin = result.kind == .exact ? .packExact : .packNormalized
                } else {
                    metrics.fallbacks += 1; if result.kind == .ambiguous { metrics.ambiguous += 1 }
                    outcome.fallback = TranslationFallback(rawValue:result.kind.rawValue) ?? .unsupported
                }
            } catch {
                metrics.fallbacks += 1; self.database = nil; state.loaded = false
                state.error = "تعذر قراءة الحزمة؛ يستمر استخدام Argos"; outcome.fallback = .unsupported; notify()
            }
            return outcome
        }
    }
    func selfTest(_ completion: @escaping (PackSelfTest) -> Void) {
        queue.async { [self] in
            var report = PackSelfTest()
            report.active = state.loaded
            report.usablePairs = state.registry.packs.first{$0.manifest.gameId == state.registry.selectedGame && $0.enabled}?.manifest.usableCount ?? 0
            if let database {
                do {
                    for (index,source) in try database.sampleSources().enumerated() {
                        let perturbed: String
                        switch index % 4 {
                        case 0: perturbed = source.trimmingCharacters(in:CharacterSet(charactersIn:".!?"))
                        case 1: perturbed = source.replacingOccurrences(of:"'",with:"’").replacingOccurrences(of:"\"",with:"“")
                        case 2: perturbed = source.replacingOccurrences(of:" ",with:"  ")
                        default: perturbed = source.replacingOccurrences(of:" ",with:"\n")
                        }
                        let match = try database.lookup(perturbed,category:"dialogue")
                        report.count += 1
                        if match.text != nil { report.matched += 1 } else { report.reasons[match.kind.rawValue,default:0] += 1 }
                    }
                } catch { report.reasons["damaged",default:0] += 1 }
            } else { report.reasons["noDatabase",default:0] += 1 }
            // Deliberately does not change attempts or published metrics.
            let value = report; DispatchQueue.main.async { completion(value) }
        }
    }
    /// Copies a scoped Files URL into managed storage, validates before registry commit.
    func importPack(_ external: URL, check: @escaping () throws -> Void = {}, completion: @escaping (Result<Void,Error>) -> Void) {
        let scoped = external.startAccessingSecurityScopedResource()
        importer.async { [self] in
            defer { if scoped { external.stopAccessingSecurityScopedResource() } }
            let result = Result { () throws -> Void in
                try check()
                let fm = FileManager.default
                try fm.createDirectory(at:root,withIntermediateDirectories:true)
                let stage = root.appendingPathComponent("stage-"+UUID().uuidString,isDirectory:true)
                try fm.createDirectory(at:stage,withIntermediateDirectories:true)
                defer { try? fm.removeItem(at:stage) }
                let package = stage.appendingPathComponent("input.glpack")
                var coordinationError: NSError?, copyError: Error?
                NSFileCoordinator().coordinate(readingItemAt:external,options:.withoutChanges,error:&coordinationError) { source in
                    do {
                        let input = try FileHandle(forReadingFrom:source); defer { try? input.close() }
                        guard fm.createFile(atPath:package.path,contents:nil) else { throw PackFailure.unavailable }
                        let output = try FileHandle(forWritingTo:package); defer { try? output.close() }
                        var count = 0
                        while let data = try input.read(upToCount:1024*1024), !data.isEmpty {
                            try check()
                            count += data.count; guard count <= 128*1024*1024 else { throw PackFailure.size }; try output.write(contentsOf:data)
                        }
                    } catch { copyError = error }
                }
                if let error = coordinationError { throw error }
                if let error = copyError { throw error }
                let manifest = try Self.unpack(package,into:stage,check:check)
                let dbURL = stage.appendingPathComponent("translations.sqlite")
                try fm.setAttributes([.protectionKey:FileProtectionType.completeUntilFirstUserAuthentication],ofItemAtPath:dbURL.path)
                let validated = try PackDatabase(url:dbURL); try validated.validateContents(manifest:manifest,check:check)
                try fm.removeItem(at:package)
                let size = Int64(try dbURL.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0)
                try queue.sync {
                    try check()
                    let old = state.registry.packs.first(where:{ $0.manifest.gameId == manifest.gameId })
                    if old?.manifest == manifest { return }
                    guard old != nil || state.registry.packs.count < 32 else { throw PackFailure.size }
                    let id = UUID().uuidString, destination = root.appendingPathComponent(id,isDirectory:true)
                    var next = state.registry; next.packs.removeAll { $0.manifest.gameId == manifest.gameId }
                    next.packs.append(InstalledGamePack(id:id,manifest:manifest,bytes:size,enabled:old?.enabled ?? true))
                    try fm.moveItem(at:stage,to:destination)
                    do { try save(next) } catch { try? fm.removeItem(at:destination); throw error }
                    state.registry = next
                    if next.selectedGame == manifest.gameId {
                        activation += 1; database = old?.enabled == false ? nil : validated; state.loaded = database != nil; state.error = nil
                    }
                    notify()
                    if let old { try? fm.removeItem(at:root.appendingPathComponent(old.id)) }
                }
            }
            DispatchQueue.main.async { completion(result) }
        }
    }
    static func unpack(_ package: URL, into stage: URL, check: () throws -> Void = {}) throws -> PackManifest {
        let archive = try Archive(url:package,accessMode:.read)
        let expected: Set<String> = ["manifest.json","translations.sqlite","checksums.json"]
        var seen = Set<String>()
        for entry in archive {
            try check()
            guard expected.contains(entry.path), !seen.contains(entry.path), entry.type == .file else { throw PackFailure.invalid }
            seen.insert(entry.path)
            let limit: UInt64 = entry.path == "translations.sqlite" ? 256*1024*1024 : entry.path == "manifest.json" ? 65536 : 2048
            guard entry.uncompressedSize <= limit, entry.uncompressedSize > 0,
                  max(1,entry.compressedSize) >= (entry.uncompressedSize+99)/100 else { throw PackFailure.size }
            let url = stage.appendingPathComponent(entry.path)
            guard FileManager.default.createFile(atPath:url.path,contents:nil) else { throw PackFailure.unavailable }
            let output = try FileHandle(forWritingTo:url); defer { try? output.close() }
            var count: UInt64 = 0
            let crc = try archive.extract(entry,bufferSize:65536,skipCRC32:false) { data in
                try check()
                count += UInt64(data.count); guard count <= limit, count <= entry.uncompressedSize else { throw PackFailure.size }
                try output.write(contentsOf:data)
            }
            guard count == entry.uncompressedSize, crc == entry.checksum else { throw PackFailure.damaged }
        }
        guard seen == expected else { throw PackFailure.invalid }
        let raw = try Data(contentsOf:stage.appendingPathComponent("manifest.json"))
        let manifest = try PackManifest.decode(raw)
        let hashes = try JSONDecoder().decode([String:String].self,from:Data(contentsOf:stage.appendingPathComponent("checksums.json")))
        guard Set(hashes.keys) == Set(["manifest.json","translations.sqlite"]),
              hashes["manifest.json"] == SHA256.hash(data:raw).map({String(format:"%02x",$0)}).joined(),
              hashes["translations.sqlite"] == manifest.databaseSha256,
              try Self.hash(stage.appendingPathComponent("translations.sqlite"),check:check) == manifest.databaseSha256 else { throw PackFailure.damaged }
        return manifest
    }
}
