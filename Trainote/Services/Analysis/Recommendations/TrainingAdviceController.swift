import Foundation
import Observation
import SwiftData

enum TrainingAdviceAdoptionError: Error {
  case inProgressWorkout
  case templateChanged
  case recordsChanged
}

/// Reads one current local snapshot for display and a new one immediately before adoption.
@MainActor
@Observable
final class TrainingAdviceController {
  let repository: any AnalysisRepository
  let healthData: (any HealthDataProviding)?
  let recovery: RecoveryService?
  let modelContext: ModelContext
  let now: () -> Date
  let timeZone: () -> TimeZone

  private(set) var routines: [Routine] = []
  private(set) var evaluation: TrainingRecommendationEvaluation?
  private(set) var errorMessage: String?
  private(set) var activeWorkout: Workout?
  private var displayedPlans: [UUID: RecommendationPlan] = [:]
  @ObservationIgnored var onSelectionChange: (() -> Void)?
  var selectedRoutineID: UUID? {
    didSet { if selectedRoutineID != oldValue { selectionChanged() } }
  }
  var alternativeRoutineIDs: Set<UUID> = [] {
    didSet { if alternativeRoutineIDs != oldValue { selectionChanged() } }
  }
  /// nil means the user has not supplied a schedule; [] explicitly means no available day.
  var availableWeekdays: [Int]? {
    didSet { if availableWeekdays != oldValue { selectionChanged() } }
  }

  private func selectionChanged() {
    evaluation = nil
    displayedPlans = [:]
    onSelectionChange?()
  }

  init(
    repository: any AnalysisRepository, healthData: (any HealthDataProviding)?,
    recovery: RecoveryService?, modelContext: ModelContext,
    now: @escaping () -> Date = { .now }, timeZone: @escaping () -> TimeZone = { .current }
  ) {
    self.repository = repository
    self.healthData = healthData
    self.recovery = recovery
    self.modelContext = modelContext
    self.now = now
    self.timeZone = timeZone
  }

  func loadRoutines() {
    do {
      routines = try currentRoutines()
      activeWorkout = try currentInProgressWorkout()
      let ids = Set(routines.map(\.id))
      if selectedRoutineID.map({ !ids.contains($0) }) == true { selectedRoutineID = nil }
      alternativeRoutineIDs.formIntersection(ids)
      errorMessage = nil
    } catch {
      routines = []
      evaluation = nil
      activeWorkout = nil
      errorMessage = "暂时无法读取训练模板，请重试。"
    }
  }

  func refresh() {
    do {
      routines = try currentRoutines()
      activeWorkout = try currentInProgressWorkout()
      evaluation = try evaluate(routines: routines, at: now())
      displayedPlans = selectedPlans(in: routines)
      errorMessage = nil
    } catch {
      evaluation = nil
      displayedPlans = [:]
      errorMessage = "暂时无法计算建议，请检查本地记录后重试。"
    }
  }

  /// Capture only the current explicit plan selection. ReportSnapshotBuilder will fetch its own
  /// fresh input and call this provider once with B/C's freshly calculated results.
  func makeRecommendationProvider() throws -> TrainingRecommendationProvider {
    guard let recovery else { throw AnalysisFailure.unavailable }
    return provider(routines: try currentRoutines(), recovery: recovery)
  }

  /// Re-reads repository, HealthKit's local snapshot and templates on the same actor before save.
  @discardableResult
  func adopt(actionID: String, parameters: [String: Double] = [:]) throws -> Workout {
    guard let displayed = evaluation else { throw TrainingAdviceAdoptionError.recordsChanged }
    let startedAt = now()
    activeWorkout = try currentInProgressWorkout()
    guard activeWorkout == nil else { throw TrainingAdviceAdoptionError.inProgressWorkout }
    let freshRoutines = try currentRoutines()
    guard selectedPlans(in: freshRoutines) == displayedPlans else {
      throw TrainingAdviceAdoptionError.templateChanged
    }
    guard let selected = displayed.candidates.first(where: { $0.actionID == actionID }),
      let plan = displayed.plansByAction[actionID],
      let routine = freshRoutines.first(where: { $0.id == plan.id }),
      [.keepPlan, .reduceSets, .increaseRIR, .swapTrainingDay].contains(selected.action)
    else { throw TrainingAdviceAdoptionError.recordsChanged }
    let workout: Workout
    do {
      workout = try RecommendationWorkoutFactory.make(
        routine: routine, displayed: displayed, actionID: actionID,
        parameters: parameters, startedAt: startedAt
      ) { try self.evaluate(routines: freshRoutines, at: startedAt) }
    } catch AnalysisFailure.staleSnapshot {
      throw TrainingAdviceAdoptionError.recordsChanged
    }
    modelContext.insert(workout)
    do {
      try modelContext.save()
    } catch {
      modelContext.rollback()
      throw AnalysisFailure.storageFailed
    }
    evaluation = nil
    displayedPlans = [:]
    activeWorkout = workout
    return workout
  }

