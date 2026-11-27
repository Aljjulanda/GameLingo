import Foundation
import CoreVideo

/// Full-screen UI discovery has its own OCR, cadence, storage and generations.
/// It never supplies text to dialogue context/learning and retains at most one frame.
final class SpatialUIPipeline {
    private let queue = DispatchQueue(label:"dev.gamelingo.spatial",qos:.utility)
    private let lock = NSLock()
    private var accepting = false, offered = false
    private var lastOffered = 0.0
    private var epoch = UUID()
    private var game = "general", version = "1"
    private var dialogue = SourceBox.dialogue
    private let translator: OfflineTranslator
    private let publish: ([String:Any]) -> Void
    private let ocr = VisionDialogueOCR()
    private var store: SpatialMemoryStore?
    private var rows: [OCRLine] = []
    private var screen: SpatialScreen?
    private var visual = ""
    private var lastScan = 0.0
    private var working = false
    private var failures = BoundedLRU<String,Bool>(capacity:64)
    private var metrics = SpatialMetrics()
    var onMetrics: ((SpatialMetrics) -> Void)?
    var onRegions: (([SourceBox]) -> Void)?
    init(translator: OfflineTranslator, publish: @escaping ([String:Any]) -> Void) { self.translator = translator; self.publish = publish }
    func configure(game: String, version: String, dialogue: SourceBox) {
        queue.async {
            guard self.game != game || self.version != version || self.dialogue != dialogue else { return }
            self.game = game; self.version = version; self.dialogue = dialogue
            self.epoch = UUID(); self.rows = []; self.screen = nil; self.failures = BoundedLRU(capacity:64)
            self.publish(TVProtocol.envelope("menu_clear"))
        }
    }
    func start() {
        lock.lock(); accepting = true; lastOffered = 0; lock.unlock()
        queue.async {
            self.epoch = UUID(); self.metrics = SpatialMetrics()
            if self.store == nil {
                let root = FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("SpatialUI",isDirectory:true)
                do {
                    self.store = try SpatialMemoryStore(url:root.appendingPathComponent("screens.sqlite"))
                    try FileManager.default.setAttributes([.protectionKey:FileProtectionType.completeUntilFirstUserAuthentication],ofItemAtPath:root.path)
                    var folder = root; var flags = URLResourceValues(); flags.isExcludedFromBackup = true; try folder.setResourceValues(flags)
                } catch { self.metrics.rejected += 1 }
            }
        }
    }
    func stop() {
        lock.lock(); accepting = false; lock.unlock()
        queue.async {
            self.epoch = UUID(); self.rows = []; self.screen = nil; self.store?.releaseMemory(); self.store = nil
            self.publish(TVProtocol.envelope("menu_clear")); self.onRegions?([])
        }
    }
    func memoryPressure() { queue.async { self.store?.releaseMemory(); self.failures = BoundedLRU(capacity:64) } }
    func invalidate() { queue.async { self.clear() } }
    private var active: Bool { lock.lock(); defer{lock.unlock()}; return accepting }
    func offer(_ buffer: CVPixelBuffer, now: Double) {
        lock.lock()
        guard accepting, !offered, now-lastOffered >= 0.85 else { lock.unlock(); return }
        offered = true; lastOffered = now; lock.unlock()
        queue.async { [self] in
            defer { lock.lock(); offered = false; lock.unlock() }
            guard active else { return }
            let hash = FrameSignature.perceptualHash(buffer)
            // Revalidate anchors periodically even with unchanged pixels. Heartbeat
            // leases remain bounded and stop when fresh frames stop arriving.
            if hash == visual, now-lastScan < 1.5, screen != nil { emit(now:now); return }
            let began = ProcessInfo.processInfo.systemUptime
            let lines = (try? autoreleasepool { try ocr.menuLines(buffer,roi:SourceBox(x:0,y:0,w:1,h:1)) }) ?? []
            guard active else { return }
            metrics.scans += 1; visual = hash; lastScan = now
            let safe = lines.filter{!TextPrivacy.excluded($0.text)}
            let category = SpatialRecognition.category(safe)
            guard category != .gameplay else { clear(); report(); return }
            rows = SpatialRecognition.rows(safe,dialogue:dialogue)
            guard !rows.isEmpty else { clear(); return }
            let fingerprint = SpatialRecognition.fingerprint(rows,category:category)
            if screen?.fingerprint != fingerprint {
                epoch = UUID(); publish(TVProtocol.envelope("menu_clear"))
                if let known = try? store?.recognize(game:game,version:version,rows:rows,category:category) {
                    screen = known; metrics.recognized += 1
                } else {
                    screen = SpatialScreen(game:game,gameVersion:"unknown",id:fingerprint,fingerprint:fingerprint,category:category,visualHash:hash,elements:[],observed:Date().timeIntervalSince1970)
                    metrics.discoveries += 1
                }
            }
            // Each element must still exist at its current location. Even an
            // ambiguous screen match can only recall an exact source translation.
            var elements: [SpatialElement] = []
            for row in rows {
                if let cached = try? store?.translation(game:game,version:version,source:row.text) {
                    metrics.cacheHits += 1
                    elements.append(element(row,target:cached.0,origin:cached.1,category:category))
                } else { metrics.misses += 1 }
            }
            screen?.elements = elements; screen?.fingerprint = fingerprint; screen?.observed = Date().timeIntervalSince1970; screen?.uses += 1
            if let screen { try? store?.save(screen,version:version) }
            onRegions?(rows.map(\.box)); emit(now:now)
            metrics.recall.record((ProcessInfo.processInfo.systemUptime-began)*1000)
            translateNext(); report()
        }
    }
    private func element(_ row: OCRLine, target: String, origin: String, category: ScreenCategory) -> SpatialElement {
        SpatialElement(source:row.text,normalized:SpatialRecognition.key(row.text),translated:target,box:row.box,scale:row.box.h,dynamic:SpatialRecognition.dynamic(row.text,category:category),origin:origin,confidence:min(0.99,row.confidence))
    }
    private func clear() {
        if screen != nil { publish(TVProtocol.envelope("menu_clear")) }
        screen = nil; rows = []; epoch = UUID(); onRegions?([])
    }
    private func translateNext() {
        guard active, !working, let screen, let row = rows.first(where:{ row in
            !screen.elements.contains(where:{$0.normalized == SpatialRecognition.key(row.text)}) && failures.get(self.version+row.text) == nil
        }) else { return }
        let id = epoch, game = game, version = version
        working = true
        translator.translateDetailed(row.text,category:"menu",eventID:nil) { [weak self] result,_ in
            guard let self else { return }
            self.queue.async {
                self.working = false
                guard self.active, self.epoch == id, self.game == game, self.version == version else { self.translateNext(); return }
                if case .success(let decision) = result, SpatialTarget.valid(source:row.text,target:decision.text) {
                    do { try self.store?.saveTranslation(game:game,version:version,source:row.text,target:decision.text,origin:decision.origin.rawValue,now:Date().timeIntervalSince1970) }
                    catch { self.metrics.rejected += 1 }
                    self.screen?.elements.append(self.element(row,target:decision.text,origin:decision.origin.rawValue,category:screen.category))
                    if SpatialRecognition.dynamic(row.text,category:screen.category) { self.metrics.dynamicUpdates += 1 }
                    if let saved = self.screen { try? self.store?.save(saved,version:version) }
                    self.emit(now:ProcessInfo.processInfo.systemUptime)
                } else { self.failures.put(true,for:version+row.text); self.metrics.rejected += 1 }
                self.translateNext(); self.report()
            }
        }
    }
    private func emit(now: Double) {
        guard active, now-lastScan < 1.6, let screen else { return }
        let items = screen.elements.compactMap { element -> [String:Any]? in
            guard let current = rows.first(where:{SpatialRecognition.key($0.text) == element.normalized}) else { return nil }
            return ["id":SpatialRecognition.hash(element.normalized),"translated":SubtitlePresentation.clean(element.translated),"source":element.source,
                    "box":["x":current.box.x,"y":current.box.y,"w":current.box.w,"h":current.box.h],"alignment":element.alignment,"scale":element.scale,"dynamic":element.dynamic]
        }
        // The existing authenticated menu protocol is extended additively.
        var bounded = Array(items.prefix(24))
        var message: [String:Any]
        repeat {
            message = TVProtocol.envelope("menu_snapshot",fields:["menu_id":"spatial-"+screen.id,"items":bounded,"appearance":["side":"right","fontSize":22,"background":true,"outline":true,"shadow":false],"spatial":true,"frame_aspect":16.0/9.0,"lease_ms":1800])
            if let data = try? TVProtocol.encode(message), data.count <= 14000 { break }
            if bounded.isEmpty { return }; bounded.removeLast()
        } while true
        publish(message); metrics.published += bounded.count
    }
    private func report() { let value = metrics; DispatchQueue.main.async { self.onMetrics?(value) } }
}
