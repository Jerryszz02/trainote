import Foundation
import SwiftData

@Model
final class Workout {
  @Attribute(.unique) var id: UUID
  var title: String
  var startedAt: Date
  var endedAt: Date?
  var statusRaw: String
  var notes: String
  var routineNameSnapshot: String?
  var restEndsAt: Date?

  @Relationship(deleteRule: .cascade, inverse: \WorkoutExercise.workout)
  var exercises: [WorkoutExercise]

  init(
    id: UUID = UUID(),
    title: String,
    startedAt: Date = .now,
    endedAt: Date? = nil,
    status: WorkoutStatus = .inProgress,
    notes: String = "",
    routineNameSnapshot: String? = nil,
    exercises: [WorkoutExercise] = []
  ) {
    self.id = id
    self.title = title
    self.startedAt = startedAt
    self.endedAt = endedAt
    self.statusRaw = status.rawValue
    self.notes = notes
    self.routineNameSnapshot = routineNameSnapshot
    self.exercises = exercises
  }

  var status: WorkoutStatus {
    get { WorkoutStatus(rawValue: statusRaw) ?? .inProgress }
    set { statusRaw = newValue.rawValue }
  }

  var sortedExercises: [WorkoutExercise] {
    exercises.sorted { lhs, rhs in
      lhs.orderIndex == rhs.orderIndex
        ? lhs.id.uuidString < rhs.id.uuidString : lhs.orderIndex < rhs.orderIndex
    }
  }

  /// A valid completed item is required; every completed item must be valid.
  var hasValidResult: Bool { validationMessage == nil }

  var validationMessage: String? {
    guard !title.trimmed.isEmpty else { return "请输入训练名称。" }
    var hasResult = false
    for exercise in exercises {
      if exercise.trackingMode.usesSets {
        for set in exercise.strengthSets where set.isCompleted {
          guard set.isValid(for: exercise.trackingMode) else {
            return "请检查「\(exercise.nameZhSnapshot)」第 \(set.orderIndex + 1) 组的数值。"
          }
          hasResult = true
        }
      } else {
        for cardio in exercise.cardioEntries {
          if cardio.durationSeconds == 0 && cardio.distanceKilometers == 0 && cardio.calories == 0 {
            continue
          }
          guard cardio.isValid else { return "请检查「\(exercise.nameZhSnapshot)」的时长、距离和热量。" }
          hasResult = true
        }
      }
    }
    return hasResult ? nil : "请至少完成一组，或填写一条有效有氧记录。"
  }

}

@Model
final class WorkoutExercise {
  @Attribute(.unique) var id: UUID
  var sourceExerciseID: String
  var nameEnSnapshot: String
  var nameZhSnapshot: String
  var orderIndex: Int
  var trackingModeRaw: String
  var notes: String
  var workout: Workout?

  @Relationship(deleteRule: .cascade, inverse: \StrengthSet.exercise)
  var strengthSets: [StrengthSet]

  @Relationship(deleteRule: .cascade, inverse: \CardioEntry.exercise)
  var cardioEntries: [CardioEntry]

  init(
    id: UUID = UUID(),
    sourceExerciseID: String,
    nameEnSnapshot: String,
    nameZhSnapshot: String,
    orderIndex: Int,
    trackingMode: TrackingMode,
    notes: String = "",
    strengthSets: [StrengthSet] = [],
    cardioEntries: [CardioEntry] = []
  ) {
    self.id = id
    self.sourceExerciseID = sourceExerciseID
    self.nameEnSnapshot = nameEnSnapshot
    self.nameZhSnapshot = nameZhSnapshot
    self.orderIndex = orderIndex
    self.trackingModeRaw = trackingMode.rawValue
    self.notes = notes
    self.strengthSets = strengthSets
    self.cardioEntries = cardioEntries
  }

  var trackingMode: TrackingMode {
    get { TrackingMode(rawValue: trackingModeRaw) ?? .strength }
    set { trackingModeRaw = newValue.rawValue }
  }

  var sortedStrengthSets: [StrengthSet] {
    strengthSets.sorted { lhs, rhs in
      lhs.orderIndex == rhs.orderIndex
        ? lhs.id.uuidString < rhs.id.uuidString : lhs.orderIndex < rhs.orderIndex
    }
  }
}

@Model
final class StrengthSet {
  @Attribute(.unique) var id: UUID
  var orderIndex: Int
  var weightKilograms: Double
  var repetitions: Int
  var durationSeconds: Int = 0
  var isCompleted: Bool
  var exercise: WorkoutExercise?

