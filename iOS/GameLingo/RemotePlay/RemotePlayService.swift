import Foundation
import CoreVideo

struct DiscoveredConsole: Identifiable {
    let host: String, name: String, state: Int
    var id: String { host }
}

private final class StreamContext {
    let decoder = VideoDecoder(hevc: false)
    let event: (Int,Int) -> Void
    init(event: @escaping (Int,Int) -> Void, frame: @escaping (CVPixelBuffer) -> Void) {
        self.event = event; decoder.onFrame = frame
    }
}

private final class RegistrationContext {
    let completion: (Int,Data?,Data?,String) -> Void
    init(_ completion: @escaping (Int,Data?,Data?,String) -> Void) { self.completion = completion }
}
private final class PresenceContext {
    let observe: (String,Int32) -> Void
    init(_ observe: @escaping (String,Int32) -> Void) { self.observe = observe }
}

/// Native start/stop/join never runs on the main thread. Each session owns its callback context until join.
final class RemotePlayService {
    var onDiscovery: ((DiscoveredConsole) -> Void)?
    var onRegistration: ((Result<ConsoleCredentials,Error>) -> Void)?
    private let control = DispatchQueue(label: "dev.gamelingo.remote.control")
    private var discovery: OpaquePointer?
    private var registration: OpaquePointer?
    private var registrationContext: RegistrationContext?
    private var session: OpaquePointer?
    private var context: StreamContext?
    private var discoveryEpoch = 0
    private var pairingEpoch = 0
    private var sessionEpoch = 0
    private var wanted: ConsoleCredentials?
    private var retries = 0
    private var startedAt = 0.0
    private var accounting = RecoveryAccounting()
    private var recoveryPolicy = StreamRecoveryPolicy()
    private var lifecycle = ConsoleLifecycle()
    private var presence: OpaquePointer?
    private var presenceContext: PresenceContext?
    private var presenceEpoch = 0
    var onPermanentStop: ((ConsoleDisconnect) -> Void)?
    private var networkAvailable = true
    func networkChanged(_ available: Bool) { control.async { self.networkAvailable = available } }
    var onState: ((String) -> Void)?
    var onLoginPIN: (() -> Void)?
    var onFrame: ((CVPixelBuffer) -> Void)?
    var onInterruption: (() -> Void)?
    var onStopped: (() -> Void)?
    var onAvailability: ((Bool) -> Void)?
    var onTelemetry: ((RemoteMetrics,String?,String,Double) -> Void)?
    private func telemetry(_ stage: String? = nil, _ detail: String = "") {
        let now = ProcessInfo.processInfo.systemUptime
        var value = accounting.snapshot(now:now)
        if let health = context?.decoder.healthSnapshot() {
            let clock = DispatchTime.now().uptimeNanoseconds
            if health.lastInputNanoseconds > 0 { value.encodedFrameAge = Double(clock-health.lastInputNanoseconds)/1_000_000_000 }
            if health.lastOutputNanoseconds > 0 { value.decodedFrameAge = Double(clock-health.lastOutputNanoseconds)/1_000_000_000 }
        }
        DispatchQueue.main.async { self.onTelemetry?(value,stage,detail,now) }
    }
    func sampleHealth() { control.async { [weak self] in self?.telemetry() } }
    /// Preserve healthy/starting sessions; restart only after confirmed frame starvation.
    func recover(_ console: ConsoleCredentials, stalled: Bool = false) {
        control.async { [self] in
            guard networkAvailable, lifecycle.wanted else { return }
            if presence == nil { monitorConsole() }
            let now = ProcessInfo.processInfo.systemUptime
            var confirmed = false
            if stalled, let health = context?.decoder.healthSnapshot() {
                let clock = DispatchTime.now().uptimeNanoseconds
                let encoded = health.lastInputNanoseconds > 0 ? Double(clock-health.lastInputNanoseconds)/1_000_000_000 : now-startedAt
                let decoded = health.lastOutputNanoseconds > 0 ? Double(clock-health.lastOutputNanoseconds)/1_000_000_000 : now-startedAt
                confirmed = recoveryPolicy.replacementNeeded(encodedAge:encoded,decodedAge:decoded,sessionAge:now-startedAt,now:now)
            } else { recoveryPolicy.resetObservation() }
            guard accounting.reserveRecovery(hasSession:session != nil,stalled:confirmed,age:now-startedAt,now:now) else { return }
            lifecycle.disconnect(confirmed ? .decoder : .suspension,now:now)
            if session != nil {
                telemetry("video.starvation","Encoded and decoded video silent >20s on repeated observations; replacing serially without wake")
                DispatchQueue.main.async { self.onInterruption?() }
            }
            telemetry("reconnect.attempt",stalled ? "frame starvation" : "session unavailable; execution/network trigger")
            closeSession(); retries = 0; sessionEpoch += 1
            scheduleRetry(epoch:sessionEpoch,reason:"بانتظار تأكيد توفر PS5")
        }
    }