  private func currentRoutines() throws -> [Routine] {
    try modelContext.fetch(FetchDescriptor<Routine>(sortBy: [SortDescriptor(\Routine.name)]))
  }

  private func currentInProgressWorkout() throws -> Workout? {
    try modelContext.fetch(FetchDescriptor<Workout>()).first { $0.status == .inProgress }
  }

  private func selectedPlans(in routines: [Routine]) -> [UUID: RecommendationPlan] {
    let selectedIDs = alternativeRoutineIDs.union(selectedRoutineID.map { [$0] } ?? [])
    return Dictionary(uniqueKeysWithValues: routines.filter { selectedIDs.contains($0.id) }
      .map { ($0.id, RecommendationPlan.snapshot($0)) })
  }

  private func evaluate(routines: [Routine], at asOf: Date) throws
    -> TrainingRecommendationEvaluation
  {
    guard let recovery else { throw AnalysisFailure.unavailable }
    let zone = timeZone()
    let window = AnalysisWindow(
      start: asOf.addingTimeInterval(-Double(RecoveryParameters.inputDays) * 86_400),
      end: asOf)
    let health =
      try healthData?.localSnapshot(window: window)
      ?? .disconnected(window: window, asOf: asOf)
    let input = try repository.analysisInput(
      asOf: asOf, window: window, timeZone: zone, health: health)
    let trend = try TrendCalculator().calculate(input)
    let recovered = try recovery.calculate(input)
    return try provider(routines: routines, recovery: recovery).evaluate(
      input: input, trend: trend, recovery: recovered)
  }

  private func provider(routines: [Routine], recovery: RecoveryService)
    -> TrainingRecommendationProvider
  {
    let byID = Dictionary(uniqueKeysWithValues: routines.map { ($0.id, $0) })
    let selected = selectedRoutineID.flatMap { byID[$0] }.map(RecommendationPlan.snapshot)
    let alternatives = alternativeRoutineIDs.sorted { $0.uuidString < $1.uuidString }
      .filter { $0 != selectedRoutineID }.compactMap { byID[$0] }.map(RecommendationPlan.snapshot)
    let reviewedEntries: [(String, [MuscleID])] = recovery.mapping.entries.compactMap { entry in
      guard entry.status == .mapped else { return nil }
      return (entry.exerciseID, entry.weights.keys.sorted { $0.rawValue < $1.rawValue })
    }
    let reviewed = Dictionary(uniqueKeysWithValues: reviewedEntries)
    return TrainingRecommendationProvider(
      selectedPlan: selected, alternativePlans: alternatives,
      availableWeekdays: availableWeekdays, exerciseMuscles: reviewed)
  }
}

/// Immutable selection adapter for a single fresh report preparation.
struct TrainingRecommendationProvider: RecommendationProviding {
  let selectedPlan: RecommendationPlan?
  let alternativePlans: [RecommendationPlan]
  let availableWeekdays: [Int]?
  let exerciseMuscles: [String: [MuscleID]]

  func context(trend: TrendResult) -> TrainingRecommendationContext {
    let nutritionReviewIDs = trend.facts.filter { fact in
      fact.metric == "diet.targetDifferencePercent" && fact.unit == .percent
        && fact.value.map { $0.isFinite && abs($0) > TrendRules().adherenceTolerance * 100 } == true
        && fact.quality.isEmpty
    }.map(\.id)
    return TrainingRecommendationContext(
      selectedPlan: selectedPlan, alternativePlans: alternativePlans,
      availableWeekdays: availableWeekdays,
      exerciseMuscles: exerciseMuscles, nutritionReviewFactIDs: nutritionReviewIDs)
  }

  func evaluate(input: AnalysisInput, trend: TrendResult, recovery: RecoveryResult) throws
    -> TrainingRecommendationEvaluation
  {
    try TrainingRecommendationRules(context: context(trend: trend)).evaluate(
      input: input, trend: trend, recovery: recovery)
  }

  func candidates(input: AnalysisInput, trend: TrendResult, recovery: RecoveryResult) throws
    -> [RecommendationCandidate]
  {
    try evaluate(input: input, trend: trend, recovery: recovery).candidates
  }

  func snapshot(input: AnalysisInput, trend: TrendResult, recovery: RecoveryResult) throws
    -> RecommendationSnapshot
  {
    let evaluated = try evaluate(input: input, trend: trend, recovery: recovery)
    return .init(
      candidates: evaluated.candidates, facts: evaluated.facts,
      contextFingerprint: evaluated.contextFingerprint)
  }
}