  init(
    id: UUID = UUID(),
    orderIndex: Int,
    weightKilograms: Double = 0,
    repetitions: Int = 8,
    durationSeconds: Int = 0,
    isCompleted: Bool = false
  ) {
    self.id = id
    self.orderIndex = orderIndex
    self.weightKilograms = weightKilograms
    self.repetitions = repetitions
    self.durationSeconds = durationSeconds
    self.isCompleted = isCompleted
  }

  func isValid(for mode: TrackingMode) -> Bool {
    switch mode {
    case .strength:
      return weightKilograms.isFinite && (0...10_000).contains(weightKilograms)
        && (1...100_000).contains(repetitions)
    case .repetitions: return (1...100_000).contains(repetitions)
    case .duration: return (1...604_800).contains(durationSeconds)
    case .cardio: return false
    }
  }
}

@Model
final class CardioEntry {
  @Attribute(.unique) var id: UUID
  var durationSeconds: Int
  var distanceKilometers: Double
  var calories: Double
  var exercise: WorkoutExercise?

  init(
    id: UUID = UUID(),
    durationSeconds: Int = 0,
    distanceKilometers: Double = 0,
    calories: Double = 0
  ) {
    self.id = id
    self.durationSeconds = durationSeconds
    self.distanceKilometers = distanceKilometers
    self.calories = calories
  }

  var isValid: Bool {
    (1...604_800).contains(durationSeconds)
      && distanceKilometers.isFinite && (0...10_000).contains(distanceKilometers)
      && calories.isFinite && (0...100_000).contains(calories)
  }
}

@Model
final class Routine {
  @Attribute(.unique) var id: UUID
  var name: String
  var notes: String
  var createdAt: Date
  var updatedAt: Date

  @Relationship(deleteRule: .cascade, inverse: \RoutineExercise.routine)
  var exercises: [RoutineExercise]

  init(
    id: UUID = UUID(),
    name: String,
    notes: String = "",
    createdAt: Date = .now,
    updatedAt: Date = .now,
    exercises: [RoutineExercise] = []
  ) {
    self.id = id
    self.name = name
    self.notes = notes
    self.createdAt = createdAt
    self.updatedAt = updatedAt
    self.exercises = exercises
  }

  var sortedExercises: [RoutineExercise] {
    exercises.sorted { lhs, rhs in
      lhs.orderIndex == rhs.orderIndex
        ? lhs.id.uuidString < rhs.id.uuidString : lhs.orderIndex < rhs.orderIndex
    }
  }
}

@Model
final class RoutineExercise {
  @Attribute(.unique) var id: UUID
  var sourceExerciseID: String
  var nameEnSnapshot: String
  var nameZhSnapshot: String
  var orderIndex: Int
  var trackingModeRaw: String
  var defaultSetCount: Int
  var defaultRepetitions: Int
  var defaultWeightKilograms: Double
  var defaultDurationSeconds: Int
  var defaultDistanceKilometers: Double
  var routine: Routine?

  init(
    id: UUID = UUID(),
    sourceExerciseID: String,
    nameEnSnapshot: String,
    nameZhSnapshot: String,
    orderIndex: Int,
    trackingMode: TrackingMode,
    defaultSetCount: Int = 3,
    defaultRepetitions: Int = 8,
    defaultWeightKilograms: Double = 0,
    defaultDurationSeconds: Int = 0,
    defaultDistanceKilometers: Double = 0
  ) {
    self.id = id
    self.sourceExerciseID = sourceExerciseID
    self.nameEnSnapshot = nameEnSnapshot
    self.nameZhSnapshot = nameZhSnapshot
    self.orderIndex = orderIndex
    self.trackingModeRaw = trackingMode.rawValue
    self.defaultSetCount = defaultSetCount
    self.defaultRepetitions = defaultRepetitions
    self.defaultWeightKilograms = defaultWeightKilograms
    self.defaultDurationSeconds = defaultDurationSeconds
    self.defaultDistanceKilometers = defaultDistanceKilometers
  }

  var trackingMode: TrackingMode {
    get { TrackingMode(rawValue: trackingModeRaw) ?? .strength }
    set { trackingModeRaw = newValue.rawValue }
  }

  var hasValidDefaults: Bool {
    switch trackingMode {
    case .strength:
      (1...100).contains(defaultSetCount)
        && (1...100_000).contains(defaultRepetitions)
        && defaultWeightKilograms.isFinite && (0...10_000).contains(defaultWeightKilograms)
    case .repetitions:
      defaultSetCount > 0 && defaultSetCount <= 100 && (1...100_000).contains(defaultRepetitions)
    case .duration:
      defaultSetCount > 0 && defaultSetCount <= 100
        && (0...604_800).contains(defaultDurationSeconds)
    case .cardio:
      (0...604_800).contains(defaultDurationSeconds)
        && defaultDistanceKilometers.isFinite && (0...10_000).contains(defaultDistanceKilometers)
    }
  }
}
