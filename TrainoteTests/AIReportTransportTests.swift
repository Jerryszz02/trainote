import DeviceCheck
import XCTest

@testable import Trainote

@MainActor
private final class ReportMemoryCredentials: ReportCredentialStoring {
  var value = ReportDeviceCredentials()
  var failSaving = false
  func load() throws -> ReportDeviceCredentials { value }
  func save(_ value: ReportDeviceCredentials) throws {
    if failSaving { throw AIReportFailure.storage }
    self.value = value
  }
}
@MainActor
private final class ReportFileCredentials: ReportCredentialStoring {
  let url: URL
  init(url: URL) { self.url = url }
  func load() throws -> ReportDeviceCredentials {
    guard FileManager.default.fileExists(atPath: url.path) else { return .init() }
    return try JSONDecoder().decode(ReportDeviceCredentials.self, from: Data(contentsOf: url))
  }
  func save(_ value: ReportDeviceCredentials) throws {
    try JSONEncoder().encode(value).write(to: url, options: .atomic)
  }
}
@MainActor
private final class SyntheticReportAttestor: ReportDeviceAttesting {
  var isSupported = true
  var attestCalls = 0
  var keys: [String] = []
  var attestedKeys: [String] = []
  var failure: ((String) -> Error?)?
  var onAttest: (() throws -> Void)?
  var assertionData: [Data] = []
  func generateKey() async throws -> String {
    let key = Data(repeating: UInt8(keys.count + 3), count: 32).base64EncodedString()
    keys.append(key)
    return key
  }
  func attest(keyID: String, challenge: Data) async throws -> Data {
    attestCalls += 1; attestedKeys.append(keyID)
    try onAttest?()
    if let error = failure?(keyID) { throw error }
    return Data("synthetic-attestation".utf8)
  }
  func assertion(keyID: String, clientData: Data) async throws -> Data {
    assertionData.append(clientData); return Data("synthetic-assertion".utf8)
  }
}
@MainActor
private final class ReportTestHTTP: ReportHTTPPerforming {
  let now = AnalysisFixtures.asOf
  var calls: [URLRequest] = []
  var onSend: ((URLRequest) -> Void)?
  var existingInstallation = false
  var deleteFails = false
  var input: ReportInput!
  func send(_ request: URLRequest) async throws -> (Data, Int) {
    calls.append(request); onSend?(request)
    var result: Any = [:]
    var status = 200
    switch request.url!.path {
    case "/v1/installations/challenge":
      let value = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
      if existingInstallation && value["purpose"] as? String == "attest" { status = 409 }
      result = ["challengeID": "7a4c9d1f-e7b2-4a21-9276-2cc8df746313",
        "challenge": Data(repeating: 7, count: 32).base64EncodedString(), "expiresAt": now.addingTimeInterval(120).timeIntervalSince1970 * 1000]
    case "/v1/session":
      result = ["token": String(repeating: "t", count: 43), "expiresAt": now.addingTimeInterval(120).timeIntervalSince1970 * 1000]
    case "/v1/reports":
      var report = LocalReportGenerator().make(try ReportWireInput(input).validationInput)
      report.reportID = UUID().uuidString; report.model = AIReportPolicy.model; report.isLocalFallback = false
      report.summary = ReportText.summary(try ReportWireInput(input).validationInput)
      return (try AIReportPolicy.encoder().encode(report), 200)
    case "/v1/consent":
      if request.httpMethod == "DELETE" && deleteFails { status = 503 }
    default: break
    }
    return (try JSONSerialization.data(withJSONObject: result), status)
  }
}

