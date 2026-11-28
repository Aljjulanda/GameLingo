import Foundation
import CoreVideo

/// Full-screen UI discovery has its own OCR, cadence, storage and generations.
/// It never supplies text to dialogue context/learning and retains at most one frame.
final class SpatialUIPipeline {
    private let queue = DispatchQueue(label:"dev.gamelingo.spatial",qos:.utility)
    private let lock = NSLock()
    private var accepting = false, offered = false, enabled = true
    private var lastOffered = 0.0
    private var epoch = UUID()
    private var game = "general", version = "1"
    private var dialogue = SourceBox.dialogue
    private var frameAspect = 16.0/9.0
    private let translator: OfflineTranslator
    private let publish: ([String:Any]) -> Void
    private let ocr: VisionDialogueOCR
    private var store: SpatialMemoryStore?
    private var rows: [OCRLine] = []
    private var screen: SpatialScreen?
    private var visual = ""
    private var lastScan = 0.0
    private var sourceConfirmed = false, missingScans = 0
    private var working = false
    private var failures = BoundedLRU<String,Bool>(capacity:64)
    private var metrics = SpatialMetrics()
    var onMetrics: ((SpatialMetrics) -> Void)?
    var onRegions: (([SourceBox]) -> Void)?
    init(translator: OfflineTranslator, softwareImageContext: Bool = false, publish: @escaping ([String:Any]) -> Void) {
        self.translator = translator; self.publish = publish
        self.ocr = VisionDialogueOCR(softwareImageContext:softwareImageContext)
    }
    func configure(game: String, version: String, dialogue: SourceBox) {
        queue.async {
            guard self.game != game || self.version != version || self.dialogue != dialogue else { return }
            self.game = game; self.version = version; self.dialogue = dialogue
            self.clear(); self.failures = BoundedLRU(capacity:64)
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
    func stop(completion: (() -> Void)? = nil) {
        lock.lock(); accepting = false; lock.unlock()
        queue.async {
            self.clear(); self.store?.releaseMemory(); self.store = nil
            completion?()
        }
    }
    func memoryPressure() { queue.async { self.store?.releaseMemory(); self.failures = BoundedLRU(capacity:64) } }
    func invalidate() { queue.async { self.clear() } }
    func setEnabled(_ value: Bool) {
        lock.lock(); enabled = value; lock.unlock()
        invalidate()
    }
    private var active: Bool { lock.lock(); defer{lock.unlock()}; return accepting && enabled }
    func offer(_ buffer: CVPixelBuffer, now: Double) {
        lock.lock()
        guard accepting, enabled, !offered, now-lastOffered >= 0.85 else { lock.unlock(); return }
        offered = true; lastOffered = now; lock.unlock()
        queue.async { [self] in
            defer { lock.lock(); offered = false; lock.unlock() }
            guard active else { return }
            frameAspect = Double(CVPixelBufferGetWidth(buffer))/Double(max(1,CVPixelBufferGetHeight(buffer)))
            let hash = FrameSignature.perceptualHash(buffer)
            // Revalidate anchors periodically even with unchanged pixels. Heartbeat
            // leases remain bounded and stop when fresh frames stop arriving.
            if hash == visual, now-lastScan < 1.5, sourceConfirmed, screen != nil { emit(now:now); return }
            let began = ProcessInfo.processInfo.systemUptime
            let lines = (try? autoreleasepool { try ocr.menuLines(buffer,roi:SourceBox(x:0,y:0,w:1,h:1)) }) ?? []
            guard active else { return }
            metrics.scans += 1; visual = hash
            let safe = lines.filter{!TextPrivacy.excluded($0.text)}
            let category = SpatialRecognition.category(safe)
            metrics.category = category.rawValue; metrics.observedRows = safe.count; metrics.selectedRows = 0
            guard category != .gameplay else { missing(); report(); return }
            let observed = SpatialRecognition.rows(safe,dialogue:dialogue,category:category)
            metrics.selectedRows = observed.count
            guard !observed.isEmpty else { missing(); return }
            sourceConfirmed = true; missingScans = 0; lastScan = now
            let fingerprint = SpatialRecognition.fingerprint(observed,category:category)
            let changed = screen?.category != category || !SpatialRecognition.sameObservation(rows,observed)
            rows = observed
            if changed {
                epoch = UUID(); publishClear()
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
        publishClear()
        screen = nil; rows = []; epoch = UUID(); sourceConfirmed = false; missingScans = 0; onRegions?([])
    }
    private func publishClear() {
        if let screen { publish(TVProtocol.envelope("menu_clear",fields:["menu_id":"spatial-"+screen.id])) }
    }
    private func missing() {
        sourceConfirmed = false; missingScans += 1; epoch = UUID()
        // Do not renew the receiver's lease on a failed read. One OCR dropout
        // keeps the existing visual briefly; a second confirms disappearance.
        if missingScans >= 2 { clear() }
    }
    private func translateNext() {
        guard active, sourceConfirmed, !working, let screen, let row = rows.first(where:{ row in
            !screen.elements.contains(where:{$0.normalized == SpatialRecognition.key(row.text)}) && failures.get(self.version+row.text) == nil
        }) else { return }
        let id = epoch, game = game, version = version
        working = true
        translator.translateDetailed(row.text,category:"menu",eventID:nil) { [weak self] result,_ in
            guard let self else { return }
            self.queue.async {
                self.working = false
                guard self.active, self.epoch == id, self.game == game, self.version == version,
                      ProcessInfo.processInfo.systemUptime-self.lastScan < 1.6,
                      self.rows.contains(where:{SpatialRecognition.key($0.text) == SpatialRecognition.key(row.text) && abs($0.box.y-row.box.y)<0.035}) else { self.translateNext(); return }
                if case .success(let decision) = result, SpatialTarget.valid(source:row.text,target:decision.text) {
                    do { try self.store?.saveTranslation(game:game,version:version,source:row.text,target:decision.text,origin:decision.origin.rawValue,now:Date().timeIntervalSince1970) }
                    catch { self.metrics.rejected += 1 }
                    self.screen?.elements.append(self.element(row,target:decision.text,origin:decision.origin.rawValue,category:screen.category))
                    if SpatialRecognition.dynamic(row.text,category:screen.category) { self.metrics.dynamicUpdates += 1 }
                    if let saved = self.screen { try? self.store?.save(saved,version:version) }
                    self.emit(now:ProcessInfo.processInfo.systemUptime)
                } else if case .failure(let error) = result, error is CancellationError {
                    // Dialogue shares the bounded worker. Its cancellation is
                    // not evidence that this menu source is untranslatable.
                } else { self.failures.put(true,for:version+row.text); self.metrics.rejected += 1 }
                self.translateNext(); self.report()
            }
        }
    }
    private func emit(now: Double) {
        guard active, sourceConfirmed, now-lastScan < 1.6, let screen else { return }
        guard let message = SpatialPresentation.snapshot(screen,rows:rows,aspect:frameAspect) else { return }
        publish(message); metrics.published += (message["items"] as? [[String:Any]])?.count ?? 0
    }
    private func report() { let value = metrics; DispatchQueue.main.async { self.onMetrics?(value) } }
}
