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

  var hasValidResult: Bool {
    exercises.contains { exercise in
      switch exercise.trackingMode {
      case .strength:
        exercise.strengthSets.contains {
          $0.isCompleted && $0.repetitions > 0 && $0.weightKilograms.isValidNonnegativeNumber
        }
      case .cardio:
        exercise.cardioEntries.contains { $0.isValid }
      }
    }
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
    TrackingMode(rawValue: trackingModeRaw) ?? .strength
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
  var isCompleted: Bool
  var exercise: WorkoutExercise?

  init(
    id: UUID = UUID(),
    orderIndex: Int,
    weightKilograms: Double = 0,
    repetitions: Int = 8,
    isCompleted: Bool = false
  ) {
    self.id = id
    self.orderIndex = orderIndex
    self.weightKilograms = weightKilograms
    self.repetitions = repetitions
    self.isCompleted = isCompleted
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
    durationSeconds > 0
      && distanceKilometers.isValidNonnegativeNumber
      && calories.isValidNonnegativeNumber
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
    TrackingMode(rawValue: trackingModeRaw) ?? .strength
  }

  var hasValidDefaults: Bool {
    switch trackingMode {
    case .strength:
      defaultSetCount > 0
        && defaultRepetitions > 0
        && defaultWeightKilograms.isValidNonnegativeNumber
    case .cardio:
      defaultDurationSeconds >= 0
        && defaultDistanceKilometers.isValidNonnegativeNumber
    }
  }
}
