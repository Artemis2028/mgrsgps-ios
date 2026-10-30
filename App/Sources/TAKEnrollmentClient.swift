import Foundation
import GridFixCore
import Security

/// Separate bootstrap from the CoT stream: an administrator-approved private
/// CA can establish enrollment trust, but cannot weaken existing stream checks.
enum TAKEnrollmentTrust {
    enum Decision {
        case trusted(TAKServerTrust.Certificate)
        case approval(TAKServerTrust.Certificate)
        case refused(String)
    }
    static func evaluate(_ trust: SecTrust, host: String, pin: String?) -> Decision {
        guard let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
              let leaf = chain.first, let root = chain.last else { return .refused("The server did not provide a certificate") }
        let metadata = TAKServerTrust.describe(leaf)
        if let pin, pin != metadata.sha256 { return .refused("The enrollment server certificate changed. Verify it with your administrator before starting a new sign-in.") }
        guard SecTrustSetNetworkFetchAllowed(trust, false) == errSecSuccess,
              SecTrustSetPolicies(trust, SecPolicyCreateSSL(true, host as CFString)) == errSecSuccess else {
            return .refused("Unable to verify enrollment server trust")
        }
        if SecTrustEvaluateWithError(trust, nil) { return .trusted(metadata) }
        // A private CA/name mismatch requires explicit approval of this exact
        // leaf. Even before offering that choice, verify its chain and dates.
        guard SecTrustSetPolicies(trust, SecPolicyCreateSSL(true, nil)) == errSecSuccess,
              SecTrustSetAnchorCertificates(trust, [root] as CFArray) == errSecSuccess,
              SecTrustSetAnchorCertificatesOnly(trust, true) == errSecSuccess,
              SecTrustEvaluateWithError(trust, nil) else {
            return .refused("The enrollment server certificate is expired, not yet valid, or has an invalid chain")
        }
        return pin == metadata.sha256 ? .trusted(metadata) : .approval(metadata)
    }
}

/// One ephemeral, bounded HTTP operation. No redirects, cookies, credential
/// storage, challenge-based Basic auth, server error-body logging or caching.
private final class EnrollmentHTTP: NSObject, URLSessionDataDelegate {
    struct Reply { let bytes: Data; let status: Int; let certificate: TAKServerTrust.Certificate }
    struct Approval: Error { let certificate: TAKServerTrust.Certificate }
    private let host: String
    private let pin: String?
    private let maximumBytes: Int
    private var session: URLSession?
    private var continuation: CheckedContinuation<Reply, Error>?
    private var certificate: TAKServerTrust.Certificate?
    private var bytes = Data()
    private var status = 0
    private var failure: Error?
    private init(host: String, pin: String?, maximumBytes: Int) {
        self.host = host; self.pin = pin; self.maximumBytes = maximumBytes
    }
    static func perform(_ request: URLRequest, host: String, pin: String?, maximumBytes: Int) async throws -> Reply {
        let operation = EnrollmentHTTP(host: host, pin: pin, maximumBytes: maximumBytes)
        return try await operation.run(request)
    }
    private func run(_ request: URLRequest) async throws -> Reply {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil; configuration.httpCookieStorage = nil; configuration.urlCredentialStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 20; configuration.timeoutIntervalForResource = 40
        configuration.tlsMinimumSupportedProtocolVersion = .TLSv12
        let queue = OperationQueue(); queue.maxConcurrentOperationCount = 1
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
        self.session = session
        defer { session.invalidateAndCancel(); self.session = nil }
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                session.dataTask(with: request).resume()
            }
        } onCancel: { session.invalidateAndCancel() }
    }
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              challenge.protectionSpace.host == host,
              let trust = challenge.protectionSpace.serverTrust else {
            failure = TAKCoT.Failure(message: "Unexpected enrollment authentication challenge")
            completionHandler(.cancelAuthenticationChallenge, nil); return
        }
        switch TAKEnrollmentTrust.evaluate(trust, host: host, pin: pin) {
        case let .trusted(value):
            certificate = value; completionHandler(.useCredential, URLCredential(trust: trust))
        case let .approval(value):
            failure = Approval(certificate: value); completionHandler(.cancelAuthenticationChallenge, nil)
        case let .refused(message):
            failure = TAKCoT.Failure(message: message); completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        failure = TAKCoT.Failure(message: "Enrollment redirects are refused. Enter the server's direct address.")
        completionHandler(nil)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let response = response as? HTTPURLResponse,
              response.expectedContentLength <= maximumBytes else {
            failure = TAKCoT.Failure(message: "Enrollment response exceeds its size limit")
            completionHandler(.cancel); return
        }
        status = response.statusCode; completionHandler(.allow)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard data.count <= maximumBytes - bytes.count else {
            failure = TAKCoT.Failure(message: "Enrollment response exceeds its size limit")
            dataTask.cancel(); return
        }
        bytes.append(data)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let continuation else { return }; self.continuation = nil
        if let failure { continuation.resume(throwing: failure) }
        else if error != nil { continuation.resume(throwing: TAKCoT.Failure(message: "Enrollment connection failed or was cancelled. Check the server address and connection.")) }
        else if let certificate { continuation.resume(returning: .init(bytes: bytes, status: status, certificate: certificate)) }
        else { continuation.resume(throwing: TAKCoT.Failure(message: "Enrollment did not establish server trust")) }
    }
}

