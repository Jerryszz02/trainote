import Foundation
import Observation
import SwiftData

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
  var selectedRoutineID: UUID? { didSet { evaluation = nil } }
  var alternativeRoutineIDs: Set<UUID> = [] { didSet { evaluation = nil } }
  /// nil means the user has not supplied a schedule; [] explicitly means no available day.
  var availableWeekdays: [Int]? { didSet { evaluation = nil } }

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
      let ids = Set(routines.map(\.id))
      if selectedRoutineID.map({ !ids.contains($0) }) == true { selectedRoutineID = nil }
      alternativeRoutineIDs.formIntersection(ids)
      errorMessage = nil
    } catch {
      routines = []
      evaluation = nil
      errorMessage = "暂时无法读取训练模板，请重试。"
    }
  }

  func refresh() {
    do {
      routines = try currentRoutines()
      evaluation = try evaluate(routines: routines, at: now())
      errorMessage = nil
    } catch {
      evaluation = nil
      errorMessage = "暂时无法计算建议，请检查本地记录后重试。"
    }
  }

  /// Re-reads repository, HealthKit's local snapshot and templates on the same actor before save.
  @discardableResult
  func adopt(actionID: String, parameters: [String: Double] = [:]) throws -> Workout {
    guard let displayed = evaluation else { throw AnalysisFailure.staleSnapshot }
    let startedAt = now()
    let freshRoutines = try currentRoutines()
    guard try !hasInProgressWorkout(),
      let selected = displayed.candidates.first(where: { $0.actionID == actionID }),
      let plan = displayed.plansByAction[actionID],
      let routine = freshRoutines.first(where: { $0.id == plan.id }),
      [.keepPlan, .reduceSets, .increaseRIR, .swapTrainingDay].contains(selected.action)
    else { throw AnalysisFailure.staleSnapshot }
    let workout = try RecommendationWorkoutFactory.make(
      routine: routine, displayed: displayed, actionID: actionID,
      parameters: parameters, startedAt: startedAt
    ) { try self.evaluate(routines: freshRoutines, at: startedAt) }
    modelContext.insert(workout)
    do {
      try modelContext.save()
    } catch {
      modelContext.rollback()
      throw AnalysisFailure.storageFailed
    }
    evaluation = nil
    return workout
  }

  private func currentRoutines() throws -> [Routine] {
    try modelContext.fetch(FetchDescriptor<Routine>(sortBy: [SortDescriptor(\Routine.name)]))
  }

  private func hasInProgressWorkout() throws -> Bool {
    try modelContext.fetch(FetchDescriptor<Workout>()).contains { $0.status == .inProgress }
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
    let byID = Dictionary(uniqueKeysWithValues: routines.map { ($0.id, $0) })
    let selected = selectedRoutineID.flatMap { byID[$0] }.map(RecommendationPlan.snapshot)
    let alternatives = alternativeRoutineIDs.sorted { $0.uuidString < $1.uuidString }
      .filter { $0 != selectedRoutineID }.compactMap { byID[$0] }.map(RecommendationPlan.snapshot)
    let reviewedEntries: [(String, [MuscleID])] = recovery.mapping.entries.compactMap { entry in
      guard entry.status == .mapped else { return nil }
      return (entry.exerciseID, entry.weights.keys.sorted { $0.rawValue < $1.rawValue })
    }
    let reviewed = Dictionary(uniqueKeysWithValues: reviewedEntries)
    let nutritionReviewIDs = trend.facts.filter { fact in
      fact.metric == "diet.targetDifferencePercent" && fact.unit == .percent
        && fact.value.map { $0.isFinite && abs($0) > TrendRules().adherenceTolerance * 100 } == true
        && fact.quality.isEmpty
    }.map(\.id)
    let context = TrainingRecommendationContext(
      selectedPlan: selected, alternativePlans: alternatives,
      availableWeekdays: availableWeekdays,
      exerciseMuscles: reviewed, nutritionReviewFactIDs: nutritionReviewIDs)
    return try TrainingRecommendationRules(context: context).evaluate(
      input: input, trend: trend, recovery: recovered)
  }
}
