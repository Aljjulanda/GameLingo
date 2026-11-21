import Foundation
import Network
import Security
import CryptoKit
import Darwin

/// The TV is the client. Network.framework handles RFC 6455 framing, masking, and TLS.
final class TVHub {
    var onStatus: ((String) -> Void)?
    var onPairing: ((String,String) -> Void)?
    var onConnected: (() -> Void)?
    var onDisconnected: (() -> Void)?
    var onDiagnostics: (([String]) -> Void)?
    var onListening: ((Bool) -> Void)?
    var onCapabilities: (([String]) -> Void)?
    var onRenderSignature: ((String) -> Void)?
    var onDisplayAck: ((String) -> Void)?
    var onListenerFailure: (() -> Void)?
    var onControl: (([String:Any]) -> Void)?
    private let queue = DispatchQueue(label:"dev.gamelingo.tv")
    private var listener: NWListener?
    private var client: NWConnection?
    private var identity: TLSIdentity?
    private var authenticated = false
    private var generation = 0
    private var sequence = TVSequence()
    private var settings = TVSettings()
    private var pin = ""
    private var deadline: TimeInterval = 0
    private var failures = 0
    private var sending = false
    private var outbound: [Data] = []
    private var heartbeat: DispatchSourceTimer?
    private var diagnosticLines: [String] = []
    private var stage = "server"
    private var receivedConnection = false
    private var listeningHost = ""
    private var tokenDigest: Data?
    private var showSpeakers = true
    private var speakerColor = "#A6C7D8"
    private var pendingDisplay = Set<String>()
    private var bonjourEnabled = true
    private var lastPong = 0.0
    private var previewActive = false
    private var settingsWire: [String:Any] {
        var value = settings.wire; value["show_speakers"] = showSpeakers; value["speaker_color"] = speakerColor
        return value
    }
    private let testingLoopback: Bool
    init(testingLoopback: Bool = false) { self.testingLoopback = testingLoopback }

