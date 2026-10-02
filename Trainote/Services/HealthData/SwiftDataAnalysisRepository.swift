import CryptoKit
import Foundation
import SwiftData

@MainActor
final class SwiftDataAnalysisRepository: AnalysisRepository {
  let container: ModelContainer
  init(container: ModelContainer) { self.container = container }

  func manualRecords() throws -> ManualHealthRecords {
    try Self.read(ModelContext(container))
  }
  static func read(_ context: ModelContext) throws -> ManualHealthRecords {
    .init(
      profiles: try context.fetch(FetchDescriptor<BodyProfile>()).map(\.value),
      weights: try context.fetch(FetchDescriptor<BodyWeightEntry>()).map(\.value),
      checkIns: try context.fetch(FetchDescriptor<DailyCheckIn>()).map(\.value),
      dietCompleteness: try context.fetch(FetchDescriptor<DietLogCompleteness>()).map(\.value),
      goalRevisions: try context.fetch(FetchDescriptor<NutritionGoalRevision>()).map(\.value),
      preferences: try context.fetch(FetchDescriptor<AnalysisPreferences>()).first?.value()
        ?? .init())
  }

  func saveProfile(_ value: BodyProfileValue) throws {
    try ManualRecordValidation.validate(value)
    try transaction { context in
      let profiles = try context.fetch(FetchDescriptor<BodyProfile>())
      if value.isActive {
        for profile in profiles where profile.id != value.id { profile.isActive = false }
      }
      if let existing = profiles.first(where: { $0.id == value.id }) {
        existing.apply(value)
      } else {
        context.insert(BodyProfile(value: value))
      }
    }
  }
  func saveWeight(_ value: ManualWeightValue) throws {
    try ManualRecordValidation.validate(value)
    try transaction { context in
      if let existing = try context.fetch(FetchDescriptor<BodyWeightEntry>()).first(where: {
        $0.id == value.id
      }) {
        existing.apply(value)
      } else {
        context.insert(BodyWeightEntry(value: value))
      }
    }
  }
  func deleteWeight(id: UUID) throws {
    try transaction { context in
      for item in try context.fetch(FetchDescriptor<BodyWeightEntry>()) where item.id == id {
        context.delete(item)
      }
    }
  }
  func saveCheckIn(_ value: CheckInValue) throws {
    try ManualRecordValidation.validate(value)
    try transaction { context in
      let all = try context.fetch(FetchDescriptor<DailyCheckIn>())
      guard
        !all.contains(where: {
          $0.id != value.id && $0.localDate == value.localDate
            && $0.timeZoneIdentifier == value.timeZoneIdentifier
        })
      else { throw AnalysisFailure.invalidInput }
      let incomingIDs = Set(value.muscleFeedback.map(\.id))
      let otherIDs = Set(all.filter { $0.id != value.id }.flatMap { $0.muscleFeedback.map(\.id) })
      guard incomingIDs.isDisjoint(with: otherIDs) else { throw AnalysisFailure.invalidInput }
      if let existing = all.first(where: { $0.id == value.id }) {
        existing.localDate = value.localDate
        existing.timeZoneIdentifier = value.timeZoneIdentifier
        existing.feelingRaw = value.feeling?.rawValue
        existing.sleepFeelingRaw = value.sleepFeeling?.rawValue
        existing.updatedAt = value.updatedAt
        let old = existing.muscleFeedback
        for item in old where !incomingIDs.contains(item.id) { context.delete(item) }
        existing.muscleFeedback = value.muscleFeedback.map { feedback in
          let item = old.first { $0.id == feedback.id } ?? MuscleFeedback(value: feedback)
          item.apply(feedback)
          item.checkIn = existing
          return item
        }
      } else {
        let item = DailyCheckIn(value: value)
        item.muscleFeedback.forEach { $0.checkIn = item }
        context.insert(item)
      }
    }
  }
  func confirmDiet(_ value: DietCompletenessValue) throws {
    try ManualRecordValidation.validate(value)
    try transaction { context in
      let all = try context.fetch(FetchDescriptor<DietLogCompleteness>())
      guard
        !all.contains(where: {
          $0.id != value.id && $0.localDate == value.localDate
            && $0.timeZoneIdentifier == value.timeZoneIdentifier
        })
      else { throw AnalysisFailure.invalidInput }
      if let existing = all.first(where: { $0.id == value.id }) {
        existing.apply(value)
      } else {
        context.insert(DietLogCompleteness(value: value))
      }
    }
  }
  func appendGoalRevision(_ value: NutritionGoalRevisionValue) throws {
    try ManualRecordValidation.validate(value)
    try transaction { context in
      let all = try context.fetch(FetchDescriptor<NutritionGoalRevision>())
      if let existing = all.first(where: { $0.id == value.id }) {
        guard existing.value == value else { throw AnalysisFailure.invalidInput }
        return
      }
      guard value.proposalID == nil || !all.contains(where: { $0.proposalID == value.proposalID }),
        value.reversesRevisionID == nil
          || all.contains(where: { $0.id == value.reversesRevisionID })
      else { throw AnalysisFailure.invalidInput }
      context.insert(NutritionGoalRevision(value: value))
    }
  }
  func savePreferences(_ value: AnalysisPreferencesValue) throws {
    try ManualRecordValidation.validate(value)
    try transaction { context in
      if let existing = try context.fetch(FetchDescriptor<AnalysisPreferences>()).first {
        try existing.apply(value)
      } else {
        context.insert(try AnalysisPreferences(value: value))
      }
    }
  }
  private func transaction(_ mutate: (ModelContext) throws -> Void) throws {
    let context = ModelContext(container)
    context.autosaveEnabled = false
    do {
      try mutate(context)
      try context.save()
    } catch {
      context.rollback()
      throw error
    }
  }

