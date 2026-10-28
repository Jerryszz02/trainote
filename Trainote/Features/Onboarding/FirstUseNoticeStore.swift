import Foundation
import Observation

/// Acknowledgment and AI preference are separate from Health/cloud consent and business backups.
@MainActor
@Observable
final class FirstUseNoticeStore {
  nonisolated static let currentVersion = "local-processing-v1"
  struct Acceptance: Codable, Equatable {
    let noticeVersion: String
    let acceptedAt: Date
    var expiresAt: Date? = nil
  }
  private struct Preference: Codable { var localAIEnabled: Bool }
  typealias Writer = (Data, URL) throws -> Void
  private let directory: URL
  private let version: String
  private let writer: Writer
  private let clock: () -> Date
  private(set) var acceptance: Acceptance?
  private(set) var localAIEnabled = true
  private var noticeStorageFailed = false
  private var preferenceStorageFailed = false
  var storageFailed: Bool { noticeStorageFailed || preferenceStorageFailed }
  private var withdrawn = false

  init(directory: URL, version: String = currentVersion,
       clock: @escaping () -> Date = Date.init,
       writer: @escaping Writer = LocalHealthStorage.write) {
    self.directory = directory
    self.version = version
    self.clock = clock
    self.writer = writer
    let recordURL = directory.appendingPathComponent("notice.json")
    if FileManager.default.fileExists(atPath: recordURL.path) {
      do { acceptance = try JSONDecoder().decode(Acceptance.self, from: Data(contentsOf: recordURL)) }
      catch { noticeStorageFailed = true }
    }
    withdrawn = FileManager.default.fileExists(atPath: withdrawalURL.path)
    let preferenceURL = directory.appendingPathComponent("local-ai-preference.json")
    if FileManager.default.fileExists(atPath: preferenceURL.path) {
      do { localAIEnabled = try JSONDecoder().decode(Preference.self, from: Data(contentsOf: preferenceURL)).localAIEnabled }
      catch { localAIEnabled = false; preferenceStorageFailed = true }
    }
    if FileManager.default.fileExists(atPath: disabledPreferenceURL.path) { localAIEnabled = false }
  }

  var accepted: Bool {
    guard !withdrawn, let acceptance, acceptance.noticeVersion == version,
      acceptance.acceptedAt.timeIntervalSince1970.isFinite,
      acceptance.acceptedAt <= clock(),
      acceptance.expiresAt.map({ $0 > clock() }) ?? true else { return false }
    return true
  }

  func accept() throws {
    let record = Acceptance(noticeVersion: version, acceptedAt: clock())
    do {
      try writer(JSONEncoder().encode(record), directory.appendingPathComponent("notice.json"))
      if FileManager.default.fileExists(atPath: withdrawalURL.path) {
        try FileManager.default.removeItem(at: withdrawalURL)
      }
      acceptance = record
      withdrawn = false
      noticeStorageFailed = false
    } catch {
      acceptance = nil
      withdrawn = true
      noticeStorageFailed = true
      // A writer can fail after replacing its destination. Keep restart fail-closed too.
      try? LocalHealthStorage.write(Data("withdrawn".utf8), to: withdrawalURL)
      throw error
    }
  }

  func withdraw() throws {
    withdrawn = true
    acceptance = nil
    do {
      try writer(Data("withdrawn".utf8), withdrawalURL)
      noticeStorageFailed = false
    } catch {
      noticeStorageFailed = true
      // Removing the acknowledgment is a second local durability path.
      try? FileManager.default.removeItem(at: directory.appendingPathComponent("notice.json"))
      throw error
    }
  }

  func setLocalAIEnabled(_ enabled: Bool) throws {
    if !enabled { localAIEnabled = false }
    do {
      // A durable stop marker wins over a previous enabled preference after a partial write.
      if !enabled { try writer(Data("disabled".utf8), disabledPreferenceURL) }
      try writer(JSONEncoder().encode(Preference(localAIEnabled: enabled)),
                 directory.appendingPathComponent("local-ai-preference.json"))
      if enabled && FileManager.default.fileExists(atPath: disabledPreferenceURL.path) {
        try FileManager.default.removeItem(at: disabledPreferenceURL)
      }
      localAIEnabled = enabled
      preferenceStorageFailed = false
    } catch {
      localAIEnabled = false
      preferenceStorageFailed = true
      // A failed writer may already have replaced the enabled value. Fail closed on restart.
      // If the filesystem cannot write either path, the visible failure must remain until retry.
      try? LocalHealthStorage.write(Data("disabled".utf8), to: disabledPreferenceURL)
      throw error
    }
  }

  private var disabledPreferenceURL: URL { directory.appendingPathComponent("local-ai-disabled") }
  private var withdrawalURL: URL { directory.appendingPathComponent("notice-withdrawn") }
}