    static func localAddresses() -> [String] {
        var first: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&first) == 0 else { return [] }; defer { freeifaddrs(first) }
        var result: [String] = [], cursor = first
        while let item = cursor {
            defer { cursor = item.pointee.ifa_next }
            guard let address = item.pointee.ifa_addr, address.pointee.sa_family == UInt8(AF_INET),
                  String(cString:item.pointee.ifa_name).hasPrefix("en"),
                  item.pointee.ifa_flags & UInt32(IFF_UP | IFF_RUNNING) == UInt32(IFF_UP | IFF_RUNNING) else { continue }
            var host = [CChar](repeating:0,count:Int(NI_MAXHOST))
            if getnameinfo(address,socklen_t(address.pointee.sa_len),&host,socklen_t(host.count),nil,0,NI_NUMERICHOST) == 0 {
                let value = String(cString:host); if LAN.isPrivateIPv4(value) { result.append(value) }
            }
        }
        return result.sorted()
    }
    private func status(_ text: String) { DispatchQueue.main.async { self.onStatus?(text) } }
    // Only application-owned messages and numeric Network.framework codes enter this ring.
    // Never include JSON, PINs, tokens, keys, certificate data, or remote close reasons.
    private func diagnostic(_ code: String, _ text: String, show: Bool = false) {
        diagnosticLines.append("\(Self.now()) [\(code)] \(text)")
        diagnosticLines = Array(diagnosticLines.suffix(80))
        let lines = diagnosticLines
        DispatchQueue.main.async { self.onDiagnostics?(lines) }
        if show { status(text) }
    }
    private static func safeError(_ error: NWError) -> String {
        switch error {
        case .posix(let code): return "POSIX \(code.rawValue)"
        case .tls(let code): return "TLS \(code)"
        case .dns(let code): return "DNS \(code)"
        @unknown default: return "Network error"
        }
    }
    // Host.description may include an interface scope (e.g. %en0). Parse bytes,
    // not its debug representation. Accept mapped IPv4 without accepting public IPs.
    static func peerIPv4(_ host: NWEndpoint.Host) -> String? {
        switch host {
        case .ipv4(let address): return address.rawValue.map(String.init).joined(separator:".")
        case .ipv6(let address):
            let bytes = Array(address.rawValue)
            guard bytes.count == 16, bytes.prefix(10).allSatisfy({ $0 == 0 }), bytes[10] == 255, bytes[11] == 255 else { return nil }
            return bytes.suffix(4).map(String.init).joined(separator:".")
        default: return nil
        }
    }
    func start(host: String, settings: TVSettings, bindAttempt: Int = 0) throws {
        guard (LAN.isPrivateIPv4(host) && Self.localAddresses().contains(host)) || (testingLoopback && host == "127.0.0.1") else { throw LingoError.invalid("اختر عنوان Wi-Fi الحالي لهذا iPhone") }
        queue.async { [self] in
          do {
            let retainedIdentity = self.identity, retainedDigest = tokenDigest
            stopNow(preserveIdentity:true); sequence = TVSequence(); self.settings = settings
            diagnosticLines.removeAll(); stage = "server"; receivedConnection = false; listeningHost = host
            let epoch = generation
            diagnostic("server.start", "جارٍ تشغيل خادم التلفزيون", show:true)
            let identity: TLSIdentity
            if let retainedIdentity { identity = retainedIdentity; tokenDigest = retainedDigest }
            else { identity = try TLSIdentity(); tokenDigest = try KeychainStore.read("tv.token.sha256.v1") }
            let random = try KeychainStore.random(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
            let pin = String(format:"%06u",random % 1_000_000)
            self.identity = identity; self.pin = pin; failures = 0; deadline = ProcessInfo.processInfo.systemUptime+300
            let tls = NWProtocolTLS.Options()
            guard let nativeIdentity = sec_identity_create(identity.identity) else { listenerFailed(); status("تعذر إعداد TLS"); return }
            sec_protocol_options_set_local_identity(tls.securityProtocolOptions,nativeIdentity)
            sec_protocol_options_set_min_tls_protocol_version(tls.securityProtocolOptions,.TLSv12)
            let parameters = NWParameters(tls:tls,tcp:NWProtocolTCP.Options())
            let websocket = NWProtocolWebSocket.Options(); websocket.autoReplyPing = true; websocket.maximumMessageSize = TVProtocol.maximumBytes
            websocket.setClientRequestHandler(queue) { [weak self] _,_ in
                if let self, self.generation == epoch {
                    self.diagnostic("tls.ok", "نجحت مصافحة TLS")
                    self.diagnostic("websocket.upgrade", "وصل طلب ترقية WebSocket")
                    self.stage = "websocket"
                }
                return NWProtocolWebSocket.Response(status:.accept,subprotocol:nil,additionalHeaders:nil)
            }
            parameters.defaultProtocolStack.applicationProtocols.insert(websocket,at:0)
            parameters.requiredLocalEndpoint = .hostPort(host:NWEndpoint.Host(host),port:NWEndpoint.Port(rawValue:TVProtocol.port)!)
            parameters.allowLocalEndpointReuse = true
            do {
                // requiredLocalEndpoint already fixes both address and port.
                // Passing on: as well makes Network.framework reject the bind.
                let listener = try NWListener(using:parameters)
                // The public identity hint only locates candidates. Clients must
                // still verify their saved full certificate pin and authenticate.
                if bonjourEnabled && !testingLoopback { listener.service = NWListener.Service(name:"GameLingo-\(identity.fingerprint.prefix(12))",type:"_gamelingo._tcp") }
                listener.stateUpdateHandler = { [weak self,weak listener] state in
                    guard let self, let listener, self.generation == epoch else { return }
                    switch state {
                    case .ready:
                        guard listener.port?.rawValue == TVProtocol.port else {
                            self.stopNow()
                            self.listenerFailed()
                            self.diagnostic("bind.wrong_port", "فشل الربط: المنفذ الفعلي \(listener.port?.rawValue ?? 0) بدلًا من \(TVProtocol.port)", show:true)
                            return
                        }
                        self.diagnostic("listen.ready", "بانتظار التلفزيون · \(host):\(listener.port!.rawValue)", show:true)
                        DispatchQueue.main.async { self.onListening?(true) }
                        DispatchQueue.main.async { self.onPairing?(host,"\(identity.fingerprint.prefix(12))-\(pin)") }
                        self.queue.asyncAfter(deadline:.now()+20) { [weak self] in
                            guard let self, self.generation == epoch, !self.receivedConnection else { return }
                            self.diagnostic("tcp.not_observed", "لم يُرصد اتصال بالخادم؛ تحقق من عنوان Wi-Fi ومسار الشبكة وتوفر التنفيذ")
                        }
                    case .waiting(let error):
                        if self.bonjourEnabled, case .dns = error {
                            self.bonjourEnabled = false
                            self.diagnostic("discovery.unavailable", "تعذر نشر الاكتشاف؛ جارٍ استعادة الاتصال اليدوي الآمن")
                            try? self.start(host:host,settings:self.settings)
                        } else { self.diagnostic("listen.waiting", "الخادم ينتظر الشبكة · \(Self.safeError(error))", show:true) }
                    case .failed(let error):
                        if self.retryBusyPort(error,host:host,settings:self.settings,attempt:bindAttempt) { return }
                        if self.bonjourEnabled, case .dns = error {
                            self.bonjourEnabled = false
                            self.diagnostic("discovery.unavailable", "تعذر الاكتشاف؛ جارٍ استعادة الاتصال اليدوي الآمن")
                            try? self.start(host:host,settings:self.settings)
                            return
                        }
                        self.stopNow(preserveIdentity:true)
                        self.listenerFailed()
                        self.diagnostic("listen.failed", "تعذر ربط خادم التلفزيون · \(Self.safeError(error))", show:true)
                    default: break
                    }
                }
                listener.newConnectionHandler = { [weak self] connection in self?.accept(connection,epoch:epoch) }
                self.listener = listener; listener.start(queue:queue)
            } catch { listenerFailed(); diagnostic("listen.failed", "تعذر إنشاء المستمع · \((error as NSError).domain) / \((error as NSError).code)", show:true) }
          } catch { listenerFailed(); diagnostic("identity.failed", "تعذر إعداد هوية TLS · \((error as NSError).domain) / \((error as NSError).code)", show:true) }
        }
    }
    private func listenerFailed() { DispatchQueue.main.async { self.onListenerFailure?() } }
    private func retryBusyPort(_ error: NWError, host: String, settings: TVSettings, attempt: Int) -> Bool {
        guard case .posix(let code) = error, code == .EADDRINUSE, attempt < 3 else { return false }
        // Cancellation releases a Network.framework socket asynchronously. A
        // cached TLS identity makes a restart fast enough to expose this race.
        stopNow(preserveIdentity:true)
        let epoch = generation
        diagnostic("bind.releasing", "بانتظار تحرير منفذ المستمع السابق")
        queue.asyncAfter(deadline:.now()+0.25*Double(attempt+1)) { [weak self] in
            guard let self, self.generation == epoch else { return }
            do { try self.start(host:host,settings:settings,bindAttempt:attempt+1) }
            catch { self.listenerFailed(); self.diagnostic("bind.address_changed", "تغير عنوان الربط أثناء إعادة تشغيل المستمع", show:true) }
        }
        return true
    }
    private func accept(_ connection: NWConnection, epoch: Int) {
        guard epoch == generation else { connection.cancel(); return }
        receivedConnection = true
        diagnostic("transport.incoming", "رُصد اتصال وارد إلى المستمع")
        guard client == nil else { diagnostic("transport.busy", "رُفض اتصال إضافي أثناء جلسة التلفزيون"); connection.cancel(); return }
        guard case .hostPort(let host,_) = connection.endpoint, let ip = Self.peerIPv4(host),
              LAN.isPrivateIPv4(ip) || (testingLoopback && ip == "127.0.0.1") else {
            diagnostic("transport.rejected", "رُفض عنوان مصدر خارج الشبكة المحلية", show:true); connection.cancel(); return
        }
        stage = "tls/websocket"
        diagnostic("handshake.start", "جارٍ تفاوض TLS وWebSocket مع \(ip)", show:true)
        client = connection; authenticated = false
        connection.stateUpdateHandler = { [weak self,weak connection] state in
            guard let self, let connection, self.client === connection else { return }
            switch state {
            case .ready:
                self.stage = "authentication"
                self.diagnostic("websocket.ready", "تم إنشاء WebSocket؛ بانتظار المصادقة", show:true)
                self.receive(connection)
            case .waiting(let error): self.diagnostic("connection.waiting", "تعثر الاتصال عند \(self.stage) · \(Self.safeError(error))", show:true)
            case .failed(let error): self.disconnect(connection,reason:"فشل الاتصال عند \(self.stage) · \(Self.safeError(error))")
            case .cancelled: self.disconnect(connection)
            default: break
            }
        }
        connection.start(queue:queue)
        queue.asyncAfter(deadline:.now()+15) { [weak self,weak connection] in
            guard let self, let connection, self.client === connection, !self.authenticated else { return }
            self.disconnect(connection,reason:"انتهت مهلة الاتصال عند \(self.stage)")
        }
    }
    private func disconnect(_ connection: NWConnection, reason: String? = nil) {
        guard client === connection else { return }
        client = nil; authenticated = false; outbound.removeAll(); sending = false; pendingDisplay.removeAll()
        heartbeat?.cancel(); heartbeat = nil; connection.cancel()
        diagnostic("connection.closed", reason ?? "التلفزيون غير متصل؛ لا تُعاد الجمل السابقة", show:true)
        // Invalidate pending inference before this queue can authenticate a replacement TV.
        onDisconnected?()
    }
    private func receive(_ connection: NWConnection) {
        connection.receiveMessage { [weak self,weak connection] data,context,_,error in
            guard let self, let connection, self.client === connection else { return }
            if let error { self.disconnect(connection,reason:"فشل الاستقبال عند \(self.stage) · \(Self.safeError(error))"); return }
            if let metadata = context?.protocolMetadata(definition:NWProtocolWebSocket.definition) as? NWProtocolWebSocket.Metadata,
               metadata.opcode == .close {
                let reply = NWProtocolWebSocket.Metadata(opcode:.close); reply.closeCode = metadata.closeCode
                connection.send(content:nil,contentContext:NWConnection.ContentContext(identifier:"close",metadata:[reply]),isComplete:true,completion:.contentProcessed { [weak self,weak connection] _ in
                    guard let self, let connection else { return }; self.disconnect(connection)
                })
                return
            }
            if let metadata = context?.protocolMetadata(definition:NWProtocolWebSocket.definition) as? NWProtocolWebSocket.Metadata,
               metadata.opcode == .ping || metadata.opcode == .pong {
                self.receive(connection); return
            }
            do {
                guard let data else { throw LingoError.invalid("رسالة فارغة") }
                let message = try TVProtocol.decode(data)
                if !self.authenticated { try self.authenticate(message) }
                else {
                    switch message["type"] as? String {
                    case "roi_edit_request", "roi_edit_result":
                        guard message["session"] as? String == self.sequence.session else { throw LingoError.invalid("جلسة التحكم غير صالحة") }
                        DispatchQueue.main.async { self.onControl?(message) }
                    case "subtitle_ack":
                        if let id = message["id"] as? String, self.pendingDisplay.remove(id) != nil {
                            let trace = message["render_signature"] as? String
                            DispatchQueue.main.async {
                                self.onDisplayAck?(id)
                                if let trace, SubtitlePresentation.isSafeRenderSignature(trace) { self.onRenderSignature?(trace) }
                            }
                        }
                    case "heartbeat": self.enqueue(TVProtocol.envelope("heartbeat",fields:["time_ms":Self.now()]))
                    case "settings_ack":
                        if let width = message["width_px"] as? Int, let height = message["height_px"] as? Int {
                            self.diagnostic("settings.ack", "أكد التلفزيون إعدادات العرض · \(width)×\(height)")
                            self.status("التلفزيون متصل · \(width)×\(height) · تم تأكيد الإعدادات")
                        }
                    default: throw LingoError.invalid("نوع رسالة غير مسموح")
                    }
                }
                self.receive(connection)
            } catch {
                // All messages supplied here are fixed local errors, never reflected client data.
                let reason = (error as? LingoError)?.errorDescription ?? "رسالة بروتوكول غير صالحة"
                self.reject(connection,reason:reason)
            }
        }
    }
    private func authenticate(_ message: [String:Any]) throws {
        switch message["type"] as? String {
        case "pair":
            diagnostic("pair.request", "وصل طلب الاقتران")
            guard failures < 5, ProcessInfo.processInfo.systemUptime < deadline, !pin.isEmpty,
                  let supplied = message["pin"] as? String, Self.equal(Data(supplied.utf8),Data(pin.utf8)) else {
                failures += 1; throw LingoError.invalid("رُفض PIN: الرمز غير صحيح أو منتهي الصلاحية")
            }
            let token = try KeychainStore.random(32).base64EncodedString()
            try KeychainStore.write(Data(SHA256.hash(data:Data(token.utf8))),account:"tv.token.sha256.v1")
            tokenDigest = Data(SHA256.hash(data:Data(token.utf8)))
            pin = ""
            diagnostic("pair.accepted", "قُبل PIN وحُفظ رمز المصادقة بأمان")
            enqueue(TVProtocol.envelope("paired",fields:["token":token]),stamp:false)
        case "hello":
            guard let token = message["token"] as? String, (32...128).contains(token.count),
              let digest = tokenDigest, Self.equal(Data(SHA256.hash(data:Data(token.utf8))),digest) else { throw LingoError.invalid("رُفض رمز المصادقة المحفوظ؛ يلزم اقتران جديد") }
        default: throw LingoError.invalid("رسالة اقتران غير صالحة")
        }
        authenticated = true
        lastPong = ProcessInfo.processInfo.systemUptime
        let capabilities = (message["features"] as? [String] ?? []).prefix(8).filter { ["document_v1","speaker_v1","display_ack"].contains($0) }
        DispatchQueue.main.async { self.onCapabilities?(capabilities) }
        stage = "connected"
        diagnostic("auth.ok", "اكتملت المصادقة؛ التلفزيون متصل")
        enqueue(TVProtocol.envelope("connection_status",fields:["state":"connected","session":sequence.session,"time_ms":Self.now(),"capabilities":["subtitle_ack","document_v1","speaker_v1"]]),stamp:false)
        enqueue(TVProtocol.envelope("settings_sync",fields:["settings":settingsWire]))
        if previewActive { enqueue(TVProtocol.envelope("subtitle_preview_show",fields:["settings":settingsWire])) }
        // Never keep or replay a subtitle across reconnection.
        let timer = DispatchSource.makeTimerSource(queue:queue)
        timer.schedule(deadline:.now()+6,repeating:6)
        timer.setEventHandler { [weak self] in
            guard let self, let peer = self.client, self.authenticated else { return }
            guard ProcessInfo.processInfo.systemUptime-self.lastPong <= 18 else {
                self.disconnect(peer,reason:"انتهت مهلة استجابة التلفزيون؛ بانتظار إعادة الاتصال"); return
            }
            self.enqueue(TVProtocol.envelope("heartbeat",fields:["time_ms":Self.now()]))
            let ping = NWProtocolWebSocket.Metadata(opcode:.ping)
            ping.setPongHandler(self.queue) { [weak self,weak peer] error in
                guard let self, let peer, self.client === peer else { return }
                if error == nil { self.lastPong = ProcessInfo.processInfo.systemUptime }
                else { self.disconnect(peer,reason:"تعذرت استجابة WebSocket من التلفزيون") }
            }
            peer.send(content:Data([0x47,0x4c]),contentContext:NWConnection.ContentContext(identifier:"liveness",metadata:[ping]),isComplete:true,completion:.contentProcessed { [weak self,weak peer] error in
                guard let self, let peer, self.client === peer, error != nil else { return }
                self.disconnect(peer,reason:"تعذر إرسال فحص استجابة التلفزيون")
            })
        }
        heartbeat = timer; timer.resume(); status("التلفزيون متصل")
        DispatchQueue.main.async { self.onConnected?() }
    }
    private func reject(_ connection: NWConnection, reason: String) {
        diagnostic("auth.rejected", reason, show:true)
        let metadata = NWProtocolWebSocket.Metadata(opcode:.close)
        metadata.closeCode = .protocolCode(.policyViolation)
        connection.send(content:nil,contentContext:NWConnection.ContentContext(identifier:"rejected",metadata:[metadata]),isComplete:true,completion:.contentProcessed { [weak self,weak connection] _ in
            guard let self, let connection else { return }; self.disconnect(connection,reason:reason)
        })
        queue.asyncAfter(deadline:.now()+1) { [weak self,weak connection] in
            guard let self, let connection else { return }; self.disconnect(connection,reason:reason)
        }
    }
    private static func equal(_ a: Data, _ b: Data) -> Bool {
        guard a.count == b.count else { return false }; var difference: UInt8 = 0
        for (x,y) in zip(a,b) { difference |= x ^ y }; return difference == 0
    }
    static func now() -> Int64 { Int64(Date().timeIntervalSince1970*1000) }
    func publish(_ message: [String:Any]) { queue.async { [self] in if authenticated { enqueue(message) } } }
    func configure(_ value: TVSettings, kind: String = "settings_sync", showSpeakers: Bool? = nil, speakerColor: String? = nil) {
        queue.async { [self] in
            settings = value
            if kind == "subtitle_preview_show" { previewActive = true }
            if kind == "subtitle_preview_hide" { previewActive = false }
            if let showSpeakers { self.showSpeakers = showSpeakers }
            if let speakerColor, speakerColor.range(of:"^#[0-9A-Fa-f]{6}$",options:.regularExpression) != nil { self.speakerColor = speakerColor }
            if authenticated { enqueue(TVProtocol.envelope(kind,fields:["settings":settingsWire])) }
        }
    }
    func configureSpeakers(show: Bool, color: String) {
        queue.async { [self] in
            guard color.range(of:"^#[0-9A-Fa-f]{6}$",options:.regularExpression) != nil,
                  show != showSpeakers || color != speakerColor else { return }
            showSpeakers = show; speakerColor = color
            if authenticated { enqueue(TVProtocol.envelope("settings_sync",fields:["settings":settingsWire])) }
        }
    }
    private func enqueue(_ message: [String:Any], stamp: Bool = true) {
        guard let client else { return }
        do {
            let data = try TVProtocol.encode(stamp ? sequence.stamp(message) : message)
            // A slow TV must not create an unbounded queue or receive stale subtitles.
            guard outbound.count < 8 else { disconnect(client); return }
            if ["subtitle_show","subtitle_update"].contains(message["type"] as? String ?? ""), let id = message["id"] as? String {
                if pendingDisplay.count >= 128 { pendingDisplay.removeAll() }
                pendingDisplay.insert(id)
            }
            outbound.append(data); sendNext()
        } catch { disconnect(client) }
    }
    private func sendNext() {
        guard !sending, let client, !outbound.isEmpty else { return }
        sending = true
        let data = outbound.removeFirst()
        let metadata = NWProtocolWebSocket.Metadata(opcode:.text)
        let context = NWConnection.ContentContext(identifier:"GameLingo",metadata:[metadata])
        client.send(content:data,contentContext:context,isComplete:true,completion:.contentProcessed { [weak self,weak client] error in
            guard let self, let client, self.client === client else { return }
            self.sending = false
            if let error { self.disconnect(client,reason:"فشل الإرسال عند \(self.stage) · \(Self.safeError(error))") } else { self.sendNext() }
        })
        queue.asyncAfter(deadline:.now()+2) { [weak self,weak client] in
            guard let self, let client, self.client === client, self.sending else { return }
            // Network.framework send completion provides backpressure; fail stalled peers.
            if self.outbound.count >= 7 { self.disconnect(client) }
        }
    }
    func validateAddress() {
        queue.async { [self] in
            guard listener != nil, !Self.localAddresses().contains(listeningHost) else { return }
            stopNow(preserveIdentity:true); listenerFailed(); diagnostic("network.changed", "تغير عنوان Wi-Fi؛ جارٍ انتظار استعادة المستمع", show:true)
        }
    }
    func stop() { queue.async { [self] in stopNow(); diagnostic("server.stopped", "أُوقف خادم التلفزيون", show:true) } }
    private func stopNow(preserveIdentity: Bool = false) {
        generation += 1; if let client { disconnect(client) }
        listener?.cancel(); listener = nil; heartbeat?.cancel(); heartbeat = nil
        if !preserveIdentity { identity = nil; tokenDigest = nil }
        DispatchQueue.main.async { self.onListening?(false) }
    }
}
