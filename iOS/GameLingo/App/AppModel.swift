import SwiftUI
import Network
import Darwin
import os

@MainActor
final class AppModel: ObservableObject {
    @Published var settings = AppSettings.load() {
        didSet {
            do { try settings.save() } catch { errorMessage = error.localizedDescription }
            pipeline.configure(mode:settings.mode,thermal:ProcessInfo.processInfo.thermalState.rawValue,lowPower:ProcessInfo.processInfo.isLowPowerModeEnabled)
            if oldValue.advanced != settings.advanced { pipeline.configureAdvanced(settings.advanced) }
            if oldValue.display != settings.display || oldValue.advanced.showSpeakers != settings.advanced.showSpeakers || oldValue.advanced.speakerColor != settings.advanced.speakerColor { scheduleStyle() }
        }
    }
    @Published var quality = QualitySettings.load() {
        didSet {
            quality.save(); pipeline.configureQuality(quality)
            if oldValue[.measurement] != quality[.measurement] { packLibrary.metrics = HybridMetrics(); packLibrary.store.resetMetrics() }
            if !oldValue[.learnNames] && quality[.learnNames] { refreshPackNamePairs() }
        }
    }
    @Published var qualityCaptureActive = false
    @Published var qualityCaptureFile: URL?
    func qualityCapture(start: Bool = false, delete: Bool = false) { pipeline.captureAction(start:start,delete:delete) }
    @Published var consoles: [ConsoleCredentials] = []
    @Published var discovered: [DiscoveredConsole] = []
    @Published var remoteStatus = "البث متوقف"
    @Published var tvStatus = "التلفزيون غير متصل"
    @Published var tvRenderSignature = ""
    @Published var tvDiagnostics: [String] = []
    @Published var tvListening = false
    @Published var sessionStatus = "متوقفة"
    @Published var audioStatus = "تجربة الخلفية متوقفة"
    @Published var streamConnected = false
    @Published var recoveryAttempts = 0
    @Published var remoteMetrics = RemoteMetrics()
    @Published var audioInterruptions = 0
    @Published var networkInterruptions = 0
    @Published var sessionDiagnostics: [String] = []
    @Published var sessionStarted = Date()
    @Published var backgroundDeliveries: UInt64 = 0
    @Published var tvConnected = false
    @Published var tvDocuments = false
    @Published var tvSpeakers = false
    @Published var readingActive = false
    @Published var readingPages: [String] = []
    @Published var readingPage = 0
    @Published var readingStatus = "القراءة مغلقة"
    @Published var cpuPercent = 0.0
    @Published var residentMegabytes = 0.0
    @Published var batteryUsed: Double?
    @Published var networkStatus = "جارٍ فحص الشبكة"
    @Published var modelStatus = "لم يُحمّل النموذج"
    @Published var pairingCode = ""
    @Published var errorMessage: String?
    @Published var showingPackLibrary = false
    @Published var running = false
    @Published var modelReady = false
    @Published var modelBusy = false
    @Published var metrics = PipelineMetrics()
    @Published var thermal = ProcessInfo.processInfo.thermalState
    @Published var availableMemory: UInt64 = 0
    @Published var loginRequired = false
    @Published var pairing = false
    @Published var addresses: [String] = []
    let packLibrary = GamePackLibrary()
    let namesLibrary = GameNamesLibrary()
    private func refreshPackNamePairs() {
        guard quality[.learnNames] else { return }
        packLibrary.store.alignedNamePairs { [weak self] game,pack,pairs in
            guard let self, self.quality[.learnNames], game == self.packLibrary.state.registry.selectedGame,
                  pack != nil, pack == self.packLibrary.state.registry.packs.first(where:{$0.manifest.gameId == game && $0.enabled})?.id,
                  self.packLibrary.state.loaded, self.namesLibrary.snapshot.game == (game ?? "general") else { return }
            self.namesLibrary.seed(pairs)
        }
    }
    lazy var translator = OfflineTranslator(packs:packLibrary.store)
    let hub = TVHub()
    let remote = RemotePlayService()
    private lazy var pipeline = FramePipeline(translator:translator,publish:{ [weak hub = self.hub] in hub?.publish($0) })
    private let monitor = NWPathMonitor()
    private var timer: Timer?
    private var styleTask: Task<Void,Never>?
    private var downloadTask: Task<Void,Never>?
    private var originalBrightness: CGFloat?
    private var lifecycle = 0
    private var policy = SessionPolicy()
    private let audio = BackgroundAudio()
    private var recoveryTask: Task<Void,Never>?
    private var executionTask: UIBackgroundTaskIdentifier = .invalid
    private var executionDeadline: Task<Void,Never>?
    private var pipelineActive = false
    private var hubStarting = false
    private var readingTicket: UUID?
    private var displayedIDs = Set<String>()
    private var resources = ResourceMonitor()
    private var initialBattery: Float = -1
    private var sessionLog = SessionDiagnostics()
    private var lastSystemSample = 0.0
    private var sessionStartedUptime = 0.0
    var performanceSnapshot: String {
        let values = [
            "GameLingo 0.3.0", "Measurement started: \(sessionStarted.formatted())", sessionStatus, audioStatus,
            "CPU: \(NumericInput.format(cpuPercent))% (100%=one core)", "RSS: \(NumericInput.format(residentMegabytes)) MB", "Thermal: \(thermal.rawValue)",
            "Translation p95: \(NumericInput.format(metrics.translationP95)) ms", "OCR p95: \(NumericInput.format(metrics.ocrP95)) ms",
            "TV background render ACKs: \(backgroundDeliveries)", "Recovery backoff index: \(recoveryAttempts)",
            "PS5 reconnect attempts: \(remoteMetrics.attempts)", "Confirmed PS5 reconnects: \(remoteMetrics.successes)", "Failed PS5 reconnects: \(remoteMetrics.failures)",
            "Frame starvation events: \(remoteMetrics.starvations)", "Decoder IDR requests: \(remoteMetrics.decoderRequests)",
            "Audio interruptions: \(audioInterruptions)", "Network interruptions: \(networkInterruptions)",
            "Duplicate OCR suppressed: \(metrics.duplicatesSuppressed)", "OCR corrections merged: \(metrics.correctionsMerged)",
            "Speaker readings detected: \(metrics.speakersDetected)", "Speaker readings uncertain: \(metrics.speakersUncertain)",
            "Confirmed labels hidden: \(metrics.speakerHidden)", metrics.nameConfidence,
            "Battery percentage change: \(batteryUsed.map(NumericInput.format) ?? "unavailable")",
            "Smart Reading: \(NumericInput.format(metrics.documentMilliseconds)) ms, sampled extra RSS \(NumericInput.format(metrics.documentExtraMegabytes)) MB",
            "Punctuation stages (logical order, no dialogue): \(metrics.punctuationTrace)",
            "TV actual-render signature: \(tvRenderSignature)"
        ]
        return (values+[packLibrary.metrics.summary]+sessionDiagnostics).joined(separator:"\n")
    }
    private func recordSession(_ stage: String, _ detail: String, at: Double? = nil) {
        sessionLog.record(stage,detail:detail,now:at ?? ProcessInfo.processInfo.systemUptime,foreground:policy.foreground,network:policy.network,interrupted:policy.interrupted)
        sessionDiagnostics = sessionLog.lines
    }

