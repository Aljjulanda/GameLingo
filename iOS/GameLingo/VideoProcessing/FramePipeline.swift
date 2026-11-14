import Foundation
import CoreVideo

struct PipelineMetrics {
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
}

final class FramePipeline {
    var onMetrics: ((PipelineMetrics) -> Void)?
    var onError: ((String) -> Void)?
    var onReading: ((UUID,Bool,[String],String) -> Void)?
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
    private var ocr = VisionDialogueOCR()
    private var signature = FrameSignature()
    private var tracker = DialogueTracker()
    private var advanced = AdvancedSettings()
    private var packSpeakerNames = ""
    private var memory = DialogueMemory()
    private var stability = PublicationStability()
    private var translations = BoundedLRU<String,(String,String)>(capacity:8)
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
    init(translator: OfflineTranslator, publish: @escaping ([String:Any]) -> Void) { self.translator = translator; self.publish = publish }

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
            advanced = value; memory.enabled = value.contextEnabled; memory.capacity = value.contextCapacity
            memory.prune(now:ProcessInfo.processInfo.systemUptime)
        }
    }
    func configurePackNames(_ names: String) { queue.async { self.packSpeakerNames = String(names.prefix(2000)) } }
    func interrupt() { translator.cancel(); queue.async { [self] in
        finishReading()
        runID = UUID(); tracker.markInterrupted(); pending = nil; publish(TVProtocol.envelope("subtitle_clear"))
        slotLock.lock(); latest = nil; slotLock.unlock()
    } }
    /// Called from the hub queue; inference never synchronously waits on that queue.
    func tvDisconnected() { translator.cancel(); queue.sync { [self] in
        finishReading(message:"انقطع اتصال التلفزيون أثناء القراءة")
        // Keep the observed dialogue identity so reconnecting does not retranslate/replay it.
        // Invalidate all in-flight publications and discard pending work.
        runID = UUID(); pending = nil
        tracker.markInterrupted()
    } }
    func stop() {
        translator.cancel()
        slotLock.lock(); active = false; latest = nil; slotLock.unlock()
        queue.async { [self] in reset(); publish(TVProtocol.envelope("subtitle_clear")) }
    }
    func pause() {
        translator.cancel()
        slotLock.lock(); active = false; latest = nil; slotLock.unlock()
        queue.async { [self] in reset(preservingState:true); publish(TVProtocol.envelope("subtitle_clear")) }
    }
    private func reset(preservingState: Bool = false) {
        finishReading()
        timer?.cancel(); timer = nil; runID = UUID(); pending = nil; ocr = VisionDialogueOCR(); ocr.setBackground(isBackground); signature = FrameSignature()
        if preservingState { tracker.markInterrupted(); memory.prune(now:ProcessInfo.processInfo.systemUptime) }
        else { tracker.reset(); memory.clear(); stability.clear(); translations = BoundedLRU(capacity:8) }
        // An already running inference still owns the single worker until its callback.
    }
    private func sample() {
        let now = ProcessInfo.processInfo.systemUptime
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
        guard signature.shouldRecognize(buffer,roi:roi,now:now,hasText:tracker.current != nil) else { return }
        do {
            let (_,box) = try autoreleasepool { try ocr.recognize(buffer,roi:roi,knownNames:advanced.speakerNames+","+packSpeakerNames) }
            guard isActive() else { return }
            let content = ocr.content
            if content.speaker != nil { metrics.speakersDetected += 1 }
            if content.uncertainSpeaker { metrics.speakersUncertain += 1 }
            metrics.punctuationTrace = "OCR " + ocr.punctuationTrace + " | parsed " + SubtitlePresentation.punctuation(content.text)
            metrics.recognitions &+= 1
            metrics.actualOCRRate = Double(metrics.recognitions)/max(0.001,ProcessInfo.processInfo.systemUptime-startedAt)
            metrics.ocrMilliseconds = (ProcessInfo.processInfo.systemUptime-now)*1000
            ocrSamples.record(metrics.ocrMilliseconds); metrics.ocrP95 = ocrSamples.p95
            metrics.contextEntries = memory.entries.count
            switch tracker.observe(text:content.text,box:box,now:now,frameMilliseconds:stamp,speaker:content.speaker,confidence:ocr.confidence) {
            case .unchanged: break
            case .gone(let id):
                translator.cancel(); pending = nil; publish(TVProtocol.envelope("subtitle_source_gone",fields:["id":id])); lastTextChange = now
            case .dialogue(let job,let previous):
                translator.packs?.recordDialogue(job.id)
                if let previous { publish(TVProtocol.envelope("subtitle_source_gone",fields:["id":previous])) }
                guard stability.shouldPublish(job) else { memory.observe(job,now:now); break }
                if !job.correction { translator.cancel() }
                pending = job; lastTextChange = now; submit()
            }
            metrics.duplicatesSuppressed = tracker.duplicatesSuppressed
            metrics.correctionsMerged = tracker.correctionsMerged
            metrics.frameMilliseconds = (ProcessInfo.processInfo.systemUptime-received)*1000
            metrics.queueDepth = (translating ? 1 : 0)+(pending == nil ? 0 : 1)
            if now-lastMetrics >= 1 { lastMetrics = now; let value = metrics; DispatchQueue.main.async { self.onMetrics?(value) } }
        } catch { DispatchQueue.main.async { self.onError?(error.localizedDescription) } }
    }
    private func submit() {
        guard isActive(), !reading, !translating, let job = pending else { return }
        pending = nil; translating = true
        let epoch = runID
        memory.prune(now:ProcessInfo.processInfo.systemUptime)
        let cached = translations.get(job.id)
        let reusable = !job.meaningfulCorrection && cached.map { DialogueText.same($0.0,job.text) && !DialogueText.prefix($0.0,job.text) } == true
        let override = reusable ? cached?.1 : Terminology.resolve(job.text,rules:advanced.terminology,context:memory.entries.filter { $0.id != job.id })
        let punctuationTrace = metrics.punctuationTrace
        let completion: (Result<String,Error>,Double) -> Void = { [weak self] result,latency in
            guard let self else { return }
            self.queue.async {
                self.translating = false
                if self.isActive() && epoch == self.runID && self.tracker.accepts(job) {
                    var delivered = job
                    if let current = self.tracker.current, DialogueText.exactWords(current.text) == DialogueText.exactWords(job.text) { delivered.speaker = current.speaker }
                    switch result {
                    case .success(let text):
                        if self.stability.shouldPublish(delivered) {
                            if !reusable { self.metrics.translationMilliseconds = latency; self.translationSamples.record(latency); self.metrics.translationP95 = self.translationSamples.p95 }
                            self.stability.didPublish(delivered)
                            self.translations.put((job.text,text),for:job.id)
                            self.metrics.punctuationTrace = punctuationTrace + " | model " + SubtitlePresentation.punctuation(text) + " | wire " + SubtitlePresentation.punctuation(SubtitlePresentation.clean(text))
                            self.memory.observe(job,now:ProcessInfo.processInfo.systemUptime)
                            self.publish(TVProtocol.subtitle(delivered,arabic:text,now:TVHub.now()))
                        }
                    case .failure(let error): if !(error is CancellationError) { DispatchQueue.main.async { self.onError?(error.localizedDescription) } }
                    }
                }
                self.submit()
            }
        }
        if let override { completion(.success(override),0) }
        else { translator.translate(job.text,eventID:job.id,completion:completion) }
    }
    func requestReading(ticket: UUID) {
        translator.cancel()
        queue.async { [self] in
            runID = UUID(); pending = nil; tracker.markInterrupted(); reading = true; captureRequested = true; readingTicket = ticket
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
