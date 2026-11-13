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
            if oldValue.display != settings.display { scheduleStyle() }
        }
    }
    @Published var consoles: [ConsoleCredentials] = []
    @Published var discovered: [DiscoveredConsole] = []
    @Published var remoteStatus = "البث متوقف"
    @Published var tvStatus = "التلفزيون غير متصل"
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
        remote.onStopped = { [weak self] in self?.stop() }
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
        hub.onPairing = { [weak self] _,code in self?.pairingCode = code }
        let processor = self.pipeline
        hub.onDisconnected = { [weak processor] in processor?.tvDisconnected() }
        // Connection resets only the TV. Previously visible dialogue is deliberately not replayed.
        pipeline.onMetrics = { [weak self] in self?.metrics = $0 }
        pipeline.onError = { [weak self] in self?.errorMessage = $0 }
        let pipeline = self.pipeline
        remote.onFrame = { [weak pipeline] in pipeline?.offer($0) }
        monitor.pathUpdateHandler = { [weak self] path in
            let available = path.status == .satisfied
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.networkStatus = available ? (path.usesInterfaceType(.wifi) ? "Wi-Fi متصل" : "الشبكة متاحة") : "الشبكة غير متاحة"
                self.refreshAddresses()
                if !available { self.pipeline.interrupt() }
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
        let host = settings.localIP, display = settings.display
        tvStatus = "جارٍ إعداد اتصال التلفزيون…"
        do { try hub.start(host:host,settings:display) }
        catch { errorMessage = error.localizedDescription }
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
            try remote.connect(console)
            pipeline.start(roi:settings.roi,mode:settings.mode); running = true
            UIApplication.shared.isIdleTimerDisabled = true
            applyDim()
        } catch { errorMessage = error.localizedDescription }
    }
    func stop() {
        running = false; pairing = false; loginRequired = false; remote.stop(); pipeline.stop()
        UIApplication.shared.isIdleTimerDisabled = false
        if let brightness = originalBrightness { UIScreen.main.brightness = brightness; originalBrightness = nil }
    }
    func background() {
        lifecycle += 1; stop(); hub.stop(); pairingCode = ""; tvStatus = "أُوقف الاتصال عند مغادرة التطبيق؛ أعد تشغيله من تبويب الاتصال"
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
                let (location,response) = try await URLSession.shared.download(from:OfflineTranslator.modelURL)
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
