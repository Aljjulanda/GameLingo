import Foundation
import Security
import CryptoKit

final class TLSIdentity {
    let identity: SecIdentity
    let fingerprint: String
    private struct Stored: Codable { let package: Data, password: String }
    init() throws {
        let stored: Stored
        if let data = try KeychainStore.read("tv.tls.identity.v1") {
            stored = try JSONDecoder().decode(Stored.self,from:data)
        } else {
            let password = try KeychainStore.random(32).base64EncodedString()
            var error: NSError?
            guard let package = GLCreateIdentityPKCS12(password,&error) else { throw error ?? LingoError.invalid("تعذر إنشاء الشهادة") as NSError }
            stored = Stored(package:package,password:password)
            try KeychainStore.write(JSONEncoder().encode(stored),account:"tv.tls.identity.v1")
        }
        var items: CFArray?
        let status = SecPKCS12Import(stored.package as CFData,[kSecImportExportPassphrase:stored.password] as CFDictionary,&items)
        guard status == errSecSuccess, let records = items as? [[String:Any]], let first = records.first,
              let reference = first[kSecImportItemIdentity as String] else { throw LingoError.invalid("تعذر استيراد هوية TLS (\(status))") }
        identity = reference as! SecIdentity
        var certificate: SecCertificate?
        guard SecIdentityCopyCertificate(identity,&certificate) == errSecSuccess, let certificate else { throw LingoError.invalid("شهادة TLS غير متاحة") }
        fingerprint = SHA256.hash(data:SecCertificateCopyData(certificate) as Data).map { String(format:"%02x",$0) }.joined()
    }
}
