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
    var onState: ((String) -> Void)?
    var onLoginPIN: (() -> Void)?
    var onFrame: ((CVPixelBuffer) -> Void)?
    var onInterruption: (() -> Void)?
    var onStopped: (() -> Void)?
    var onAvailability: ((Bool) -> Void)?
    /// A recovery trigger must not destroy a live or currently starting session.
    func recover(_ console: ConsoleCredentials) {
        control.async { [self] in
            guard session == nil else { return }
            wanted = console; retries = 0; sessionEpoch += 1; start(console,epoch:sessionEpoch)
        }
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
        control.async { [self] in wanted = console; retries = 0; sessionEpoch += 1; start(console,epoch:sessionEpoch) }
    }
    private func state(_ text: String) { DispatchQueue.main.async { self.onState?(text) } }
    private func start(_ console: ConsoleCredentials, epoch: Int) {
        closeSession(); state("جارٍ الاتصال بـ PS5…")
        let ctx = StreamContext(event: { [weak self] event,reason in
            guard let self else { return }
            self.control.async {
                guard self.sessionEpoch == epoch, self.wanted != nil else { return }
                switch event {
                case 1:
                    self.retries = 0; self.state("بث PS5 متصل")
                    DispatchQueue.main.async { self.onAvailability?(true) }
                case 3: DispatchQueue.main.async { self.onLoginPIN?() }; self.state("PS5 يطلب رمز تسجيل الدخول")
                case 2:
                    self.closeSession()
                    DispatchQueue.main.async { self.onInterruption?() }
                    self.retries += 1
                    guard self.retries <= 5 else { self.wanted = nil; self.state("توقف البث (\(reason))؛ أعد الاتصال يدويًا"); DispatchQueue.main.async { self.onStopped?() }; return }
                    self.state("انقطع البث (\(reason))؛ إعادة الاتصال \(self.retries)/5")
                    self.control.asyncAfter(deadline: .now()+Double(min(16,1 << self.retries))) {
                        if self.sessionEpoch == epoch, let wanted = self.wanted { self.start(wanted,epoch:epoch) }
                    }
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
                guard let self, self.sessionEpoch == epoch else { return }; GLSessionRequestRecovery(self.session)
            } }
            error = GLSessionStart(session)
        }
        if error != 0 || session == nil { closeSession(); wanted = nil; state("تعذر بدء البث (\(error))"); DispatchQueue.main.async { self.onStopped?() } }
    }
    private func closeSession() {
        let hadSession = session != nil
        GLSessionDestroy(session); session = nil
        context?.decoder.shutdown(); context = nil
        if hadSession { DispatchQueue.main.async { self.onAvailability?(false) } }
    }
    func loginPIN(_ pin: String) throws {
        guard pin.count == 4, pin.utf8.allSatisfy({ (48...57).contains($0) }) else { throw LingoError.invalid("رمز تسجيل الدخول يجب أن يكون 4 أرقام") }
        control.async { [self] in pin.withCString { _ = GLSessionLoginPIN(session,$0) } }
    }
    func stop() {
        control.async { [self] in
            wanted = nil; sessionEpoch += 1; pairingEpoch += 1; discoveryEpoch += 1
            GLDiscoveryDestroy(discovery); discovery = nil
            GLRegistrationDestroy(registration); registration = nil
            registrationContext = nil
            closeSession(); state("البث متوقف")
        }
    }
}
