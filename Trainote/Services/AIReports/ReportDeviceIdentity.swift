import CryptoKit
import DeviceCheck
import Foundation
import Security

struct ReportDeviceCredentials: Codable, Equatable {
  var keyID: String?
  var registered = false
  var revocationPending = false
}
@MainActor
protocol ReportCredentialStoring {
  func load() throws -> ReportDeviceCredentials
  func save(_ value: ReportDeviceCredentials) throws
}
@MainActor
final class KeychainReportCredentials: ReportCredentialStoring {
  private let account: String
  init(proxyHost: String) { account = proxyHost }
  private var query: [String: Any] {
    [kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: "com.jerryszz.trainote.ai-reports",
      kSecAttrAccount as String: account, kSecAttrSynchronizable as String: false]
  }
  func load() throws -> ReportDeviceCredentials {
    var query = query
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    if status == errSecItemNotFound { return .init() }
    guard status == errSecSuccess, let data = item as? Data else { throw AIReportFailure.storage }
    return try JSONDecoder().decode(ReportDeviceCredentials.self, from: data)
  }
  func save(_ value: ReportDeviceCredentials) throws {
    let attributes: [String: Any] = [kSecValueData as String: try JSONEncoder().encode(value),
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
    let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    if status == errSecItemNotFound {
      var combined = query
      attributes.forEach { combined[$0.key] = $0.value }
      guard SecItemAdd(combined as CFDictionary, nil) == errSecSuccess else { throw AIReportFailure.storage }
    } else if status != errSecSuccess { throw AIReportFailure.storage }
  }
}

@MainActor
protocol ReportDeviceAttesting {
  var isSupported: Bool { get }
  func generateKey() async throws -> String
  func attest(keyID: String, challenge: Data) async throws -> Data
  func assertion(keyID: String, clientData: Data) async throws -> Data
}
@MainActor
struct AppleReportDeviceAttestor: ReportDeviceAttesting {
  var isSupported: Bool { DCAppAttestService.shared.isSupported }
  func generateKey() async throws -> String {
    guard isSupported else { throw AIReportFailure.deviceUnavailable }
    return try await withCheckedThrowingContinuation { continuation in
      DCAppAttestService.shared.generateKey { key, error in
        if let key { continuation.resume(returning: key) }
        else { continuation.resume(throwing: error ?? AIReportFailure.deviceUnavailable) }
      }
    }
  }
  func attest(keyID: String, challenge: Data) async throws -> Data {
    guard isSupported else { throw AIReportFailure.deviceUnavailable }
    let hash = Data(SHA256.hash(data: challenge))
    return try await withCheckedThrowingContinuation { continuation in
      DCAppAttestService.shared.attestKey(keyID, clientDataHash: hash) { data, error in
        if let data { continuation.resume(returning: data) }
        else { continuation.resume(throwing: error ?? AIReportFailure.deviceUnavailable) }
      }
    }
  }
  func assertion(keyID: String, clientData: Data) async throws -> Data {
    guard isSupported else { throw AIReportFailure.deviceUnavailable }
    let hash = Data(SHA256.hash(data: clientData))
    return try await withCheckedThrowingContinuation { continuation in
      DCAppAttestService.shared.generateAssertion(keyID, clientDataHash: hash) { data, error in
        if let data { continuation.resume(returning: data) }
        else { continuation.resume(throwing: error ?? AIReportFailure.deviceUnavailable) }
      }
    }
  }
}
