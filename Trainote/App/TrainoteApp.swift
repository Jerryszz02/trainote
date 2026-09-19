import Foundation
import SwiftData
import SwiftUI

@main
@MainActor
struct TrainoteApp: App {
  @State private var catalog: ExerciseCatalog
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
  }

  var body: some Scene {
    WindowGroup {
      switch containerResult {
      case .success(let container):
        AppShell()
          .environment(catalog)
          .modelContainer(container)
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

    // 1.1 adds only optional/defaulted attributes; SwiftData performs a lightweight migration.
    // The legacy on-disk fixture is opened by PersistenceUpgradeTests before each release.
    let schema = Schema(modelTypes, version: Schema.Version(1, 1, 0))
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
