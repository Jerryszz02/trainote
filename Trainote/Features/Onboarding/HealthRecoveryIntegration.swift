import Foundation
import Observation

/// F's assembly owns one C service/control for the UI and, later, fresh report preparation.
/// The displayed result is transient UI state and must never be reused as a report snapshot.
@MainActor
@Observable
final class HealthRecoveryIntegration {
  let repository: any AnalysisRepository
  let healthData: (any HealthDataProviding)?
  let calibration: RecoveryCalibrationControl
  let service: RecoveryService?
  private(set) var todayResult: RecoveryResult?
  private(set) var failureMessage: String?
  private(set) var healthReadFailed = false

  init(
    repository: any AnalysisRepository, healthData: (any HealthDataProviding)?,
    calibration: RecoveryCalibrationControl = .init(), bundle: Bundle = .main
  ) {
    self.repository = repository
    self.healthData = healthData
    self.calibration = calibration
    do {
      service = try RecoveryService(bundle: bundle, calibration: calibration)
    } catch {
      service = nil
      failureMessage = "恢复分析资源暂时无法载入。训练、饮食和体感记录仍可使用。"
    }
  }

  /// Only C's explicitly reviewed entries can inform training candidates.
  var reviewedExerciseMuscles: [String: [MuscleID]] {
    guard let service else { return [:] }
    return Dictionary(
      uniqueKeysWithValues: service.mapping.entries.compactMap { entry in
        guard entry.status == .mapped else { return nil }
        return (entry.exerciseID, entry.weights.keys.sorted { $0.rawValue < $1.rawValue })
      })
  }

  func reloadToday(at now: Date = .now, timeZone: TimeZone = .current) {
    guard let service else { return }
    let window = AnalysisWindow(
      start: now.addingTimeInterval(-Double(RecoveryParameters.inputDays) * 86_400), end: now)
    do {
      let health: HealthDataSnapshot
      do {
        health =
          try healthData?.localSnapshot(window: window)
          ?? .disconnected(window: window, asOf: now)
        healthReadFailed = false
      } catch {
        healthReadFailed = true
        health = .init(
          window: window, fetchedAt: now, isFresh: false, samples: [],
          statuses: HealthDataType.allCases.map {
            .init(type: $0, state: .failed, queriedAt: now, failure: .readFailed)
          })
      }
      let input = try repository.analysisInput(
        asOf: now, window: window, timeZone: timeZone, health: health)
      todayResult = try service.calculate(input)
      failureMessage = nil
    } catch {
      todayResult = nil
      failureMessage = "暂时无法更新恢复状态，请稍后重试。原有记录仍保留。"
    }
  }

  func checkInDraft(at now: Date = .now, timeZone: TimeZone = .current) throws -> CheckInValue {
    let today = AnalysisFingerprint.localDate(now, timeZone: timeZone)
    return try repository.manualRecords().checkIns.first {
      $0.localDate == today && $0.timeZoneIdentifier == timeZone.identifier
    }
      ?? .init(
        id: UUID(), localDate: today, timeZoneIdentifier: timeZone.identifier, updatedAt: now)
  }

  func offerCheckIn(at now: Date = .now, timeZone: TimeZone = .current) throws -> Bool {
    try RecoveryCheckInPrompt.offer(
      repository: repository, records: repository.manualRecords(), date: now, timeZone: timeZone)
  }

  func suggestedMuscles(at now: Date = .now) -> [MuscleID] {
    todayResult?.muscles.filter {
      $0.hasPain || $0.hasMovementLimitation
        || $0.lastTrainedAt.map { $0 <= now && now.timeIntervalSince($0) <= 7 * 86_400 } == true
    }.map(\.muscleID) ?? []
  }

  var needsRecoveryReview: Bool {
    todayResult?.muscles.contains { $0.hasPain || $0.hasMovementLimitation } == true
      || todayResult?.systemicState == .low || todayResult?.systemicState == .limited
      || todayResult?.facts.contains { $0.id == "recovery.feeling" && $0.value == 0 } == true
  }

  func todayMessage(hasRoutines: Bool) -> String {
    if let failureMessage { return failureMessage }
    if todayResult?.muscles.contains(where: { $0.hasPain || $0.hasMovementLimitation }) == true {
      return "已记录疼痛或活动受限，先查看受影响肌群，再安排训练。"
    }
    if needsRecoveryReview { return "今天体感偏疲惫，查看恢复状态后再安排训练。" }
    if !hasRoutines { return "先选择一套训练模板，按自己的安排开始。" }
    if todayResult?.facts.contains(where: {
      $0.id == "recovery.unallocatedRecords" && ($0.value ?? 0) > 0
    }) == true {
      return "部分训练尚未分配肌群负荷，先查看记录覆盖与体感。"
    }
    return "结合已记录的训练与体感，查看今天的恢复状态。"
  }
}