  func analysisInput(
    asOf: Date, window: AnalysisWindow, timeZone: TimeZone,
    health: HealthDataSnapshot
  ) throws -> AnalysisInput {
    guard window.start < window.end, health.window == window else {
      throw AnalysisFailure.invalidInput
    }
    let context = ModelContext(container)
    let manual = try Self.read(context)
    let workouts = try context.fetch(FetchDescriptor<Workout>())
      .filter { window.contains($0.startedAt) }.sorted {
        $0.startedAt == $1.startedAt
          ? $0.id.uuidString < $1.id.uuidString : $0.startedAt < $1.startedAt
      }
      .map { workout in
        AnalysisWorkout(
          id: workout.id, startedAt: workout.startedAt, endedAt: workout.endedAt,
          isCompleted: workout.status == .completed, routineName: workout.routineNameSnapshot,
          exercises: workout.sortedExercises.map { exercise in
            .init(
              id: exercise.id, sourceExerciseID: exercise.sourceExerciseID,
              trackingMode: exercise.trackingModeRaw,
              sets: exercise.sortedStrengthSets.map {
                .init(
                  id: $0.id, orderIndex: $0.orderIndex, weightKilograms: $0.weightKilograms,
                  repetitions: $0.repetitions, durationSeconds: $0.durationSeconds,
                  isCompleted: $0.isCompleted, rir: $0.rir, role: $0.setRole)
              }, cardioDurationSeconds: exercise.cardioEntries.reduce(0) { $0 + $1.durationSeconds }
            )
          })
      }
    let foodLogs = try context.fetch(FetchDescriptor<FoodLogEntry>()).filter {
      window.contains($0.loggedAt)
    }
    let grouped = Dictionary(grouping: foodLogs) {
      AnalysisFingerprint.localDate($0.loggedAt, timeZone: timeZone)
    }
    let confirmedDays = manual.dietCompleteness.filter {
      $0.timeZoneIdentifier == timeZone.identifier
        && $0.localDate >= AnalysisFingerprint.localDate(window.start, timeZone: timeZone)
        && $0.localDate <= AnalysisFingerprint.localDate(window.end, timeZone: timeZone)
    }.map(\.localDate)
    let nutrition = try Set(Array(grouped.keys) + confirmedDays).sorted().map {
      day -> DailyNutrition in
      let logs = (grouped[day] ?? []).sorted { $0.id.uuidString < $1.id.uuidString }
      let fingerprint = try AnalysisFingerprint.foodLogs(logs)
      return .init(
        localDate: day, timeZoneIdentifier: timeZone.identifier,
        totals: .init(
          calories: logs.reduce(0) { $0 + $1.calories },
          carbohydrates: logs.reduce(0) { $0 + $1.carbohydrates },
          protein: logs.reduce(0) { $0 + $1.protein }, fat: logs.reduce(0) { $0 + $1.fat }),
        logIDs: logs.map(\.id), logFingerprint: fingerprint,
        isComplete: manual.dietCompleteness.contains {
          $0.localDate == day && $0.timeZoneIdentifier == timeZone.identifier
            && $0.foodLogFingerprint == fingerprint
        })
    }
    let weights = HealthValueMerge.weights(
      manual: manual.weights.filter { window.contains($0.measuredAt) },
      health: health, preferences: manual.preferences)
    let currentGoal = try context.fetch(FetchDescriptor<NutritionGoal>()).sorted {
      $0.updatedAt > $1.updatedAt
    }.first
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    let expectedDays = max(
      1,
      calendar.dateComponents(
        [.day], from: calendar.startOfDay(for: window.start),
        to: calendar.startOfDay(for: window.end)
      ).day ?? 1)
    let observedWeights = Set(
      weights.map { AnalysisFingerprint.localDate($0.measuredAt, timeZone: timeZone) }
    ).count
    var coverage: [DataCoverage] = [
      .init(
        field: "weights", observedDays: observedWeights, expectedDays: expectedDays,
        quality: observedWeights == 0 ? [.missing] : []),
      .init(
        field: "completeDiet", observedDays: nutrition.filter(\.isComplete).count,
        expectedDays: expectedDays,
        quality: nutrition.filter(\.isComplete).count < expectedDays ? [.partial] : []),
      .init(
        field: "workouts",
        observedDays: Set(
          workouts.map { AnalysisFingerprint.localDate($0.startedAt, timeZone: timeZone) }
        ).count,
        expectedDays: expectedDays, quality: workouts.isEmpty ? [.insufficientHistory] : []),
    ]
    for status in health.statuses.sorted(by: { $0.type.rawValue < $1.type.rawValue }) {
      let days = Set(
        health.samples.filter { $0.type == status.type }.map {
          AnalysisFingerprint.localDate($0.start, timeZone: timeZone)
        }
      ).count
      var flags: [DataQualityFlag] = days == 0 ? [.missing] : []
      if status.state == .failed { flags.append(.readFailed) }
      if !health.isFresh { flags.append(.stale) }
      coverage.append(
        .init(
          field: status.type.rawValue, observedDays: days, expectedDays: expectedDays,
          quality: flags))
    }
    var input = AnalysisInput(
      asOf: asOf, calendarTimeZone: timeZone.identifier, inputFingerprint: "",
      profile: manual.profiles.first { $0.isActive }, workouts: workouts, nutrition: nutrition,
      weights: weights,
      health: HealthValueMerge.summary(
        health, timeZone: timeZone,
        preferredSources: manual.preferences.preferredHealthSourceIDs, localWorkouts: workouts),
      checkIns: manual.checkIns.filter {
        $0.localDate
          >= AnalysisFingerprint.localDate(
            window.start, timeZone: TimeZone(identifier: $0.timeZoneIdentifier)!)
          && $0.localDate
            <= AnalysisFingerprint.localDate(
              window.end, timeZone: TimeZone(identifier: $0.timeZoneIdentifier)!)
      }.sorted {
        $0.localDate == $1.localDate
          ? $0.id.uuidString < $1.id.uuidString : $0.localDate < $1.localDate
      },
      goalHistory: manual.goalRevisions.sorted {
        $0.effectiveAt == $1.effectiveAt
          ? $0.id.uuidString < $1.id.uuidString : $0.effectiveAt < $1.effectiveAt
      },
      currentManualTargets: currentGoal.map {
        .init(
          calories: $0.calories, carbohydrates: $0.carbohydrates, protein: $0.protein, fat: $0.fat)
      },
      preferences: manual.preferences, coverage: coverage)
    var fingerprintInput = input
    for index in fingerprintInput.health.statuses.indices {
      fingerprintInput.health.statuses[index].queriedAt = asOf
    }
    input.inputFingerprint = try AnalysisFingerprint.digest(fingerprintInput)
    return input
  }
}

enum AnalysisFingerprint {
  static func digest<T: Encodable>(_ value: T) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(value)
    return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
  static func localDate(_ date: Date, timeZone: TimeZone) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.timeZone = timeZone
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: date)
  }
  static func foodLogs(_ logs: [FoodLogEntry]) throws -> String {
    // Include edits to names/servings as well as totals; no user text leaves this digest.
    struct Revision: Encodable {
      var id: UUID
      var date: Date
      var name: String
      var serving: String
      var mealType: String
      var sourcePresetID: UUID?
      var sourceMealTemplateID: UUID?
      var quantity: Double
      var calories: Double
      var carbohydrates: Double
      var protein: Double
      var fat: Double
    }
    return try digest(
      logs.sorted { $0.id.uuidString < $1.id.uuidString }.map {
        Revision(
          id: $0.id, date: $0.loggedAt, name: $0.name, serving: $0.servingDescription,
          mealType: $0.mealTypeRaw, sourcePresetID: $0.sourcePresetID,
          sourceMealTemplateID: $0.sourceMealTemplateID,
          quantity: $0.quantity, calories: $0.calories, carbohydrates: $0.carbohydrates,
          protein: $0.protein, fat: $0.fat)
      })
  }
}
