import SwiftData
import XCTest

@testable import Trainote

@MainActor
final class ConsentPersistenceTests: XCTestCase {
  private var directory: URL!
  private var url: URL { directory.appendingPathComponent("consent.json") }
  private let date = AnalysisFixtures.asOf

  override func setUp() {
    super.setUp()
    directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  }

  override func tearDown() {
    try? FileManager.default.removeItem(at: directory)
    super.tearDown()
  }

  func testFailedHealthConsentWriteCannotRestoreGrantAfterRestart() throws {
    try seedBothScopes()
    let store = try LocalConsentStore(url: url, writer: { _, _ in throw AnalysisFailure.storageFailed })
    let lease = try store.lease(for: .healthData, version: LocalConsentStore.healthConsentVersion)
    var cancelled = false
    store.onRevocation(.healthData) { cancelled = true }
    XCTAssertThrowsError(try store.revoke(.healthData, at: date))
    XCTAssertTrue(cancelled)
    XCTAssertThrowsError(try store.validate(lease))
    XCTAssertFalse(try XCTUnwrap(store.record(for: .healthData)).isGranted)
    XCTAssertTrue(try persistedRecord(.healthData).isGranted)  // The original file really stayed stale.
    let reopened = try LocalConsentStore(url: url)
    XCTAssertFalse(try XCTUnwrap(reopened.record(for: .healthData)).isGranted)
    XCTAssertThrowsError(
      try reopened.lease(for: .healthData, version: LocalConsentStore.healthConsentVersion))
    XCTAssertTrue(try XCTUnwrap(reopened.record(for: .aiReports)).isGranted)
    let foundation = HealthFoundation(
      container: try PersistenceController.makeContainer(inMemory: true), localDirectory: directory)
    XCTAssertFalse(try XCTUnwrap(foundation.consent?.record(for: .healthData)).isGranted)
    try reopened.revoke(.healthData, at: date.addingTimeInterval(1))
    XCTAssertFalse(try persistedRecord(.healthData).isGranted)
    try reopened.grant(.healthData, version: LocalConsentStore.healthConsentVersion, at: date.addingTimeInterval(2))
    XCTAssertTrue(try XCTUnwrap(LocalConsentStore(url: url).record(for: .healthData)).isGranted)
  }

  func testSuccessfulRemoteAIDeletionCannotUndoFailedLocalRevocationOnRestart() throws {
    try seedBothScopes()
    let store = try LocalConsentStore(url: url, writer: { _, _ in throw AnalysisFailure.storageFailed })
    XCTAssertThrowsError(try store.revoke(.aiReports, at: date))
    // A transport may clear its own retry flag after a successful DELETE. That independent state
    // must not clear the shared local user's withdrawal or cause the old grant to reappear.
    let transportFlag = directory.appendingPathComponent("simulated-transport-revocation-pending")
    try Data([1]).write(to: transportFlag)
    try FileManager.default.removeItem(at: transportFlag)
    XCTAssertFalse(FileManager.default.fileExists(atPath: transportFlag.path))
    XCTAssertTrue(try persistedRecord(.aiReports).isGranted)
    let reopened = try LocalConsentStore(url: url)
    XCTAssertFalse(try XCTUnwrap(reopened.record(for: .aiReports)).isGranted)
    XCTAssertThrowsError(try reopened.lease(for: .aiReports, version: LocalConsentStore.aiConsentVersion))
    XCTAssertTrue(try XCTUnwrap(reopened.record(for: .healthData)).isGranted)
  }

