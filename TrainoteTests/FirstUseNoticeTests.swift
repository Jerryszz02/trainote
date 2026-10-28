import XCTest
import SwiftData
@testable import Trainote

@MainActor
final class FirstUseNoticeTests: XCTestCase {
  private var directory: URL!
  private let now = Date(timeIntervalSince1970: 1_800_000_000)

  override func setUpWithError() throws {
    directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  }
  override func tearDownWithError() throws {
    if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
  }
  private func store(version: String = FirstUseNoticeStore.currentVersion) -> FirstUseNoticeStore {
    FirstUseNoticeStore(directory: directory, version: version, clock: { self.now })
  }

  func testFirstLaunchAcceptRestartAndVersionChange() throws {
    let notice = store()
    XCTAssertFalse(notice.accepted)
    XCTAssertTrue(notice.localAIEnabled)
    try notice.accept()
    XCTAssertEqual(notice.acceptance?.acceptedAt, now)
    XCTAssertTrue(store().accepted)
    XCTAssertFalse(store(version: "future-purpose-v2").accepted)
    let values = try directory.appendingPathComponent("notice.json").resourceValues(forKeys: [.isExcludedFromBackupKey])
    XCTAssertEqual(values.isExcludedFromBackup, true)
  }

  func testExpiredFutureAndCorruptRecordsFailClosed() throws {
    try LocalHealthStorage.prepare(directory)
    let url = directory.appendingPathComponent("notice.json")
    for record in [
      FirstUseNoticeStore.Acceptance(noticeVersion: FirstUseNoticeStore.currentVersion,
                                    acceptedAt: now, expiresAt: now),
      FirstUseNoticeStore.Acceptance(noticeVersion: FirstUseNoticeStore.currentVersion,
                                    acceptedAt: now.addingTimeInterval(1))
    ] {
      try LocalHealthStorage.write(JSONEncoder().encode(record), to: url)
      XCTAssertFalse(store().accepted)
    }
    try LocalHealthStorage.write(Data("corrupt".utf8), to: url)
    XCTAssertFalse(store().accepted)
    XCTAssertTrue(store().storageFailed)
  }

  func testFailedAcceptanceBeforeOrAfterReplacementRemainsGatedOnRestart() throws {
    for replace in [false, true] {
      let notice = FirstUseNoticeStore(directory: directory, clock: { self.now }, writer: { data, url in
        if replace { try LocalHealthStorage.write(data, to: url) }
        throw AnalysisFailure.storageFailed
      })
      XCTAssertThrowsError(try notice.accept())
      XCTAssertFalse(notice.accepted)
      XCTAssertFalse(store().accepted)
    }
  }

  func testWithdrawalAndReacceptancePreserveDisabledIndependentPreference() throws {
    let notice = store()
    try notice.accept()
    try notice.setLocalAIEnabled(false)
    try notice.withdraw()
    XCTAssertFalse(store().accepted)
    XCTAssertFalse(store().localAIEnabled)
    try notice.accept()
    XCTAssertTrue(store().accepted)
    XCTAssertFalse(store().localAIEnabled)
    let pref = try directory.appendingPathComponent("local-ai-preference.json")
      .resourceValues(forKeys: [.isExcludedFromBackupKey])
    XCTAssertEqual(pref.isExcludedFromBackup, true)
  }

  func testFailedWithdrawalStopsCurrentSessionAndUsesFallbackRemoval() throws {
    try store().accept()
    let notice = FirstUseNoticeStore(directory: directory, clock: { self.now },
                                    writer: { _, _ in throw AnalysisFailure.storageFailed })
    XCTAssertThrowsError(try notice.withdraw())
    XCTAssertFalse(notice.accepted)
    XCTAssertFalse(store().accepted)
  }

  func testAcknowledgmentDoesNotGrantHealthOrCloudConsentAndBackupDoesNotContainIt() throws {
    let notice = store()
    try notice.accept()
    let healthConsent = try LocalConsentStore(url: directory.appendingPathComponent("health-consent.json"))
    XCTAssertNil(healthConsent.record(for: .healthData))
    XCTAssertNil(healthConsent.record(for: .aiReports))
    let container = try PersistenceController.makeContainer(inMemory: true)
    container.mainContext.insert(BodyWeightEntry(value: .init(id: UUID(), measuredAt: now, kilograms: 72, timeZoneIdentifier: "UTC", createdAt: now, updatedAt: now)))
    try container.mainContext.save()
    let backup = try BackupArchiveService.export(context: container.mainContext)
    let json = String(decoding: backup, as: UTF8.self)
    XCTAssertFalse(json.contains("noticeVersion"))
    XCTAssertFalse(json.contains("localAIEnabled"))
    XCTAssertTrue(notice.accepted)
  }

  func testRestrictedDeletionRemovesRecordsWithoutChangingAcknowledgmentOrPreference() throws {
    let container = try PersistenceController.makeContainer(inMemory: true)
    container.mainContext.insert(BodyWeightEntry(value: .init(id: UUID(), measuredAt: now, kilograms: 72, timeZoneIdentifier: "UTC", createdAt: now, updatedAt: now)))
    try container.mainContext.save()
    let notice = store()
    try notice.setLocalAIEnabled(false)
    try FirstUseNoticeDataDeletion.deleteManualRecords(context: container.mainContext)
    XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<BodyWeightEntry>()), 0)
    XCTAssertFalse(notice.accepted)
    XCTAssertFalse(store().localAIEnabled)
  }
  func testFailedPreferenceWriteCannotReenableAfterRestartAndNoticeAcceptanceDoesNotHideFailure() throws {
    try store().setLocalAIEnabled(true)
    var failPreferenceWrites = true
    let notice = FirstUseNoticeStore(directory: directory, clock: { self.now }, writer: { data, url in
      if failPreferenceWrites && url.lastPathComponent.hasPrefix("local-ai") {
        throw AnalysisFailure.storageFailed
      }
      try LocalHealthStorage.write(data, to: url)
    })
    XCTAssertThrowsError(try notice.setLocalAIEnabled(false))
    XCTAssertFalse(notice.localAIEnabled)
    XCTAssertFalse(store().localAIEnabled)
    try notice.accept()
    XCTAssertTrue(notice.accepted)
    XCTAssertTrue(notice.storageFailed, "Accepting notice must not clear an unrelated preference failure")
    failPreferenceWrites = false
    try notice.setLocalAIEnabled(true)
    XCTAssertTrue(store().localAIEnabled)
    XCTAssertFalse(notice.storageFailed)
  }

  func testFailedEnablingAfterReplacementRemainsDisabledOnRestart() throws {
    try store().setLocalAIEnabled(false)
    let notice = FirstUseNoticeStore(directory: directory, clock: { self.now }, writer: { data, url in
      try LocalHealthStorage.write(data, to: url)
      throw AnalysisFailure.storageFailed
    })
    XCTAssertThrowsError(try notice.setLocalAIEnabled(true))
    XCTAssertFalse(notice.localAIEnabled)
    XCTAssertFalse(store().localAIEnabled)
  }

}
