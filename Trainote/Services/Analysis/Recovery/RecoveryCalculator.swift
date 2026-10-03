import Foundation

struct RecoveryCalculator: RecoveryCalculating {
  let mapping: ExerciseMuscleMap
  var calibrationResetAt: Date? = nil

  func calculate(_ input: AnalysisInput) throws -> RecoveryResult {
    guard input.schemaVersion == AnalysisContract.schemaVersion,
      input.asOf.timeIntervalSince1970.isFinite,
      let timeZone = TimeZone(identifier: input.calendarTimeZone),
      Set(input.workouts.map(\.id)).count == input.workouts.count,
      Set(mapping.entries.map(\.exerciseID)).count == mapping.entries.count,
      Set(input.workouts.flatMap(\.exercises).map(\.id)).count
        == input.workouts.flatMap(\.exercises).count,
      Set(input.workouts.flatMap(\.exercises).flatMap(\.sets).map(\.id)).count
        == input.workouts.flatMap(\.exercises).flatMap(\.sets).count
    else { throw AnalysisFailure.invalidInput }
    let extraction = extract(input)
    let recentStart = input.asOf.addingTimeInterval(
      -Double(RecoveryParameters.historyDays) * 86_400)
    let window = AnalysisWindow(start: recentStart, end: input.asOf)
    let recent = extraction.sessions.filter { $0.endedAt >= recentStart }
    let gaps = extraction.gaps.filter { $0.endedAt >= recentStart }
    let feedback = RecoveryFeedback(input: input)
    let calibrations = RecoveryCalibration.evaluate(
      input: input, sessions: extraction.sessions, mapping: mapping, resetAt: calibrationResetAt,
      unallocated: extraction.gaps)
    var facts = feedback.facts
    let gapDependencies = RecoveryEvidence.dependencies(gaps.flatMap(\.dependencies))
    let gapQuality =
      gaps.isEmpty
      ? [] : RecoveryEvidence.quality([.partial, .unknownExercise] + gaps.flatMap(\.quality))
    let gapSources = RecoveryEvidence.sortedSources([.manual] + gaps.flatMap(\.sources))
    facts.append(
      .init(
        id: "recovery.unallocatedRecords", metric: "recovery.unallocatedRecords",
        value: Double(Set(gaps.map(\.workoutID)).count), unit: .count, window: window,
        sources: gapSources, dependencies: gapDependencies, quality: gapQuality))
    var muscles: [MuscleRecovery] = []
    for muscle in MuscleID.allCases {
      let sessions = recent.filter { $0.load[muscle] != nil }
      let dependencies = RecoveryEvidence.dependencies(
        sessions.flatMap(\.dependencies) + gapDependencies)
      let calibration = calibrations[muscle]
      let tau = calibration?.tauHours ?? RecoveryParameters.tauHours
      let residual = sessions.reduce(0.0) {
        $0 + ($1.load[muscle] ?? 0) * exp(-input.asOf.timeIntervalSince($1.endedAt) / 3600 / tau)
      }
      let score =
        sessions.isEmpty || !gaps.isEmpty
        ? nil
        : RecoveryParameters.score(residualLoad: residual)
      var quality = RecoveryEvidence.quality(
        [.estimated] + sessions.flatMap(\.quality) + gapQuality
          + (sessions.isEmpty ? [.insufficientHistory] : []))
      if score == nil { quality = RecoveryEvidence.quality(quality + [.missing]) }
      let prefix = "recovery.\(muscle.rawValue)"
      let tauFact = MetricFact(
        id: "\(prefix).tau", metric: "recovery.tau", value: tau * 3600, unit: .seconds,
        window: .init(start: calibration?.windowStart ?? recentStart, end: input.asOf),
        sources: RecoveryEvidence.sortedSources(
          (calibration?.sources ?? [.manual])
            + [.init(kind: .calculation, identifier: RecoveryParameters.version)]),
        dependencies: calibration?.dependencies ?? [], quality: [.estimated])
      facts.append(tauFact)
      facts.append(
        .init(
          id: "\(prefix).load", metric: "recovery.residualLoad",
          value: sessions.isEmpty ? nil : residual,
          unit: .count, window: window, sources: gapSources,
          dependencies: RecoveryEvidence.dependencies(
            dependencies + [.init(kind: .metricFact, id: tauFact.id)]),
          quality: quality))
      facts.append(
        .init(
          id: "\(prefix).score", metric: "recovery.readiness", value: score, unit: .score,
          window: window, sources: gapSources,
          dependencies: [.init(kind: .metricFact, id: "\(prefix).load")], quality: quality))
      if let last = sessions.last {
        facts.append(
          .init(
            id: "\(prefix).lastLoad", metric: "recovery.lastSessionLoad", value: last.load[muscle],
            unit: .count, window: .init(start: last.endedAt, end: last.endedAt),
            sources: [.manual], dependencies: last.dependencies, quality: last.quality))
      }
      var influences: [RecoveryInfluence] = [
        .init(
          code: score == nil ? "insufficientRecords" : "recordedLoad",
          factIDs: ["\(prefix).score", "\(prefix).load"])
      ]
      if quality.contains(.unknownRIR) {
        influences.append(.init(code: "unknownRIRPrior", factIDs: ["\(prefix).load"]))
      }
      if quality.contains(.unknownSetRole) {
        influences.append(.init(code: "historicalRolePrior", factIDs: ["\(prefix).load"]))
      }
      if !gaps.isEmpty {
        influences.append(
          .init(code: "unallocatedExercise", factIDs: ["recovery.unallocatedRecords"]))
      }
      if calibration?.isAdopted == true {
        influences.append(
          .init(
            code: "calibratedCandidate", factIDs: [tauFact.id],
            dependencies: calibration?.dependencies ?? []))
      }
      let local = feedback.muscles[muscle]
      var state = RecoveryParameters.state(score: score)
      if local?.soreness == .significant {
        influences.append(.init(code: "significantSoreness", factIDs: local?.sorenessFactIDs ?? []))
        if state == .ready { state = .moderate }
      } else if local?.soreness == .mild {
        influences.append(.init(code: "mildSoreness", factIDs: local?.sorenessFactIDs ?? []))
      }
      let pain = local?.hasPain == true
      let limited = local?.hasMovementLimitation == true
      if pain || limited {
        state = .limited
        influences.append(.init(code: "excludeTraining", factIDs: local?.constraintFactIDs ?? []))
      }
      muscles.append(
        .init(
          muscleID: muscle, score: score, state: state, hasPain: pain,
          hasMovementLimitation: limited,
          lastTrainedAt: sessions.last?.endedAt, influences: influences,
          coverage: [
            .init(
              field: "recovery.\(muscle.rawValue)",
              observedDays: Set(
                sessions.map { AnalysisFingerprint.localDate($0.endedAt, timeZone: timeZone) }
              ).count,
              expectedDays: RecoveryParameters.historyDays, quality: quality)
          ]))
    }
    let systemic = RecoverySystemic.calculate(input, feedback: feedback)
    facts += systemic.facts.filter { fact in !facts.contains(where: { $0.id == fact.id }) }
    return .init(
      inputFingerprint: input.inputFingerprint, asOf: input.asOf, muscles: muscles,
      systemicState: systemic.state, systemicFactIDs: systemic.facts.map(\.id),
      facts: facts.sorted { $0.id < $1.id },
      calculationVersion: "\(RecoveryParameters.version)+\(mapping.version)"
        + (calibrationResetAt.map { "+reset-\($0.timeIntervalSince1970)" } ?? ""))
  }

