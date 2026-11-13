// Standalone Apple Network.framework regression probe. No device credentials.
import Foundation
import Network
import Darwin

var first: UnsafeMutablePointer<ifaddrs>?
guard getifaddrs(&first) == 0 else { fatalError("getifaddrs") }
var cursor = first
var address: String?
while let item = cursor {
    defer { cursor = item.pointee.ifa_next }
    guard let raw = item.pointee.ifa_addr, raw.pointee.sa_family == UInt8(AF_INET),
          String(cString:item.pointee.ifa_name).hasPrefix("en"),
          item.pointee.ifa_flags & UInt32(IFF_UP | IFF_RUNNING) == UInt32(IFF_UP | IFF_RUNNING) else { continue }
    var text = [CChar](repeating:0,count:Int(NI_MAXHOST))
    if getnameinfo(raw,socklen_t(raw.pointee.sa_len),&text,socklen_t(text.count),nil,0,NI_NUMERICHOST) == 0 {
        address = String(cString:text); break
    }
}
freeifaddrs(first)
guard let address else { fatalError("No active LAN IPv4") }
let queue = DispatchQueue(label:"probe")
for explicitPort in [false,true] {
    let done = DispatchSemaphore(value:0)
    let parameters = NWParameters.tcp
    parameters.requiredLocalEndpoint = .hostPort(host:NWEndpoint.Host(address),port:explicitPort ? .any : 38443)
    let listener = try NWListener(using:parameters,on:explicitPort ? 38443 : .any)
    var outgoing: NWConnection?
    var incoming: NWConnection?
    listener.newConnectionHandler = { connection in
        incoming = connection
        if case .hostPort(let host,_) = connection.endpoint {
            print("LAN probe explicitPort=\(explicitPort) endpoint=\(host)")
            if case .ipv4(let ip) = host { print("LAN probe IPv4 bytes=\(Array(ip.rawValue))") }
        }
        connection.cancel(); done.signal()
    }
    listener.stateUpdateHandler = { state in
        switch state {
        case .ready:
            print("LAN probe explicitPort=\(explicitPort) requested=38443 actual=\(listener.port?.rawValue ?? 0)")
            let client = NWConnection(host:NWEndpoint.Host(address),port:listener.port!,using:.tcp)
            outgoing = client; client.start(queue:queue)
        case .failed(let error): print("LAN probe listener failed: \(error)"); done.signal()
        default: break
        }
    }
    listener.start(queue:queue)
    if done.wait(timeout:.now()+10) == .timedOut { print("LAN probe timed out") }
    outgoing?.cancel(); incoming?.cancel(); listener.cancel()
}
