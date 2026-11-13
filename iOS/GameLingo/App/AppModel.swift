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
            pipeline.configureAdvanced(settings.advanced)
            hub.configureSpeakers(show:settings.advanced.showSpeakers,color:settings.advanced.speakerColor)
            if oldValue.display != settings.display { scheduleStyle() }
        }
    }
    @Published var consoles: [ConsoleCredentials] = []
    @Published var discovered: [DiscoveredConsole] = []
    @Published var remoteStatus = "البث متوقف"
    @Published var tvStatus = "التلفزيون غير متصل"
    @Published var tvDiagnostics: [String] = []
    @Published var tvListening = false
    @Published var sessionStatus = "متوقفة"
    @Published var audioStatus = "تجربة الخلفية متوقفة"
    @Published var streamConnected = false
    @Published var recoveryAttempts = 0
    @Published var backgroundDeliveries: UInt64 = 0
    @Published var networkStatus = "جارٍ فحص الشبكة"
    @Published var modelStatus = "لم يُحمّل النموذج"
    @Published var pairingCode = ""
    @Published var errorMessage: String?
    @Published var running = false
    @Published var modelReady = false
    @Published var modelBusy = false
    @Published var metrics = PipelineMetrics()
    @Published var thermal = ProcessInfo.processInfo.thermalState
    @Published var availableMemory: UInt64 = 0
    @Published var loginRequired = false
    @Published var pairing = false
    @Published var addresses: [String] = []
    let translator = OfflineTranslator()
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

    init() {
        do {
            if let data = try KeychainStore.read("consoles.v1") {
                consoles = try JSONDecoder().decode([ConsoleCredentials].self,from:data)
                for console in consoles { try console.validate() }
            }
        } catch { errorMessage = error.localizedDescription; consoles = [] }
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
            if connected { self.recoveryAttempts = 0; self.sessionStatus = "البث متصل؛ الترجمة نشطة" }
        }
        audio.onChange = { [weak self] active,interrupted,text in
            guard let self else { return }
            self.audioStatus = text; self.policy.audioActive = active; self.policy.interrupted = interrupted
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
            self.tvListening = listening
            if !listening { self.pairingCode = "" }
            if !listening && self.policy.wanted { self.scheduleRecovery() }
            UIApplication.shared.isIdleTimerDisabled = listening || self.running
        }
        let processor = self.pipeline
        hub.onDisconnected = { [weak processor] in processor?.tvDisconnected() }
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
                self.policy.network = available
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
        thermal = ProcessInfo.processInfo.thermalState
        availableMemory = UInt64(os_proc_available_memory())
        pipeline.configure(mode:settings.mode,thermal:thermal.rawValue,lowPower:ProcessInfo.processInfo.isLowPowerModeEnabled)
        if thermal == .critical && running { stop(); errorMessage = "أُوقفت الجلسة بسبب الحالة الحرارية الحرجة" }
    }
    func connectTV() {
        refreshAddresses(); pairingCode = ""
        hubStarting = true
        let host = settings.localIP, display = settings.display
        tvStatus = "جارٍ إعداد اتصال التلفزيون…"
        do { try hub.start(host:host,settings:display) }
        catch { hubStarting = false; errorMessage = error.localizedDescription }
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
        guard !running, modelReady, !pairing, let console = consoles.first(where:{ $0.id == settings.selectedConsoleID }) else { errorMessage = "اختر PS5 مسجلًا وجهّز نموذج الترجمة أولًا"; return }
        guard settings.roi.isValid else { errorMessage = "اضبط منطقة الحوار داخل حدود صورة البث أولًا"; return }
        do {
            policy.start(); policy.experimentalAudio = settings.advanced.backgroundAudio
            sessionStatus = "جارٍ بدء الجلسة"; recoveryAttempts = 0
            if policy.experimentalAudio { audio.start() }
            try remote.connect(console)
            pipeline.start(roi:settings.roi,mode:settings.mode); pipelineActive = true; running = true
            if !tvListening && !hubStarting { connectTV() }
            UIApplication.shared.isIdleTimerDisabled = true
            applyDim()
        } catch { policy.stop(); audio.stop(); errorMessage = error.localizedDescription }
    }
    func stop() {
        policy.stop(); recoveryTask?.cancel(); recoveryTask = nil; endExecutionGrace(); audio.stop()
        pipelineActive = false; sessionStatus = "أوقفها المستخدم"
        running = false; pairing = false; loginRequired = false; remote.stop(); pipeline.stop()
        UIApplication.shared.isIdleTimerDisabled = tvListening
        if let brightness = originalBrightness { UIScreen.main.brightness = brightness; originalBrightness = nil }
    }
    func background() {
        lifecycle += 1; policy.foreground = false
        pipeline.setBackground(true)
        if policy.wanted && policy.canExecute { sessionStatus = "تجربة الخلفية نشطة؛ راقب وصول جمل جديدة على TCL"; return }
        if policy.wanted { beginExecutionGrace() }
        else { hub.stop(); pairingCode = ""; tvStatus = "أُوقف الاتصال عند مغادرة التطبيق" }
    }
    func foreground() {
        policy.foreground = true; endExecutionGrace()
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
        guard policy.network else { sessionStatus = "بانتظار الشبكة"; return }
        audio.recover()
        guard policy.canRecover else { sessionStatus = "بانتظار السماح بالتنفيذ"; return }
        if !pipelineActive { pipeline.start(roi:settings.roi,mode:settings.mode,preservingState:true); pipelineActive = true }
        if let console = consoles.first(where:{ $0.id == settings.selectedConsoleID }) { remote.recover(console) }
        if !tvListening {
            // A previous bind failure must not leave the UI's in-progress flag stuck.
            hubStarting = false; connectTV()
        }
        sessionStatus = streamConnected ? "الترجمة نشطة" : "جارٍ استرداد الاتصال"
    }
    func applyDim() {
        if running && settings.dimScreen {
            if originalBrightness == nil { originalBrightness = UIScreen.main.brightness }
            UIScreen.main.brightness = 0.04
        } else if let brightness = originalBrightness { UIScreen.main.brightness = brightness; originalBrightness = nil }
    }
    func loadModel() {
        modelBusy = true; modelReady = false; modelStatus = "جارٍ تحميل النموذج في الذاكرة…"
        translator.load { [weak self] result in
            guard let self else { return }; self.modelBusy = false
            switch result {
            case .success: self.modelReady = true; self.modelStatus = "English → Arabic جاهز دون إنترنت"
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
            guard !Task.isCancelled, let self else { return }; self.hub.configure(self.settings.display)
        }
    }
    func move(x: Double,y: Double,step: Double) {
        settings.display.set("x",.number(settings.display.number("x")+x*step))
        settings.display.set("y",.number(settings.display.number("y")+y*step))
    }
}
