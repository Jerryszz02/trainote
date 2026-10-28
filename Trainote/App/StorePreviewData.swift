#if DEBUG
import Foundation
import SwiftData
import SwiftUI

/// Synthetic store screenshots only. Never touches the installed user's persistent container.
@MainActor
enum StorePreviewData {
  static var enabled: Bool {
    let arguments = ProcessInfo.processInfo.arguments
    return arguments.contains("-ui-testing") && arguments.contains("-store-screenshots")
  }

  static func seed(_ container: ModelContainer, now: Date = .now) throws {
    guard enabled, container.configurations.allSatisfy({ $0.isStoredInMemoryOnly }) else { return }
    let context = container.mainContext
    let calendar = Calendar.current
    let example = L10n.name(zh: "示例", en: "Example")
    let goal = NutritionGoal(calories: 2200, carbohydrates: 260, protein: 140, fat: 65,
                             updatedAt: now.addingTimeInterval(-30 * 86400))
    context.insert(goal)
    let routine = Routine(name: L10n.name(zh: "示例 · 全身力量", en: "Example · Full-body strength"),
      notes: "Synthetic screenshot data", exercises: [
        RoutineExercise(sourceExerciseID: "0025", nameEnSnapshot: "Barbell bench press",
          nameZhSnapshot: "杠铃卧推", orderIndex: 0, trackingMode: .strength,
          defaultSetCount: 3, defaultRepetitions: 8, defaultWeightKilograms: 50),
        RoutineExercise(sourceExerciseID: "0043", nameEnSnapshot: "Barbell full squat",
          nameZhSnapshot: "杠铃深蹲", orderIndex: 1, trackingMode: .strength,
          defaultSetCount: 3, defaultRepetitions: 8, defaultWeightKilograms: 60)
      ])
    context.insert(routine)
    context.insert(BodyProfile(value: .init(id: UUID(), heightCentimeters: 175,
      ageYears: 28, formulaSex: .male, activityLevel: .moderate, goalDirection: .maintain,
      trainingDaysPerWeek: 3, isAdultGeneralFitness: true, updatedAt: now)))
    for offset in 0..<21 {
      let day = calendar.date(byAdding: .day, value: -offset, to: now)!
      let start = calendar.startOfDay(for: day)
      let meals: [(MealType, String, String, Double, Double, Double, Double, Int)] = [
        (.breakfast, "燕麦与酸奶", "Oats and yogurt", 480, 65, 28, 12, 8),
        (.lunch, "鸡肉米饭碗", "Chicken rice bowl", 720, 85, 48, 20, 12),
        (.dinner, "三文鱼与土豆", "Salmon and potatoes", 690, 70, 45, 26, 18)
      ]
      for (type, zh, en, calories, carbs, protein, fat, hour) in meals {
        // Today shows completed breakfast/lunch rather than a fictional future dinner.
        if offset == 0 && type == .dinner { continue }
        let loggedAt = calendar.date(byAdding: .hour, value: hour, to: start)!
        context.insert(FoodLogEntry(loggedAt: min(loggedAt, now), mealType: type,
          name: example + " · " + L10n.name(zh: zh, en: en),
          servingDescription: L10n.name(zh: "1 份", en: "1 serving"), quantity: 1,
          calories: calories + Double(offset % 3) * 20, carbohydrates: carbs, protein: protein, fat: fat))
      }
      context.insert(BodyWeightEntry(value: .init(id: UUID(), measuredAt: min(day, now),
        kilograms: 71.8 - Double(20 - offset) * 0.025, timeZoneIdentifier: TimeZone.current.identifier,
        createdAt: day, updatedAt: day)))
      context.insert(DailyCheckIn(value: .init(id: UUID(),
        localDate: AnalysisFingerprint.localDate(day, timeZone: .current),
        timeZoneIdentifier: TimeZone.current.identifier, feeling: offset == 1 ? .tired : .good,
        sleepFeeling: .normal, updatedAt: day)))
      if offset % 2 == 0 {
        let finished = day.addingTimeInterval(-2700)
        let workout = Workout(title: example + " · " + L10n.name(zh: "力量训练", en: "Strength session"),
          startedAt: finished.addingTimeInterval(-2400), endedAt: finished, status: .completed,
          notes: "Synthetic screenshot data", exercises: [
            exercise(completed: 3, weight: 50 + Double((20 - offset) / 5), example: example),
            exercise(completed: 3, weight: 60, example: example, squat: true)
          ])
        context.insert(workout)
      }
    }
    let active = Workout(title: example + " · " + L10n.name(zh: "全身力量", en: "Full-body strength"),
      startedAt: now.addingTimeInterval(-12 * 60), notes: "Synthetic screenshot data",
      exercises: [exercise(completed: 1, weight: 55, example: example)])
    context.insert(active)
    try context.save()
    // Completeness is a user fact; give synthetic historical days matching their actual log hash.
    let logs = try context.fetch(FetchDescriptor<FoodLogEntry>())
    for offset in 1..<21 {
      let day = calendar.date(byAdding: .day, value: -offset, to: now)!
      let entries = logs.filter { calendar.isDate($0.loggedAt, inSameDayAs: day) }
      context.insert(DietLogCompleteness(value: .init(id: UUID(),
        localDate: AnalysisFingerprint.localDate(day, timeZone: .current),
        timeZoneIdentifier: TimeZone.current.identifier, confirmedAt: now,
        foodLogFingerprint: try AnalysisFingerprint.foodLogs(entries))))
    }
    try context.save()
  }

  private static func exercise(completed: Int, weight: Double, example: String,
                               squat: Bool = false) -> WorkoutExercise {
    WorkoutExercise(sourceExerciseID: squat ? "0043" : "0025",
      nameEnSnapshot: "Example · " + (squat ? "Barbell full squat" : "Barbell bench press"),
      nameZhSnapshot: "示例 · " + (squat ? "杠铃深蹲" : "杠铃卧推"),
      orderIndex: squat ? 1 : 0, trackingMode: .strength,
      strengthSets: (0..<3).map {
        StrengthSet(orderIndex: $0, weightKilograms: weight, repetitions: 8,
                    isCompleted: $0 < completed, rir: 2, setRole: .working)
      })
  }
}

struct StorePreviewLayout: ViewModifier {
  @ViewBuilder
  func body(content: Content) -> some View {
    if StorePreviewData.enabled {
      VStack(spacing: 0) {
        StorePreviewLabel()
        content
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    } else {
      content
    }
  }
}

struct StorePreviewLabel: View {
  var body: some View {
    Text(L10n.name(zh: "示例数据", en: "Sample data"))
      .font(.caption2.weight(.medium))
      .padding(.horizontal, 8).padding(.vertical, 3)
      .frame(maxWidth: .infinity)
      .background(Color(.secondarySystemBackground))
      .allowsHitTesting(false)
      .accessibilityIdentifier("store.sampleData")
  }
}
#endif