  func testNormalRegrantAcknowledgesRetainedJournalWithoutChangingOtherScope() throws {
    try seedBothScopes()
    let store = try LocalConsentStore(url: url)
    let healthLease = try store.lease(for: .healthData, version: LocalConsentStore.healthConsentVersion)
    let aiLease = try store.lease(for: .aiReports, version: LocalConsentStore.aiConsentVersion)
    try store.revoke(.healthData, at: date)
    XCTAssertThrowsError(try store.validate(healthLease))
    XCTAssertNoThrow(try store.validate(aiLease))
    let intent = try journalID(.healthData)
    XCTAssertFalse(try persistedRecord(.healthData).isGranted)
    try store.grant(.healthData, version: "health-read-v2", at: date.addingTimeInterval(1))
    XCTAssertNoThrow(try store.validate(aiLease))
    XCTAssertThrowsError(try store.validate(healthLease))
    XCTAssertEqual(try journalID(.healthData), intent)
    let reopened = try LocalConsentStore(url: url)
    XCTAssertNoThrow(try reopened.lease(for: .healthData, version: "health-read-v2"))
    let newHealthLease = try reopened.lease(for: .healthData, version: "health-read-v2")
    try reopened.revoke(.aiReports, at: date.addingTimeInterval(2))
    XCTAssertNoThrow(try reopened.validate(newHealthLease))
    let again = try LocalConsentStore(url: url)
    XCTAssertTrue(try XCTUnwrap(again.record(for: .healthData)).isGranted)
    XCTAssertFalse(try XCTUnwrap(again.record(for: .aiReports)).isGranted)
    let backup = try BackupArchiveService.export(
      context: ModelContext(PersistenceController.makeContainer(inMemory: true)))
    let text = String(decoding: backup, as: UTF8.self)
    for scope in ConsentScope.allCases {
      XCTAssertTrue(try journalURL(scope).resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
      XCTAssertFalse(text.contains(try journalID(scope).uuidString))
    }
    XCTAssertTrue(try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
  }

  func testFailedJournalWriteFallsBackToRevokedStateAndMustBeRepairedBeforeRegrant() throws {
    try seedBothScopes()
    let original = try LocalConsentStore(url: url)
    try original.revoke(.healthData, at: date)
    try original.grant(.healthData, version: LocalConsentStore.healthConsentVersion, at: date.addingTimeInterval(1))
    let previousIntent = try journalID(.healthData)
    var failJournal = true
    let store = try LocalConsentStore(url: url, writer: LocalHealthStorage.write, revocationWriter: { data, destination in
      if failJournal { throw AnalysisFailure.storageFailed }
      try LocalHealthStorage.write(data, to: destination)
    })
    let lease = try store.lease(for: .healthData, version: LocalConsentStore.healthConsentVersion)
    var cancelled = false
    store.onRevocation(.healthData) { cancelled = true }
    XCTAssertThrowsError(try store.revoke(.healthData, at: date.addingTimeInterval(2)))
    XCTAssertTrue(cancelled)
    XCTAssertThrowsError(try store.validate(lease))
    XCTAssertEqual(try journalID(.healthData), previousIntent)
    XCTAssertFalse(try persistedRecord(.healthData).isGranted)
    XCTAssertFalse(try XCTUnwrap(LocalConsentStore(url: url).record(for: .healthData)).isGranted)
    XCTAssertThrowsError(try store.grant(.healthData, version: "health-read-v2", at: date.addingTimeInterval(3)))
    XCTAssertFalse(try XCTUnwrap(store.record(for: .healthData)).isGranted)
    failJournal = false
    try store.grant(.healthData, version: "health-read-v2", at: date.addingTimeInterval(4))
    XCTAssertNotEqual(try journalID(.healthData), previousIntent)
    let reopened = try LocalConsentStore(url: url)
    XCTAssertNoThrow(try reopened.lease(for: .healthData, version: "health-read-v2"))
    XCTAssertNoThrow(try reopened.lease(for: .aiReports, version: LocalConsentStore.aiConsentVersion))
  }

  func testJournalFailureAfterReplacementStillBlocksRestartWhenOriginalWriteAlsoFails() throws {
    try seedBothScopes()
    let store = try LocalConsentStore(
      url: url, writer: { _, _ in throw AnalysisFailure.storageFailed },
      revocationWriter: { data, destination in
        try LocalHealthStorage.write(data, to: destination)
        throw AnalysisFailure.storageFailed
      })
    XCTAssertThrowsError(try store.revoke(.aiReports, at: date))
    XCTAssertTrue(try persistedRecord(.aiReports).isGranted)
    XCTAssertFalse(try XCTUnwrap(LocalConsentStore(url: url).record(for: .aiReports)).isGranted)
  }

  func testOriginalRevokedWriteFailureAfterReplacementStillSurfacesError() throws {
    try seedBothScopes()
    let store = try LocalConsentStore(url: url, writer: { data, destination in
      try LocalHealthStorage.write(data, to: destination)
      throw AnalysisFailure.storageFailed
    })
    XCTAssertThrowsError(try store.revoke(.healthData, at: date))
    XCTAssertFalse(try persistedRecord(.healthData).isGranted)
    XCTAssertFalse(try XCTUnwrap(LocalConsentStore(url: url).record(for: .healthData)).isGranted)
  }

  func testNewWithdrawalSupersedesAcknowledgedGrantWhenOriginalWriteFails() throws {
    try seedBothScopes()
    let original = try LocalConsentStore(url: url)
    try original.revoke(.healthData, at: date)
    try original.grant(.healthData, version: LocalConsentStore.healthConsentVersion, at: date.addingTimeInterval(1))
    let acknowledgedID = try journalID(.healthData)
    let store = try LocalConsentStore(url: url, writer: { _, _ in throw AnalysisFailure.storageFailed })
    XCTAssertTrue(try XCTUnwrap(store.record(for: .healthData)).isGranted)
    XCTAssertThrowsError(try store.revoke(.healthData, at: date.addingTimeInterval(2)))
    XCTAssertNotEqual(try journalID(.healthData), acknowledgedID)
    XCTAssertTrue(try persistedRecord(.healthData).isGranted)
    let reopened = try LocalConsentStore(url: url)
    XCTAssertFalse(try XCTUnwrap(reopened.record(for: .healthData)).isGranted)
    XCTAssertNoThrow(try reopened.lease(for: .aiReports, version: LocalConsentStore.aiConsentVersion))
  }

  func testRegrantCannotSkipFailedRevokedStateConfirmation() throws {
    try seedBothScopes()
    let failing = try LocalConsentStore(url: url, writer: { _, _ in throw AnalysisFailure.storageFailed })
    XCTAssertThrowsError(try failing.revoke(.healthData, at: date))
    let reopened = try LocalConsentStore(url: url, writer: { _, _ in throw AnalysisFailure.storageFailed })
    XCTAssertThrowsError(try reopened.grant(.healthData, version: "health-read-v2", at: date.addingTimeInterval(1)))
    XCTAssertTrue(try persistedRecord(.healthData).isGranted)
    XCTAssertFalse(try XCTUnwrap(reopened.record(for: .healthData)).isGranted)
    XCTAssertFalse(try XCTUnwrap(LocalConsentStore(url: url).record(for: .healthData)).isGranted)
  }

  func testFailedFinalGrantBeforeOrAfterReplacementCannotEnableConsentOnRestart() throws {
    for afterReplacement in [false, true] {
      let caseURL = directory.appendingPathComponent("\(afterReplacement)/consent.json")
      try seedBothScopes(at: caseURL)
      let original = try LocalConsentStore(url: caseURL)
      try original.revoke(.healthData, at: date)
      var failGrant = true
      let store = try LocalConsentStore(url: caseURL, writer: { data, destination in
        let records = try JSONDecoder().decode(StoredRecords.self, from: data)
        if failGrant && records.records[ConsentScope.healthData.rawValue]?.isGranted == true {
          if afterReplacement { try LocalHealthStorage.write(data, to: destination) }
          throw AnalysisFailure.storageFailed
        }
        try LocalHealthStorage.write(data, to: destination)
      })
      let unrelatedLease = try store.lease(for: .aiReports, version: LocalConsentStore.aiConsentVersion)
      XCTAssertThrowsError(try store.grant(.healthData, version: "health-read-v2", at: date.addingTimeInterval(1)))
      XCTAssertFalse(try XCTUnwrap(store.record(for: .healthData)).isGranted)
      XCTAssertNoThrow(try store.validate(unrelatedLease))
      XCTAssertFalse(try XCTUnwrap(LocalConsentStore(url: caseURL).record(for: .healthData)).isGranted)
      failGrant = false
      try store.grant(.healthData, version: "health-read-v2", at: date.addingTimeInterval(2))
      let lease = try store.lease(for: .healthData, version: "health-read-v2")
      XCTAssertNoThrow(try store.validate(lease))
      let reopened = try LocalConsentStore(url: caseURL)
      XCTAssertNoThrow(try reopened.lease(for: .healthData, version: "health-read-v2"))
      XCTAssertNoThrow(try reopened.lease(for: .aiReports, version: LocalConsentStore.aiConsentVersion))
    }
  }

  func testCorruptUnreadableOrMissingAcknowledgedJournalMakesStoreUnavailable() throws {
    for damage in ["corrupt", "directory", "missing", "wrongScope", "futureVersion"] {
      let caseURL = directory.appendingPathComponent("\(damage)/consent.json")
      try seedBothScopes(at: caseURL)
      let store = try LocalConsentStore(url: caseURL)
      try store.revoke(.healthData, at: date)
      try store.grant(.healthData, version: LocalConsentStore.healthConsentVersion, at: date.addingTimeInterval(1))
      let journal = journalURL(.healthData, at: caseURL)
      let originalData = try Data(contentsOf: journal)
      try FileManager.default.removeItem(at: journal)
      switch damage {
      case "corrupt": try Data("incomplete-json".utf8).write(to: journal)
      case "directory": try FileManager.default.createDirectory(at: journal, withIntermediateDirectories: true)
      case "wrongScope", "futureVersion":
        var value = try XCTUnwrap(JSONSerialization.jsonObject(with: originalData) as? [String: Any])
        if damage == "wrongScope" { value["scope"] = ConsentScope.aiReports.rawValue }
        else { value["schemaVersion"] = 99 }
        try JSONSerialization.data(withJSONObject: value).write(to: journal)
      default: break
      }
      XCTAssertThrowsError(try LocalConsentStore(url: caseURL), damage)
      let foundation = HealthFoundation(
        container: try PersistenceController.makeContainer(inMemory: true),
        localDirectory: caseURL.deletingLastPathComponent())
      XCTAssertNil(foundation.consent, damage)
      XCTAssertNil(foundation.healthData, damage)
      XCTAssertEqual(foundation.setupFailure, .storageFailed, damage)
    }
  }

  func testBothStoragePathsFailStillCancelsAndReportsFailureWithoutClaimingDurability() throws {
    try seedBothScopes()
    let original = try Data(contentsOf: url)
    let store = try LocalConsentStore(
      url: url, writer: { _, _ in throw AnalysisFailure.storageFailed },
      revocationWriter: { _, _ in throw AnalysisFailure.storageFailed })
    let lease = try store.lease(for: .healthData, version: LocalConsentStore.healthConsentVersion)
    var cancelled = false
    store.onRevocation(.healthData) { cancelled = true }
    XCTAssertThrowsError(try store.revoke(.healthData, at: date))
    XCTAssertTrue(cancelled)
    XCTAssertThrowsError(try store.validate(lease))
    XCTAssertFalse(try XCTUnwrap(store.record(for: .healthData)).isGranted)
    XCTAssertEqual(try Data(contentsOf: url), original)
    XCTAssertFalse(FileManager.default.fileExists(atPath: journalURL(.healthData).path))
    // No persistence operation succeeded. This failure must remain visible for explicit retry;
    // an in-memory flag cannot truthfully promise safety after a process restart in this case.
  }

  func testLegacyConsentStateStillLoadsAndUpgradesOnWithdrawal() throws {
    try seedBothScopes()
    var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    legacy["schemaVersion"] = 1
    legacy.removeValue(forKey: "acknowledgedRevocations")
    try LocalHealthStorage.write(JSONSerialization.data(withJSONObject: legacy), to: url)
    let store = try LocalConsentStore(url: url)
    XCTAssertNoThrow(try store.lease(for: .healthData, version: LocalConsentStore.healthConsentVersion))
    XCTAssertNoThrow(try store.lease(for: .aiReports, version: LocalConsentStore.aiConsentVersion))
    try store.revoke(.healthData, at: date)
    let current = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    XCTAssertEqual(current["schemaVersion"] as? Int, 2)
    XCTAssertFalse(try XCTUnwrap(LocalConsentStore(url: url).record(for: .healthData)).isGranted)
  }

  func testLegacyTrailingClosureStillInjectsTheMainConsentWriter() throws {
    var calls = 0
    let store = try LocalConsentStore(url: url) { _, _ in
      calls += 1
      throw AnalysisFailure.storageFailed
    }
    XCTAssertThrowsError(try store.grant(.aiReports, version: LocalConsentStore.aiConsentVersion, at: date))
    XCTAssertGreaterThan(calls, 0)
    XCTAssertFalse(try XCTUnwrap(store.record(for: .aiReports)).isGranted)
    XCTAssertFalse(try XCTUnwrap(LocalConsentStore(url: url).record(for: .aiReports)).isGranted)
  }

  private func seedBothScopes(at consentURL: URL? = nil) throws {
    let store = try LocalConsentStore(url: consentURL ?? url)
    try store.grant(.healthData, version: LocalConsentStore.healthConsentVersion, at: date)
    try store.grant(.aiReports, version: LocalConsentStore.aiConsentVersion, at: date)
  }

  private func persistedRecord(_ scope: ConsentScope) throws -> LocalConsentRecord {
    return try XCTUnwrap(
      JSONDecoder().decode(StoredRecords.self, from: Data(contentsOf: url)).records[scope.rawValue])
  }

  private struct StoredRecords: Decodable { var records: [String: LocalConsentRecord] }

  private func journalURL(_ scope: ConsentScope, at consentURL: URL? = nil) -> URL {
    (consentURL ?? url).appendingPathExtension("revocation-\(scope.rawValue).json")
  }

  private func journalID(_ scope: ConsentScope) throws -> UUID {
    struct Intent: Decodable { var id: UUID }
    return try JSONDecoder().decode(Intent.self, from: Data(contentsOf: journalURL(scope))).id
  }
}
