import SwiftUI
import Network
import Darwin
import os
import WidgetKit

@MainActor
final class AppModel: ObservableObject {
    @Published var settings = AppSettings.load() {
        didSet {
            do { try settings.save() } catch { errorMessage = error.localizedDescription }
            pipeline.configure(mode:settings.mode,thermal:ProcessInfo.processInfo.thermalState.rawValue,lowPower:ProcessInfo.processInfo.isLowPowerModeEnabled)
            if oldValue.advanced != settings.advanced { pipeline.configureAdvanced(settings.advanced) }
            if oldValue.display != settings.display || oldValue.advanced.showSpeakers != settings.advanced.showSpeakers || oldValue.advanced.speakerColor != settings.advanced.speakerColor { scheduleStyle() }
            saveCurrentProfile()
        }
    }
    @Published var quality = QualitySettings.load() {
        didSet {
            quality.save(); packLibrary.store.configureQuality(PackQualityOptions(quality)); packLibrary.configureQuality(quality); pipeline.configureQuality(quality)
            if oldValue[.measurement] != quality[.measurement] { packLibrary.metrics = HybridMetrics(); packLibrary.store.resetMetrics() }
            if (!oldValue[.learnNames] && quality[.learnNames]) || oldValue[.packLabels] != quality[.packLabels] || oldValue[.packMarkup] != quality[.packMarkup] { refreshPackNamePairs() }
            if !quality[.corrections] { correctionsLibrary.clearRecent() }
            saveCurrentProfile()
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
    @Published var tvMenus = false
    @Published var tvSpatial = false
    @Published var tvRegionEditing = false
    @Published var tvPersistentPreview = false
    @Published var readingActive = false
    @Published var readingPages: [String] = []
    @Published var readingPage = 0
    @Published var readingStatus = "القراءة مغلقة"
    @Published var currentMenuReadout = CurrentMenuReadout()
    @Published private(set) var menuSuggestionVisible = false
    private(set) var menuSuggestionToken = UUID()
    func receiveMenuSuggestion(_ visible: Bool, token: UUID, expiresAt: Double) {
        guard token == menuSuggestionToken else { return }
        menuSuggestionVisible = visible && ProcessInfo.processInfo.systemUptime < expiresAt && gameOptions.suggestMenus == true && running && streamConnected && !readingActive && currentMenuTicket == nil
    }
    private func configureMenuOptions() {
        menuSuggestionToken = UUID(); menuSuggestionVisible = false
        pipeline.configureMenus(gameOptions,suggestionToken:menuSuggestionToken)
    }
    private var currentMenuTicket: UUID?
    func translateCurrentMenu() {
        guard running, modelReady, streamConnected, !readingActive else {
            errorMessage = "ابدأ بث PS5 وأغلق قراءة المستند قبل طلب القائمة"; return
        }
        let ticket = UUID(); currentMenuTicket = ticket
        menuSuggestionVisible = false
        currentMenuReadout = CurrentMenuReadout(active:true,status:"بانتظار إطار جديد للقائمة…")
        pipeline.requestCurrentMenu(ticket:ticket)
    }
    func closeCurrentMenu() {
        if currentMenuTicket != nil {
            localMenuItems = []; localMenuUntil = 0
            hub.publish(TVProtocol.envelope("menu_clear"))
        }
        currentMenuTicket = nil; currentMenuReadout = CurrentMenuReadout()
        pipeline.closeCurrentMenu()
    }
    @Published var cpuPercent = 0.0
    @Published var residentMegabytes = 0.0
    @Published var batteryUsed: Double?
    @Published var networkStatus = "جارٍ فحص الشبكة"
    @Published var modelStatus = "لم يُحمّل النموذج"
    @Published var pairingCode = ""
    @Published var errorMessage: String?
    @Published var showingPackLibrary = false
    @Published var running = false
    var modelAvailable: Bool { modelReady || (translator.installed && !modelBusy) }
    @Published var modelReady = false
    @Published var modelBusy = false
    let modelDownload = ModelDownloadService()
    private var modelRequest = UUID()
    let improvementWorker = ImprovementWorker()
    @Published var learningConsent = false {
        didSet { improvementWorker.setConsent(learningConsent); pipeline.configureLearning(learningConsent); if !learningConsent && !running { translator.cancel() } }
    }
    @Published var improvementStatus = "التحسين المحلي متوقف"
    @Published var improvementExport: URL?
    func runImprovement() { guard !running, modelReady, learningConsent else { return }; improvementWorker.run(translator:translator) }
    func exportImprovement() { improvementWorker.export { [weak self] in self?.improvementExport = $0 } }
    @Published var metrics = PipelineMetrics()
    @Published var thermal = ProcessInfo.processInfo.thermalState
    @Published var availableMemory: UInt64 = 0
    @Published var loginRequired = false
    @Published var pairing = false
    @Published var addresses: [String] = []
    @Published var localSubtitles = LocalSubtitleState()
    @Published var previewFrame: UIImage?
    @Published var setupLines: [OCRLine] = []
    @Published var localMenuItems: [MenuOverlayItem] = []
    @Published var localMenuAppearance = MenuAppearance()
    @Published var localMenuUntil = 0.0
    @Published var gameOptions = GameOptions() {
        didSet {
            guard !applyingProfile else { return }
            if oldValue.destination != gameOptions.destination {
                localSubtitles.clear(); hub.publish(TVProtocol.envelope("subtitle_clear"))
                localMenuItems = []; localMenuUntil = 0; hub.publish(TVProtocol.envelope("menu_clear"))
                if previewActive { preview(false); preview(true) }
                if running && gameOptions.destination.tvEnabled && !tvListening && !hubStarting { connectTV() }
            }
            if oldValue.menusEnabled != gameOptions.menusEnabled || oldValue.allowedMenus != gameOptions.allowedMenus || oldValue.menuRegion != gameOptions.menuRegion || oldValue.currentMenuAppearance != gameOptions.currentMenuAppearance || oldValue.suggestMenus != gameOptions.suggestMenus {
                configureMenuOptions()
            }
            saveCurrentProfile()
        }
    }
    @Published var previewActive = false
    @Published var currentGame = "general"
    @Published var gameProfiles: [GameProfile] = []
    private var profileStore: GameProfileStore?
    private var applyingProfile = false
    private var profileReady = false
    private var profileSelection: String?
    private var regionTicket: UUID?
    private var regionGame: String?
    func startTVRegionEditing() {
        guard tvConnected, tvRegionEditing else { errorMessage = "يلزم تحديث GameLingo TV لدعم تحديد المنطقة بالريموت"; return }
        let ticket = UUID(); regionTicket = ticket; regionGame = currentGame
        let b = settings.roi
        hub.publish(TVProtocol.envelope("roi_edit_start",fields:["ticket":ticket.uuidString,"box":["x":b.x,"y":b.y,"w":b.w,"h":b.h]]))
    }
    let packLibrary = GamePackLibrary()
    let namesLibrary = GameNamesLibrary()
    let correctionsLibrary = CorrectionsLibrary()
    private func refreshPackNamePairs() {
        guard quality[.learnNames] else { return }
        packLibrary.store.alignedNamePairs { [weak self] game,pack,pairs in
            guard let self, self.quality[.learnNames], game == self.packLibrary.state.registry.selectedGame,
                  pack != nil, pack == self.packLibrary.state.registry.packs.first(where:{$0.manifest.gameId == game && $0.enabled})?.id,
                  self.packLibrary.state.loaded, self.namesLibrary.snapshot.game == (game ?? "general") else { return }
            self.namesLibrary.seed(pairs)
        }
        guard quality[.packLabels] else { return }
        packLibrary.store.qualityNames { [weak self] game,pack,names in
            guard let self, self.quality[.learnNames], self.quality[.packLabels], self.packLibrary.state.loaded,
                  game == self.packLibrary.state.registry.selectedGame, self.namesLibrary.snapshot.game == (game ?? "general"),
                  pack != nil, pack == self.packLibrary.state.registry.packs.first(where:{$0.manifest.gameId == game && $0.enabled})?.id else { return }
            self.namesLibrary.seedPackLabels(names)
        }
    }
    lazy var translator = OfflineTranslator(packs:packLibrary.store)
    let hub = TVHub()
    let remote = RemotePlayService()
    private let outputFence = DeliveryFence()
    private lazy var pipeline = FramePipeline(translator:translator,publish:{ [weak self,fence = self.outputFence] message in
        let epoch = fence.snapshot()
        DispatchQueue.main.async { if fence.accepts(epoch) { self?.route(message) } }
    })
    func route(_ message: [String:Any]) {
        let type = message["type"] as? String ?? ""
        guard running || ["subtitle_clear","document_hide","menu_clear"].contains(type) else { return }
        if type == "menu_snapshot", let id = message["menu_id"] as? String, id.hasPrefix("current-") {
            guard streamConnected, let ticket = currentMenuTicket, id == "current-"+ticket.uuidString else { return }
        }
        if gameOptions.destination.tvEnabled && (type != "menu_snapshot" || (message["spatial"] as? Bool == true ? tvSpatial : tvMenus)) { hub.publish(message) }
        if gameOptions.destination.phoneEnabled {
            localSubtitles.apply(message,settings:settings.display,now:ProcessInfo.processInfo.systemUptime)
            if type == "menu_clear" { localMenuItems = []; localMenuUntil = 0 }
            if type == "menu_snapshot", let raw = message["items"], let data = try? JSONSerialization.data(withJSONObject:raw),
               let items = try? JSONDecoder().decode([MenuOverlayItem].self,from:data), items.count <= 24,
               let style = message["appearance"], let styleData = try? JSONSerialization.data(withJSONObject:style),
               let appearance = try? JSONDecoder().decode(MenuAppearance.self,from:styleData), appearance.valid {
                localMenuItems = items; localMenuAppearance = appearance; localMenuUntil = ProcessInfo.processInfo.systemUptime+1.8
            }
        }
    }
    func framePreview(_ enabled: Bool) { pipeline.setPreview(enabled); if !enabled { previewFrame = nil; setupLines = [] } }
    func captureMenuSetup(_ region: SourceBox) { setupLines = []; pipeline.requestSetupFrame(region:region) }
    func saveRegion(_ box: SourceBox, menu: Bool) {
        guard box.isValid else { return }
        if menu { gameOptions.menuRegion = box }
        else { settings.roi = box; gameOptions.manualDialogueRegion = true; pipeline.configureRegion(box,manual:true) }
    }
    func saveMenu(_ menu: AllowedMenu) {
        guard menu.valid, gameOptions.allowedMenus.count < 32 || gameOptions.allowedMenus.contains(where:{$0.id == menu.id}) else { errorMessage = "اختر ثلاثة دلائل ثابتة مميزة مع مواقعها على الأقل؛ لا تستخدم قيمًا رقمية متغيرة"; return }
        if let i = gameOptions.allowedMenus.firstIndex(where:{$0.id == menu.id}) { gameOptions.allowedMenus[i] = menu }
        else { gameOptions.allowedMenus.append(menu) }
    }
    private func optionsSnapshot() -> GameOptions {
        var value = gameOptions; value.display = settings.display; value.dialogueRegion = settings.roi; value.advanced = settings.advanced; value.quality = quality
        value.packEnabled = packLibrary.state.registry.packs.first(where:{$0.manifest.gameId == currentGame})?.enabled ?? gameOptions.packEnabled
        return value
    }
    private func saveCurrentProfile() {
        guard profileReady, !applyingProfile, let profileStore, profileStore.profile(currentGame)?.enabled == true else { return }
        do { try profileStore.update(currentGame,options:optionsSnapshot()); gameProfiles = profileStore.profiles }
        catch { errorMessage = error.localizedDescription }
    }
    private func activateProfile(_ game: String?) {
        guard !applyingProfile else { return }
        let id = game ?? "general"
        guard !profileReady || currentGame != id else { return }
        if running { stop(reason:"توقفت الجلسة لتبديل ملف اللعبة") }
        regionTicket = nil; regionGame = nil; hub.publish(TVProtocol.envelope("roi_edit_end"))
        preview(false); pipeline.interrupt(); translator.cancel()
        outputFence.invalidate()
        do {
            guard let profileStore else { return }
            let title = packLibrary.state.registry.packs.first(where:{$0.manifest.gameId == game})?.manifest.gameTitle ?? (id == "general" ? "عام" : id)
            let packEnabled = packLibrary.state.registry.packs.first(where:{$0.manifest.gameId == id})?.enabled ?? true
            var migration = optionsSnapshot(); migration.packEnabled = packEnabled
            try profileStore.ensure(id,title:title,migration:migration,packEnabled:packEnabled)
            let value = profileStore.profile(id)!.effective
            applyingProfile = true; profileReady = true; currentGame = id; gameOptions = value
            var display = value.display
            display.revision = max(settings.display.revision+1,Int64(Date().timeIntervalSince1970*1000))
            settings.display = display; settings.roi = value.dialogueRegion; settings.advanced = value.advanced; quality = value.quality
            applyingProfile = false; profileReady = true; gameProfiles = profileStore.profiles
            configureMenuOptions()
            pipeline.configureRegion(value.dialogueRegion,manual:value.manualDialogueRegion)
            if let pack = packLibrary.state.registry.packs.first(where:{$0.manifest.gameId == id}), pack.enabled != value.packEnabled { packLibrary.store.enable(pack.id,value.packEnabled) }
        } catch { applyingProfile = false; errorMessage = error.localizedDescription }
    }
    func selectGame(_ id: String) { if running { stop(reason:"توقفت الجلسة لتبديل اللعبة") }; packLibrary.store.changeSelection(game:id == "general" ? nil : id) }
    func addGame(title: String) {
        do { let id = "game-"+UUID().uuidString.lowercased(); try profileStore?.ensure(id,title:title); gameProfiles = profileStore?.profiles ?? []; selectGame(id) }
        catch { errorMessage = error.localizedDescription }
    }
    func changeProfile(_ action: String) {
        if running { stop(reason:"توقفت الجلسة لتعديل ملف اللعبة") }
        do {
            switch action {
            case "disable": try profileStore?.enable(currentGame,false)
            case "enable": try profileStore?.enable(currentGame,true)
            case "reset": try profileStore?.reset(currentGame)
            case "undo": try profileStore?.undo(currentGame)
            default: break
            }
            profileReady = false; activateProfile(currentGame == "general" ? nil : currentGame)
        } catch { errorMessage = error.localizedDescription }
    }
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
    private var memoryCheckpoints: [String:UInt64] = [:]
    private var peakResident: UInt64 = 0
    private var startAfterModelLoad = false
    private var controlObserver: NSObjectProtocol?
    private var pressureObserver: NSObjectProtocol?
    @Published private(set) var spatialMetrics = SpatialMetrics()
    private func syncControl() {
        let phase: SessionControlSnapshot.Phase = !policy.wanted ? .stopped : !pipelineActive ? .suspended : streamConnected ? .active : .recovering
        let changed = SessionControlStore.snapshot().phase != phase
        SessionControlStore.save(phase)
        if changed, #available(iOS 18.0, *) { ControlCenter.shared.reloadControls(ofKind:SessionControlStore.kind) }
    }
    private func consumeControlRequest() {
        guard let enabled = SessionControlStore.consumeRequest() else { return }
        if enabled { if !running { start() } } else { stop(reason:"أُوقفت من مركز التحكم") }
    }
    private var initialBattery: Float = -1
    private var sessionLog = SessionDiagnostics()
    private var lastSystemSample = 0.0
    private var sessionStartedUptime = 0.0
    var performanceSnapshot: String {
        func age(_ at: Double?) -> String { at.map { NumericInput.format(max(0,ProcessInfo.processInfo.systemUptime-$0))+" s" } ?? "not observed" }
        let values = [
            "GameLingo 0.5.0 (11)", "Measurement started: \(sessionStarted.formatted())", sessionStatus, audioStatus,
            "CPU: \(NumericInput.format(cpuPercent))% (100%=one core)", "RSS: \(NumericInput.format(residentMegabytes)) MB", "Thermal: \(thermal.rawValue)",
            "Translation p95: \(NumericInput.format(metrics.translationP95)) ms", "OCR p95: \(NumericInput.format(metrics.ocrP95)) ms",
            "PS5 native connected: \(streamConnected); encoded age: \(remoteMetrics.encodedFrameAge.map(NumericInput.format) ?? "none"); decoded age: \(remoteMetrics.decodedFrameAge.map(NumericInput.format) ?? "none")",
            "Last processed frame age: \(age(metrics.lastFrameAt)); last OCR age: \(age(metrics.lastOCRAt)); last translation publication age: \(age(metrics.lastTranslationAt))",
            "TV connected: \(tvConnected); destination: \(gameOptions.destination.rawValue)",
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
            "TV actual-render signature: \(tvRenderSignature)", spatialMetrics.summary,
            "Peak sampled RSS MB: \(Double(peakResident)/1048576)",
            "RSS checkpoints (whole-process bytes, not allocator attribution): \(memoryCheckpoints)",
            "Memory limits: latest CVPixelBuffer <=1; compressed decode queue <=8; translation cache <=256; pack pages <=2 MiB; spatial pages <=1 MiB; learning ingress <=16. Native/Swift/VT/Vision/Chiaki allocator attribution requires device Instruments."
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

    init(profileRoot: URL? = nil) {
        SessionControlStore.save(.stopped)
        memoryCheckpoints["app.initialized"] = ResourceMonitor.residentBytes()
        translator.onResource = { [weak self] stage,bytes in self?.memoryCheckpoints[stage] = bytes }
        pipeline.onSpatialMetrics = { [weak self] in self?.spatialMetrics = $0 }
        controlObserver = NotificationCenter.default.addObserver(forName:Notification.Name("GameLingoControlRequest"),object:nil,queue:.main) { [weak self] _ in
            Task { @MainActor in self?.consumeControlRequest() }
        }
        pressureObserver = NotificationCenter.default.addObserver(forName:UIApplication.didReceiveMemoryWarningNotification,object:nil,queue:.main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.memoryCheckpoints["memory.warning"] = ResourceMonitor.residentBytes()
                self.pipeline.memoryPressure(); self.translator.memoryPressure()
                if !self.running { self.translator.releaseResources(); self.modelReady = false }
            }
        }
        improvementWorker.onUpdate = { [weak self] status,snapshot in self?.improvementStatus = status; self?.pipeline.configureImprovedMemory(snapshot) }
        modelDownload.completion = { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let file):
                guard self.modelBusy else { try? FileManager.default.removeItem(at:file); return }
                self.installModel(file,temporary:true)
            case .failure(let error): self.modelBusy = false; self.modelStatus = "تعذر تنزيل النموذج"; self.errorMessage = error.localizedDescription
            }
        }
        do { profileStore = try GameProfileStore(root:profileRoot ?? FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("GameProfiles",isDirectory:true)) }
        catch { errorMessage = error.localizedDescription }
        try? LocalizationInbox().prepare()
        packLibrary.store.configureQuality(PackQualityOptions(quality)); packLibrary.configureQuality(quality); pipeline.configureQuality(quality)
        pipeline.onCaptureState = { [weak self] active,file in self?.qualityCaptureActive = active; self?.qualityCaptureFile = file }
#if GAMELINGO_TYPEWRITER_RESEARCH
        pipeline.onTypewriterDetected = { [weak self] game in
            guard let self, self.quality[.typewriter], !self.quality.typewriterGames.contains(game) else { return }
            self.quality.rememberTypewriter(game:game)
        }
#endif
        pipeline.captureAction()
        pipeline.onLearningExample = { [weak self] example in
            guard let self, self.learningConsent, self.running, self.currentGame == example.game else { return }; self.improvementWorker.observe(example)
        }
        pipeline.onPreview = { [weak self] image,lines in self?.previewFrame = UIImage(cgImage:image); if !lines.isEmpty { self?.setupLines = lines } }
        namesLibrary.onChange = { [weak self] store,snapshot in self?.pipeline.configureNames(store,snapshot:snapshot) }
        pipeline.configureNames(namesLibrary.store,snapshot:namesLibrary.snapshot)
        correctionsLibrary.onChange = { [weak self] snapshot in
            guard let self else { return }; self.pipeline.configureCorrections(snapshot,recentToken:self.correctionsLibrary.historyToken)
        }
        pipeline.configureCorrections(correctionsLibrary.snapshot,recentToken:correctionsLibrary.historyToken)
        pipeline.onRecentPublished = { [weak self] line,token in
            guard let self, self.running, self.quality[.corrections] else { return }
            self.correctionsLibrary.published(line,token:token)
        }
        packLibrary.onNamesChanged = { [weak self] names in
            guard let self else { return }
            self.activateProfile(self.packLibrary.state.registry.selectedGame)
            self.namesLibrary.select(self.packLibrary.state.registry.selectedGame)
            self.correctionsLibrary.select(self.packLibrary.state.registry.selectedGame)
            self.pipeline.configurePackNames(names); self.refreshPackNamePairs()
            self.saveCurrentProfile()
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
        remote.onPermanentStop = { [weak self] cause in
            guard let self, self.policy.wanted else { return }
            self.stop(reason:cause == .rest ? "PS5 في وضع الراحة؛ يلزم بدء يدوي" : "انتهى اتصال PS5؛ يلزم بدء يدوي")
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
            if !connected { self.configureMenuOptions() }
            if !connected && self.policy.wanted {
                self.sessionStatus = !self.policy.canExecute ? "بانتظار السماح بالتنفيذ" : !self.policy.network ? "بانتظار الشبكة" : "جارٍ استرداد بث PS5"
            }
            if connected { self.recoveryAttempts = 0; self.sessionStatus = "البث متصل؛ الترجمة نشطة" }
            self.syncControl()
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
        hub.onControl = { [weak self] message in
            guard let self else { return }
            if message["type"] as? String == "roi_edit_request" { self.startTVRegionEditing(); return }
            guard let ticket = self.regionTicket, message["ticket"] as? String == ticket.uuidString, self.regionGame == self.currentGame else { return }
            self.regionTicket = nil; self.regionGame = nil
            if message["save"] as? Bool == true, let raw = message["box"], let data = try? JSONSerialization.data(withJSONObject:raw), let box = try? JSONDecoder().decode(SourceBox.self,from:data), box.isValid { self.saveRegion(box,menu:false) }
        }
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
        hub.onDisconnected = { [weak self] in
            DispatchQueue.main.async { self?.tvConnected = false; self?.tvDocuments = false; self?.tvSpeakers = false; self?.tvMenus = false; self?.regionTicket = nil; self?.regionGame = nil }
        }
        hub.onConnected = { [weak self] in self?.tvConnected = true }
        hub.onCapabilities = { [weak self] in
            self?.tvDocuments = $0.contains("document_v1"); self?.tvSpeakers = $0.contains("speaker_v1")
            self?.tvSpatial = $0.contains("spatial_v1"); self?.tvMenus = $0.contains("menu_v1"); self?.tvRegionEditing = $0.contains("roi_edit_v1"); self?.tvPersistentPreview = $0.contains("persistent_preview_v1")
        }
        hub.onRenderSignature = { [weak self] trace in if self?.quality[.punctuationTrace] == true { self?.tvRenderSignature = trace } }
        hub.onDisplayAck = { [weak self] id in
            guard let self, self.policy.wanted, !self.displayedIDs.contains(id) else { return }
            if self.displayedIDs.count >= 128 { self.displayedIDs.removeAll() }
            self.displayedIDs.insert(id)
            if !self.policy.foreground { self.backgroundDeliveries &+= 1 }
        }
        pipeline.onCurrentMenu = { [weak self] ticket,state in
            guard let self, self.currentMenuTicket == ticket else { return }
            self.currentMenuReadout = state
        }
        pipeline.onMenuSuggestion = { [weak self] token,visible,expiresAt in self?.receiveMenuSuggestion(visible,token:token,expiresAt:expiresAt) }
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
                self.remote.networkChanged(available)
                if self.policy.wanted && changed {
                    if !available { self.networkInterruptions += 1 }
                    self.recordSession(available ? "network.restored" : "network.unavailable","NWPathMonitor availability transition")
                }
                self.refreshAddresses()
                self.hub.validateAddress()
                if !available { if self.policy.wanted { self.pipeline.interrupt(); self.sessionStatus = "بانتظار Wi-Fi" } }
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
        consumeControlRequest(); syncControl()
        localSubtitles.expire(now:ProcessInfo.processInfo.systemUptime)
        packLibrary.refreshMetrics()
        let now = ProcessInfo.processInfo.systemUptime
        if policy.wanted && lastSystemSample > 0 && now-lastSystemSample > 8 { recordSession("execution.callback_gap","Main callback gap=\(Int(now-lastSystemSample))s; OS suspension is not confirmed") }
        lastSystemSample = now; remote.sampleHealth()
        let usage = resources.sample(); cpuPercent = usage.cpu; residentMegabytes = Double(usage.residentBytes)/1048576
        peakResident = max(peakResident,usage.residentBytes)
        memoryCheckpoints[running ? "session.steady_latest" : "session.idle_latest"] = usage.residentBytes
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
        if !modelReady && translator.installed && !modelBusy { startAfterModelLoad = true; loadModel(); return }
        guard !packLibrary.busy else { errorMessage = "انتظر اكتمال استيراد التعريب أو ألغِه قبل بدء الجلسة"; return }
        guard !running, modelReady, !pairing, let console = consoles.first(where:{ $0.id == settings.selectedConsoleID }) else { errorMessage = "اختر PS5 مسجلًا وجهّز نموذج الترجمة أولًا"; return }
        guard settings.roi.isValid else { errorMessage = "اضبط منطقة الحوار داخل حدود صورة البث أولًا"; return }
        do {
            improvementWorker.cancel(); translator.cancel()
            learningConsent = true
            pipeline.configureSpatial(game:currentGame,version:packLibrary.store.outputKey)
            memoryCheckpoints["session.before_start"] = ResourceMonitor.residentBytes()
            outputFence.invalidate()
            configureMenuOptions()
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
            syncControl()
            if gameOptions.destination.tvEnabled && !tvListening && !hubStarting { connectTV() }
            UIApplication.shared.isIdleTimerDisabled = true
            applyDim()
        } catch { policy.stop(); SessionIntentStore.save(false); audio.stop(); errorMessage = error.localizedDescription }
    }
    func stop(reason: String = "أوقفها المستخدم") {
        startAfterModelLoad = false; modelRequest = UUID(); modelBusy = false
        menuSuggestionToken = UUID(); menuSuggestionVisible = false
        outputFence.invalidate(); hub.publish(TVProtocol.envelope("subtitle_clear")); hub.publish(TVProtocol.envelope("menu_clear"))
        regionTicket = nil; regionGame = nil; hub.publish(TVProtocol.envelope("roi_edit_end"))
        correctionsLibrary.clearRecent()
        recordSession("session.stop",reason+"; automatic recovery disabled")
        closeCurrentMenu(); closeReading()
        policy.stop(); recoveryTask?.cancel(); recoveryTask = nil; endExecutionGrace(); audio.stop()
        SessionIntentStore.save(false); UIDevice.current.isBatteryMonitoringEnabled = false
        pipelineActive = false; sessionStatus = reason
        running = false; streamConnected = false; pairing = false; loginRequired = false; remote.stop(); pipeline.stop()
        learningConsent = false; improvementWorker.cancel(); translator.releaseResources(); modelReady = false
        syncControl()
        localSubtitles.clear()
        localMenuItems = []; localMenuUntil = 0
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
        consumeControlRequest()
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
        remote.suspend(); pipeline.pause(); pipelineActive = false; hub.stop(); hubStarting = false
        streamConnected = false; syncControl()
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
        if gameOptions.destination.tvEnabled && !tvListening && !hubStarting { connectTV(automatic:true) }
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
        modelRequest = UUID(); let request = modelRequest
        modelBusy = true; modelReady = false; modelStatus = "جارٍ تحميل النموذج في الذاكرة…"
        translator.load { [weak self] result in
            guard let self, self.modelRequest == request else { return }; self.modelBusy = false
            switch result {
            case .success:
                self.modelReady = true; self.modelStatus = "English → Arabic جاهز دون إنترنت"; self.recoverSession()
                if self.startAfterModelLoad { self.startAfterModelLoad = false; self.start() }
            case .failure(let error): self.startAfterModelLoad = false; self.modelStatus = "النموذج غير جاهز"; self.errorMessage = error.localizedDescription
            }
        }
    }
    func downloadModel() {
        guard !modelBusy, !running else { return }
        modelBusy = true; modelStatus = "تنزيل النموذج · 88.5 MB؛ يلزم الإنترنت لهذه الخطوة فقط"
        modelRequest = UUID(); modelDownload.start()
    }
    func cancelModelDownload() { modelRequest = UUID(); modelDownload.pause(); translator.cancel(); modelBusy = false; modelStatus = "توقف التنزيل/التثبيت؛ النموذج السابق محفوظ" }
    func importModel(_ url: URL) {
        guard !running, !modelBusy else { return }
        let access = url.startAccessingSecurityScopedResource()
        modelRequest = UUID(); let request = modelRequest
        modelBusy = true; modelStatus = "جارٍ التحقق من النموذج وتثبيته…"
        translator.install(package:url) { [weak self] result in
            if access { url.stopAccessingSecurityScopedResource() }
            guard self?.modelRequest == request else { return }; self?.installed(result)
        }
    }
    private func installModel(_ url: URL, temporary: Bool) {
        let request = modelRequest
        translator.install(package:url) { [weak self] result in
            if temporary { try? FileManager.default.removeItem(at:url) }
            guard self?.modelRequest == request else { return }; self?.installed(result)
        }
    }
    private func installed(_ result: Result<Void,Error>) {
        switch result { case .success: loadModel(); case .failure(let error): modelBusy = false; modelStatus = "تعذر تثبيت النموذج"; errorMessage = error.localizedDescription }
    }
    func removeModel() {
        guard !running, !modelBusy else { return }
        modelRequest = UUID(); modelDownload.discard()
        modelReady = false; modelBusy = true
        translator.remove { [weak self] result in
            guard let self else { return }; self.modelBusy = false; self.modelStatus = "النموذج غير مثبت"
            if case .failure(let error) = result { self.errorMessage = error.localizedDescription }
        }
    }
    func preview(_ show: Bool) {
        previewActive = show
        let kind = show ? "subtitle_preview_show" : "subtitle_preview_hide"
        if !show || gameOptions.destination.tvEnabled { hub.configure(settings.display,kind:kind) }
        if !show || gameOptions.destination.phoneEnabled { localSubtitles.apply(TVProtocol.envelope(kind),settings:settings.display,now:ProcessInfo.processInfo.systemUptime) }
    }
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
