import DeviceCheck
import Foundation

/// Deployment configuration only. F must keep transport nil until disclosure, signing and deployment gates pass.
struct ReportProxyConfiguration {
  let baseURL: URL
  init(approvedBaseURL: URL) throws {
    guard approvedBaseURL.scheme == "https", approvedBaseURL.host != nil,
      approvedBaseURL.user == nil, approvedBaseURL.password == nil,
      approvedBaseURL.query == nil, approvedBaseURL.fragment == nil,
      ["", "/"].contains(approvedBaseURL.path), approvedBaseURL.port == nil || approvedBaseURL.port == 443
    else { throw AIReportFailure.invalidInput }
    baseURL = approvedBaseURL
  }
}
@MainActor
protocol ReportHTTPPerforming {
  func send(_ request: URLRequest) async throws -> (Data, Int)
}
private final class RejectReportRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
  func urlSession(_ session: URLSession, task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
    completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
@MainActor
final class ReportProxyHTTP: ReportHTTPPerforming {
  private let session: URLSession
  init() {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.urlCache = nil
    configuration.httpCookieStorage = nil
    configuration.urlCredentialStorage = nil
    configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
    configuration.timeoutIntervalForRequest = 30
    configuration.timeoutIntervalForResource = 30
    session = URLSession(configuration: configuration, delegate: RejectReportRedirects(), delegateQueue: nil)
  }
  func send(_ request: URLRequest) async throws -> (Data, Int) {
    let (bytes, response) = try await session.bytes(for: request)
    guard let response = response as? HTTPURLResponse,
      response.expectedContentLength <= AIReportPolicy.responseByteLimit
    else { throw AIReportFailure.invalidResponse }
    var data = Data()
    for try await byte in bytes {
      try Task.checkCancellation()
      guard data.count < AIReportPolicy.responseByteLimit else { throw AIReportFailure.invalidResponse }
      data.append(byte)
    }
    return (data, response.statusCode)
  }
}

@MainActor
final class ProxyReportTransport: AIReportTransport {
  private struct Intent: Encodable { var method: String; var path: String; var bodyHash: String }
  private struct ChallengeRequest: Encodable { var keyID: String; var purpose: String; var intent: Intent? }
  private struct Challenge: Decodable { var challengeID: String; var challenge: String; var expiresAt: Date }
  private struct Attestation: Encodable { var keyID: String; var challengeID: String; var attestation: String }
  private struct Assertion: Encodable { var keyID: String; var challengeID: String; var assertion: String }
  private struct Session: Decodable { var token: String; var expiresAt: Date }
  private struct Consent: Encodable { var consentVersion: String; var grantedAt: Date }
  private struct Empty: Encodable {}
  private let configuration: ReportProxyConfiguration
  private let credentials: any ReportCredentialStoring
  private let attestor: any ReportDeviceAttesting
  private let http: any ReportHTTPPerforming
  private let clock: () -> Date
  private var identity: ReportDeviceCredentials
  private var generation = UUID()
  private var revocationTask: Task<Void, Error>?
  private var reportDeadline: Date?
  var revocationPending: Bool { identity.revocationPending }

  init(configuration: ReportProxyConfiguration, credentials: any ReportCredentialStoring,
    attestor: any ReportDeviceAttesting, http: any ReportHTTPPerforming,
    clock: @escaping () -> Date = { .now }) throws {
    self.configuration = configuration
    self.credentials = credentials
    self.attestor = attestor
    self.http = http
    self.clock = clock
    identity = try credentials.load()
  }

  func generate(_ input: ReportInput, requestID: UUID, consent: ConsentLease,
    grantedAt: Date, beforeSending: @escaping @MainActor () throws -> Void) async throws -> ReportResult {
    let originalGeneration = generation
    reportDeadline = clock().addingTimeInterval(30)
    defer { reportDeadline = nil }
    let guardSend: @MainActor () throws -> Void = { [self] in
      try beforeSending()
      try Task.checkCancellation()
      guard generation == originalGeneration, !identity.revocationPending else { throw AIReportFailure.cancelled }
      guard reportDeadline.map({ $0 > clock() }) == true else { throw AIReportFailure.stale }
    }
    try guardSend()
    guard consent.scope == .aiReports, consent.version == LocalConsentStore.aiConsentVersion else { throw AIReportFailure.consentRequired }
    let envelope = try AIReportPolicy.encoder().encode(ReportRequestEnvelope(input: input, requestID: requestID))
    guard envelope.count <= AIReportPolicy.requestByteLimit else { throw AIReportFailure.invalidInput }
    try await register(guardSend)
    // Refresh the server record for this valid local lease; server restarts intentionally clear grants.
    let consentBytes = try AIReportPolicy.encoder().encode(Consent(consentVersion: consent.version, grantedAt: grantedAt))
    _ = try await authenticated(method: "PUT", path: "/v1/consent", body: consentBytes, beforeSending: guardSend)
    try guardSend()
    let bytes = try await authenticated(method: "POST", path: "/v1/reports", body: envelope, beforeSending: guardSend)
    try guardSend()
    return try ReportResultValidator.decode(bytes, input: input, now: clock())
  }

  func cancelAndMarkRevocation() throws {
    generation = UUID()
    identity.revocationPending = identity.registered
    try credentials.save(identity)
  }
  func revokeServerConsent() async throws {
    guard identity.revocationPending else { return }
    if let revocationTask { try await revocationTask.value; return }
    let task = Task { @MainActor [self] in
      // Revocation is permitted without AI consent. It can only authenticate DELETE /v1/consent.
      let bytes = try AIReportPolicy.encoder().encode(Empty())
      _ = try await authenticated(method: "DELETE", path: "/v1/consent", body: bytes, beforeSending: {})
      var next = identity; next.revocationPending = false
      try credentials.save(next)
      identity = next
    }
    revocationTask = task
    defer { revocationTask = nil }
    try await task.value
  }

  private func register(_ guardSend: @escaping @MainActor () throws -> Void) async throws {
    try guardSend()
    guard attestor.isSupported else { throw AIReportFailure.deviceUnavailable }
    if identity.keyID == nil {
      let keyID = try await attestor.generateKey()
      try guardSend()
      identity.keyID = keyID
      try credentials.save(identity)
    }
    guard !identity.registered else { return }
    let keyID = identity.keyID!
    let challenge: Challenge
    do {
      challenge = try await json("/v1/installations/challenge",
        value: ChallengeRequest(keyID: keyID, purpose: "attest"), beforeSending: guardSend)
    } catch AIReportFailure.server(409) {
      // Apple's key attestation is one-time. Recover a lost response via a new assertion, not re-attestation.
      try guardSend()
      identity.registered = true
      try credentials.save(identity)
      return
    }
    guard let nonce = Data(base64Encoded: challenge.challenge), nonce.count == 32, challenge.expiresAt > clock() else { throw AIReportFailure.invalidResponse }
    let attestation: Data
    do {
      attestation = try await attestor.attest(keyID: keyID, challenge: nonce)
    } catch {
      let failure = error as NSError
      let retrySameKey = failure.domain == DCError.errorDomain
        && failure.code == DCError.Code.serverUnavailable.rawValue
      if !retrySameKey, identity.keyID == keyID, !identity.registered {
        // Apple only permits retrying serverUnavailable with this one-time attestation key.
        // Persist removal now; generate its replacement on the next explicit report request.
        // Preserve any revocation state changed while awaiting DeviceCheck.
        identity.keyID = nil
        try credentials.save(identity)
      }
      throw error
    }
    try guardSend()
    let body = try AIReportPolicy.encoder().encode(Attestation(keyID: keyID, challengeID: challenge.challengeID,
      attestation: attestation.base64EncodedString()))
    do {
      _ = try await send(method: "POST", path: "/v1/installations/attest", body: body, beforeSending: guardSend)
    } catch AIReportFailure.server(409) {
      // Lost registration response: the subsequent assertion still has to prove possession of this key.
    }
    try guardSend()
    identity.registered = true
    try credentials.save(identity)
  }
  private func authenticated(method: String, path: String, body: Data,
    beforeSending: @escaping @MainActor () throws -> Void) async throws -> Data {
    try beforeSending()
    guard identity.registered, let keyID = identity.keyID, attestor.isSupported else { throw AIReportFailure.deviceUnavailable }
    let intent = Intent(method: method, path: path, bodyHash: AIReportPolicy.digest(body))
    let challenge: Challenge = try await json("/v1/installations/challenge",
      value: ChallengeRequest(keyID: keyID, purpose: "session", intent: intent), beforeSending: beforeSending)
    guard challenge.expiresAt > clock(), UUID(uuidString: challenge.challengeID) != nil,
      Data(base64Encoded: challenge.challenge)?.count == 32 else { throw AIReportFailure.invalidResponse }
    let clientData = Data("trainote-session-v1\n\(challenge.challengeID)\n\(challenge.challenge)\n\(method)\n\(path)\n\(intent.bodyHash)".utf8)
    let assertion = try await attestor.assertion(keyID: keyID, clientData: clientData)
    try beforeSending()
    let session: Session = try await json("/v1/session", value: Assertion(keyID: keyID,
      challengeID: challenge.challengeID, assertion: assertion.base64EncodedString()), beforeSending: beforeSending)
    guard session.expiresAt > clock(), session.token.range(of: "^[A-Za-z0-9_-]{43}$", options: .regularExpression) != nil else { throw AIReportFailure.invalidResponse }
    return try await send(method: method, path: path, body: body, token: session.token, beforeSending: beforeSending)
  }
  private func json<Value: Encodable, Result: Decodable>(_ path: String, value: Value,
    beforeSending: @escaping @MainActor () throws -> Void) async throws -> Result {
    let data = try await send(method: "POST", path: path, body: AIReportPolicy.encoder().encode(value), beforeSending: beforeSending)
    return try AIReportPolicy.decoder().decode(Result.self, from: data)
  }
  private func send(method: String, path: String, body: Data, token: String? = nil,
    beforeSending: @escaping @MainActor () throws -> Void) async throws -> Data {
    try beforeSending() // Immediately before EVERY request, including auth, consent, and any retry.
    guard body.count <= AIReportPolicy.requestByteLimit,
      ["/v1/installations/challenge", "/v1/installations/attest", "/v1/session", "/v1/consent", "/v1/reports"].contains(path)
    else { throw AIReportFailure.invalidInput }
    var request = URLRequest(url: configuration.baseURL.appendingPathComponent(String(path.dropFirst())))
    // Auth handshakes share the report's total interaction budget. DELETE keeps its own short timeout.
    request.timeoutInterval = method == "DELETE" || identity.revocationPending
      ? 30 : min(30, max(0.1, reportDeadline?.timeIntervalSince(clock()) ?? 30))
    request.httpMethod = method
    request.httpBody = body
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
    let (data, status) = try await http.send(request)
    try beforeSending()
    guard data.count <= AIReportPolicy.responseByteLimit else { throw AIReportFailure.invalidResponse }
    guard (200..<300).contains(status) else { throw AIReportFailure.server(status) }
    return data
  }
}
