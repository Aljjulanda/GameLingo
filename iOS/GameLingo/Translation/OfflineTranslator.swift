import Foundation
import CryptoKit
import ZIPFoundation

/// One model instance and one inference worker. No text is sent to a remote service.
final class OfflineTranslator {
    static let modelID = "argos-en_ar-1.0"
    static let modelURL = URL(string:"https://argos-net.com/v1/translate-en_ar-1_0.argosmodel")!
    static let modelDigest = "e2a6e84337f7ebbb55f9dc61dcba3a861c0d786ae5a46fa198fd8d6473f5c775"
    static let modelSize: Int64 = 88_502_631
    static let required = ["model/model.bin","model/shared_vocabulary.txt","sentencepiece.model","metadata.json","README.md"]
    let folder: URL
    let packs: TranslationPackStore?
    private let queue = DispatchQueue(label:"dev.gamelingo.translation",qos:.userInitiated)
    private let lock = NSLock()
    private var engine: GLTranslation?
    private var cancellationGeneration: UInt64 = 0
    private var cache = BoundedLRU<String,String>(capacity:256)
    private var names = GameNamesSnapshot(game:"general")
    private var quality = QualitySettings()
    private var lastPackKey = ""
    func configureQuality(_ value: QualitySettings) {
        queue.async { [self] in
            if quality.outputKey != value.outputKey { cache = BoundedLRU(capacity:256) }
            quality = value; packs?.configureQuality(PackQualityOptions(value))
        }
    }
    private var corrections = CorrectionContext(CorrectionsSnapshot(game:"general",general:true),enabled:false)
    func configureCorrections(_ snapshot: CorrectionsSnapshot, enabled: Bool) {
        queue.async { [self] in
            let next = CorrectionContext(snapshot,enabled:enabled)
            if corrections.outputKey != next.outputKey { cache = BoundedLRU(capacity:256) }
            corrections = next
        }
    }
    private var engineDiagnostics = false
    func configureEngineDiagnostics(_ value: Bool) { queue.async { self.engineDiagnostics = value } }
    func configureNames(_ snapshot: GameNamesSnapshot) {
        queue.async { [self] in
            if names.outputKey != snapshot.outputKey { cache = BoundedLRU(capacity:256) }
            names = snapshot
        }
    }
    init(folder: URL? = nil, packs: TranslationPackStore? = nil) {
        self.packs = packs
        self.folder = folder ?? FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent(Self.modelID,isDirectory:true)
    }
    var installed: Bool { Self.required.allSatisfy { FileManager.default.fileExists(atPath:folder.appendingPathComponent($0).path) } }
    func load(completion: @escaping (Result<Void,Error>) -> Void) {
        lock.lock(); let generation = cancellationGeneration; lock.unlock()
        queue.async { [self] in
            do {
                guard isCurrent(generation) else { throw CancellationError() }
                guard installed else { throw LingoError.invalid("نزّل نموذج English → Arabic أولًا") }
                lock.lock(); let alreadyLoaded = engine != nil; lock.unlock()
                if alreadyLoaded { DispatchQueue.main.async { completion(.success(Void())) }; return }
                var error: NSError?
                guard let loaded = GLTranslation(modelPath:folder.path,error:&error) else { throw error ?? LingoError.invalid("تعذر تهيئة النموذج") as NSError }
                lock.lock()
                guard cancellationGeneration == generation else { lock.unlock(); throw CancellationError() }
                engine = loaded; lock.unlock()
                DispatchQueue.main.async { completion(.success(Void())) }
            } catch { DispatchQueue.main.async { completion(.failure(error)) } }
        }
    }
    func cancel() { lock.lock(); cancellationGeneration &+= 1; engine?.cancel(); lock.unlock() }
    func propose(_ source: String, completion: @escaping (Result<String,Error>) -> Void) {
        lock.lock(); let generation = cancellationGeneration; lock.unlock()
        queue.async { [self] in
            do {
                guard isCurrent(generation), !source.isEmpty, source.count <= 1800 else { throw CancellationError() }
                lock.lock(); let current = engine; current?.resume(); lock.unlock()
                var error: NSError?
                guard let current, let output = current.translate(source,error:&error), isCurrent(generation) else { throw error ?? LingoError.invalid("تعذر توليد اقتراح محلي") as NSError }
                completion(.success(output))
            } catch { completion(.failure(error)) }
        }
    }
    private func isCurrent(_ generation: UInt64) -> Bool {
        lock.lock(); defer { lock.unlock() }; return cancellationGeneration == generation
    }
    func translate(_ text: String, category: String = "dialogue", eventID: String? = nil, completion: @escaping (Result<String,Error>,Double) -> Void) {
        translateDetailed(text,category:category,eventID:eventID) { result,latency in completion(result.map(\.text),latency) }
    }
    func translateDetailed(_ text: String, category: String = "dialogue", eventID: String? = nil, completion: @escaping (Result<TranslationDecision,Error>,Double) -> Void) {
        lock.lock(); let generation = cancellationGeneration; lock.unlock()
        queue.async { [self] in
            let start = ProcessInfo.processInfo.systemUptime
            let result: Result<TranslationDecision,Error>
            do {
                guard isCurrent(generation) else { throw CancellationError() }
                let normalized = DialogueText.normalized(text)
                let packKey = packs?.outputKey ?? ""
                if lastPackKey != packKey { cache = BoundedLRU(capacity:256); lastPackKey = packKey }
                let key = Self.modelID+"/"+category+"/commands-v2/en/ar/"+quality.outputKey+"/"+names.outputKey+"/"+corrections.outputKey+"/"+packKey+"/"+normalized
                let selectedGame = packs?.publication("",origin:.rule).game
                let corrected = category == "dialogue" && (packs == nil || corrections.matches(game:selectedGame)) ? corrections.lookup(text) : nil
                let selected = corrected != nil ? packs?.publication(eventID ?? "",origin:.userCorrection) : nil
                let lookup = corrected != nil ? PackLookupOutcome(game:selected?.game,pack:selected?.pack) : packs?.lookupDetailed(text,category:category,eventID:eventID) ?? PackLookupOutcome(fallback:.noDatabase)
                let fallback = category == "dialogue" ? lookup.fallback : TranslationFallback.notDialogue
                func decision(_ value: String, _ origin: TranslationOrigin) -> TranslationDecision {
                    var chosen = TranslationDecision(text:value,origin:origin,fallback:(origin == .argosInference || origin == .argosCache) ? fallback : nil,game:lookup.game,pack:lookup.pack)
                    if quality[.punctuationTrace] || quality[.punctuationRepair] { chosen.punctuationUnbalanced = SourceGuidedPunctuation.unbalanced(value) }
                    return chosen
                }
                if let corrected {
                    packs?.recordAttempt(.userCorrection,game:lookup.game,pack:lookup.pack)
                    result = .success(decision(corrected,.userCorrection))
                } else if let localized = lookup.text {
                    packs?.recordAttempt(lookup.origin,game:lookup.game,pack:lookup.pack)
                    result = .success(decision(localized,lookup.origin))
                } else if category == "menu", let term = MenuTerminology.translation(normalized) {
                    packs?.recordAttempt(.command,game:lookup.game,pack:lookup.pack)
                    result = .success(decision(term,.command))
                } else if let cached = cache.get(key) {
                    let origin = DialogueCommands.cachedOrigin(normalized)
                    packs?.recordAttempt(origin,fallback:origin == .argosCache ? fallback : nil,game:lookup.game,pack:lookup.pack)
                    packs?.recordArgos(); result = .success(decision(cached,origin))
                } else {
                    let planned = DialogueCommands.legacy[DialogueCommands.key(normalized)] == nil ? TranslationOrigin.argosInference : .command
                    // Count requested inference even when it is later cancelled;
                    // publishing has a separate stable-ID ledger.
                    packs?.recordAttempt(planned,fallback:planned == .argosInference ? fallback : nil,game:lookup.game,pack:lookup.pack)
                    packs?.recordArgos()
                    lock.lock()
                    let current = cancellationGeneration == generation ? engine : nil
                    current?.resume()
                    lock.unlock()
                    guard isCurrent(generation) else { throw CancellationError() }
                    guard let current else { throw LingoError.invalid("نموذج الترجمة غير جاهز") }
                    let command = DialogueCommands.value(normalized,sourcePunctuation:quality[.commandPunctuation])
                    var error: NSError?
                    var engineInput: String?, rawOutput: String?
                    func infer(_ input: String) throws -> String {
                        guard isCurrent(generation), let output = current.translate(input,error:&error), !output.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else { throw error ?? LingoError.invalid("الترجمة فارغة") as NSError }
                        if engineDiagnostics { engineInput = input; rawOutput = output }
                        return output
                    }
                    let raw = try command ?? infer(normalized)
                    // Pack entries, explicit corrections and command-map output
                    // retain their own authority. Only model output is repaired.
                    let value = command == nil ? SourceGuidedPunctuation.repair(raw,source:normalized,enabled:quality[.punctuationRepair]).text : raw
                    cache.put(value,for:key)
                    var chosen = decision(value,command == nil ? .argosInference : .command)
                    chosen.engineInput = engineInput; chosen.rawOutput = rawOutput; result = .success(chosen)
                }
            } catch { result = .failure(isCurrent(generation) ? error : CancellationError()) }
            let final = isCurrent(generation) ? result : .failure(CancellationError())
            completion(final,(ProcessInfo.processInfo.systemUptime-start)*1000)
        }
    }
    /// Verify the original package before extraction; extract only the five known files.
    func install(package: URL, completion: @escaping (Result<Void,Error>) -> Void) {
        lock.lock(); let generation = cancellationGeneration; lock.unlock()
        queue.async { [self] in
            do {
                guard isCurrent(generation) else { throw CancellationError() }
                let size = try package.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0
                guard size == Self.modelSize else { throw LingoError.invalid("حجم نموذج الترجمة غير صحيح") }
                let data = try Data(contentsOf:package,options:.mappedIfSafe)
                let digest = SHA256.hash(data:data).map { String(format:"%02x",$0) }.joined()
                guard digest == Self.modelDigest else { throw LingoError.invalid("فشل التحقق من SHA-256 للنموذج") }
                let parent = folder.deletingLastPathComponent()
                try FileManager.default.createDirectory(at:parent,withIntermediateDirectories:true)
                let capacity = try parent.resourceValues(forKeys:[.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage ?? 0
                guard capacity > 300*1024*1024 else { throw LingoError.invalid("لا توجد مساحة كافية لفك الحزمة مع حفظ النموذج السابق") }
                let stage = parent.appendingPathComponent("model-stage-"+UUID().uuidString,isDirectory:true)
                try FileManager.default.createDirectory(at:stage,withIntermediateDirectories:true)
                defer { try? FileManager.default.removeItem(at:stage) }
                let archive = try Archive(url:package,accessMode:.read)
                for file in Self.required {
                    guard isCurrent(generation) else { throw CancellationError() }
                    guard let entry = archive["en_ar/"+file], entry.type == .file, entry.uncompressedSize <= 250*1024*1024 else { throw LingoError.invalid("محتويات حزمة النموذج غير صالحة") }
                    let destination = stage.appendingPathComponent(file)
                    try FileManager.default.createDirectory(at:destination.deletingLastPathComponent(),withIntermediateDirectories:true)
                    _ = try archive.extract(entry,to:destination)
                }
                let metadata = try JSONSerialization.jsonObject(with:Data(contentsOf:stage.appendingPathComponent("metadata.json"))) as? [String:Any]
                guard metadata?["from_code"] as? String == "en", metadata?["to_code"] as? String == "ar" else { throw LingoError.invalid("زوج لغات غير صحيح") }
                guard isCurrent(generation) else { throw CancellationError() }
                if FileManager.default.fileExists(atPath:folder.path) { _ = try FileManager.default.replaceItemAt(folder,withItemAt:stage) }
                else { try FileManager.default.moveItem(at:stage,to:folder) }
                var stored = folder; var values = URLResourceValues(); values.isExcludedFromBackup = true; try stored.setResourceValues(values)
                DispatchQueue.main.async { completion(.success(Void())) }
            } catch { DispatchQueue.main.async { completion(.failure(error)) } }
        }
    }
    func remove(completion: @escaping (Result<Void,Error>) -> Void) {
        cancel()
        queue.async { [self] in
            do {
                lock.lock(); engine = nil; lock.unlock(); cache = BoundedLRU(capacity:256)
                if FileManager.default.fileExists(atPath:folder.path) { try FileManager.default.removeItem(at:folder) }
                DispatchQueue.main.async { completion(.success(Void())) }
            } catch { DispatchQueue.main.async { completion(.failure(error)) } }
        }
    }
}
