import Foundation
import CoreVideo

struct PipelineMetrics {
    var ocrMilliseconds = 0.0, translationMilliseconds = 0.0, frameMilliseconds = 0.0, samplingRate = 0.0
    var actualOCRRate = 0.0
    var frames: UInt64 = 0, dropped: UInt64 = 0
    var recognitions: UInt64 = 0
    var queueDepth = 0
}

final class FramePipeline {
    var onMetrics: ((PipelineMetrics) -> Void)?
    var onError: ((String) -> Void)?
    private let translator: OfflineTranslator
    private let publish: ([String:Any]) -> Void
    private let queue = DispatchQueue(label:"dev.gamelingo.ocr",qos:.userInitiated)
    private let slotLock = NSLock()
    private var latest: (CVPixelBuffer,TimeInterval,Int64)?
    private var active = false
    private var runID = UUID()
    private var roi = SourceBox.dialogue
    private var mode = PerformanceMode.balanced
    private var thermal = 0, lowPower = false
    private var timer: DispatchSourceTimer?
    private var ocr = VisionDialogueOCR()
    private var signature = FrameSignature()
    private var tracker = DialogueTracker()
    private var pending: DialogueJob?
    private var translating = false
    private var lastSample = 0.0
    private var lastMetrics = 0.0
    private var lastTextChange = 0.0
    private var startedAt = 0.0
    private var metrics = PipelineMetrics()
    init(translator: OfflineTranslator, publish: @escaping ([String:Any]) -> Void) { self.translator = translator; self.publish = publish }

    /// Decode callback retains one buffer; it never allocates one OCR task per received frame.
    func offer(_ buffer: CVPixelBuffer) {
        slotLock.lock(); defer { slotLock.unlock() }
        guard active else { return }
        if latest != nil { metricsDropped &+= 1 }
        latest = (buffer,ProcessInfo.processInfo.systemUptime,TVHub.now())
    }
    private var metricsDropped: UInt64 = 0
    func start(roi: SourceBox, mode: PerformanceMode) {
        queue.async { [self] in
            guard roi.isValid else { return }
            reset(); self.roi = roi; self.mode = mode; runID = UUID(); lastSample = 0; lastTextChange = 0
            metrics = PipelineMetrics()
            startedAt = ProcessInfo.processInfo.systemUptime
            slotLock.lock(); active = true; metricsDropped = 0; slotLock.unlock()
            let timer = DispatchSource.makeTimerSource(queue:queue)
            timer.schedule(deadline:.now(),repeating:.milliseconds(50),leeway:.milliseconds(10))
            timer.setEventHandler { [weak self] in self?.sample() }; self.timer = timer; timer.resume()
        }
    }
    func configure(mode: PerformanceMode, thermal: Int, lowPower: Bool) {
        queue.async { [self] in self.mode = mode; self.thermal = thermal; self.lowPower = lowPower }
    }
    func interrupt() { translator.cancel(); queue.async { [self] in
        runID = UUID(); tracker.reset(); pending = nil; publish(TVProtocol.envelope("subtitle_clear"))
        slotLock.lock(); latest = nil; slotLock.unlock()
    } }
    /// Called from the hub queue; inference never synchronously waits on that queue.
    func tvDisconnected() { translator.cancel(); queue.sync { [self] in
        // Keep the observed dialogue identity so reconnecting does not retranslate/replay it.
        // Invalidate all in-flight publications and discard pending work.
        runID = UUID(); pending = nil
    } }
    func stop() {
        translator.cancel()
        slotLock.lock(); active = false; latest = nil; slotLock.unlock()
        queue.async { [self] in reset(); publish(TVProtocol.envelope("subtitle_clear")) }
    }
    private func reset() {
        timer?.cancel(); timer = nil; runID = UUID(); tracker.reset(); pending = nil; ocr = VisionDialogueOCR(); signature = FrameSignature()
        // An already running inference still owns the single worker until its callback.
    }
    private func sample() {
        let now = ProcessInfo.processInfo.systemUptime
        let rate = mode.samplingRate(thermal:thermal,lowPower:lowPower)
        metrics.samplingRate = rate
        guard rate > 0 else { return }
        let interval = max(1/rate,now-lastTextChange > 2 ? 0.35 : 0)
        guard now-lastSample >= interval else { return }
        slotLock.lock(); let frame = latest; latest = nil; let dropped = metricsDropped; slotLock.unlock()
        guard let (buffer,received,stamp) = frame else { return }
        guard now-received < 1 else { return }
        lastSample = now; metrics.frames &+= 1; metrics.dropped = dropped
        guard signature.shouldRecognize(buffer,roi:roi,now:now,hasText:tracker.current != nil) else { return }
        do {
            let (text,box) = try autoreleasepool { try ocr.recognize(buffer,roi:roi) }
            metrics.recognitions &+= 1
            metrics.actualOCRRate = Double(metrics.recognitions)/max(0.001,ProcessInfo.processInfo.systemUptime-startedAt)
            metrics.ocrMilliseconds = (ProcessInfo.processInfo.systemUptime-now)*1000
            switch tracker.observe(text:text,box:box,now:now,frameMilliseconds:stamp) {
            case .unchanged: break
            case .gone(let id):
                translator.cancel(); pending = nil; publish(TVProtocol.envelope("subtitle_source_gone",fields:["id":id])); lastTextChange = now
            case .dialogue(let job,let previous):
                if let previous { publish(TVProtocol.envelope("subtitle_source_gone",fields:["id":previous])) }
                if !job.correction { translator.cancel() }
                pending = job; lastTextChange = now; submit()
            }
            metrics.frameMilliseconds = (ProcessInfo.processInfo.systemUptime-received)*1000
            metrics.queueDepth = (translating ? 1 : 0)+(pending == nil ? 0 : 1)
            if now-lastMetrics >= 1 { lastMetrics = now; let value = metrics; DispatchQueue.main.async { self.onMetrics?(value) } }
        } catch { DispatchQueue.main.async { self.onError?(error.localizedDescription) } }
    }
    private func submit() {
        guard !translating, let job = pending else { return }
        pending = nil; translating = true
        let epoch = runID
        translator.translate(job.text) { [weak self] result,latency in
            guard let self else { return }
            self.queue.async {
                self.translating = false
                if epoch == self.runID && self.tracker.accepts(job) {
                    switch result {
                    case .success(let text): self.metrics.translationMilliseconds = latency; self.publish(TVProtocol.subtitle(job,arabic:text,now:TVHub.now()))
                    case .failure(let error): DispatchQueue.main.async { self.onError?(error.localizedDescription) }
                    }
                }
                self.submit()
            }
        }
    }
}