@MainActor
final class AIReportTransportTests: XCTestCase {
  private func input() -> ReportInput {
    var result = AnalysisFixtures.report
    result.inputFingerprint = String(repeating: "a", count: 64)
    result.knowledgeVersion = AIReportPolicy.knowledgeVersion
    result.calculationVersions = ["test-v1"]
    return result
  }
  private func transport(_ store: any ReportCredentialStoring, _ attestor: SyntheticReportAttestor,
    _ http: ReportTestHTTP) throws -> ProxyReportTransport {
    http.input = input()
    return try ProxyReportTransport(configuration: ReportProxyConfiguration(approvedBaseURL: URL(string: "https://reports.example.invalid")!),
      credentials: store, attestor: attestor, http: http, clock: { AnalysisFixtures.asOf })
  }
  private func generate(_ transport: ProxyReportTransport, guardSend: @escaping @MainActor () throws -> Void = {}) async throws -> ReportResult {
    try await transport.generate(input(), requestID: UUID(),
      consent: .init(scope: .aiReports, version: LocalConsentStore.aiConsentVersion, generation: UUID()),
      grantedAt: AnalysisFixtures.asOf, beforeSending: guardSend)
  }
  func testFullSyntheticTransportUsesRequestBoundAssertionsAndNoCredentialsInReportBody() async throws {
    let store = ReportMemoryCredentials(), attestor = SyntheticReportAttestor(), http = ReportTestHTTP()
    let transport = try transport(store, attestor, http)
    let result = try await generate(transport)
    XCTAssertFalse(result.isLocalFallback)
    XCTAssertEqual(attestor.attestCalls, 1)
    XCTAssertEqual(attestor.assertionData.count, 2)
    XCTAssertTrue(String(data: attestor.assertionData.last!, encoding: .utf8)!.contains("\nPOST\n/v1/reports\n"))
    XCTAssertTrue(http.calls.allSatisfy { $0.url?.host == "reports.example.invalid" })
    let reportRequest = try XCTUnwrap(http.calls.last)
    let body = String(data: reportRequest.httpBody!, encoding: .utf8)!
    XCTAssertFalse(body.contains("synthetic-assertion")); XCTAssertFalse(body.contains("token"))
    XCTAssertNotNil(reportRequest.value(forHTTPHeaderField: "Authorization"))
    XCTAssertTrue(store.value.registered)
  }
  func testInvalidLeaseOrUnavailableSimulatorHasZeroNetwork() async throws {
    let store = ReportMemoryCredentials(), attestor = SyntheticReportAttestor(), http = ReportTestHTTP()
    let transport = try transport(store, attestor, http)
    do { _ = try await generate(transport) { throw AIReportFailure.consentRequired }; XCTFail() } catch {}
    XCTAssertTrue(http.calls.isEmpty)
    attestor.isSupported = false
    do { _ = try await generate(transport); XCTFail() } catch {}
    XCTAssertTrue(http.calls.isEmpty)
  }
  func testRevocationInAuthHandshakeStopsBeforeConsentAndReport() async throws {
    let store = ReportMemoryCredentials(), attestor = SyntheticReportAttestor(), http = ReportTestHTTP()
    let transport = try transport(store, attestor, http)
    var valid = true
    http.onSend = { _ in valid = false }
    do { _ = try await generate(transport) { if !valid { throw AIReportFailure.cancelled } }; XCTFail() } catch {}
    XCTAssertEqual(http.calls.count, 1)
    XCTAssertFalse(http.calls.contains { $0.url!.path == "/v1/reports" || $0.url!.path == "/v1/consent" })
  }
  func testLostAttestationResponseRecoversUsingAssertionWithoutAttestingAgain() async throws {
    let store = ReportMemoryCredentials(), attestor = SyntheticReportAttestor(), http = ReportTestHTTP()
    store.value.keyID = Data(repeating: 3, count: 32).base64EncodedString()
    http.existingInstallation = true
    let transport = try transport(store, attestor, http)
    _ = try await generate(transport)
    XCTAssertEqual(attestor.attestCalls, 0); XCTAssertEqual(attestor.assertionData.count, 2)
  }
  func testInvalidAttestationKeyIsDiscardedOnDiskAndNextExplicitAttemptReplacesIt() async throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: url) }
    let store = ReportFileCredentials(url: url), attestor = SyntheticReportAttestor(), http = ReportTestHTTP()
    attestor.failure = { key in key == attestor.keys.first
      ? NSError(domain: DCError.errorDomain, code: DCError.Code.invalidKey.rawValue) : nil }
    let initial = try transport(store, attestor, http)
    do { _ = try await generate(initial); XCTFail("Invalid first key must fail without an automatic retry") } catch {}
    XCTAssertEqual(attestor.keys.count, 1); XCTAssertEqual(attestor.attestCalls, 1)
    XCTAssertNil(try ReportFileCredentials(url: url).load().keyID)
    XCTAssertFalse(http.calls.contains { $0.url!.path == "/v1/consent" || $0.url!.path == "/v1/reports" })
    // Recreate both credential store and transport: memory-only cleanup would strand this retry.
    let restarted = try transport(ReportFileCredentials(url: url), attestor, http)
    let result = try await generate(restarted)
    XCTAssertFalse(result.isLocalFallback)
    XCTAssertEqual(attestor.keys.count, 2); XCTAssertEqual(attestor.attestedKeys, attestor.keys)
    XCTAssertEqual(try store.load().keyID, attestor.keys[1]); XCTAssertTrue(try store.load().registered)
  }
  func testServerUnavailableKeepsSameAttestationKeyAcrossRestart() async throws {
    let store = ReportMemoryCredentials(), attestor = SyntheticReportAttestor(), http = ReportTestHTTP()
    attestor.failure = { _ in NSError(domain: DCError.errorDomain, code: DCError.Code.serverUnavailable.rawValue) }
    do { _ = try await generate(transport(store, attestor, http)); XCTFail() } catch {}
    XCTAssertEqual(attestor.keys.count, 1); XCTAssertEqual(attestor.attestCalls, 1)
    XCTAssertEqual(store.value.keyID, attestor.keys[0]); XCTAssertFalse(store.value.registered)
    attestor.failure = nil
    _ = try await generate(transport(store, attestor, http))
    XCTAssertEqual(attestor.keys.count, 1)
    XCTAssertEqual(attestor.attestedKeys, [attestor.keys[0], attestor.keys[0]])
  }
  func testNonDeviceCheckErrorWithTransientCodeStillDiscardsKeyAndCancellationStopsDelivery() async throws {
    let store = ReportMemoryCredentials(), attestor = SyntheticReportAttestor(), http = ReportTestHTTP()
    let transport = try transport(store, attestor, http)
    attestor.onAttest = { try transport.cancelAndMarkRevocation() }
    attestor.failure = { _ in NSError(domain: "synthetic-other-domain", code: DCError.Code.serverUnavailable.rawValue) }
    do { _ = try await generate(transport); XCTFail() } catch {}
    XCTAssertNil(store.value.keyID); XCTAssertEqual(attestor.keys.count, 1)
    XCTAssertFalse(http.calls.contains { $0.url!.path == "/v1/reports" || $0.url!.path == "/v1/consent" })
  }
  func testFailureToPersistDiscardedKeyFailsClosedUntilNextExplicitAttemptCanSave() async throws {
    let store = ReportMemoryCredentials(), attestor = SyntheticReportAttestor(), http = ReportTestHTTP()
    let transport = try transport(store, attestor, http)
    attestor.onAttest = { store.failSaving = true }
    attestor.failure = { _ in NSError(domain: DCError.errorDomain, code: DCError.Code.invalidKey.rawValue) }
    do { _ = try await generate(transport); XCTFail() } catch { XCTAssertEqual(error as? AIReportFailure, .storage) }
    XCTAssertEqual(attestor.keys.count, 1)
    XCTAssertFalse(http.calls.contains { $0.url!.path == "/v1/installations/attest" || $0.url!.path == "/v1/reports" })
    store.failSaving = false; attestor.onAttest = nil; attestor.failure = nil
    _ = try await generate(transport)
    XCTAssertEqual(attestor.keys.count, 2); XCTAssertEqual(store.value.keyID, attestor.keys[1])
  }
  func testPendingRevocationPersistsAcrossRestartAndCanOnlySendDelete() async throws {
    let store = ReportMemoryCredentials(), attestor = SyntheticReportAttestor(), http = ReportTestHTTP()
    let transport = try transport(store, attestor, http)
    _ = try await generate(transport)
    try transport.cancelAndMarkRevocation(); XCTAssertTrue(store.value.revocationPending)
    http.calls = []; http.deleteFails = true
    let restarted = try self.transport(store, attestor, http)
    do { _ = try await generate(restarted); XCTFail() } catch {}
    XCTAssertTrue(http.calls.isEmpty)
    do { try await restarted.revokeServerConsent(); XCTFail() } catch {}
    XCTAssertTrue(store.value.revocationPending)
    XCTAssertEqual(http.calls.last?.httpMethod, "DELETE")
    XCTAssertFalse(http.calls.contains { $0.url!.path == "/v1/reports" || $0.httpMethod == "PUT" })
    http.deleteFails = false; try await restarted.revokeServerConsent()
    XCTAssertFalse(store.value.revocationPending)
  }
  func testUserCannotConfigureNonHTTPSCredentialsOrPathInProxyURL() {
    for url in ["http://127.0.0.1", "https://user:secret@example.invalid", "https://example.invalid/endpoint", "https://example.invalid?system=prompt"] {
      XCTAssertThrowsError(try ReportProxyConfiguration(approvedBaseURL: URL(string: url)!))
    }
  }
}
