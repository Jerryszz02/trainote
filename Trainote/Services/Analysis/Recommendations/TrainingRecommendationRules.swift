import CryptoKit
import Foundation

/// Local plan selection for F. The caller supplies an explicitly selected template;
/// a recently edited or used template is not evidence of a scheduled long-term plan.
struct RecommendationPlan: Codable, Equatable, Sendable {
  var id: UUID
  var revision: String
  var exerciseIDs: [String]
  /// Only reviewed resistance modes with valid defaults can create a workout snapshot.
  var isSupported: Bool = true
}

struct TrainingRecommendationContext: Codable, Equatable, Sendable {
  var selectedPlan: RecommendationPlan?
  var alternativePlans: [RecommendationPlan] = []
  /// Calendar weekday 1...7, provided by the user. nil is unknown, [] is no training day.
  var availableWeekdays: [Int]? = nil
  /// Adapt C's reviewed mapping. A missing/empty entry never means zero muscle load.
  var exerciseMuscles: [String: [MuscleID]] = [:]
  /// B decides adherence against historical targets. F does not duplicate that calculation.
  var nutritionReviewFactIDs: [String] = []

  var fingerprint: String {
    var canonical = self
    canonical.alternativePlans.sort { $0.id.uuidString < $1.id.uuidString }
    canonical.availableWeekdays = availableWeekdays.map { Array(Set($0)).sorted() }
    canonical.exerciseMuscles = exerciseMuscles.mapValues {
      Array(Set($0)).sorted { $0.rawValue < $1.rawValue }
    }
    canonical.nutritionReviewFactIDs.sort()
    return RecommendationIdentity.digest(canonical)
  }
}

struct TrainingRecommendationEvaluation: Equatable, Sendable {
  var candidates: [RecommendationCandidate]
  var facts: [MetricFact]
  var plansByAction: [String: RecommendationPlan]
  /// The rule that actually selected each action, kept separate from supporting facts.
  var primaryReasonsByAction: [String: TrainingAdviceReason]
  var contextFingerprint: String
  var localDay: String
  var blockedMuscles: [MuscleID]
  /// Semantic answers in today's effective check-in; excludes read/edit timestamps.
  var feedbackIdentity: String
}

enum TrainingAdviceReason: Equatable, Sendable {
  case unavailableToday
  case noWeeklyTrainingDays
  case tiredCheckIn
  case systemicLimited
  case systemicLow
  case restrictedMuscles([MuscleID])
  case unverifiedMappingWithRestriction
  case significantSoreness
  case recentWorkingSets(Int)
  case reducedReadiness
  case insufficientCoverage
  case noSelectedPlan
  case ready
  case nutritionDifference
}

enum TrainingRecommendationPolicy {
  // Engineering starting points, not validated physiological thresholds.
  static let version = "training-candidates-p1"
  static let recentTrainingHours: Double = 24
  static let retainedSetPercent = 50.0...75.0
  static let suggestedRIR = 2.0...4.0
}

struct TrainingRecommendationRules: RecommendationProviding {
  let context: TrainingRecommendationContext

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

