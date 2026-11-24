import Foundation
import CoreVideo
import CoreImage

struct PipelineMetrics {
    var lastFrameAt: Double?, lastOCRAt: Double?, lastTranslationAt: Double?
    var ocrMilliseconds = 0.0, translationMilliseconds = 0.0, frameMilliseconds = 0.0, samplingRate = 0.0
    var actualOCRRate = 0.0
    var frames: UInt64 = 0, dropped: UInt64 = 0
    var recognitions: UInt64 = 0
    var queueDepth = 0
    var contextEntries = 0
    var translationP95 = 0.0, ocrP95 = 0.0
    var documentMilliseconds = 0.0, documentOCRMilliseconds = 0.0, documentTranslationMilliseconds = 0.0, documentExtraMegabytes = 0.0
    var documentCompleted = 0, documentTotal = 0
    var duplicatesSuppressed = 0, correctionsMerged = 0, speakersDetected = 0, speakersUncertain = 0
    var punctuationTrace = ""
    var speakerHidden = 0
    var nameConfidence = ""
}

final class FramePipeline {
    var onMetrics: ((PipelineMetrics) -> Void)?
    var onError: ((String) -> Void)?
    var onCurrentMenu: ((UUID,CurrentMenuReadout) -> Void)?
#if DEBUG
    // Native synthetic fixtures opt in. No production hook, logger, or capture.
    var onCurrentMenuObservation: (([OCRLine],SourceBox,Double,Double) -> Void)?
    var onCurrentMenuFrameProof: ((Double,Bool,Double) -> Void)?
#endif
    var onReading: ((UUID,Bool,[String],String) -> Void)?
    var onPreview: ((CGImage,[OCRLine]) -> Void)?
    var onLearningExample: ((ImprovementExample) -> Void)?
    private var learningConsent = false
    private var improvedMemory = ImprovedMemorySnapshot()
    func configureLearning(_ enabled: Bool) { queue.async { self.learningConsent = enabled } }
    func configureImprovedMemory(_ value: ImprovedMemorySnapshot) { queue.async { self.improvedMemory = value; self.translations = BoundedLRU(capacity:8) } }
    private func learningContext(source: String, speaker: String?) -> String {
        let previous = memory.entries.filter{$0.confidence >= 0.9 && DialogueText.normalized($0.source) != DialogueText.normalized(source)}.suffix(2)
        guard !previous.isEmpty else { return "" }
        return String(((speaker ?? "-")+"|"+previous.map{($0.speaker ?? "-")+":"+$0.source}.joined(separator:"|")).prefix(4096))
    }
    private var previewRequested = false
    private var setupRequested = false
    private var setupRegion = GameOptions().menuRegion
    private var previewEnabled = false
    private var manualRegion = false
    private struct MenuContext { var id: String; var region: SourceBox; var appearance: MenuAppearance }
    private var currentMenu = CurrentMenuSession()
    private var currentMenuLastSample = 0.0
    private var currentMenuAspect = 16.0/9.0
    private var menuFailures = Set<String>()
    private var currentMenuColors: [String:String] = [:]
    private var menuOptions = GameOptions()
    private var menuItems: [MenuOverlayItem] = []
    private var menuReadings: [OCRLine] = []
    private var menuIdentity: String?
    private var menuEpoch = UUID()
    private var menuWorking = false
    private var menuCache = BoundedLRU<String,String>(capacity:128)
    private var menuLastSeen = 0.0
    private var menuLastPublished = 0.0
    private let previewContext = CIContext(options:[.cacheIntermediates:false])
    func setPreview(_ enabled: Bool) { queue.async { self.previewEnabled = enabled; self.previewRequested = enabled } }
    func requestSetupFrame(region: SourceBox) { queue.async { self.setupRegion = region; self.setupRequested = true; self.previewRequested = true } }
    func configureRegion(_ value: SourceBox, manual: Bool) {
        guard value.isValid else { return }
        translator.cancel()
        queue.async { [self] in
            finishCurrentMenu("تغيرت منطقة المصدر؛ أعد طلب القائمة")
            roi = value; manualRegion = manual; ocr.strictRegion = manual
            runID = UUID(); pending = nil; tracker.reset(); memory.clear(); stability.clear(); translations = BoundedLRU(capacity:8); signature = FrameSignature()
            publish(TVProtocol.envelope("subtitle_clear"))
        }
    }
    func configureMenus(_ value: GameOptions) {
        queue.async { [self] in
            if menuOptions.menuRegion != value.menuRegion || menuOptions.allowedMenus != value.allowedMenus || menuOptions.menusEnabled != value.menusEnabled {
                finishCurrentMenu("تغيرت إعدادات القوائم؛ أعد الطلب")
            }
            menuOptions = value; menuFailures = []; menuEpoch = UUID(); menuIdentity = nil; menuItems = []; menuReadings = []; menuCache = BoundedLRU(capacity:128)
            publish(TVProtocol.envelope("menu_clear"))
        }
    }
    private let translator: OfflineTranslator
    private let publish: ([String:Any]) -> Void
    private let queue = DispatchQueue(label:"dev.gamelingo.ocr",qos:.userInitiated)
    private let slotLock = NSLock()
    private var latest: (CVPixelBuffer,TimeInterval,Int64)?
    private var lastArrival = 0.0
    var frameAge: TimeInterval {
        slotLock.lock(); defer { slotLock.unlock() }
        return lastArrival > 0 ? ProcessInfo.processInfo.systemUptime-lastArrival : .infinity
    }
    private var active = false
    private var runID = UUID()
    private var roi = SourceBox.dialogue
    private var mode = PerformanceMode.balanced
    private var thermal = 0, lowPower = false
    private var timer: DispatchSourceTimer?
    private var ocr: VisionDialogueOCR
    private let softwareImageContext: Bool
    private var signature = FrameSignature()
    private var tracker = DialogueTracker()
    private var advanced = AdvancedSettings()
    private var quality = QualitySettings()
    // Deferred research is compile-time excluded from this production preview.
#if GAMELINGO_TYPEWRITER_RESEARCH
    private var typewriter = TypewriterPublication()
    private var typewriterScope: String?
    private var heldPublication: (job:DialogueJob,deliver:()->Void)?
    var onTypewriterDetected: ((String) -> Void)?
#endif
    private var namesStore: GameNamesStore?
    private var namesSnapshot = GameNamesSnapshot(game:"general")
    private var namesWords = ""
    private var speakerWords = ""
    private var namesByKey: [String:String] = [:]
    private var namesConfigured = false
    private var namesCacheKey: String { namesSnapshot.outputKey }
    private var correctionSnapshot = CorrectionsSnapshot(game:"general",general:true)
    private var corrections = CorrectionContext(CorrectionsSnapshot(game:"general",general:true),enabled:false)
    private var recentToken = UUID()
    var onRecentPublished: ((RecentPublishedLine,UUID) -> Void)?
    private var advancedEpoch: UInt64 = 0
    private var translationsContextKey = ""
    private var outputContextKey: String { namesCacheKey+"|"+corrections.outputKey+"|"+quality.outputKey+"|\(advancedEpoch)|"+(translator.packs?.outputKey ?? "") }
    func configureCorrections(_ snapshot: CorrectionsSnapshot, recentToken: UUID? = nil, completion: (() -> Void)? = nil) { queue.async {
        if let recentToken { self.recentToken = recentToken }
        let sameScope = self.correctionSnapshot.scopeKey == snapshot.scopeKey
        let oldKey = self.corrections.outputKey
        self.correctionSnapshot = snapshot
        let context = CorrectionContext(snapshot,enabled:self.quality[.corrections])
        if self.corrections.outputKey != context.outputKey { self.translations = BoundedLRU(capacity:8) }
        self.corrections = context; self.translator.configureCorrections(snapshot,enabled:self.quality[.corrections])
#if GAMELINGO_TYPEWRITER_RESEARCH
        if oldKey != context.outputKey { self.retryHeldPublication(sameScope:sameScope) }
#endif
        completion?()
    } }
    func configureNames(_ store: GameNamesStore?, snapshot: GameNamesSnapshot) { queue.async {
        let changed = self.namesCacheKey != snapshot.outputKey, sameScope = self.namesSnapshot.scopeKey == snapshot.scopeKey
        self.namesStore = store
        self.applyNames(snapshot)
#if GAMELINGO_TYPEWRITER_RESEARCH
        if changed { self.retryHeldPublication(sameScope:sameScope) }
#endif
    } }
#if GAMELINGO_TYPEWRITER_RESEARCH
    private func retryHeldPublication(sameScope: Bool) {
        guard let held = heldPublication else { return }
        heldPublication = nil
        if sameScope && isActive() && !reading && tracker.accepts(held.job) {
            if pending == nil { pending = held.job }
            submit()
        }
    }
#endif
    private func applyNames(_ snapshot: GameNamesSnapshot) {
        if !namesConfigured || namesSnapshot.outputKey != snapshot.outputKey {
            let effective = snapshot.effective(packLabels:quality[.packLabels])
            translations = BoundedLRU(capacity:8); namesWords = effective.words; speakerWords = effective.speakerWords
            namesByKey = Dictionary(uniqueKeysWithValues:effective.entries.map{($0.id,$0.arabic)})
            namesConfigured = true
        }
        namesSnapshot = snapshot
        translator.configureNames(snapshot)
    }
    private let capture = QualityCapture(folder:FileManager.default.urls(for:.cachesDirectory,in:.userDomainMask)[0].appendingPathComponent("QualityCapture",isDirectory:true))
    var onCaptureState: ((Bool,URL?) -> Void)?
    private var captureGeneration = UUID()
    private var pendingCapture: [CaptureLine] = []
    private var pendingSegments: [CaptureLine] = []
    func configureQuality(_ value: QualitySettings) { queue.async {
        let outputChanged = self.quality.outputKey != value.outputKey
        if outputChanged { self.translations = BoundedLRU(capacity:8) }
#if GAMELINGO_TYPEWRITER_RESEARCH
        if self.quality[.typewriter] != value[.typewriter] { self.typewriter = TypewriterPublication(); self.typewriterScope = nil }
#endif
        if self.quality[.packLabels] != value[.packLabels] { self.namesConfigured = false }
        self.quality = value; self.ocr.quality = value; self.ocr.qualityTrace = value[.punctuationTrace]
        self.corrections = CorrectionContext(self.correctionSnapshot,enabled:value[.corrections])
        self.translator.configureCorrections(self.correctionSnapshot,enabled:value[.corrections])
        self.applyNames(self.namesSnapshot)
        self.translator.configureQuality(value)
        self.translator.packs?.configureQuality(PackQualityOptions(value))
        self.translator.configureEngineDiagnostics(value[.punctuationTrace] || self.capture.active)
#if GAMELINGO_TYPEWRITER_RESEARCH
        if outputChanged { self.retryHeldPublication(sameScope:true) }
        else if value.settleSeconds == 0, let held = self.heldPublication { self.heldPublication = nil; held.deliver() }
#endif
        if !value[.sessionCapture] { self.capture.stop(); self.ocr.captureLines = false; self.reportCapture() }
    } }
    func captureAction(start: Bool = false, delete: Bool = false) {
        queue.async { [self] in
            captureGeneration = UUID(); let ticket = captureGeneration
            do { if delete { try capture.delete() } else if start && quality[.sessionCapture] { try capture.start(consent:true) } else { capture.stop() } }
            catch { DispatchQueue.main.async { self.onError?("تعذر حفظ تسجيل الاختبار المحلي") } }
            ocr.captureLines = capture.active
            translator.configureEngineDiagnostics(quality[.punctuationTrace] || capture.active)
            reportCapture()
            if capture.active { queue.asyncAfter(deadline:.now()+1800) { [weak self] in
                guard let self, self.captureGeneration == ticket else { return }
                self.capture.stop(); self.ocr.captureLines = false; self.reportCapture()
            } }
        }
    }
    private func reportCapture() {
        translator.configureEngineDiagnostics(quality[.punctuationTrace] || capture.active)
        let active = capture.active, file = capture.export()
        DispatchQueue.main.async { self.onCaptureState?(active,file) }
    }
    private var packSpeakerNames = ""
    private var memory = DialogueMemory()
    private var stability = PublicationStability()
    private var translations = BoundedLRU<String,(String,String,TranslationDecision)>(capacity:8)
    private var isBackground = false
    private var reading = false, captureRequested = false
    private var readingTicket = UUID()
    private var documentStarted = 0.0
    private var documentResident: UInt64 = 0
    private var pending: DialogueJob?
    private var translating = false
    private var lastSample = 0.0
    private var lastMetrics = 0.0
    private var lastTextChange = 0.0
    private var startedAt = 0.0
    private var metrics = PipelineMetrics()
    private var translationSamples = LatencySamples(), ocrSamples = LatencySamples()
    private var lastContextPrune = 0.0
    init(translator: OfflineTranslator, softwareImageContext: Bool = false, publish: @escaping ([String:Any]) -> Void) {
        self.translator = translator; self.publish = publish; self.softwareImageContext = softwareImageContext
        self.ocr = VisionDialogueOCR(softwareImageContext:softwareImageContext)
    }