    func openTranslationPack(_ url: URL) {
        if packLibrary.importFile(url,sessionRunning:running) { showingPackLibrary = true }
        else { errorMessage = packLibrary.message }
    }

    init() {
        try? LocalizationInbox().prepare()
        pipeline.configureQuality(quality)
        pipeline.onCaptureState = { [weak self] active,file in self?.qualityCaptureActive = active; self?.qualityCaptureFile = file }
        pipeline.captureAction()
        namesLibrary.onChange = { [weak self] store,snapshot in self?.pipeline.configureNames(store,snapshot:snapshot) }
        pipeline.configureNames(namesLibrary.store,snapshot:namesLibrary.snapshot)
        packLibrary.onNamesChanged = { [weak self] names in
            guard let self else { return }
            self.namesLibrary.select(self.packLibrary.state.registry.selectedGame)
            self.pipeline.configurePackNames(names); self.refreshPackNamePairs()
        }
        do {
            if let data = try KeychainStore.read("consoles.v1") {
                consoles = try JSONDecoder().decode([ConsoleCredentials].self,from:data)
                for console in consoles { try console.validate() }
            }
        } catch { errorMessage = error.localizedDescription; consoles = [] }
        policy.network = false
        if SessionIntentStore.load(), consoles.contains(where:{ $0.id == settings.selectedConsoleID }) {
            policy.start(); running = true; policy.experimentalAudio = settings.advanced.backgroundAudio
            sessionStatus = "الجلسة السابقة مطلوبة؛ بانتظار النموذج والشبكة"
            UIDevice.current.isBatteryMonitoringEnabled = true
        }
        remote.onDiscovery = { [weak self] item in
            guard let self else { return }
            self.discovered.removeAll { $0.host == item.host }; self.discovered.append(item)
            if self.discovered.count > 16 { self.discovered.removeFirst() }
        }
        remote.onState = { [weak self] in self?.remoteStatus = $0 }
        remote.onLoginPIN = { [weak self] in self?.loginRequired = true }
        remote.onInterruption = { [weak self] in self?.pipeline.interrupt() }
        remote.onStopped = { [weak self] in
            guard let self, self.policy.wanted else { return }
            self.sessionStatus = "انقطع بث PS5؛ جارٍ الاسترداد"
            self.scheduleRecovery()
        }
        remote.onAvailability = { [weak self] connected in
            guard let self else { return }
            if connected && !self.policy.wanted { return }
            self.streamConnected = connected
            if !connected && self.policy.wanted {
                self.sessionStatus = !self.policy.canExecute ? "بانتظار السماح بالتنفيذ" : !self.policy.network ? "بانتظار الشبكة" : "جارٍ استرداد بث PS5"
            }
            if connected { self.recoveryAttempts = 0; self.sessionStatus = "البث متصل؛ الترجمة نشطة" }
        }
        remote.onTelemetry = { [weak self] metrics,stage,detail,time in
            guard let self, !self.policy.wanted || time >= self.sessionStartedUptime else { return }; self.remoteMetrics = metrics
            if let stage { self.recordSession(stage,detail,at:time) }
        }
        audio.onChange = { [weak self] active,interrupted,text in
            guard let self else { return }
            let wasInterrupted = self.policy.interrupted
            self.audioStatus = text; self.policy.audioActive = active; self.policy.interrupted = interrupted
            if interrupted && !wasInterrupted && self.policy.wanted { self.audioInterruptions += 1; self.recordSession("audio.interruption",text) }
            if active && wasInterrupted { self.recordSession("audio.restored",text) }
            if active { self.endExecutionGrace() }
            else if self.policy.wanted && !self.policy.foreground { self.beginExecutionGrace() }
        }
        audio.onRecovery = { [weak self] in self?.recoverSession() }
        remote.onRegistration = { [weak self] result in
            guard let self else { return }; self.pairing = false
            do {
                var console = try result.get(); try console.validate()
                if let old = self.consoles.first(where:{ $0.host == console.host }) { console.id = old.id }
                self.consoles.removeAll { $0.host == console.host }; self.consoles.append(console)
                self.settings.selectedConsoleID = console.id
                try KeychainStore.write(JSONEncoder().encode(self.consoles),account:"consoles.v1")
                self.remoteStatus = "تم تسجيل \(console.name)"
            } catch { self.errorMessage = error.localizedDescription }
        }
        hub.onStatus = { [weak self] in self?.tvStatus = $0 }
        hub.onPairing = { [weak self] _,code in self?.pairingCode = code; self?.hubStarting = false }
        hub.onDiagnostics = { [weak self] in self?.tvDiagnostics = $0 }
        hub.onListening = { [weak self] listening in
            guard let self else { return }
            let wasListening = self.tvListening
            self.tvListening = listening
            if listening { self.hubStarting = false }
            if !listening { self.pairingCode = "" }
            if !listening && wasListening && self.policy.wanted { self.scheduleRecovery() }
            UIApplication.shared.isIdleTimerDisabled = self.policy.foreground && (listening || self.running)
        }
        hub.onListenerFailure = { [weak self] in self?.hubStarting = false; self?.scheduleRecovery() }
        let processor = self.pipeline
        hub.onDisconnected = { [weak self,weak processor] in
            processor?.tvDisconnected()
            DispatchQueue.main.async { self?.tvConnected = false; self?.tvDocuments = false; self?.tvSpeakers = false }
        }
        hub.onConnected = { [weak self] in self?.tvConnected = true }
        hub.onCapabilities = { [weak self] in self?.tvDocuments = $0.contains("document_v1"); self?.tvSpeakers = $0.contains("speaker_v1") }
        hub.onRenderSignature = { [weak self] trace in if self?.quality[.punctuationTrace] == true { self?.tvRenderSignature = trace } }
        hub.onDisplayAck = { [weak self] id in
            guard let self, self.policy.wanted, !self.displayedIDs.contains(id) else { return }
            if self.displayedIDs.count >= 128 { self.displayedIDs.removeAll() }
            self.displayedIDs.insert(id)
            if !self.policy.foreground { self.backgroundDeliveries &+= 1 }
        }
        pipeline.onReading = { [weak self] ticket,active,pages,status in
            guard let self, self.readingTicket == ticket else { return }
            self.readingActive = active; self.readingPages = pages; self.readingStatus = status; self.readingPage = 0
            if !pages.isEmpty { self.showReadingPage() }
        }
        // Connection resets only the TV. Previously visible dialogue is deliberately not replayed.
        pipeline.onMetrics = { [weak self] in self?.metrics = $0 }
        pipeline.onError = { [weak self] in self?.errorMessage = $0 }
        let pipeline = self.pipeline
        pipeline.configureAdvanced(settings.advanced)
        hub.configureSpeakers(show:settings.advanced.showSpeakers,color:settings.advanced.speakerColor)
        remote.onFrame = { [weak pipeline] in pipeline?.offer($0) }
        monitor.pathUpdateHandler = { [weak self] path in
            let available = path.status == .satisfied
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.networkStatus = available ? (path.usesInterfaceType(.wifi) ? "Wi-Fi متصل" : "الشبكة متاحة") : "الشبكة غير متاحة"
                let changed = self.policy.network != available
                self.policy.network = available
                if self.policy.wanted && changed {
                    if !available { self.networkInterruptions += 1 }
                    self.recordSession(available ? "network.restored" : "network.unavailable","NWPathMonitor availability transition")
                }
                self.refreshAddresses()
                self.hub.validateAddress()
                if !available { self.pipeline.interrupt(); self.sessionStatus = "بانتظار Wi-Fi" }
                else { self.recoverSession() }
            }
        }
        monitor.start(queue:DispatchQueue(label:"dev.gamelingo.path"))
        refreshAddresses()
        timer = Timer.scheduledTimer(withTimeInterval:2,repeats:true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.sampleSystem() }
        }
        if translator.installed { loadModel() }
    }
    func refreshAddresses() {
        addresses = TVHub.localAddresses()
        if !addresses.contains(settings.localIP), let first = addresses.first { settings.localIP = first }
    }
    func sampleSystem() {
        packLibrary.refreshMetrics()
        let now = ProcessInfo.processInfo.systemUptime
        if policy.wanted && lastSystemSample > 0 && now-lastSystemSample > 8 { recordSession("execution.callback_gap","Main callback gap=\(Int(now-lastSystemSample))s; OS suspension is not confirmed") }
        lastSystemSample = now; remote.sampleHealth()
        let usage = resources.sample(); cpuPercent = usage.cpu; residentMegabytes = Double(usage.residentBytes)/1048576
        let battery = UIDevice.current.batteryLevel
        if running && battery >= 0 {
            if initialBattery < 0 { initialBattery = battery }
            batteryUsed = max(0,Double(initialBattery-battery)*100)
        }
        thermal = ProcessInfo.processInfo.thermalState
        availableMemory = UInt64(os_proc_available_memory())
        pipeline.configure(mode:settings.mode,thermal:thermal.rawValue,lowPower:ProcessInfo.processInfo.isLowPowerModeEnabled)
        if thermal == .critical && running { stop(reason:"أُوقفت الجلسة بسبب الحرارة"); errorMessage = "أُوقفت الجلسة بسبب الحالة الحرارية الحرجة" }
        if running && policy.canRecover && streamConnected && pipeline.frameAge > 12 { scheduleRecovery() }
    }
    func connectTV(automatic: Bool = false) {
        refreshAddresses(); pairingCode = ""
        hubStarting = true
        let host = settings.localIP, display = settings.display
        tvStatus = "جارٍ إعداد اتصال التلفزيون…"
        do { try hub.start(host:host,settings:display) }
        catch {
            hubStarting = false
            if automatic { sessionStatus = "تعذر ربط عنوان Wi-Fi؛ ستعاد المحاولة"; scheduleRecovery() }
            else { errorMessage = error.localizedDescription }
        }
    }
    func pair(host: String, account: String, pin: String) {
        do { try remote.pair(host:host,account:account,pin:pin); pairing = true }
        catch { errorMessage = error.localizedDescription }
    }
    func removeConsole(_ id: String) {
        if running { stop() }
        consoles.removeAll { $0.id == id }
        if settings.selectedConsoleID == id { settings.selectedConsoleID = consoles.first?.id }
        do { try KeychainStore.write(JSONEncoder().encode(consoles),account:"consoles.v1") }
        catch { errorMessage = error.localizedDescription }
    }
    func start() {
        guard !packLibrary.busy else { errorMessage = "انتظر اكتمال استيراد التعريب أو ألغِه قبل بدء الجلسة"; return }
        guard !running, modelReady, !pairing, let console = consoles.first(where:{ $0.id == settings.selectedConsoleID }) else { errorMessage = "اختر PS5 مسجلًا وجهّز نموذج الترجمة أولًا"; return }
        guard settings.roi.isValid else { errorMessage = "اضبط منطقة الحوار داخل حدود صورة البث أولًا"; return }
        do {
            packLibrary.store.resetMetrics()
            policy.start(); policy.experimentalAudio = settings.advanced.backgroundAudio
            SessionIntentStore.save(true); initialBattery = -1; batteryUsed = nil; UIDevice.current.isBatteryMonitoringEnabled = true
            displayedIDs.removeAll(); backgroundDeliveries = 0
            remoteMetrics = RemoteMetrics(); audioInterruptions = 0; networkInterruptions = 0
            sessionLog = SessionDiagnostics(); sessionDiagnostics = []; sessionStarted = Date(); lastSystemSample = ProcessInfo.processInfo.systemUptime
            sessionStartedUptime = lastSystemSample
            recordSession("session.start","Counters reset for this user-started session")
            sessionStatus = "جارٍ بدء الجلسة"; recoveryAttempts = 0
            if policy.experimentalAudio { audio.start() }
            try remote.connect(console)
            pipeline.start(roi:settings.roi,mode:settings.mode); pipelineActive = true; running = true
            if !tvListening && !hubStarting { connectTV() }
            UIApplication.shared.isIdleTimerDisabled = true
            applyDim()
        } catch { policy.stop(); SessionIntentStore.save(false); audio.stop(); errorMessage = error.localizedDescription }
    }
    func stop(reason: String = "أوقفها المستخدم") {
        recordSession("session.stop",reason+"; automatic recovery disabled")
        closeReading()
        policy.stop(); recoveryTask?.cancel(); recoveryTask = nil; endExecutionGrace(); audio.stop()
        SessionIntentStore.save(false); UIDevice.current.isBatteryMonitoringEnabled = false
        pipelineActive = false; sessionStatus = reason
        running = false; pairing = false; loginRequired = false; remote.stop(); pipeline.stop()
        UIApplication.shared.isIdleTimerDisabled = policy.foreground && tvListening
        if let brightness = originalBrightness { UIScreen.main.brightness = brightness; originalBrightness = nil }
    }
    func smartRead() {
        guard running, modelReady, streamConnected, tvConnected, tvDocuments else { return }
        let ticket = UUID(); readingTicket = ticket; readingActive = true; readingPages = []; readingPage = 0
        readingStatus = "جارٍ طلب إطار جديد…"; pipeline.requestReading(ticket:ticket)
    }
    func closeReading() {
        readingTicket = nil; readingActive = false; readingPages.removeAll(); readingPage = 0; readingStatus = "القراءة مغلقة"
        pipeline.closeReading()
    }
    func moveReadingPage(_ delta: Int) {
        guard !readingPages.isEmpty else { return }
        readingPage = max(0,min(readingPages.count-1,readingPage+delta)); showReadingPage()
    }
    private func showReadingPage() {
        guard readingActive, tvConnected, readingPages.indices.contains(readingPage) else { return }
        hub.publish(TVProtocol.envelope("document_show",fields:["translated":readingPages[readingPage],"page":readingPage+1,"pages":readingPages.count]))
    }
    func background() {
        lifecycle += 1; policy.foreground = false
        if policy.wanted { recordSession("lifecycle.background","UI left foreground; user intent remains active") }
        relaxDisplay()
        pipeline.setBackground(true)
        if policy.wanted && policy.canExecute { sessionStatus = "تجربة الخلفية نشطة؛ راقب وصول جمل جديدة على TCL"; return }
        if policy.wanted { beginExecutionGrace() }
        else { hub.stop(); pairingCode = ""; tvStatus = "أُوقف الاتصال عند مغادرة التطبيق" }
    }
    func foreground() {
        policy.foreground = true; endExecutionGrace()
        if policy.wanted { recordSession("lifecycle.foreground","Execution opportunity; preserve healthy sessions") }
        UIApplication.shared.isIdleTimerDisabled = tvListening || running
        applyDim()
        pipeline.setBackground(false)
        if policy.wanted { audio.recover(foreground:true); recoverSession() }
    }
    func updateBackgroundExperiment() {
        policy.experimentalAudio = settings.advanced.backgroundAudio
        if policy.wanted && policy.experimentalAudio { audio.start() }
        else { audio.stop() }
    }
    private func beginExecutionGrace() {
        guard policy.wanted, executionTask == .invalid else { return }
        sessionStatus = "مهلة خلفية محدودة؛ بانتظار السماح بالتنفيذ"
        executionTask = UIApplication.shared.beginBackgroundTask(withName:"GameLingo recovery") { [weak self] in
            Task { @MainActor [weak self] in self?.suspendForExecution() }
        }
        guard executionTask != .invalid else { suspendForExecution(); return }
        executionDeadline = Task { [weak self] in
            try? await Task.sleep(nanoseconds:20_000_000_000)
            guard !Task.isCancelled else { return }; self?.suspendForExecution()
        }
    }
    private func endExecutionGrace() {
        executionDeadline?.cancel(); executionDeadline = nil
        if executionTask != .invalid { UIApplication.shared.endBackgroundTask(executionTask); executionTask = .invalid }
    }
    private func suspendForExecution() {
        endExecutionGrace()
        guard !policy.canExecute else { return }
        recordSession("execution.unavailable","Finite execution grace expired; awaiting execution opportunity")
        remote.stop(); pipeline.pause(); pipelineActive = false; hub.stop(); hubStarting = false
        sessionStatus = "التنفيذ غير متاح؛ الاستئناف عند سماح iOS أو العودة للتطبيق"
    }
    private func scheduleRecovery() {
        guard policy.wanted, recoveryTask == nil else { return }
        let epoch = policy.epoch
        let delay = SessionPolicy.retryDelay(recoveryAttempts,jitter:Double.random(in:0...1))
        recoveryAttempts += 1
        recoveryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds:UInt64(delay*1_000_000_000))
            guard !Task.isCancelled, let self, self.policy.accepts(epoch) else { return }
            self.recoveryTask = nil; self.recoverSession()
        }
    }
    private func recoverSession() {
        guard policy.wanted else { return }
        guard modelReady else { sessionStatus = "بانتظار جاهزية نموذج الترجمة"; return }
        guard ProcessInfo.processInfo.thermalState != .critical else { sessionStatus = "بانتظار انخفاض الحرارة"; return }
        guard policy.network else { sessionStatus = "بانتظار الشبكة"; return }
        if policy.experimentalAudio && !audio.wanted { audio.start() }
        else { audio.recover() }
        guard policy.canRecover else { sessionStatus = "بانتظار السماح بالتنفيذ"; return }
        refreshAddresses()
        guard !addresses.isEmpty else { sessionStatus = "بانتظار عنوان Wi-Fi محلي"; scheduleRecovery(); return }
        if !pipelineActive { pipeline.start(roi:settings.roi,mode:settings.mode,preservingState:true); pipelineActive = true }
        if let console = consoles.first(where:{ $0.id == settings.selectedConsoleID }) {
            remote.recover(console,stalled:streamConnected && pipeline.frameAge > 12)
        }
        if !tvListening && !hubStarting { connectTV(automatic:true) }
        sessionStatus = streamConnected ? "الترجمة نشطة" : "جارٍ استرداد الاتصال"
    }
    func applyDim() {
        if running && settings.dimScreen && policy.foreground {
            if originalBrightness == nil { originalBrightness = UIScreen.main.brightness }
            UIScreen.main.brightness = 0.04
        } else if let brightness = originalBrightness { UIScreen.main.brightness = brightness; originalBrightness = nil }
    }
    func relaxDisplay() {
        UIApplication.shared.isIdleTimerDisabled = false
        if let brightness = originalBrightness { UIScreen.main.brightness = brightness; originalBrightness = nil }
    }
    func loadModel() {
        modelBusy = true; modelReady = false; modelStatus = "جارٍ تحميل النموذج في الذاكرة…"
        translator.load { [weak self] result in
            guard let self else { return }; self.modelBusy = false
            switch result {
            case .success: self.modelReady = true; self.modelStatus = "English → Arabic جاهز دون إنترنت"; self.recoverSession()
            case .failure(let error): self.modelStatus = "النموذج غير جاهز"; self.errorMessage = error.localizedDescription
            }
        }
    }
    func downloadModel() {
        guard !modelBusy, !running else { return }
        modelBusy = true; modelStatus = "تنزيل النموذج · 88.5 MB؛ يلزم الإنترنت لهذه الخطوة فقط"
        downloadTask = Task { [weak self] in
            guard let self else { return }
            do {
                var request = URLRequest(url:OfflineTranslator.modelURL)
                request.setValue("GameLingo/1.0",forHTTPHeaderField:"User-Agent")
                let (location,response) = try await URLSession.shared.download(for:request)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw LingoError.invalid("فشل تنزيل النموذج") }
                self.installModel(location,temporary:true)
            } catch { self.modelBusy = false; self.errorMessage = error.localizedDescription; self.modelStatus = "فشل التنزيل" }
        }
    }
    func importModel(_ url: URL) {
        guard !running, !modelBusy else { return }
        let access = url.startAccessingSecurityScopedResource()
        modelBusy = true; modelStatus = "جارٍ التحقق من النموذج وتثبيته…"
        translator.install(package:url) { [weak self] result in
            if access { url.stopAccessingSecurityScopedResource() }
            self?.installed(result)
        }
    }
    private func installModel(_ url: URL, temporary: Bool) {
        translator.install(package:url) { [weak self] result in
            if temporary { try? FileManager.default.removeItem(at:url) }
            self?.installed(result)
        }
    }
    private func installed(_ result: Result<Void,Error>) {
        switch result { case .success: loadModel(); case .failure(let error): modelBusy = false; modelStatus = "تعذر تثبيت النموذج"; errorMessage = error.localizedDescription }
    }
    func removeModel() {
        guard !running, !modelBusy else { return }
        modelReady = false; modelBusy = true
        translator.remove { [weak self] result in
            guard let self else { return }; self.modelBusy = false; self.modelStatus = "النموذج غير مثبت"
            if case .failure(let error) = result { self.errorMessage = error.localizedDescription }
        }
    }
    func preview(_ show: Bool) { hub.configure(settings.display,kind:show ? "subtitle_preview_show" : "subtitle_preview_hide") }
    private func scheduleStyle() {
        styleTask?.cancel()
        styleTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds:120_000_000)
            guard !Task.isCancelled, let self else { return }
            self.hub.configure(self.settings.display,showSpeakers:self.settings.advanced.showSpeakers,speakerColor:self.settings.advanced.speakerColor)
        }
    }
    func move(x: Double,y: Double,step: Double) {
        settings.display.set("x",.number(settings.display.number("x")+x*step))
        settings.display.set("y",.number(settings.display.number("y")+y*step))
    }
}
