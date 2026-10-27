import Foundation
import SwiftData
import SwiftUI

@main
@MainActor
struct TrainoteApp: App {
  @State private var catalog: ExerciseCatalog
  @State private var firstUseNotice: FirstUseNoticeStore
  @State private var healthFoundation: HealthFoundation?
  @State private var healthAccess: HealthFeatureAccess?
  @State private var recoveryIntegration: HealthRecoveryIntegration?
  @State private var trendIntegration: HealthTrendIntegration?
  @State private var trainingAdvice: TrainingAdviceController?
  @State private var reportIntegration: HealthReportIntegration?
  @Environment(\.scenePhase) private var scenePhase
  private let containerResult: Result<ModelContainer, Error>

  init() {
    _catalog = State(initialValue: ExerciseCatalog())
    #if DEBUG
      let inMemory = ProcessInfo.processInfo.arguments.contains("-ui-testing")
    #else
      let inMemory = false
    #endif
    #if DEBUG
      let noticeTestID = ProcessInfo.processInfo.environment["TRAINOTE_UI_NOTICE_ID"]
        .flatMap(UUID.init(uuidString:)) ?? UUID()
    #else
      let noticeTestID = UUID()
    #endif
    let noticeDirectory = inMemory
      ? FileManager.default.temporaryDirectory.appendingPathComponent("notice-test-\(noticeTestID.uuidString)")
      : URL.applicationSupportDirectory.appendingPathComponent("FirstUseNotice", isDirectory: true)
    let notice = FirstUseNoticeStore(directory: noticeDirectory)
    #if DEBUG
      // Existing UI suites exercise business flows; dedicated first-use tests opt in.
      if inMemory && !ProcessInfo.processInfo.arguments.contains("-ui-testing-first-use") {
        try? notice.accept()
      }
    #endif
    _firstUseNotice = State(initialValue: notice)
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
      let container = try PersistenceController.makeContainer(inMemory: inMemory)
      #if DEBUG
        if inMemory && StorePreviewData.enabled { try StorePreviewData.seed(container) }
        if inMemory && ProcessInfo.processInfo.arguments.contains("-ui-testing-legacy-goal") {
          // An upgraded 1.0 goal has no revision history until the user adopts or edits it.
          container.mainContext.insert(
            NutritionGoal(
              calories: 2000, carbohydrates: 250, protein: 150, fat: 65,
              updatedAt: Date.now.addingTimeInterval(-30 * 86_400)))
          try container.mainContext.save()
        }
      #endif
      return container
    }
    if case .success(let container) = containerResult {
      let directory =
        inMemory
        ? FileManager.default.temporaryDirectory.appendingPathComponent(
          "health-test-\(UUID().uuidString)")
        : LocalHealthStorage.directory
      let foundation = HealthFoundation(container: container, localDirectory: directory)
      _healthFoundation = State(initialValue: foundation)
      let defaults =
        inMemory
        ? UserDefaults(suiteName: "recovery-test-\(UUID().uuidString)") ?? .standard : .standard
      let recovery = HealthRecoveryIntegration(
        repository: foundation.repository, healthData: foundation.healthData,
        calibration: RecoveryCalibrationControl(defaults: defaults))
      let trend = HealthTrendIntegration(
        repository: foundation.repository, health: foundation.healthData, defaults: defaults)
      let advice = TrainingAdviceController(
        repository: foundation.repository, healthData: foundation.healthData,
        recovery: recovery.service, modelContext: container.mainContext)
      let reports = HealthReportIntegration(
        foundation: foundation, trend: trend.calculator, recovery: recovery.service,
        advice: advice, directory: directory.appendingPathComponent("AIReports", isDirectory: true))
      foundation.healthData?.setProcessingAllowed(notice.accepted)
      reports.setProcessingAllowed(notice.accepted)
      reports.setOnDeviceAIEnabled(notice.localAIEnabled)
      _recoveryIntegration = State(initialValue: recovery)
      _trendIntegration = State(initialValue: trend)
      _trainingAdvice = State(initialValue: advice)
      _reportIntegration = State(initialValue: reports)
      _healthAccess = State(
        initialValue: HealthFeatureAccess(foundation: foundation, reports: reports))
    } else {
      _healthFoundation = State(initialValue: nil)
      _healthAccess = State(initialValue: nil)
      _recoveryIntegration = State(initialValue: nil)
      _trendIntegration = State(initialValue: nil)
      _trainingAdvice = State(initialValue: nil)
      _reportIntegration = State(initialValue: nil)
    }
  }

  var body: some Scene {
    WindowGroup {
      Group {
        switch containerResult {
        case .success(let container):
          if let healthFoundation, let healthAccess, let recoveryIntegration, let trendIntegration,
            let trainingAdvice, let reportIntegration
          {
            Group {
              if firstUseNotice.accepted {
                AppShell(
                  analysisDestinations: .verifiedModules(
                    trend: trendIntegration, recovery: recoveryIntegration, advice: trainingAdvice),
                  recoveryIntegration: recoveryIntegration, trainingAdvice: trainingAdvice,
                  reportIntegration: reportIntegration,
                  processingAllowed: { firstUseNotice.accepted }
                )
              } else {
                FirstUseNoticeView()
              }
            }
            .environment(catalog)
            .environment(firstUseNotice)
            .environment(healthFoundation)
            .environment(healthAccess)
            .modelContainer(container)
            .task { await catalog.load() }
            .task(id: firstUseNotice.accepted) {
              updateProcessingGate(foundation: healthFoundation, reports: reportIntegration)
              // Previously requested withdrawal/deletion may finish while business UI is gated.
              await healthAccess.resumePendingRevocation()
              guard firstUseNotice.accepted, !Task.isCancelled else { return }
              await resume(foundation: healthFoundation, recovery: recoveryIntegration,
                           trend: trendIntegration, advice: trainingAdvice, reports: reportIntegration)
            }
            .onChange(of: firstUseNotice.localAIEnabled) { _, enabled in
              reportIntegration.setOnDeviceAIEnabled(enabled)
            }
            .onChange(of: firstUseNotice.accepted) { _, _ in
              updateProcessingGate(foundation: healthFoundation, reports: reportIntegration)
            }
            .onChange(of: scenePhase) { _, phase in
              if phase == .active {
                LanguageSettings.shared.refreshSystem()
                updateProcessingGate(foundation: healthFoundation, reports: reportIntegration)
                Task {
                  await healthAccess.resumePendingRevocation()
                  guard firstUseNotice.accepted else { return }
                  await resume(foundation: healthFoundation, recovery: recoveryIntegration,
                               trend: trendIntegration, advice: trainingAdvice, reports: reportIntegration)
                }
              } else {
                reportIntegration.cancelPendingRequests()
              }
            }
          }
        case .failure(let error):
          PersistenceErrorView(message: error.localizedDescription)
        }
      }
      .environment(\.locale, L10n.locale)
      #if DEBUG
        .modifier(StorePreviewLayout())
      #endif
    }
  }

  private func updateProcessingGate(foundation: HealthFoundation, reports: HealthReportIntegration) {
    foundation.healthData?.setProcessingAllowed(firstUseNotice.accepted)
    reports.setProcessingAllowed(firstUseNotice.accepted)
    reports.setOnDeviceAIEnabled(firstUseNotice.localAIEnabled)
  }

  private func resume(foundation: HealthFoundation, recovery: HealthRecoveryIntegration,
                      trend: HealthTrendIntegration, advice: TrainingAdviceController,
                      reports: HealthReportIntegration) async {
    guard firstUseNotice.accepted else { return }
    await foundation.resume()
    guard firstUseNotice.accepted, !Task.isCancelled else { return }
    recovery.reloadToday()
    trend.refreshAfterHealthSync()
    advice.refresh()
    await reports.refreshLocalAfterHealthSync()
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
      Label(L10n.text("storage.openFailed"), systemImage: "externaldrive.badge.exclamationmark")
    } description: {
      Text(message)
    } actions: {
      Text(L10n.text("storage.restart"))
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
    .padding()
  }
}