    /// Decode callback retains one buffer; it never allocates one OCR task per received frame.
    func offer(_ buffer: CVPixelBuffer) {
        slotLock.lock(); defer { slotLock.unlock() }
        guard active else { return }
        if latest != nil { metricsDropped &+= 1 }
        let received = ProcessInfo.processInfo.systemUptime
        lastArrival = received; latest = (buffer,received,TVHub.now())
    }
    private var metricsDropped: UInt64 = 0
    private func isActive() -> Bool { slotLock.lock(); defer { slotLock.unlock() }; return active }
    func start(roi: SourceBox, mode: PerformanceMode, preservingState: Bool = false) {
        queue.async { [self] in
            guard roi.isValid else { return }
            reset(preservingState:preservingState); self.roi = roi; self.mode = mode; runID = UUID(); lastSample = 0; lastTextChange = 0
            if !preservingState { metrics = PipelineMetrics() }
            if !preservingState { translationSamples = LatencySamples(); ocrSamples = LatencySamples() }
            if !preservingState || startedAt == 0 { startedAt = ProcessInfo.processInfo.systemUptime }
            slotLock.lock(); active = true; metricsDropped = 0; slotLock.unlock()
            let timer = DispatchSource.makeTimerSource(queue:queue)
            timer.schedule(deadline:.now(),repeating:.milliseconds(50),leeway:.milliseconds(10))
            timer.setEventHandler { [weak self] in self?.sample() }; self.timer = timer; timer.resume()
        }
    }
    func configure(mode: PerformanceMode, thermal: Int, lowPower: Bool) {
        queue.async { [self] in self.mode = mode; self.thermal = thermal; self.lowPower = lowPower }
    }
    func setBackground(_ value: Bool) { queue.async { [self] in isBackground = value; ocr.setBackground(value) } }
    func configureAdvanced(_ value: AdvancedSettings) {
        queue.async { [self] in
            if advanced != value { advancedEpoch &+= 1; translations = BoundedLRU(capacity:8) }
            advanced = value; memory.enabled = value.contextEnabled; memory.capacity = value.contextCapacity
            memory.prune(now:ProcessInfo.processInfo.systemUptime)
        }
    }
    func configurePackNames(_ names: String) { queue.async { self.packSpeakerNames = String(names.prefix(2000)) } }
    func interrupt() { translator.cancel(); queue.async { [self] in
        finishReading(); finishCurrentMenu("انقطع المصدر؛ أعد طلب القائمة بعد عودة البث")
#if GAMELINGO_TYPEWRITER_RESEARCH
        heldPublication = nil; typewriter = TypewriterPublication(); typewriterScope = nil
#endif
        runID = UUID(); tracker.markInterrupted(); pending = nil; publish(TVProtocol.envelope("subtitle_clear"))
        slotLock.lock(); latest = nil; slotLock.unlock()
    } }
    /// Called from the hub queue; inference never synchronously waits on that queue.
    func tvDisconnected() { translator.cancel(); queue.sync { [self] in
        finishReading(message:"انقطع اتصال التلفزيون أثناء القراءة")
#if GAMELINGO_TYPEWRITER_RESEARCH
        heldPublication = nil; typewriter = TypewriterPublication(); typewriterScope = nil
#endif
        // Keep the observed dialogue identity so reconnecting does not retranslate/replay it.
        // Invalidate all in-flight publications and discard pending work.
        runID = UUID(); pending = nil
        tracker.markInterrupted()
    } }
    func stop(completion: (() -> Void)? = nil) {
        queue.async { self.capture.stop(); self.ocr.captureLines = false; self.reportCapture() }
        translator.cancel()
        slotLock.lock(); active = false; latest = nil; slotLock.unlock()
        // Optional queue-drain notification lets native tests retire their
        // in-flight Vision request before beginning the next fixture. Existing
        // callers retain the same asynchronous Stop behavior.
        queue.async { [self] in
            slotLock.lock(); active = false; latest = nil; slotLock.unlock()
            reset(); publish(TVProtocol.envelope("subtitle_clear")); completion?()
        }
    }
    func pause() {
        translator.cancel()
        slotLock.lock(); active = false; latest = nil; slotLock.unlock()
        queue.async { [self] in reset(preservingState:true); publish(TVProtocol.envelope("subtitle_clear")) }
    }
    private func reset(preservingState: Bool = false) {
        finishReading(); finishCurrentMenu("توقفت الجلسة أو تغير المصدر")
#if GAMELINGO_TYPEWRITER_RESEARCH
        heldPublication = nil; typewriter = TypewriterPublication(); typewriterScope = nil
#endif
        timer?.cancel(); timer = nil; runID = UUID(); pending = nil; pendingCapture = []; pendingSegments = []; ocr = VisionDialogueOCR(softwareImageContext:softwareImageContext); ocr.setBackground(isBackground); ocr.qualityTrace = quality[.punctuationTrace]; ocr.captureLines = capture.active; signature = FrameSignature()
        ocr.quality = quality
        ocr.strictRegion = manualRegion
        menuEpoch = UUID(); menuIdentity = nil; menuItems = []; menuReadings = []; menuCache = BoundedLRU(capacity:128)
        publish(TVProtocol.envelope("menu_clear"))
        if preservingState { tracker.markInterrupted(); memory.prune(now:ProcessInfo.processInfo.systemUptime) }
        else { tracker.reset(); memory.clear(); stability.clear(); translations = BoundedLRU(capacity:8) }
        // An already running inference still owns the single worker until its callback.
    }
    private func sample() {
        let now = ProcessInfo.processInfo.systemUptime
        let menuTicket = currentMenu.ticket
        if currentMenu.active, currentMenu.expire(now:now,sourceAge:frameAge), let ticket = menuTicket {
            translator.cancel(); clearMenu(); resetDialogueAfterMenu()
            reportCurrentMenu(ticket:ticket)
        }
        if now-lastContextPrune >= 5 { memory.prune(now:now); lastContextPrune = now }
        let rate = mode.samplingRate(thermal:thermal,lowPower:lowPower)
        metrics.samplingRate = rate
        guard rate > 0 else { return }
        let interval = max(1/rate,now-lastTextChange > 2 ? 0.35 : 0)
        guard now-lastSample >= interval else { return }
        slotLock.lock(); let frame = latest; latest = nil; let dropped = metricsDropped; slotLock.unlock()
        guard let (buffer,received,stamp) = frame else { return }
        guard now-received < 1 else { return }
        lastSample = now; metrics.frames &+= 1; metrics.dropped = dropped
        metrics.lastFrameAt = received
        if previewEnabled || previewRequested {
            previewRequested = false
            let lines = setupRequested ? (try? ocr.menuLines(buffer,roi:setupRegion)) ?? [] : []
            setupRequested = false
            let image = CIImage(cvPixelBuffer:buffer)
            if let cg = previewContext.createCGImage(image,from:image.extent) { DispatchQueue.main.async { self.onPreview?(cg,lines) } }
        }
        if currentMenu.active && !reading {
            processCurrentMenu(buffer,received:received,now:now)
            return // Dialogue resumes from the next fresh frame, never this menu frame.
        }
        if menuOptions.menusEnabled && !reading { processMenu(buffer,now:now) }
        else if !menuItems.isEmpty { clearMenu() }
        if reading {
            if captureRequested {
                captureRequested = false
                do {
                    let paragraphs = try autoreleasepool { try ocr.document(buffer) }
                    guard isActive() else { return }
                    metrics.documentOCRMilliseconds = (ProcessInfo.processInfo.systemUptime-now)*1000
                    guard paragraphs.reduce(0,{ $0+$1.count }) <= 16000 else {
                        finishReading(message:"النص طويل جدًا؛ اعرض المستند على أجزاء أصغر ثم أعد القراءة"); return
                    }
                    let chunks = DocumentText.chunks(paragraphs)
                    metrics.documentTotal = chunks.count; reportDocumentMetrics()
                    guard !chunks.isEmpty else { finishReading(message:"لم يُعثر على نص إنجليزي واضح"); return }
                    translateDocument(chunks,index:0,translated:[],epoch:runID)
                } catch { finishReading(message:"تعذرت قراءة النص من الإطار") }
            }
            return
        }
        let changed = signature.shouldRecognize(buffer,roi:roi,now:now,hasText:tracker.current != nil)
        // Confirmation is a real OCR read of a fresh offered frame, through the
        // unchanged sampling pacer above. A bitmap hash never counts as a read.
#if GAMELINGO_TYPEWRITER_RESEARCH
        guard changed || (quality[.typewriter] && typewriter.needsConfirmation) else { return }
#else
        guard changed else { return }
#endif
        do {
            let names = advanced.speakerNames+","+packSpeakerNames
            let storedNames = quality[.learnNames] ? speakerWords : ""
            let (_,box) = try autoreleasepool { try ocr.recognize(buffer,roi:roi,knownNames:names+","+storedNames,dictionaryNames:names+","+namesWords) }
            guard isActive() else { return }
            let content = ocr.content
            if learningConsent, namesSnapshot.game != "general", !content.text.isEmpty {
                let example = ImprovementExample(game:namesSnapshot.game,source:content.text,context:learningContext(source:content.text,speaker:content.speaker),confidence:ocr.confidence)
                DispatchQueue.main.async { self.onLearningExample?(example) }
            }
            if capture.active {
                let raw = ocr.lastLines.map{CaptureLine(text:$0.text,box:$0.box,confidence:$0.confidence)}
                let segments = ocr.lastSegments.map{CaptureLine(text:$0.text,box:$0.box,confidence:$0.confidence)}
                do { try capture.append(QualityCaptureRecord(eventID:capture.observationID(),lines:raw,parsed:content.text,engineInput:"",engineOutput:"",origin:nil,stage:.observation,timestamp:capture.elapsed,segments:segments)) }
                catch { capture.stop() }
                if !capture.active { ocr.captureLines = false; reportCapture() }
            }
            if content.speaker != nil { metrics.speakersDetected += 1 }
            if content.uncertainSpeaker { metrics.speakersUncertain += 1 }
            if content.speakerHidden { metrics.speakerHidden += 1 }
            if quality[.speakerClassification] || quality[.visionNames] { metrics.nameConfidence = ocr.nameConfidence.summary }
            metrics.punctuationTrace = quality[.punctuationTrace] ? "OCR " + ocr.punctuationTrace + " | parsed " + SubtitlePresentation.punctuation(content.text) : ""
            metrics.recognitions &+= 1
            metrics.lastOCRAt = ProcessInfo.processInfo.systemUptime
            metrics.actualOCRRate = Double(metrics.recognitions)/max(0.001,ProcessInfo.processInfo.systemUptime-startedAt)
            metrics.ocrMilliseconds = (ProcessInfo.processInfo.systemUptime-now)*1000
            ocrSamples.record(metrics.ocrMilliseconds); metrics.ocrP95 = ocrSamples.p95
            metrics.contextEntries = memory.entries.count
#if GAMELINGO_TYPEWRITER_RESEARCH
            if quality[.typewriter] {
                let selectedGame: String?
                if let packs = translator.packs { selectedGame = packs.publication("",origin:.rule).game }
                else { selectedGame = namesConfigured && namesSnapshot.general != true ? namesSnapshot.game : nil }
                let scope = selectedGame ?? ""
                if typewriterScope != scope {
                    typewriter = TypewriterPublication(knownTypewriter:selectedGame.map{quality.typewriterGames.contains($0)} ?? false)
                    typewriterScope = scope; heldPublication = nil
                }
                let alreadyDetected = typewriter.detected
                let observed = TypewriterReading(text:content.text,speaker:content.speaker,box:box,confidence:ocr.confidence)
                let ready = typewriter.observe(observed,now:now,enabled:!(content.engineText == "" && content.cue != nil),maxWait:quality.settleSeconds,window:quality.typewriterWindow)
                // Flush a completed result before the unchanged tracker advances
                // source identity. The TV retains its existing minimum/grace.
                if let held = heldPublication, TypewriterPublication.canFlush(held.job,ready:ready,current:observed) { heldPublication = nil; held.deliver() }
                if !alreadyDetected && typewriter.detected, let selectedGame, quality.rememberTypewriter(game:selectedGame) {
                    DispatchQueue.main.async { self.onTypewriterDetected?(selectedGame) }
                }
            }
#endif
            switch tracker.observe(text:content.text,box:box,now:now,frameMilliseconds:stamp,speaker:content.speaker,confidence:ocr.confidence) {
            case .unchanged: break
            case .gone(let id):
                translator.cancel(); pending = nil; publish(TVProtocol.envelope("subtitle_source_gone",fields:["id":id])); lastTextChange = now
            case .dialogue(var job,let previous):
                job.engineText = content.engineText; job.cue = content.cue
                if quality[.learnNames], let speaker = content.speaker, let form = content.labelForm, let namesStore {
                    do {
                        if try namesStore.learn(speaker,form:form,confidence:content.speakerConfidence ?? ocr.confidence,eventID:job.id,colonThreshold:quality.colonNameThreshold,otherThreshold:quality.otherNameThreshold) { applyNames(namesStore.snapshot) }
                    } catch { DispatchQueue.main.async { self.onError?("تعذر حفظ الاسم المتعلّم؛ يستمر الحوار دون تغيير") } }
                }
                if quality[.learnNames], let speaker = job.speaker { job.speakerArabic = namesByKey[GameName.key(speaker)] }
                translator.packs?.recordDialogue(job.id)
                if let previous { publish(TVProtocol.envelope("subtitle_source_gone",fields:["id":previous])) }
                guard stability.shouldPublish(job) else { memory.observe(job,now:now); break }
                if !job.correction { translator.cancel() }
                pendingCapture = capture.active ? ocr.lastLines.map{ CaptureLine(text:$0.text,box:$0.box,confidence:$0.confidence) } : []
                pendingSegments = capture.active ? ocr.lastSegments.map{ CaptureLine(text:$0.text,box:$0.box,confidence:$0.confidence) } : []
                pending = job; lastTextChange = now; submit()
            }
#if GAMELINGO_TYPEWRITER_RESEARCH
            if let held = heldPublication, tracker.current?.id != held.job.id { heldPublication = nil }
#endif
            metrics.duplicatesSuppressed = tracker.duplicatesSuppressed
            metrics.correctionsMerged = tracker.correctionsMerged
            metrics.frameMilliseconds = (ProcessInfo.processInfo.systemUptime-received)*1000
            metrics.queueDepth = (translating ? 1 : 0)+(pending == nil ? 0 : 1)
            if now-lastMetrics >= 1 { lastMetrics = now; let value = metrics; DispatchQueue.main.async { self.onMetrics?(value) } }
        } catch { DispatchQueue.main.async { self.onError?(error.localizedDescription) } }
    }
    func requestCurrentMenu(ticket: UUID) {
        translator.cancel()
        queue.async { [self] in
            guard isActive(), !reading else {
                let state = CurrentMenuReadout(status:"البث غير جاهز للقائمة أو قراءة المستند مفتوحة؛ أعد الطلب بعد تجهيز الجلسة")
                DispatchQueue.main.async { self.onCurrentMenu?(ticket,state) }; return
            }
            finishCurrentMenu()
            clearMenu(); resetDialogueAfterMenu()
            currentMenu.request(ticket,now:ProcessInfo.processInfo.systemUptime)
            currentMenuLastSample = 0; menuFailures = []
            slotLock.lock(); latest = nil; slotLock.unlock()
            publish(TVProtocol.envelope("subtitle_clear"))
            reportCurrentMenu(ticket:ticket)
        }
    }
    func closeCurrentMenu() { queue.async { self.finishCurrentMenu() } }
    private func resetDialogueAfterMenu() {
        runID = UUID(); pending = nil; tracker.reset(); memory.clear(); stability.clear(); signature = FrameSignature()
    }
    private func finishCurrentMenu(_ message: String = "أُغلقت القائمة؛ عاد مسار الحوار") {
        guard let ticket = currentMenu.ticket else { return }
        translator.cancel()
        slotLock.lock(); latest = nil; slotLock.unlock()
        currentMenu.close(message); clearMenu(); resetDialogueAfterMenu(); reportCurrentMenu(ticket:ticket)
    }
    private func currentMenuContext() -> MenuContext? {
        guard let ticket = currentMenu.ticket else { return nil }
        return MenuContext(id:"current-"+ticket.uuidString,region:currentMenu.region ?? SourceBox(x:0,y:0,w:1,h:1),appearance:menuOptions.currentMenuAppearance ?? MenuAppearance())
    }
    private func currentMenuTranslations(_ context: MenuContext) -> [MenuOverlayItem] {
        guard currentMenu.stable else { return [] }
        return currentMenu.rows.enumerated().compactMap { index,line in
            guard let text = menuCache.get(context.id+"|"+line.text) else { return nil }
            let id = context.id+"-\(index)"
            return MenuOverlayItem(id:id,source:line.text,translated:SubtitlePresentation.clean(text),box:line.box,color:currentMenuColors[id])
        }
    }
    private func reportCurrentMenu(ticket: UUID) {
        var state = CurrentMenuReadout(active:currentMenu.active,status:currentMenu.status)
        state.sources = currentMenu.rows
        if let context = currentMenuContext() {
            state.items = currentMenuTranslations(context)
            state.pending = currentMenu.rows.filter { menuCache.get(context.id+"|"+$0.text) == nil && !menuFailures.contains(context.id+"|"+$0.text) }.count
            state.withheld = currentMenu.rows.count-state.pending-menuItems.count
            state.rejectedSources = Set(currentMenu.rows.filter { menuFailures.contains(context.id+"|"+$0.text) }.map(\.text))
        }
        DispatchQueue.main.async { self.onCurrentMenu?(ticket,state) }
    }
    private func processCurrentMenu(_ buffer: CVPixelBuffer, received: Double, now: Double) {
        guard now-currentMenuLastSample >= 0.5, let ticket = currentMenu.ticket else { return }
        currentMenuLastSample = now
        defer { currentMenuLastSample = ProcessInfo.processInfo.systemUptime }
        if currentMenu.region == nil { currentMenu.beginFrame(); reportCurrentMenu(ticket:ticket) }
        do {
            let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
            // A broad read happens only on explicit acquisition. Subsequent
            // reads crop to the observed menu; no new automatic full-screen OCR.
            let scanRegion = currentMenu.region ?? SourceBox(x:0,y:0,w:1,h:1)
            let lines = try autoreleasepool { try ocr.menuLines(buffer,roi:scanRegion) }
            guard isActive() else { return }
#if DEBUG
            if onCurrentMenuObservation != nil {
                let elapsed = (ProcessInfo.processInfo.systemUptime-now)*1000, arrivalAge = frameAge
                DispatchQueue.main.async { self.onCurrentMenuObservation?(lines,scanRegion,elapsed,arrivalAge) }
            }
#endif
            metrics.recognitions &+= 1; metrics.lastOCRAt = ProcessInfo.processInfo.systemUptime
            metrics.ocrMilliseconds = (ProcessInfo.processInfo.systemUptime-now)*1000
            ocrSamples.record(metrics.ocrMilliseconds); metrics.ocrP95 = ocrSamples.p95
            metrics.actualOCRRate = Double(metrics.recognitions)/max(0.001,ProcessInfo.processInfo.systemUptime-startedAt)
            if now-lastMetrics >= 1 { lastMetrics = now; let value = metrics; DispatchQueue.main.async { self.onMetrics?(value) } }
            let finished = ProcessInfo.processInfo.systemUptime
            guard frameAge < CurrentMenuSession.maximumObservationAge else {
                finishCurrentMenu("توقفت إطارات المصدر أثناء القراءة؛ تحقق من البث وأعد الطلب"); return
            }
            var verifiedArrival = received
            if finished-received >= CurrentMenuSession.maximumObservationAge {
                slotLock.lock(); let newest = latest; slotLock.unlock()
                var exact = false
                if let (candidate,arrival,_) = newest, arrival > received,
                   finished-arrival < CurrentMenuSession.maximumObservationAge,
                   ExactMenuFrameProof.matches(buffer,candidate),
                   ProcessInfo.processInfo.systemUptime-arrival < CurrentMenuSession.maximumObservationAge {
                    verifiedArrival = arrival; exact = true
                }
#if DEBUG
                if onCurrentMenuFrameProof != nil {
                    let age = ProcessInfo.processInfo.systemUptime-verifiedArrival, proven = exact
                    DispatchQueue.main.async { self.onCurrentMenuFrameProof?(finished-received,proven,age) }
                }
#endif
                if !exact {
                    currentMenu.prepareFreshFrame(lines,width:width,height:height)
                    menuEpoch = UUID(); menuIdentity = nil; menuReadings = []; menuItems = []; currentMenuColors = [:]
                    publish(TVProtocol.envelope("menu_clear")); reportCurrentMenu(ticket:ticket)
                    return
                }
            }
            let previous = currentMenu.generation
            // One real OCR read, rebound only to proven identical fresh pixels.
            currentMenu.observe(lines,width:width,height:height,now:verifiedArrival)
            guard currentMenu.active, let context = currentMenuContext() else {
                translator.cancel(); clearMenu(); resetDialogueAfterMenu(); reportCurrentMenu(ticket:ticket); return
            }
            if currentMenu.generation != previous { menuEpoch = UUID() }
            menuIdentity = context.id; menuReadings = currentMenu.stable ? currentMenu.rows : []; menuLastSeen = verifiedArrival
            currentMenuAspect = Double(width)/Double(max(1,height))
            currentMenuColors = [:]
            if context.appearance.matchColor {
                for (index,row) in currentMenu.rows.enumerated() {
                    currentMenuColors[context.id+"-\(index)"] = GlyphColorSampler.sample(buffer,box:row.box,context:previewContext)
                }
            }
            refreshCurrentMenuOutput(context,now:ProcessInfo.processInfo.systemUptime)
            submitMenu(context)
        } catch { finishCurrentMenu("تعذرت قراءة القائمة؛ تحقق من وضوح النص وأعد الطلب") }
    }
    private func clearMenu() {
        menuEpoch = UUID(); menuIdentity = nil; menuItems = []; menuReadings = []
        currentMenuColors = [:]
        publish(TVProtocol.envelope("menu_clear"))
    }
    private func refreshCurrentMenuOutput(_ context: MenuContext, now: Double) {
        guard let ticket = currentMenu.ticket, menuIdentity == context.id else { return }
        menuItems = now-currentMenu.lastSeen < CurrentMenuSession.maximumObservationAge
            ? CurrentMenuLayout.overlay(currentMenuTranslations(context),appearance:context.appearance,aspect:currentMenuAspect,sourceBoxes:currentMenu.rows.map(\.box)) : []
        publishMenu(context,now:now); reportCurrentMenu(ticket:ticket)
    }
    private func processMenu(_ buffer: CVPixelBuffer, now: Double) {
        do {
            let regions = menuOptions.allowedMenus.filter{$0.enabled && $0.valid}.map(\.region)
            let lines = try autoreleasepool { try ocr.menuLines(buffer,regions:regions) }
            guard isActive(), let menu = MenuRecognition.recognized(menuOptions.allowedMenus,lines:lines) else { if menuIdentity != nil { clearMenu() }; return }
            let rows = Array(MenuItemGrouping.rows(lines.filter { menu.region.contains($0.box) && $0.text.count <= 120 }).prefix(20))
            if menuIdentity != menu.id { clearMenu(); menuIdentity = menu.id }
            menuLastSeen = now; menuReadings = rows
            menuItems = rows.enumerated().compactMap { index,line in
                guard let translated = menuCache.get(menu.id+"|"+line.text), translated.count <= 240 else { return nil }
                return MenuOverlayItem(id:menu.id+"-\(index)",source:line.text,translated:SubtitlePresentation.clean(translated),box:line.box,color:menu.appearance.matchColor ? GlyphColorSampler.sample(buffer,box:line.box,context:previewContext) : nil)
            }
            let context = MenuContext(id:menu.id,region:menu.region,appearance:menu.appearance)
            publishMenu(context,now:now)
            submitMenu(context)
        } catch { if menuIdentity != nil { clearMenu() } }
    }
    private func publishMenu(_ menu: MenuContext, now: Double) {
        let encoder = JSONEncoder()
        if currentMenu.active {
            // Reserve room for the existing sequence/authentication envelope.
            // Anything withheld here remains in the complete phone readout.
            while !menuItems.isEmpty {
                if let data = try? encoder.encode(menuItems), let items = try? JSONSerialization.jsonObject(with:data),
                   let styleData = try? encoder.encode(menu.appearance), let style = try? JSONSerialization.jsonObject(with:styleData),
                   let wire = try? TVProtocol.encode(TVProtocol.envelope("menu_snapshot",fields:["menu_id":menu.id,"items":items,"appearance":style,"lease_ms":1800])), wire.count <= 14_000 { break }
                menuItems.removeLast()
            }
        }
        guard let data = try? encoder.encode(menuItems), let items = try? JSONSerialization.jsonObject(with:data),
              let styleData = try? encoder.encode(menu.appearance), let appearance = try? JSONSerialization.jsonObject(with:styleData) else { return }
        publish(TVProtocol.envelope("menu_snapshot",fields:["menu_id":menu.id,"items":items,"appearance":appearance,"lease_ms":1800]))
        menuLastPublished = now
    }
    private func submitMenu(_ menu: MenuContext) {
        guard !menuWorking, isActive(), menuIdentity == menu.id,
              let line = menuReadings.first(where:{ menuCache.get(menu.id+"|"+$0.text) == nil && !menuFailures.contains(menu.id+"|"+$0.text) }) else { return }
        let currentTicket = currentMenu.ticket, currentGeneration = currentMenu.generation
        if currentTicket != nil && !currentMenu.stable { return }
        menuWorking = true; let epoch = menuEpoch, run = runID, key = menu.id+"|"+line.text
        translator.translate(line.text,category:"menu") { [weak self] result,_ in
            guard let self else { return }
            self.queue.async {
                self.menuWorking = false
                guard self.isActive(), self.menuEpoch == epoch, self.runID == run, self.menuIdentity == menu.id,
                      ProcessInfo.processInfo.systemUptime-self.menuLastSeen < 1.5 else { return }
                if let ticket = currentTicket {
                    guard self.currentMenu.accepts(ticket:ticket,generation:currentGeneration,source:line.text,now:ProcessInfo.processInfo.systemUptime) else { return }
                    if case .success(let text) = result, MenuTranslationGuard.safe(text,source:line.text,names:self.namesByKey) {
                        self.menuCache.put(text,for:key)
                    } else { self.menuFailures.insert(key) }
                    self.refreshCurrentMenuOutput(menu,now:ProcessInfo.processInfo.systemUptime)
                } else if case .success(let text) = result, !text.isEmpty { self.menuCache.put(text,for:key) }
                // Current frame geometry and values are used by the next read;
                // an old completion can never add an item absent from that read.
                if case .success = result { self.submitMenu(menu) }
            }
        }
    }
    private func submit() {
        guard isActive(), !reading, !translating, let job = pending else { return }
        pending = nil; translating = true
        let epoch = runID
        let contextKey = outputContextKey
        if translationsContextKey != contextKey { translations = BoundedLRU(capacity:8); translationsContextKey = contextKey }
        let correctionScope = correctionSnapshot.scopeKey
        let publicationToken = recentToken
        memory.prune(now:ProcessInfo.processInfo.systemUptime)
        let cached = translations.get(job.id)
        let engineInput = job.engineText ?? job.text
        let reusable = !job.meaningfulCorrection && cached.map { DialogueText.same($0.0,job.text) && !DialogueText.prefix($0.0,job.text) } == true
        let cueOnly = engineInput.isEmpty && job.cue != nil
        let correctionSource = engineInput.isEmpty ? job.text : engineInput
        let selectedGame = translator.packs?.publication("",origin:.rule).game
        let applicable = translator.packs == nil || corrections.matches(game:selectedGame) ? corrections : CorrectionContext(correctionSnapshot,enabled:false)
        var override = DialogueOverride.resolve(source:correctionSource,corrections:applicable,reuse:reusable ? cached?.2 : nil,cue:cueOnly ? job.cue : nil) {
            Terminology.resolve(engineInput,rules:advanced.terminology,context:memory.entries.filter { $0.id != job.id })
        }
        let learningKey = learningContext(source:job.text,speaker:job.speaker)
        if override == nil, translator.packs?.publication("",origin:.rule).pack == nil,
           let learned = improvedMemory.lookup(game:namesSnapshot.game,source:engineInput,context:learningKey) { override = TranslationDecision(text:learned,origin:.rule,game:namesSnapshot.game) }
        let punctuationTrace = metrics.punctuationTrace
        let captureLines = pendingCapture, captureSegments = pendingSegments
        let selection = override != nil && (quality[.measurement] || quality[.provenanceMarker] || capture.active) ? translator.packs?.publication(job.id,origin:override?.origin ?? .rule) : nil
        let completion: (Result<TranslationDecision,Error>,Double) -> Void = { [weak self] result,latency in
            guard let self else { return }
            self.queue.async {
                self.translating = false
                if self.isActive() && epoch == self.runID && self.tracker.accepts(job) {
                    if correctionScope != self.correctionSnapshot.scopeKey { self.submit(); return }
                    // An explicit edit/scope/flag change affects only an unpublished
                    // job. Never replay an already displayed card or reset clocks.
                    if contextKey != self.outputContextKey {
                        if self.pending == nil { self.pending = job }
                        self.submit(); return
                    }
                    let deliver: (Bool) -> Void = { [weak self] recheck in
                    guard let self else { return }
                    if recheck {
                        guard self.isActive(), epoch == self.runID, self.tracker.accepts(job), correctionScope == self.correctionSnapshot.scopeKey, contextKey == self.outputContextKey else { return }
                    }
                    var delivered = job
                    if let current = self.tracker.current, DialogueText.exactWords(current.text) == DialogueText.exactWords(job.text) { delivered.speaker = current.speaker }
                    delivered.speakerArabic = self.quality[.learnNames] ? delivered.speaker.flatMap { self.namesByKey[GameName.key($0)] } : nil
                    switch result {
                    case .success(let decision):
                        let text = decision.text
                        if self.stability.shouldPublish(delivered) {
                            if !reusable { self.metrics.translationMilliseconds = latency; self.translationSamples.record(latency); self.metrics.translationP95 = self.translationSamples.p95 }
                            self.stability.didPublish(delivered)
                            self.translations.put((job.text,text,decision.withoutEngineTrace),for:job.id)
                            self.memory.observe(job,now:ProcessInfo.processInfo.systemUptime)
                            var message = TVProtocol.qualityFields(TVProtocol.subtitle(delivered,arabic:text,now:TVHub.now()),settings:self.quality,origin:decision.origin,basis:decision.basis)
                            if self.quality[.stageCues], let cue = job.cue {
                                message["cue"] = cueOnly && (decision.origin == .userCorrection || decision.basis == .userCorrection) ? text : cue
                                if cueOnly { message["cue_only"] = true }
                            }
                            if self.quality[.measurement] {
                                self.translator.packs?.recordPublished(PublishedTranslation(eventID:delivered.id,game:decision.game,pack:decision.pack,origin:decision.origin,fallback:decision.fallback,basis:decision.basis))
                            }
                            if self.quality[.punctuationTrace] {
                                let inputTrace = decision.engineInput.map(SubtitlePresentation.punctuation) ?? "لا استدلال جديد"
                                let rawTrace = decision.rawOutput.map(SubtitlePresentation.punctuation) ?? "غير متاح · لا مخرج نموذج جديد"
                                self.metrics.punctuationTrace = punctuationTrace + " | input " + inputTrace + " | raw " + rawTrace + " | repair " + SubtitlePresentation.punctuation(text) + " | unbalanced " + String(decision.punctuationUnbalanced) + " | wire " + SubtitlePresentation.punctuation(message["translated"] as? String ?? "")
                            }
                            if self.capture.active {
                                do { try self.capture.append(QualityCaptureRecord(eventID:delivered.id,lines:captureLines,parsed:job.text,engineInput:decision.engineInput ?? "",engineOutput:decision.rawOutput ?? "",origin:decision.origin,stage:.published,timestamp:self.capture.elapsed,segments:captureSegments,basis:decision.basis,finalOutput:text,rawEngineTraceAvailable:decision.engineInput != nil && decision.rawOutput != nil)) }
                                catch { self.capture.stop() }
                                self.reportCapture()
                            }
                            self.publish(message)
                            self.metrics.lastTranslationAt = ProcessInfo.processInfo.systemUptime
                            if self.learningConsent, decision.origin == .packExact, let pack = decision.pack {
                                let example = ImprovementExample(game:self.namesSnapshot.game,source:engineInput,context:learningKey,confidence:job.confidence,trustedTarget:text,authority:"pack-exact:"+pack)
                                DispatchQueue.main.async { self.onLearningExample?(example) }
                            }
                            if self.quality[.corrections] {
                                let recent = RecentPublishedLine(id:delivered.id,scope:self.correctionSnapshot.scopeKey,source:correctionSource,target:message["translated"] as? String ?? text,origin:decision.origin)
                                DispatchQueue.main.async { self.onRecentPublished?(recent,publicationToken) }
                            }
                        }
                    case .failure(let error): if !(error is CancellationError) { DispatchQueue.main.async { self.onError?(error.localizedDescription) } }
                    }
                    }
#if GAMELINGO_TYPEWRITER_RESEARCH
                    if case .success = result, !self.typewriter.canPublish(job) {
                        self.heldPublication = (job,{ deliver(true) })
                    } else { deliver(false) }
#else
                    deliver(false)
#endif
                }
                self.submit()
            }
        }
        if var decision = override {
            if decision.origin != .reuse { decision.game = selection?.game; decision.pack = selection?.pack }
            if quality[.measurement] { translator.packs?.recordAttempt(decision.origin,fallback:decision.fallback,game:decision.game,pack:decision.pack) }
            completion(.success(decision),0)
        } else { translator.translateDetailed(engineInput,eventID:job.id,completion:completion) }
    }
    func requestReading(ticket: UUID) {
        translator.cancel()
        queue.async { [self] in
            finishCurrentMenu("انتقلت إلى قراءة النص")
            runID = UUID(); pending = nil; tracker.markInterrupted(); reading = true; captureRequested = true; readingTicket = ticket
#if GAMELINGO_TYPEWRITER_RESEARCH
            heldPublication = nil; typewriter = TypewriterPublication(); typewriterScope = nil
#endif
            documentStarted = ProcessInfo.processInfo.systemUptime; documentResident = ResourceMonitor.residentBytes()
            metrics.documentMilliseconds = 0; metrics.documentTranslationMilliseconds = 0; metrics.documentOCRMilliseconds = 0
            metrics.documentCompleted = 0; metrics.documentTotal = 0; metrics.documentExtraMegabytes = 0
            reportDocumentMetrics()
            slotLock.lock(); latest = nil; slotLock.unlock() // Require a newly decoded frame.
            publish(TVProtocol.envelope("subtitle_clear"))
            DispatchQueue.main.async { self.onReading?(ticket,true,[],"بانتظار إطار جديد لقراءة النص…") }
            let epoch = runID
            queue.asyncAfter(deadline:.now()+6) { [weak self] in
                guard let self, self.runID == epoch, self.captureRequested else { return }
                self.finishReading(message:"لم يصل إطار PS5 جديد؛ تحقق من البث")
            }
        }
    }
    private func translateDocument(_ chunks: [String], index: Int, translated: [String], epoch: UUID) {
        guard isActive(), reading, runID == epoch else { return }
        guard index < chunks.count else {
            let pages = DocumentText.pages(translated)
            guard !pages.isEmpty else { finishReading(message:"النص المترجم طويل جدًا؛ اقرأ المستند على أجزاء"); return }
            let ticket = readingTicket
            metrics.documentMilliseconds = (ProcessInfo.processInfo.systemUptime-documentStarted)*1000; reportDocumentMetrics()
            DispatchQueue.main.async { self.onReading?(ticket,true,pages,"القراءة جاهزة · \(pages.count) صفحات") }
            return
        }
        translator.translate(chunks[index],category:"document") { [weak self] result,latency in
            guard let self else { return }
            self.queue.async {
                guard self.isActive(), self.reading, self.runID == epoch else { return }
                self.metrics.documentTranslationMilliseconds += latency; self.metrics.documentCompleted = index+1
                if index+1 == chunks.count || ProcessInfo.processInfo.systemUptime-self.lastMetrics >= 0.25 { self.reportDocumentMetrics() }
                switch result {
                case .success(let text): self.translateDocument(chunks,index:index+1,translated:translated+[text],epoch:epoch)
                case .failure: self.finishReading(message:"تعذرت ترجمة المستند؛ أعد المحاولة")
                }
            }
        }
    }
    private func reportDocumentMetrics() {
        metrics.contextEntries = memory.entries.count
        let resident = ResourceMonitor.residentBytes()
        let extra = resident > documentResident ? Double(resident-documentResident)/1048576 : 0
        metrics.documentExtraMegabytes = max(metrics.documentExtraMegabytes,extra)
        lastMetrics = ProcessInfo.processInfo.systemUptime
        let value = metrics; DispatchQueue.main.async { self.onMetrics?(value) }
    }
    func closeReading() {
        translator.cancel(); queue.async { [self] in runID = UUID(); finishReading() }
    }
    private func finishReading(message: String = "القراءة مغلقة") {
        guard reading else { return }
        reading = false; captureRequested = false
        let ticket = readingTicket
        publish(TVProtocol.envelope("document_hide"))
        DispatchQueue.main.async { self.onReading?(ticket,false,[],message) }
    }
}