  func evaluate(input: AnalysisInput, trend: TrendResult, recovery: RecoveryResult) throws
    -> TrainingRecommendationEvaluation
  {
    guard input.inputFingerprint == trend.inputFingerprint,
      input.inputFingerprint == recovery.inputFingerprint,
      let timeZone = TimeZone(identifier: input.calendarTimeZone),
      context.availableWeekdays?.allSatisfy({ (1...7).contains($0) }) != false
    else { throw AnalysisFailure.invalidInput }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    let dayStart = calendar.startOfDay(for: input.asOf)
    let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!
    let window = AnalysisWindow(start: dayStart, end: dayEnd)
    let source = DataSource(
      kind: .calculation, identifier: "trainote.recommendations",
      version: TrainingRecommendationPolicy.version)
    var facts = [MetricFact]()
    func addFact(
      _ key: String, _ value: Double?, unit: MetricUnit = .count,
      dependencies: [SourceDependency] = [], quality: [DataQualityFlag] = []
    ) -> String {
      let id = "recommendation.\(key)"
      facts.append(
        .init(
          id: id, metric: id, value: value, unit: unit, window: window,
          sources: [source], dependencies: dependencies,
          quality: value == nil ? [.missing] : quality))
      return id
    }
    let planFact = addFact(
      "selectedPlan", context.selectedPlan == nil ? nil : 1,
      dependencies: context.selectedPlan.map { [.init(kind: .manualRecord, id: $0.id.uuidString)] }
        ?? [])
    let goalFact = addFact(
      "goal.\(input.profile?.goalDirection?.rawValue ?? "unknown")",
      input.profile?.goalDirection == nil ? nil : 1,
      dependencies: input.profile.map { [.init(kind: .manualRecord, id: $0.id.uuidString)] } ?? [])
    let frequencyFact = addFact(
      "trainingDaysPerWeek", input.profile?.trainingDaysPerWeek.map(Double.init),
      dependencies: input.profile.map { [.init(kind: .manualRecord, id: $0.id.uuidString)] } ?? [])
    let todayAvailable = context.availableWeekdays.map {
      $0.contains(calendar.component(.weekday, from: input.asOf))
    }
    let scheduleFact = addFact("availableToday", todayAvailable.map { $0 ? 1 : 0 })
    let availableFacts = input.health.facts + trend.facts + recovery.facts
    let availableFactIDs = Set(availableFacts.map(\.id))
    guard context.nutritionReviewFactIDs.allSatisfy({ availableFactIDs.contains($0) }) else {
      throw AnalysisFailure.invalidInput
    }
    let hasUnallocatedRecords = recovery.facts.contains {
      $0.metric == "recovery.unallocatedRecords"
        && (($0.value ?? 1) > 0 || $0.quality.contains(.partial))
    }
    let checkIn = input.checkIns.filter {
      $0.timeZoneIdentifier == input.calendarTimeZone && $0.updatedAt <= input.asOf
        && AnalysisFingerprint.localDate($0.updatedAt, timeZone: timeZone)
          == AnalysisFingerprint.localDate(input.asOf, timeZone: timeZone)
        && $0.localDate == AnalysisFingerprint.localDate(input.asOf, timeZone: timeZone)
    }.sorted {
      $0.updatedAt == $1.updatedAt
        ? $0.id.uuidString < $1.id.uuidString : $0.updatedAt > $1.updatedAt
    }.first
    let feelingFact = addFact(
      "feeling.tired", checkIn?.feeling.map { $0 == .tired ? 1 : 0 },
      dependencies: checkIn.map { [.init(kind: .manualRecord, id: $0.id.uuidString)] } ?? [])
    let recentFeedback = checkIn?.muscleFeedback.filter { $0.recordedAt <= input.asOf } ?? []
    struct FeedbackContent: Encodable {
      var muscle: MuscleID
      var soreness: SorenessLevel?
      var pain: Bool?
      var movementLimitation: Bool?
    }
    struct FeedbackIdentity: Encodable {
      var timeZone: String
      var feeling: OverallFeeling?
      var sleepFeeling: SleepFeeling?
      var muscles: [FeedbackContent]
    }
    let feedbackIdentity = RecommendationIdentity.digest(
      FeedbackIdentity(
        timeZone: input.calendarTimeZone, feeling: checkIn?.feeling,
        sleepFeeling: checkIn?.sleepFeeling,
        muscles: recentFeedback.map {
          FeedbackContent(
            muscle: $0.muscleID, soreness: $0.soreness,
            pain: $0.hasPain, movementLimitation: $0.hasMovementLimitation)
        }.sorted { lhs, rhs in
          let left = [
            lhs.muscle.rawValue, lhs.soreness?.rawValue ?? "missing",
            lhs.pain.map { $0 ? "true" : "false" } ?? "missing",
            lhs.movementLimitation.map { $0 ? "true" : "false" } ?? "missing",
          ]
          let right = [
            rhs.muscle.rawValue, rhs.soreness?.rawValue ?? "missing",
            rhs.pain.map { $0 ? "true" : "false" } ?? "missing",
            rhs.movementLimitation.map { $0 ? "true" : "false" } ?? "missing",
          ]
          return left.lexicographicallyPrecedes(right)
        }))
    let blocked = Set(
      recovery.muscles.filter { $0.hasPain || $0.hasMovementLimitation }.map(\.muscleID)
    )
    .union(
      recentFeedback.filter { $0.hasPain == true || $0.hasMovementLimitation == true }.map(
        \.muscleID))
    let hasPainObservation =
      !blocked.isEmpty
      || recentFeedback.contains { $0.hasPain != nil || $0.hasMovementLimitation != nil }
    let painFact = addFact(
      "painOrLimitation", hasPainObservation ? Double(blocked.count) : nil,
      dependencies: recentFeedback.filter { $0.hasPain != nil || $0.hasMovementLimitation != nil }
        .map { .init(kind: .manualRecord, id: $0.id.uuidString) }
        + recovery.muscles.filter { $0.hasPain || $0.hasMovementLimitation }.flatMap {
          muscleDependencies($0)
        })
    let systemicFact = addFact(
      "systemic.\(recovery.systemicState.rawValue)",
      recovery.systemicState == .unknown ? nil : 1,
      dependencies: recovery.systemicFactIDs.map { .init(kind: .metricFact, id: $0) })
    var candidates = [RecommendationCandidate]()
    var plans = [String: RecommendationPlan]()
    var primaryReasons = [String: TrainingAdviceReason]()
    let commonFacts = [
      planFact, goalFact, frequencyFact, scheduleFact, feelingFact, painFact, systemicFact,
    ]
    let seed = [
      input.inputFingerprint, context.fingerprint, String(dayStart.timeIntervalSince1970),
      TrainingRecommendationPolicy.version, trend.calculationVersion, recovery.calculationVersion,
    ].joined(separator: "|")
    func append(
      _ action: RecommendationAction, plan: RecommendationPlan? = nil,
      muscles: [MuscleID] = [], reasons: [String] = [], parameters: [AllowedParameter] = [],
      exclusions: [String] = [], primaryReason: TrainingAdviceReason
    ) {
      let actionID =
        "\(TrainingRecommendationPolicy.version).\(action.rawValue)."
        + RecommendationIdentity.digest(
          seed + "|" + action.rawValue + "|" + (plan?.id.uuidString ?? "none"))
      let reasonIDs = Array(Set(commonFacts + reasons)).sorted()
      candidates.append(
        .init(
          actionID: actionID, action: action,
          muscleIDs: Array(Set(muscles)).sorted { $0.rawValue < $1.rawValue },
          reasonFactIDs: reasonIDs,
          allowedParameters: parameters, exclusionCodes: exclusions.sorted(),
          dependencies: reasonIDs.map { .init(kind: .metricFact, id: $0) }))
      if let plan { plans[actionID] = plan }
      primaryReasons[actionID] = primaryReason
    }
    func restOptions(reasons: [String] = [], primaryReason: TrainingAdviceReason) {
      append(
        .rest, reasons: reasons, exclusions: ["no_training_snapshot"],
        primaryReason: primaryReason)
      if blocked.isEmpty && recovery.systemicState != .limited {
        append(
          .lightActivity, reasons: reasons, exclusions: ["no_prescribed_intensity", "stop_if_pain"],
          primaryReason: primaryReason)
      }
    }
    if todayAvailable == false || input.profile?.trainingDaysPerWeek == 0
      || recovery.systemicState == .limited || recovery.systemicState == .low
      || checkIn?.feeling == .tired
    {
      let reason: TrainingAdviceReason
      if todayAvailable == false { reason = .unavailableToday }
      else if input.profile?.trainingDaysPerWeek == 0 { reason = .noWeeklyTrainingDays }
      else if checkIn?.feeling == .tired { reason = .tiredCheckIn }
      else if recovery.systemicState == .limited { reason = .systemicLimited }
      else { reason = .systemicLow }
      restOptions(primaryReason: reason)
    } else if let plan = context.selectedPlan, !plan.exerciseIDs.isEmpty {
      let muscles = mappedMuscles(plan)
      let isMapped = isFullyMapped(plan)
      let overlap = Set(muscles).intersection(blocked)
      let selectedRecovery = recovery.muscles.filter { muscles.contains($0.muscleID) }
      let readinessFacts = selectedRecovery.map { item in
        addFact(
          "readiness.\(item.muscleID.rawValue)", item.state == .unknown ? nil : item.score,
          unit: .score, dependencies: muscleDependencies(item))
      }
      if !overlap.isEmpty || (!isMapped && !blocked.isEmpty) {
        // Never keep/reduce a painful plan just because its score is high.
        for alternative in context.alternativePlans.sorted(by: {
          $0.id.uuidString < $1.id.uuidString
        })
        where alternative.id != plan.id && isFullyMapped(alternative) {
          let alternativeMuscles = mappedMuscles(alternative)
          let states = recovery.muscles.filter { alternativeMuscles.contains($0.muscleID) }
          if !hasUnallocatedRecords, Set(alternativeMuscles).isDisjoint(with: blocked),
            states.count == alternativeMuscles.count,
            states.allSatisfy({
              $0.state == .ready && $0.score?.isFinite == true && !$0.hasPain
                && !$0.hasMovementLimitation
            })
          {
            let alternativeFacts = states.map { item in
              addFact(
                "alternative.\(alternative.id.uuidString).\(item.muscleID.rawValue)", item.score,
                unit: .score, dependencies: muscleDependencies(item))
            }
            append(
              .swapTrainingDay, plan: alternative, muscles: alternativeMuscles,
              reasons: readinessFacts + alternativeFacts,
              exclusions: ["exclude_painful_muscles", "requires_explicit_template_choice"],
              primaryReason: overlap.isEmpty
                ? .unverifiedMappingWithRestriction
                : .restrictedMuscles(overlap.sorted { $0.rawValue < $1.rawValue }))
          }
        }
        restOptions(
          reasons: readinessFacts,
          primaryReason: overlap.isEmpty
            ? .unverifiedMappingWithRestriction
            : .restrictedMuscles(overlap.sorted { $0.rawValue < $1.rawValue }))
      } else if !isMapped || hasUnallocatedRecords || selectedRecovery.count != muscles.count
        || selectedRecovery.contains(where: {
          $0.state == .unknown || $0.score == nil || $0.score?.isFinite == false
        })
      {
        append(
          .choosePlan, plan: plan, muscles: muscles, reasons: readinessFacts,
          exclusions: ["readiness_unknown", "review_exercise_coverage", "no_automatic_workout"],
          primaryReason: .insufficientCoverage)
      } else {
        let recent = completedRecentWorkouts(input, involving: Set(muscles))
        let setCount = recent.flatMap(\.exercises).filter {
          !(Set(context.exerciseMuscles[$0.sourceExerciseID] ?? []).intersection(muscles)).isEmpty
        }.filter { ["strength", "repetitions"].contains($0.trackingMode) }
          .flatMap(\.sets).filter { $0.isCompleted && $0.role != .warmup }.count
        let recentFact = addFact(
          "recentWorkingSets", recent.isEmpty ? nil : Double(setCount),
          dependencies: recent.map { .init(kind: .manualRecord, id: $0.id.uuidString) },
          quality: recent.flatMap(\.exercises).flatMap(\.sets).contains { $0.role == .unknown }
            ? [.unknownSetRole] : [])
        let soreness = recentFeedback.contains {
          muscles.contains($0.muscleID) && $0.soreness == .significant
        }
        let sorenessFact = addFact(
          "significantSoreness",
          recentFeedback.contains { muscles.contains($0.muscleID) && $0.soreness != nil }
            ? (soreness ? 1 : 0) : nil,
          dependencies: recentFeedback.filter {
            muscles.contains($0.muscleID) && $0.soreness != nil
          }
          .map { .init(kind: .manualRecord, id: $0.id.uuidString) })
        let needsReduction =
          soreness || setCount > 0
          || selectedRecovery.contains {
            $0.state == .low || $0.state == .moderate || $0.state == .limited
          }
        if needsReduction {
          let reductionReason: TrainingAdviceReason = soreness ? .significantSoreness
            : setCount > 0 ? .recentWorkingSets(setCount) : .reducedReadiness
          append(
            .reduceSets, plan: plan, muscles: muscles,
            reasons: readinessFacts + [recentFact, sorenessFact],
            parameters: [
              .init(
                name: "retainedSetPercent",
                minimum: TrainingRecommendationPolicy.retainedSetPercent.lowerBound,
                maximum: TrainingRecommendationPolicy.retainedSetPercent.upperBound, unit: .percent)
            ],
            exclusions: ["no_load_increase", "exclude_painful_muscles"],
            primaryReason: reductionReason)
          append(
            .increaseRIR, plan: plan, muscles: muscles,
            reasons: readinessFacts + [recentFact, sorenessFact],
            parameters: [
              .init(
                name: "minimumRIR", minimum: TrainingRecommendationPolicy.suggestedRIR.lowerBound,
                maximum: TrainingRecommendationPolicy.suggestedRIR.upperBound, unit: .count)
            ],
            exclusions: ["do_not_record_target_as_measured_rir", "exclude_painful_muscles"],
            primaryReason: reductionReason)
        } else {
          append(
            .keepPlan, plan: plan, muscles: muscles,
            reasons: readinessFacts + [recentFact, sorenessFact],
            exclusions: ["no_load_increase", "exclude_painful_muscles"], primaryReason: .ready)
        }
      }
    } else {
      append(
        .choosePlan, exclusions: ["no_existing_plan", "requires_explicit_template_choice"],
        primaryReason: .noSelectedPlan)
    }
    if !context.nutritionReviewFactIDs.isEmpty {
      append(
        .reviewNutrition, reasons: context.nutritionReviewFactIDs,
        exclusions: ["no_automatic_goal_change", "not_a_muscle_score_penalty"],
        primaryReason: .nutritionDifference)
    }
    return .init(
      candidates: candidates, facts: facts, plansByAction: plans,
      primaryReasonsByAction: primaryReasons,
      contextFingerprint: context.fingerprint,
      localDay: AnalysisFingerprint.localDate(input.asOf, timeZone: timeZone),
      blockedMuscles: blocked.sorted { $0.rawValue < $1.rawValue },
      feedbackIdentity: feedbackIdentity)
  }

