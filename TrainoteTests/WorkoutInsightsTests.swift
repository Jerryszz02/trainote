import Foundation
import XCTest

@testable import Trainote

@MainActor
final class WorkoutInsightsTests: XCTestCase {
  func testPersonalRecordsNeedEarlierBaselineAndIgnoreTiesAndUnfinishedSets() {
    let first = workout(weight: 60, reps: 8, at: Date(timeIntervalSince1970: 100))
    XCTAssertTrue(WorkoutInsights.personalRecords(for: first, history: [first]).isEmpty)
    let second = workout(weight: 60, reps: 8, at: Date(timeIntervalSince1970: 200))
    XCTAssertTrue(WorkoutInsights.personalRecords(for: second, history: [first, second]).isEmpty)
    second.exercises[0].strengthSets.append(
      StrengthSet(orderIndex: 1, weightKilograms: 200, repetitions: 8))
    XCTAssertTrue(WorkoutInsights.personalRecords(for: second, history: [first, second]).isEmpty)
    second.exercises[0].strengthSets[0].weightKilograms = 65
    let records = WorkoutInsights.personalRecords(for: second, history: [first, second])
    XCTAssertEqual(records.count, 2)
    XCTAssertEqual(records.first(where: { $0.metric == .weight })?.previousValue, 60)
    XCTAssertEqual(records.first(where: { $0.metric == .volume })?.value, 520)
    second.status = .inProgress
    XCTAssertTrue(WorkoutInsights.personalRecords(for: second, history: [first, second]).isEmpty)
  }

  func testRecordsAggregateRepeatedExerciseWithoutMixingModesOrFutureSessions() {
    let old = workout(weight: 60, reps: 10, at: Date(timeIntervalSince1970: 100))
    let current = workout(weight: 60, reps: 6, at: Date(timeIntervalSince1970: 200))
    let extra = WorkoutExercise(
      sourceExerciseID: "0025", nameEnSnapshot: "bench press", nameZhSnapshot: "卧推", orderIndex: 1,
      trackingMode: .strength)
    extra.strengthSets = [
      StrengthSet(orderIndex: 0, weightKilograms: 60, repetitions: 6, isCompleted: true)
    ]
    current.exercises.append(extra)
    let future = workout(weight: 100, reps: 10, at: Date(timeIntervalSince1970: 300))
    let records = WorkoutInsights.personalRecords(for: current, history: [old, current, future])
    XCTAssertEqual(records.map(\.metric), [.volume])
    XCTAssertEqual(records.first?.value, 720)
    extra.trackingMode = .repetitions
    XCTAssertTrue(WorkoutInsights.personalRecords(for: current, history: [old, current]).isEmpty)
  }

  func testCompletionRejectsAnInvalidCompletedSetBesideAValidOne() {
    let session = workout(weight: 60, reps: 8, at: .now)
    session.exercises[0].strengthSets.append(
      StrengthSet(orderIndex: 1, weightKilograms: -1, repetitions: 8, isCompleted: true))
    XCTAssertFalse(session.hasValidResult)
    session.exercises[0].strengthSets[1].isCompleted = false
    XCTAssertTrue(session.hasValidResult)
    session.exercises[0].trackingMode = .duration
    XCTAssertFalse(session.hasValidResult)
    session.exercises[0].strengthSets[0].durationSeconds = 30
    XCTAssertTrue(session.hasValidResult)
  }

  func testWeeklySummaryUsesMondayBoundariesAndDoesNotCountMissingNutritionAsZero() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
    let monday = calendar.date(from: DateComponents(year: 2026, month: 9, day: 14))!
    let entry = FoodLogEntry(
      loggedAt: monday, mealType: .lunch, name: "午餐", servingDescription: "份", quantity: 1,
      calories: 600, carbohydrates: 50, protein: 30, fat: 20)
    let unknown = FoodLogEntry(
      loggedAt: monday.addingTimeInterval(86400), mealType: .lunch, name: "未填",
      servingDescription: "份", quantity: 1, calories: 0, carbohydrates: 0, protein: 0, fat: 0)
    let before = workout(weight: 60, reps: 8, at: monday.addingTimeInterval(-1))
    let inside = workout(weight: 65, reps: 8, at: monday)
    let after = workout(weight: 70, reps: 8, at: monday.addingTimeInterval(7 * 86400))
    let summary = WeeklySummary(
      date: monday, workouts: [before, inside, after], food: [entry, unknown], calendar: calendar)
    XCTAssertEqual(summary.trainingCount, 1)
    XCTAssertEqual(summary.completedSetCount, 1)
    XCTAssertEqual(summary.nutritionDays, 2)
    XCTAssertEqual(summary.nutritionValueDays, 1)
    XCTAssertEqual(summary.unknownFoodCount, 1)
    XCTAssertEqual(summary.averageCalories, 600)
    XCTAssertEqual(summary.averageProtein, 30)
  }

  func testEntireCatalogHasExplicitDefaultsAndMeaningfulExamples() throws {
    let catalog = ExerciseCatalog()
    XCTAssertNil(catalog.errorMessage)
    XCTAssertEqual(catalog.items.count, 1324)
    XCTAssertTrue(catalog.items.allSatisfy { $0.recommendedTrackingMode != nil })
    let modes = Dictionary(
      uniqueKeysWithValues: catalog.items.map { ($0.id, $0.defaultTrackingMode) })
    XCTAssertEqual(modes["0025"], .strength)
    XCTAssertEqual(modes["0630"], .repetitions)
    XCTAssertEqual(modes["1374"], .repetitions)
    XCTAssertEqual(modes["1708"], .duration)
    XCTAssertEqual(modes["2135"], .duration)
    XCTAssertEqual(modes["0464"], .repetitions)
    XCTAssertEqual(modes["0685"], .cardio)
  }

  private func workout(weight: Double, reps: Int, at: Date) -> Workout {
    let workout = Workout(
      title: "力量训练", startedAt: at, endedAt: at.addingTimeInterval(100), status: .completed)
    let exercise = WorkoutExercise(
      sourceExerciseID: "0025", nameEnSnapshot: "bench press", nameZhSnapshot: "卧推", orderIndex: 0,
      trackingMode: .strength)
    let set = StrengthSet(
      orderIndex: 0, weightKilograms: weight, repetitions: reps, isCompleted: true)
    set.exercise = exercise
    exercise.strengthSets = [set]
    exercise.workout = workout
    workout.exercises = [exercise]
    return workout
  }
}
