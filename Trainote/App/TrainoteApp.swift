import Foundation
import SwiftData
import SwiftUI

@main
@MainActor
struct TrainoteApp: App {
  @State private var catalog: ExerciseCatalog
  @State private var healthFoundation: HealthFoundation?
  @Environment(\.scenePhase) private var scenePhase
  private let containerResult: Result<ModelContainer, Error>

  init() {
    _catalog = State(initialValue: ExerciseCatalog())
    let inMemory = ProcessInfo.processInfo.arguments.contains("-ui-testing")
    containerResult = Result {
      #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ui-testing-readonly") {
          let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "readonly-\(UUID().uuidString).store")
          try autoreleasepool {
            let initial = try PersistenceController.makeContainer(storeURL: url)
            try initial.mainContext.save()
          }
          return try PersistenceController.makeContainer(storeURL: url, allowsSave: false)
        }
      #endif
      return try PersistenceController.makeContainer(inMemory: inMemory)
    }
    if case .success(let container) = containerResult {
      let directory = inMemory
        ? FileManager.default.temporaryDirectory.appendingPathComponent("health-test-\(UUID().uuidString)")
        : LocalHealthStorage.directory
      _healthFoundation = State(initialValue: HealthFoundation(container: container, localDirectory: directory))
    } else { _healthFoundation = State(initialValue: nil) }
  }

  var body: some Scene {
    WindowGroup {
      switch containerResult {
      case .success(let container):
        if let healthFoundation {
          AppShell()
            .environment(catalog)
            .environment(healthFoundation)
            .modelContainer(container)
            .task { await healthFoundation.resume() }
            .onChange(of: scenePhase) { _, phase in
              if phase == .active { Task { await healthFoundation.resume() } }
            }
        }
      case .failure(let error):
        PersistenceErrorView(message: error.localizedDescription)
      }
    }
  }
}

enum PersistenceController {
  static let modelTypes: [any PersistentModel.Type] = [
    Workout.self,
    WorkoutExercise.self,
    StrengthSet.self,
    CardioEntry.self,
    Routine.self,
    RoutineExercise.self,
    FoodPreset.self,
    MealTemplate.self,
    MealTemplateItem.self,
    FoodLogEntry.self,
    NutritionGoal.self,
    BodyProfile.self,
    BodyWeightEntry.self,
    DailyCheckIn.self,
    MuscleFeedback.self,
    DietLogCompleteness.self,
    NutritionGoalRevision.self,
    AnalysisPreferences.self,
  ]

  static func makeContainer(inMemory: Bool = false, storeURL: URL? = nil, allowsSave: Bool = true)
    throws -> ModelContainer
  {
    if !inMemory {
      try FileManager.default.createDirectory(
        at: URL.applicationSupportDirectory,
        withIntermediateDirectories: true
      )
    }

    // 1.2 adds user facts plus optional/defaulted set fields. Both frozen 1.0 and 1.1
    // disk fixtures must pass lightweight migration; never fall back to an empty store.
    let schema = Schema(modelTypes, version: Schema.Version(1, 2, 0))
    let configuration: ModelConfiguration
    if let storeURL {
      configuration = ModelConfiguration(
        schema: schema, url: storeURL, allowsSave: allowsSave, cloudKitDatabase: .none)
    } else {
      configuration = ModelConfiguration(
        schema: schema, isStoredInMemoryOnly: inMemory, allowsSave: allowsSave,
        cloudKitDatabase: .none)
    }
    return try ModelContainer(for: schema, configurations: [configuration])
  }
}

private struct PersistenceErrorView: View {
  let message: String

  var body: some View {
    ContentUnavailableView {
      Label("无法打开本地数据", systemImage: "externaldrive.badge.exclamationmark")
    } description: {
      Text(message)
    } actions: {
      Text("Trainote 不会用临时数据库替代你的记录。请重新启动 App。")
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
    .padding()
  }
}