  private func mappedMuscles(_ plan: RecommendationPlan) -> [MuscleID] {
    Array(Set(plan.exerciseIDs.flatMap { context.exerciseMuscles[$0] ?? [] })).sorted {
      $0.rawValue < $1.rawValue
    }
  }
  private func isFullyMapped(_ plan: RecommendationPlan) -> Bool {
    plan.isSupported && !plan.exerciseIDs.isEmpty
      && plan.exerciseIDs.allSatisfy { context.exerciseMuscles[$0]?.isEmpty == false }
  }
  private func muscleDependencies(_ muscle: MuscleRecovery) -> [SourceDependency] {
    muscle.influences.flatMap {
      $0.dependencies + $0.factIDs.map { .init(kind: .metricFact, id: $0) }
    }
  }
  private func completedRecentWorkouts(_ input: AnalysisInput, involving muscles: Set<MuscleID>)
    -> [AnalysisWorkout]
  {
    input.workouts.filter { workout in
      let end = workout.endedAt ?? workout.startedAt
      guard workout.isCompleted, end <= input.asOf, end >= workout.startedAt,
        input.asOf.timeIntervalSince(end) < TrainingRecommendationPolicy.recentTrainingHours * 3600
      else { return false }
      let completed = workout.exercises.flatMap { exercise in
        exercise.sets.filter { $0.isCompleted }.map { (exercise, $0) }
      }
      guard !completed.isEmpty,
        completed.allSatisfy({ exercise, set in
          ["strength", "repetitions"].contains(exercise.trackingMode)
            && set.weightKilograms.isFinite && set.weightKilograms >= 0 && set.repetitions > 0
            && set.rir.map({ (0...5).contains($0) }) != false
        })
      else { return false }
      return completed.contains { exercise, set in
        set.role != .warmup
          && !muscles.isDisjoint(with: context.exerciseMuscles[exercise.sourceExerciseID] ?? [])
      }
    }
  }
}

enum RecommendationIdentity {
  static func digest<T: Encodable>(_ value: T) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    // All callers pass closed value types with finite fields.
    guard let bytes = try? encoder.encode(value) else { return "invalid" }
    return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
  }
}