    private func monitorConsole() {
        presenceEpoch += 1
        GLDiscoveryDestroy(presence); presence = nil
        let epoch = presenceEpoch
        let context = PresenceContext { [weak self] address,state in
            self?.control.async { [weak self] in
                guard let self, self.presenceEpoch == epoch, self.lifecycle.wanted, self.wanted?.host == address else { return }
                self.lifecycle.discovered(ready:state == 1,standby:state == 2,now:ProcessInfo.processInfo.systemUptime)
                if !self.lifecycle.wanted { self.permanentStop(.rest) }
            }
        }
        presenceContext = context
        var error: Int32 = 0
        presence = GLDiscoveryCreate({ host,_,state,user in
            guard let host, let user else { return }
            Unmanaged<PresenceContext>.fromOpaque(user).takeUnretainedValue().observe(String(cString:host),state)
        },Unmanaged.passUnretained(context).toOpaque(),&error)
        if error != 0 { telemetry("console.discovery_unavailable","Recovery requires READY; no wake permission") }
    }
    private func permanentStop(_ cause: ConsoleDisconnect) {
        lifecycle.disconnect(cause,now:ProcessInfo.processInfo.systemUptime)
        wanted = nil; sessionEpoch += 1; retries = 0; accounting.stop()
        GLDiscoveryDestroy(presence); presence = nil; presenceContext = nil; presenceEpoch += 1
        closeSession(); telemetry("console.requires_activation",String(describing:cause))
        DispatchQueue.main.async { self.onPermanentStop?(cause) }
    }

