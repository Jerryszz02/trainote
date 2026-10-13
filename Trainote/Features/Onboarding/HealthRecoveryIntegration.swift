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
  private(set) var failureMessageKey: String?
  private(set) var failureMessage: String? {
    get { failureMessageKey.map { L10n.text($0) } }
    set { failureMessageKey = newValue }
  }
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
      failureMessage = "health.healthrecoveryintegration.recovery.resources.could.not.be.loaded.e5af04"
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
      failureMessage = "health.healthrecoveryintegration.recovery.could.not.be.updated.try.0b10e8"
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
      return L10n.text("health.healthrecoveryintegration.pain.or.limited.movement.is.recorded.7b08a6")
    }
    if needsRecoveryReview { return L10n.text("health.healthrecoveryintegration.you.reported.feeling.tired.today.review.75bacb") }
    if !hasRoutines { return L10n.text("health.healthrecoveryintegration.choose.a.workout.template.and.start.edd184") }
    if todayResult?.facts.contains(where: {
      $0.id == "recovery.unallocatedRecords" && ($0.value ?? 0) > 0
    }) == true {
      return L10n.text("health.healthrecoveryintegration.some.workouts.have.no.allocated.muscle.65b731")
    }
    return L10n.text("health.healthrecoveryintegration.review.today.s.recovery.using.your.bff516")
  }
}