enum TAKEnrollmentClient {
    struct VerifiedServer {
        let target: TAKEnrollment.Target
        let certificate: TAKServerTrust.Certificate
        let explicitlyApproved: Bool
    }
    struct NeedsApproval: Error { let certificate: TAKServerTrust.Certificate }
    /// No Authorization header exists in this phase. Cancel the TLS challenge
    /// before any HTTP request if private CA/name approval is required.
    static func verify(_ target: TAKEnrollment.Target, approvedPin: String? = nil) async throws -> VerifiedServer {
        let request = URLRequest(url: target.url(path: "/Marti/api/tls/config"))
        do {
            let reply = try await EnrollmentHTTP.perform(request, host: target.host, pin: approvedPin, maximumBytes: 64 * 1024)
            try Task.checkCancellation()
            return .init(target: target, certificate: reply.certificate, explicitlyApproved: approvedPin != nil)
        } catch let approval as EnrollmentHTTP.Approval { throw NeedsApproval(certificate: approval.certificate) }
    }
    struct Result {
        let server: VerifiedServer
        let key: TAKEnrollmentKey
        let certificates: TAKEnrollment.Certificates
        let credentials: TAKImportedCredentials
    }
    static func enroll(server: VerifiedServer, username: String, password: String, deviceUID: String) async throws -> Result {
        guard !username.isEmpty, !username.contains(":"), username.utf8.count <= 1024, !password.isEmpty, password.utf8.count <= 8192,
              !username.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw TAKCoT.Failure(message: "Enter a username and password or token")
        }
        let authorization = "Basic " + Data((username + ":" + password).utf8).base64EncodedString()
        var get = URLRequest(url: server.target.url(path: "/Marti/api/tls/config"))
        get.setValue(authorization, forHTTPHeaderField: "Authorization")
        let config = try await EnrollmentHTTP.perform(get, host: server.target.host, pin: server.certificate.sha256, maximumBytes: 64 * 1024)
        try checkStatus(config.status); try Task.checkCancellation()
        let subject = try TAKEnrollment.configuration(config.bytes)
        let key = try TAKEnrollmentKey(deviceUID: deviceUID)
        let csr = try key.request(subject: subject, username: username)
        var post = URLRequest(url: server.target.url(path: "/Marti/api/tls/signClient/v2", deviceUID: deviceUID))
        post.httpMethod = "POST"; post.httpBody = TAKEnrollment.CSR.body(csr)
        post.setValue(authorization, forHTTPHeaderField: "Authorization")
        post.setValue("text/plain", forHTTPHeaderField: "Content-Type")
        post.setValue("application/json", forHTTPHeaderField: "Accept")
        let response = try await EnrollmentHTTP.perform(post, host: server.target.host, pin: server.certificate.sha256, maximumBytes: 1024 * 1024)
        try checkStatus(response.status); try Task.checkCancellation()
        let certificates = try TAKEnrollment.certificates(response.bytes)
        let credentials = try key.identity(certificate: certificates.client, authorities: certificates.authorities)
        return .init(server: server, key: key, certificates: certificates, credentials: credentials)
    }
    private static func checkStatus(_ status: Int) throws {
        if status == 401 || status == 403 { throw TAKCoT.Failure(message: "Sign-in refused. Check your username and password or token.") }
        guard (200..<300).contains(status) else { throw TAKCoT.Failure(message: "The enrollment server refused the request (HTTP \(status))") }
    }
}
