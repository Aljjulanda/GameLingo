import Foundation

struct QRBootstrap: Codable, Equatable {
    var v: Int, kind: String, host: String, port: Int, session: String, nonce: String, fingerprint: String, name: String, expires: Int64
    func validate(now: Int64) throws {
        guard v == 1, kind == "gamelingo-tv-pair", LAN.isPrivateIPv4(host), port == 38444,
              UUID(uuidString:session) != nil, Data(base64Encoded:nonce)?.count == 32,
              fingerprint.range(of:"^[0-9a-f]{64}$",options:.regularExpression) != nil,
              !name.isEmpty, name.count <= 80, expires > now, expires-now <= 180_000 else { throw LingoError.invalid("QR غير صالح أو منتهي؛ أنشئ جلسة جديدة على TV") }
    }
    static func decode(_ value: String, now: Int64) throws -> QRBootstrap {
        guard value.utf8.count <= 2048 else { throw LingoError.invalid("QR غير صالح") }
        let result = try JSONDecoder().decode(Self.self,from:Data(value.utf8)); try result.validate(now:now); return result
    }
}
