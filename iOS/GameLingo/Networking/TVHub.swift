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
    private let testingLoopback: Bool
    init(testingLoopback: Bool = false) { self.testingLoopback = testingLoopback }

    static func localAddresses() -> [String] {
        var first: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&first) == 0 else { return [] }; defer { freeifaddrs(first) }
        var result: [String] = [], cursor = first
        while let item = cursor {
            defer { cursor = item.pointee.ifa_next }
            guard let address = item.pointee.ifa_addr, address.pointee.sa_family == UInt8(AF_INET),
                  String(cString:item.pointee.ifa_name).hasPrefix("en") else { continue }
            var host = [CChar](repeating:0,count:Int(NI_MAXHOST))
            if getnameinfo(address,socklen_t(address.pointee.sa_len),&host,socklen_t(host.count),nil,0,NI_NUMERICHOST) == 0 {
                let value = String(cString:host); if LAN.isPrivateIPv4(value) { result.append(value) }
            }
        }
        return result.sorted()
    }
    private func status(_ text: String) { DispatchQueue.main.async { self.onStatus?(text) } }
    func start(host: String, settings: TVSettings) throws {
        guard (LAN.isPrivateIPv4(host) && Self.localAddresses().contains(host)) || (testingLoopback && host == "127.0.0.1") else { throw LingoError.invalid("اختر عنوان Wi-Fi الحالي لهذا iPhone") }
        queue.async { [self] in
          do {
            stopNow(); sequence = TVSequence(); self.settings = settings
            let identity = try TLSIdentity()
            let random = try KeychainStore.random(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
            let pin = String(format:"%06u",random % 1_000_000)
            self.identity = identity; self.pin = pin; failures = 0; deadline = ProcessInfo.processInfo.systemUptime+300
            let tls = NWProtocolTLS.Options()
            guard let nativeIdentity = sec_identity_create(identity.identity) else { status("تعذر إعداد TLS"); return }
            sec_protocol_options_set_local_identity(tls.securityProtocolOptions,nativeIdentity)
            sec_protocol_options_set_min_tls_protocol_version(tls.securityProtocolOptions,.TLSv12)
            let parameters = NWParameters(tls:tls,tcp:NWProtocolTCP.Options())
            let websocket = NWProtocolWebSocket.Options(); websocket.autoReplyPing = true; websocket.maximumMessageSize = TVProtocol.maximumBytes
            parameters.defaultProtocolStack.applicationProtocols.insert(websocket,at:0)
            parameters.requiredLocalEndpoint = .hostPort(host:NWEndpoint.Host(host),port:NWEndpoint.Port(rawValue:TVProtocol.port)!)
            parameters.allowLocalEndpointReuse = true
            do {
                // requiredLocalEndpoint already fixes both address and port.
                // Passing on: as well makes Network.framework reject the bind.
                let listener = try NWListener(using:parameters)
                let epoch = generation
                listener.stateUpdateHandler = { [weak self] state in
                    guard let self, self.generation == epoch else { return }
                    switch state {
                    case .ready:
                        self.status("بانتظار التلفزيون · \(host):38443")
                        DispatchQueue.main.async { self.onPairing?(host,"\(identity.fingerprint.prefix(12))-\(pin)") }
                    case .failed: self.status("تعذر تشغيل خادم التلفزيون؛ راجع إذن الشبكة المحلية"); self.stopNow()
                    default: break
                    }
                }
                listener.newConnectionHandler = { [weak self] connection in self?.accept(connection,epoch:epoch) }
                self.listener = listener; listener.start(queue:queue)
            } catch { status("تعذر بدء خادم التلفزيون: \(error.localizedDescription)") }
          } catch { status("تعذر إعداد هوية اتصال التلفزيون: \(error.localizedDescription)") }
        }
    }
    private func accept(_ connection: NWConnection, epoch: Int) {
        guard epoch == generation, client == nil,
              case .hostPort(let host,_) = connection.endpoint,
              LAN.isPrivateIPv4(String(describing:host)) || (testingLoopback && String(describing:host) == "127.0.0.1") else { connection.cancel(); return }
        client = connection; authenticated = false
        connection.stateUpdateHandler = { [weak self,weak connection] state in
            guard let self, let connection, self.client === connection else { return }
            switch state {
            case .ready: self.receive(connection)
            case .failed, .cancelled: self.disconnect(connection)
            default: break
            }
        }
        connection.start(queue:queue)
        queue.asyncAfter(deadline:.now()+8) { [weak self,weak connection] in
            guard let self, let connection, self.client === connection, !self.authenticated else { return }; self.disconnect(connection)
        }
    }
    private func disconnect(_ connection: NWConnection) {
        guard client === connection else { return }
        client = nil; authenticated = false; outbound.removeAll(); sending = false
        heartbeat?.cancel(); heartbeat = nil; connection.cancel(); status("التلفزيون غير متصل؛ لا تُعاد الجمل السابقة")
        // Invalidate pending inference before this queue can authenticate a replacement TV.
        onDisconnected?()
    }
    private func receive(_ connection: NWConnection) {
        connection.receiveMessage { [weak self,weak connection] data,context,_,error in
            guard let self, let connection, self.client === connection else { return }
            guard error == nil else { self.disconnect(connection); return }
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
                    case "heartbeat": self.enqueue(TVProtocol.envelope("heartbeat",fields:["time_ms":Self.now()]))
                    case "settings_ack":
                        if let width = message["width_px"] as? Int, let height = message["height_px"] as? Int {
                            self.status("التلفزيون متصل · \(width)×\(height) · تم تأكيد الإعدادات")
                        }
                    default: throw LingoError.invalid("نوع رسالة غير مسموح")
                    }
                }
                self.receive(connection)
            } catch { self.disconnect(connection) }
        }
    }
    private func authenticate(_ message: [String:Any]) throws {
        switch message["type"] as? String {
        case "pair":
            guard failures < 5, ProcessInfo.processInfo.systemUptime < deadline, !pin.isEmpty,
                  let supplied = message["pin"] as? String, Self.equal(Data(supplied.utf8),Data(pin.utf8)) else {
                failures += 1; throw LingoError.invalid("رُفض الاقتران")
            }
            let token = try KeychainStore.random(32).base64EncodedString()
            try KeychainStore.write(Data(SHA256.hash(data:Data(token.utf8))),account:"tv.token.sha256.v1")
            pin = ""
            enqueue(TVProtocol.envelope("paired",fields:["token":token]),stamp:false)
        case "hello":
            guard let token = message["token"] as? String, (32...128).contains(token.count),
                  let digest = try KeychainStore.read("tv.token.sha256.v1"), Self.equal(Data(SHA256.hash(data:Data(token.utf8))),digest) else { throw LingoError.invalid("رُفض الاتصال") }
        default: throw LingoError.invalid("رسالة اقتران غير صالحة")
        }
        authenticated = true
        enqueue(TVProtocol.envelope("connection_status",fields:["state":"connected","session":sequence.session,"time_ms":Self.now()]),stamp:false)
        enqueue(TVProtocol.envelope("settings_sync",fields:["settings":settings.wire]))
        // Never keep or replay a subtitle across reconnection.
        let timer = DispatchSource.makeTimerSource(queue:queue)
        timer.schedule(deadline:.now()+6,repeating:6)
        timer.setEventHandler { [weak self] in self?.enqueue(TVProtocol.envelope("heartbeat",fields:["time_ms":Self.now()])) }
        heartbeat = timer; timer.resume(); status("التلفزيون متصل")
        DispatchQueue.main.async { self.onConnected?() }
    }
    private static func equal(_ a: Data, _ b: Data) -> Bool {
        guard a.count == b.count else { return false }; var difference: UInt8 = 0
        for (x,y) in zip(a,b) { difference |= x ^ y }; return difference == 0
    }
    static func now() -> Int64 { Int64(Date().timeIntervalSince1970*1000) }
    func publish(_ message: [String:Any]) { queue.async { [self] in if authenticated { enqueue(message) } } }
    func configure(_ value: TVSettings, kind: String = "settings_sync") {
        queue.async { [self] in settings = value; if authenticated { enqueue(TVProtocol.envelope(kind,fields:["settings":value.wire])) } }
    }
    private func enqueue(_ message: [String:Any], stamp: Bool = true) {
        guard let client else { return }
        do {
            let data = try TVProtocol.encode(stamp ? sequence.stamp(message) : message)
            // A slow TV must not create an unbounded queue or receive stale subtitles.
            guard outbound.count < 8 else { disconnect(client); return }
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
            if error != nil { self.disconnect(client) } else { self.sendNext() }
        })
        queue.asyncAfter(deadline:.now()+2) { [weak self,weak client] in
            guard let self, let client, self.client === client, self.sending else { return }
            // Network.framework send completion provides backpressure; fail stalled peers.
            if self.outbound.count >= 7 { self.disconnect(client) }
        }
    }
    func stop() { queue.async { [self] in stopNow() } }
    private func stopNow() {
        generation += 1; if let client { disconnect(client) }
        listener?.cancel(); listener = nil; heartbeat?.cancel(); heartbeat = nil; identity = nil
    }
}
