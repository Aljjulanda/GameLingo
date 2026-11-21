import Foundation
import Security
import CryptoKit

/// Pins the ephemeral TV identity scanned from its display. No global trust/ATS exception.
final class QRBootstrapClient: NSObject, URLSessionDelegate, URLSessionTaskDelegate {
    let invitation: QRBootstrap
    init(_ invitation: QRBootstrap) { self.invitation = invitation }
    func exchange(phone: String, code: String, name: String) async throws {
        try invitation.validate(now:TVHub.now())
        guard LAN.isPrivateIPv4(phone), code.range(of:"^[0-9a-f]{64}-[0-9]{6}$",options:.regularExpression) != nil else { throw LingoError.invalid("بيانات مصدر الترجمة غير جاهزة") }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 55; configuration.timeoutIntervalForResource = 60
        let session = URLSession(configuration:configuration,delegate:self,delegateQueue:nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url:URL(string:"https://\(invitation.host):38444/pair")!)
        request.httpMethod = "POST"; request.setValue("application/json",forHTTPHeaderField:"Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject:["session":invitation.session,"nonce":invitation.nonce,"host":phone,"code":code,"name":String(name.prefix(80))])
        let (data,response) = try await session.data(for:request)
        guard data.count <= 1024, (response as? HTTPURLResponse)?.statusCode == 200,
              let value = try JSONSerialization.jsonObject(with:data) as? [String:Any], value["accepted"] as? Bool == true else { throw LingoError.invalid("لم يُقبل الجهاز على TV؛ أنشئ QR جديدًا للمحاولة") }
    }
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              challenge.protectionSpace.host == invitation.host, challenge.protectionSpace.port == 38444,
              let trust = challenge.protectionSpace.serverTrust, let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate], let certificate = chain.first else { completionHandler(.cancelAuthenticationChallenge,nil); return }
        let digest = SHA256.hash(data:SecCertificateCopyData(certificate) as Data).map{String(format:"%02x",$0)}.joined()
        guard digest == invitation.fingerprint else { completionHandler(.cancelAuthenticationChallenge,nil); return }
        SecTrustSetPolicies(trust,SecPolicyCreateBasicX509())
        SecTrustSetAnchorCertificates(trust,[certificate] as CFArray); SecTrustSetAnchorCertificatesOnly(trust,true)
        guard SecTrustEvaluateWithError(trust,nil) else { completionHandler(.cancelAuthenticationChallenge,nil); return }
        completionHandler(.useCredential,URLCredential(trust:trust))
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