  struct Extraction {
    var sessions: [RecoveryLoadSession] = []
    var gaps: [RecoveryLoadSession] = []
  }
  func extract(_ input: AnalysisInput) -> Extraction {
    var result = Extraction()
    let byID = mapping.byID
    for workout in input.workouts.sorted(by: {
      let a = $0.endedAt ?? $0.startedAt
      let b = $1.endedAt ?? $1.startedAt
      return a == b ? $0.id.uuidString < $1.id.uuidString : a < b
    }) where workout.isCompleted {
      let end = workout.endedAt ?? workout.startedAt
      guard end.timeIntervalSince1970.isFinite, workout.startedAt.timeIntervalSince1970.isFinite,
        end >= workout.startedAt, end <= input.asOf
      else { continue }
      var session = RecoveryLoadSession(
        workoutID: workout.id, endedAt: end, load: [:],
        quality: workout.endedAt == nil ? [.estimated] : [],
        dependencies: [.init(kind: .manualRecord, id: workout.id.uuidString)])
      // A completed workout containing invalid completed sets is not a valid completed training.
      let invalid = workout.exercises.contains { exercise in
        exercise.sets.contains { $0.isCompleted && !Self.valid($0, mode: exercise.trackingMode) }
          && exercise.trackingMode != TrackingMode.cardio.rawValue
      }
      if invalid {
        result.gaps.append(session)
        continue
      }
      for exercise in workout.exercises.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
        let sets = exercise.sets.filter { $0.isCompleted && $0.role != .warmup }
          .sorted { $0.id.uuidString < $1.id.uuidString }
        guard !sets.isEmpty, exercise.trackingMode != TrackingMode.cardio.rawValue else { continue }
        let entry = byID[exercise.sourceExerciseID]
        let deps =
          [
            .init(kind: SourceDependency.Kind.manualRecord, id: workout.id.uuidString),
            .init(kind: .manualRecord, id: exercise.id.uuidString),
          ]
          + sets.map { SourceDependency(kind: .manualRecord, id: $0.id.uuidString) }
        guard
          [TrackingMode.strength.rawValue, TrackingMode.repetitions.rawValue].contains(
            exercise.trackingMode),
          let entry, entry.status == .mapped
        else {
          // No duration, stretch or unknown movement is silently converted into zero work.
          result.gaps.append(
            .init(
              workoutID: workout.id, endedAt: end, load: [:],
              quality: [.unknownExercise], dependencies: deps))
          continue
        }
        session.dependencies += deps
        for set in sets {
          for (muscle, weight) in entry.weights {
            session.load[muscle, default: 0] += weight * RecoveryParameters.effort(rir: set.rir)
          }
          if set.rir == nil { session.quality.append(.unknownRIR) }
          if set.role == .unknown { session.quality.append(.unknownSetRole) }
        }
      }
      session.dependencies = RecoveryEvidence.dependencies(session.dependencies)
      session.quality = RecoveryEvidence.quality(session.quality)
      if !session.load.isEmpty { result.sessions.append(session) }
    }
    for external in input.health.externalWorkouts.sorted(by: { $0.id.uuidString < $1.id.uuidString }
    ) {
      guard external.activityCode.map(RecoveryParameters.resistanceActivityCodes.contains) == true,
        external.start.timeIntervalSince1970.isFinite, external.end.timeIntervalSince1970.isFinite,
        external.start <= external.end, external.end <= input.asOf
      else { continue }
      // A possible duplicate is not a confirmed match to a fully recorded local workout.
      // Retain the uncertainty; never infer sets from duration or allocate it as zero work.
      result.gaps.append(
        .init(
          workoutID: external.id, endedAt: external.end, load: [:],
          quality: external.possibleDuplicateIDs.isEmpty
            ? [.partial] : [.partial, .sourceConflict],
          dependencies: [
            .init(kind: .healthSample, id: external.id.uuidString, healthType: .workout)
          ],
          sources: [external.source]))
    }
    return result
  }

  static func valid(_ set: AnalysisSet, mode: String) -> Bool {
    guard set.rir.map({ (0...5).contains($0) }) != false else { return false }
    switch mode {
    case TrackingMode.strength.rawValue:
      return set.weightKilograms.isFinite && (0...10_000).contains(set.weightKilograms)
        && (1...100_000).contains(set.repetitions)
    case TrackingMode.repetitions.rawValue: return (1...100_000).contains(set.repetitions)
    case TrackingMode.duration.rawValue: return (1...604_800).contains(set.durationSeconds)
    default: return false
    }
  }
}

extension RecoveryResult {
  func bodyMapPresentation(selected: MuscleID? = nil) -> BodyMapPresentation {
    .init(
      muscles: muscles.map {
        .init(
          muscleID: $0.muscleID, score: $0.score, state: $0.state,
          isSelected: $0.muscleID == selected, hasPain: $0.hasPain,
          hasMovementLimitation: $0.hasMovementLimitation)
      }, asOf: asOf, calculationVersion: calculationVersion)
  }
}
