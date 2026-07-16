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
    containerResult = Result { try PersistenceController.makeContainer(inMemory: inMemory) }
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

  static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
    if !inMemory {
      try FileManager.default.createDirectory(
        at: URL.applicationSupportDirectory,
        withIntermediateDirectories: true
      )
    }

    let schema = Schema(modelTypes)
    let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
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