    func discover() {
        control.async { [self] in
            discoveryEpoch += 1; let epoch = discoveryEpoch
            GLDiscoveryDestroy(discovery); discovery = nil
            var error: Int32 = 0
            discovery = GLDiscoveryCreate({ host,name,state,user in
                guard let host, let name, let user else { return }
                let owner = Unmanaged<RemotePlayService>.fromOpaque(user).takeUnretainedValue()
                let item = DiscoveredConsole(host: String(cString: host),name: String(cString: name),state: Int(state))
                DispatchQueue.main.async { owner.onDiscovery?(item) }
            },Unmanaged.passUnretained(self).toOpaque(),&error)
            if error != 0 { state("تعذر اكتشاف الأجهزة (\(error))؛ استخدم عنوان PS5 يدويًا") }
            // Discovery is bounded in time and can be repeated explicitly.
            control.asyncAfter(deadline: .now()+12) { [weak self] in
                guard let self, self.discoveryEpoch == epoch else { return }; GLDiscoveryDestroy(self.discovery); self.discovery = nil
            }
        }
    }
    func pair(host: String, account: String, pin: String) throws {
        guard LAN.isPrivateIPv4(host) else { throw LingoError.invalid("عنوان PS5 المحلي غير صالح") }
        let bytes = try ConsoleCredentials.accountID(account,pin: pin)
        control.async { [self] in
            pairingEpoch += 1
            let epoch = pairingEpoch
            GLRegistrationDestroy(registration); registration = nil; registrationContext = nil
            let ctx = RegistrationContext { [weak self] result,savedKey,savedSecret,title in
                guard let self else { return }
                self.control.async {
                    guard self.pairingEpoch == epoch else { return }
                    let value: Result<ConsoleCredentials,Error>
                    if result == 2, let savedKey, let savedSecret {
                        value = .success(ConsoleCredentials(id:UUID().uuidString,name:title,host:host,registrationKey:savedKey,key:savedSecret))
                    } else { value = .failure(LingoError.invalid("فشل تسجيل PS5؛ راجع Account ID ورمز الربط")) }
                    GLRegistrationDestroy(self.registration); self.registration = nil; self.registrationContext = nil
                    DispatchQueue.main.async { self.onRegistration?(value) }
                }
            }
            registrationContext = ctx
            var error: Int32 = 0
            registration = bytes.withUnsafeBytes { accountBytes in
                host.withCString { hostBytes in
                    GLRegistrationCreate(hostBytes,accountBytes.bindMemory(to: UInt8.self).baseAddress,bytes.count,UInt32(pin)!,{ result,registrationKey,key,name,user in
                        guard let user else { return }
                        let owner = Unmanaged<RegistrationContext>.fromOpaque(user).takeUnretainedValue()
                        let savedKey = registrationKey.map { Data(bytes:$0,count:16) }
                        let savedSecret = key.map { Data(bytes:$0,count:16) }
                        let title = name.map { String(cString:$0) } ?? "PS5"
                        owner.completion(Int(result),savedKey,savedSecret,title)
                    },Unmanaged.passUnretained(ctx).toOpaque(),&error)
                }
            }
            if error != 0 { DispatchQueue.main.async { self.onRegistration?(.failure(LingoError.invalid("تعذر بدء التسجيل (\(error))"))) } }
        }
    }
    func connect(_ console: ConsoleCredentials) throws {
        try console.validate()
        control.async { [self] in lifecycle.activate(); accounting.initial(now:ProcessInfo.processInfo.systemUptime); wanted = console; retries = 0; sessionEpoch += 1; monitorConsole(); start(console,epoch:sessionEpoch) }
    }
    private func state(_ text: String) { DispatchQueue.main.async { self.onState?(text) } }
    private func start(_ console: ConsoleCredentials, epoch: Int) {
        startedAt = ProcessInfo.processInfo.systemUptime
        closeSession(); state("جارٍ الاتصال بـ PS5…")
        let ctx = StreamContext(event: { [weak self] event,reason in
            guard let self else { return }
            self.control.async {
                guard self.sessionEpoch == epoch, self.wanted != nil, self.session != nil else { return }
                switch event {
                case 1:
                    self.lifecycle.connected()
                    let wasReplacement = self.accounting.metrics.attempts > self.accounting.metrics.successes + self.accounting.metrics.failures
                    guard self.accounting.established(now:ProcessInfo.processInfo.systemUptime) else { return }
                    self.telemetry(wasReplacement ? "reconnect.success" : "ps5.connected","Native connected event confirmed")
                    self.retries = 0; self.state("بث PS5 متصل")
                    DispatchQueue.main.async { self.onAvailability?(true) }
                case 3:
                    self.accounting.loginRequired(); self.telemetry("ps5.login_required","User login PIN required")
                    DispatchQueue.main.async { self.onLoginPIN?() }; self.state("PS5 يطلب رمز تسجيل الدخول")
                case 2:
                    let cause = ConsoleDisconnect(rawValue:reason) ?? .unknown
                    self.lifecycle.disconnect(cause,now:ProcessInfo.processInfo.systemUptime)
                    let uptime = self.accounting.snapshot(now:ProcessInfo.processInfo.systemUptime).uptime
                    let failures = self.accounting.metrics.failures
                    self.accounting.ended()
                    self.telemetry(self.accounting.metrics.failures > failures ? "reconnect.failure" : "ps5.disconnected","Native reason=\(reason); uptime=\(Int(uptime))s")
                    self.closeSession()
                    DispatchQueue.main.async { self.onInterruption?() }
                    if cause.terminal { self.permanentStop(cause); return }
                    self.scheduleRetry(epoch:epoch,reason:"انقطع البث (\(reason))")
                default: break
                }
            }
        },frame: { [weak self] frame in self?.onFrame?(frame) })
        context = ctx
        var error: Int32 = 0
        session = console.registrationKey.withUnsafeBytes { registration in
            console.key.withUnsafeBytes { key in
                console.host.withCString { host in
                    GLSessionCreate(host,registration.bindMemory(to:UInt8.self).baseAddress,console.registrationKey.count,key.bindMemory(to:UInt8.self).baseAddress,console.key.count,{ event,reason,user in
                        guard let user else { return }; Unmanaged<StreamContext>.fromOpaque(user).takeUnretainedValue().event(Int(event),Int(reason))
                    },{ bytes,count,user in
                        guard let bytes, let user, count > 0, count <= 4*1024*1024 else { return false }
                        return Unmanaged<StreamContext>.fromOpaque(user).takeUnretainedValue().decoder.decode(Data(bytes:bytes,count:count))
                    },Unmanaged.passUnretained(ctx).toOpaque(),&error)
                }
            }
        }
        if let session {
            ctx.decoder.onRecoveryNeeded = { [weak self] _ in self?.control.async { [weak self] in
                guard let self, self.sessionEpoch == epoch, self.session != nil else { return }
                self.accounting.decoderRequested(); self.telemetry("decoder.recovery_request","VideoToolbox requested native IDR recovery")
                GLSessionRequestRecovery(self.session)
            } }
            error = GLSessionStart(session)
        }
        if error != 0 || session == nil {
            lifecycle.disconnect(.network,now:ProcessInfo.processInfo.systemUptime)
            accounting.ended(); telemetry("ps5.start_failed","Native start error=\(error)")
            closeSession(); scheduleRetry(epoch:epoch,reason:"تعذر بدء البث (\(error))")
        } else { telemetry("ps5.start","Native start accepted; waiting for connected event") }
    }
    private func scheduleRetry(epoch: Int, reason: String) {
        guard wanted != nil, sessionEpoch == epoch else { return }
        retries = min(6,retries+1)
        accounting.scheduleRetry()
        let delay = StreamRecoveryPolicy.delay(retries)
        telemetry("reconnect.scheduled","Single native retry owner; delay=\(Int(delay))s; no wake")
        state(reason+"؛ إعادة محاولة الاتصال دون إيقاظ بعد \(Int(delay)) ثانية")
        awaitRetry(epoch:epoch,delay:delay)
    }
    private func awaitRetry(epoch: Int, delay: Double) {
        control.asyncAfter(deadline:.now()+delay) { [weak self] in
            guard let self, self.sessionEpoch == epoch, let wanted = self.wanted else { return }
            // A missing network does not spend attempts or create a second timer.
            guard self.networkAvailable else { self.awaitRetry(epoch:epoch,delay:5); return }
            let now = ProcessInfo.processInfo.systemUptime
            if self.lifecycle.expireUnknown(now:now,network:true) { self.permanentStop(.unknown); return }
            guard self.lifecycle.canRetry(now:now,network:true) else { self.awaitRetry(epoch:epoch,delay:2); return }
            guard self.accounting.beginRetry(now:ProcessInfo.processInfo.systemUptime) else { return }
            self.sessionEpoch += 1
            self.telemetry("reconnect.attempt","Serial native retry; connection only, no wake")
            self.start(wanted,epoch:self.sessionEpoch)
        }
    }
    private func closeSession() {
        let hadSession = session != nil
        GLSessionDestroy(session); session = nil
        context?.decoder.shutdown(); context = nil
        if hadSession { DispatchQueue.main.async { self.onAvailability?(false) } }
    }
    func loginPIN(_ pin: String) throws {
        guard pin.count == 4, pin.utf8.allSatisfy({ (48...57).contains($0) }) else { throw LingoError.invalid("رمز تسجيل الدخول يجب أن يكون 4 أرقام") }
        control.async { [self] in accounting.loginSubmitted(); pin.withCString { _ = GLSessionLoginPIN(session,$0) } }
    }
    func stop() {
        control.async { [self] in
            wanted = nil; sessionEpoch += 1; pairingEpoch += 1; discoveryEpoch += 1
            lifecycle.stop(); GLDiscoveryDestroy(presence); presence = nil; presenceContext = nil; presenceEpoch += 1
            accounting.stop(); telemetry("ps5.stop","Session stopped; pending native retries invalidated")
            GLDiscoveryDestroy(discovery); discovery = nil
            GLRegistrationDestroy(registration); registration = nil
            registrationContext = nil
            closeSession(); state("البث متوقف")
        }
    }
    func suspend() {
        control.async { [self] in
            guard lifecycle.wanted else { return }
            lifecycle.disconnect(.suspension,now:ProcessInfo.processInfo.systemUptime)
            sessionEpoch += 1; accounting.stop()
            GLDiscoveryDestroy(presence); presence = nil; presenceContext = nil; presenceEpoch += 1
            closeSession(); telemetry("execution.suspended","Retained intent; foreground recovery needs fresh READY")
        }
    }
}
