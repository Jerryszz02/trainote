import Foundation

struct PersonalRecord: Identifiable {
  enum Metric: String { case weight, volume }
  let workoutID: UUID
  let exerciseID: String
  let exerciseName: String
  let metric: Metric
  let value: Double
  let previousValue: Double
  var id: String { workoutID.uuidString + exerciseID + metric.rawValue }
  var title: String { metric == .weight ? "重量 PR" : "单次容量 PR" }
  var unit: String { metric == .weight ? "kg" : "kg·次" }
}

@MainActor
enum WorkoutInsights {
  static func previousExercise(
    for exercise: WorkoutExercise, before workout: Workout, history: [Workout]
  ) -> WorkoutExercise? {
    history.filter {
      $0.id != workout.id && $0.status == .completed && $0.startedAt < workout.startedAt
    }
    .sorted { $0.startedAt > $1.startedAt }
    .lazy.compactMap { previous in
      previous.sortedExercises.first { candidate in
        candidate.sourceExerciseID == exercise.sourceExerciseID
          && candidate.trackingMode == exercise.trackingMode
          && (candidate.trackingMode == .cardio
            ? candidate.cardioEntries.contains(where: { $0.isValid })
            : candidate.strengthSets.contains(where: {
              $0.isCompleted && $0.isValid(for: candidate.trackingMode)
            }))
      }
    }.first
  }

  static func completedSets(in workout: Workout) -> Int {
    workout.exercises.reduce(0) { sum, exercise in
      sum
        + exercise.strengthSets.filter { $0.isCompleted && $0.isValid(for: exercise.trackingMode) }
        .count
    }
  }

  static func volume(in workout: Workout) -> Double {
    weightedResults(in: workout).values.reduce(0) { $0 + $1.volume }
  }

  static func personalRecords(for workout: Workout, history: [Workout]) -> [PersonalRecord] {
    guard workout.status == .completed else { return [] }
    let previous = history.filter {
      $0.id != workout.id && $0.status == .completed && $0.startedAt < workout.startedAt
    }
    return weightedResults(in: workout).sorted { $0.key < $1.key }.flatMap {
      id, result -> [PersonalRecord] in
      let earlier = previous.compactMap { weightedResults(in: $0)[id] }
      guard !earlier.isEmpty else { return [] }  // A first session establishes a baseline.
      let maxWeight = earlier.map(\.weight).max() ?? 0
      let maxVolume = earlier.map(\.volume).max() ?? 0
      var records: [PersonalRecord] = []
      if result.weight > maxWeight + 0.000_001 {
        records.append(
          PersonalRecord(
            workoutID: workout.id, exerciseID: id, exerciseName: result.name, metric: .weight,
            value: result.weight, previousValue: maxWeight))
      }
      if result.volume > maxVolume + 0.000_001 {
        records.append(
          PersonalRecord(
            workoutID: workout.id, exerciseID: id, exerciseName: result.name, metric: .volume,
            value: result.volume, previousValue: maxVolume))
      }
      return records
    }
  }

  private struct WeightedResult {
    let name: String
    var weight: Double
    var volume: Double
  }

  private static func weightedResults(in workout: Workout) -> [String: WeightedResult] {
    var results: [String: WeightedResult] = [:]
    for exercise in workout.exercises where exercise.trackingMode == .strength {
      let sets = exercise.strengthSets.filter {
        $0.isCompleted && $0.isValid(for: .strength) && $0.weightKilograms > 0
      }
      guard !sets.isEmpty else { continue }
      var result =
        results[exercise.sourceExerciseID]
        ?? WeightedResult(name: exercise.nameZhSnapshot, weight: 0, volume: 0)
      result.weight = max(result.weight, sets.map(\.weightKilograms).max() ?? 0)
      result.volume += sets.reduce(0) { $0 + $1.weightKilograms * Double($1.repetitions) }
      results[exercise.sourceExerciseID] = result
    }
    return results
  }
}

struct WeeklySummary {
  let interval: DateInterval
  let trainingCount: Int
  let completedSetCount: Int
  let volume: Double
  let nutritionDays: Int
  let nutritionValueDays: Int
  let unknownFoodCount: Int
  let averageCalories: Double?
  let averageProtein: Double?
  let personalRecords: [PersonalRecord]

  @MainActor
  init(date: Date, workouts: [Workout], food: [FoodLogEntry], calendar: Calendar = .current) {
    var calendar = calendar
    calendar.firstWeekday = 2
    calendar.minimumDaysInFirstWeek = 4
    let interval = calendar.dateInterval(of: .weekOfYear, for: date)!
    self.interval = interval
    let sessions = workouts.filter {
      $0.status == .completed && $0.startedAt >= interval.start && $0.startedAt < interval.end
    }
    trainingCount = sessions.count
    completedSetCount = sessions.reduce(0) { $0 + WorkoutInsights.completedSets(in: $1) }
    volume = sessions.reduce(0) { $0 + WorkoutInsights.volume(in: $1) }
    let entries = food.filter { $0.loggedAt >= interval.start && $0.loggedAt < interval.end }
    let days = Set(entries.map { calendar.startOfDay(for: $0.loggedAt) })
    nutritionDays = days.count
    let knownEntries = entries.filter {
      $0.calories > 0 || $0.carbohydrates > 0 || $0.protein > 0 || $0.fat > 0
    }
    let knownDays = Set(knownEntries.map { calendar.startOfDay(for: $0.loggedAt) })
    nutritionValueDays = knownDays.count
    unknownFoodCount = entries.count - knownEntries.count
    averageCalories =
      knownDays.isEmpty
      ? nil : knownEntries.reduce(0) { $0 + $1.calories } / Double(knownDays.count)
    averageProtein =
      knownDays.isEmpty ? nil : knownEntries.reduce(0) { $0 + $1.protein } / Double(knownDays.count)
    personalRecords = sessions.flatMap {
      WorkoutInsights.personalRecords(for: $0, history: workouts)
    }
  }
}
