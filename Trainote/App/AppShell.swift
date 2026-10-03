import SwiftUI

enum AppTab: Hashable {
  case today
  case training
  case nutrition
  case trends
  case recovery
}

private enum AppSheet: Identifiable {
  case healthOnboarding
  case settings
  case checkIn(CheckInValue)

  var id: String {
    switch self {
    case .healthOnboarding: return "healthOnboarding"
    case .settings: return "settings"
    case .checkIn(let draft): return "checkIn.\(draft.id)"
    }
  }
}

struct AppShell: View {
  @State private var selectedTab: AppTab = .today
  @State private var startWorkoutRequest = 0
  @State private var logFoodRequest = 0
  @State private var todayPath: [LibrarySection] = []
  @State private var presentedSheet: AppSheet?
  @State private var sheetDismissal: (() -> Void)?
  @AppStorage("health.onboarding.v1.completed") private var healthOnboardingCompleted = false
  var analysisDestinations: HealthAnalysisDestinations = .pending
  var recoveryIntegration: HealthRecoveryIntegration? = nil
  var trainingAdvice: TrainingAdviceController? = nil
  var reportIntegration: HealthReportIntegration? = nil

  var body: some View {
    TabView(selection: $selectedTab) {
      NavigationStack(path: $todayPath) {
        TodayView(
          onStartWorkout: {
            selectedTab = .training
            startWorkoutRequest += 1
          },
          onLogFood: {
            selectedTab = .nutrition
            logFoodRequest += 1
          },
          onOpenTemplates: {
            todayPath.append(.routines)
          },
          onOpenRecovery: { selectedTab = .recovery },
          onOpenSettings: {
            sheetDismissal = {
              recoveryIntegration?.reloadToday()
              trainingAdvice?.refresh()
            }
            presentedSheet = .settings
          },
          onOpenCheckIn: { draft, onDismiss in
            sheetDismissal = onDismiss
            presentedSheet = .checkIn(draft)
          },
          recoveryIntegration: recoveryIntegration, trainingAdvice: trainingAdvice,
          reportIntegration: reportIntegration
        )
        .navigationDestination(for: LibrarySection.self) { LibraryView(initialSection: $0) }
      }
      .tabItem { Label("今日", systemImage: "chart.bar.fill") }
      .tag(AppTab.today)

      NavigationStack {
        TrainingView(startRequest: startWorkoutRequest)
      }
      .tabItem { Label("训练", systemImage: "figure.strengthtraining.traditional") }
      .tag(AppTab.training)

      NavigationStack {
        NutritionView(addRequest: logFoodRequest)
      }
      .tabItem { Label("饮食", systemImage: "fork.knife") }
      .tag(AppTab.nutrition)

      NavigationStack {
        analysisDestinations.trends()
      }
      .tabItem { Label("趋势", systemImage: "chart.xyaxis.line") }
      .tag(AppTab.trends)

      NavigationStack {
        analysisDestinations.recovery(
          { _ in
            selectedTab = .training
            startWorkoutRequest += 1
          }, { selectedTab = .trends })
      }
      .tabItem { Label("恢复", systemImage: "figure.stand") }
      .tag(AppTab.recovery)
    }
    .tint(.accentColor)
    #if DEBUG
      .preferredColorScheme(
        ProcessInfo.processInfo.arguments.contains("-ui-testing-dark") ? .dark : nil)
    #endif
    .task {
      #if DEBUG
        if ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("-ui-testing") }) {
          presentedSheet =
            ProcessInfo.processInfo.arguments.contains("-health-onboarding")
            ? .healthOnboarding : nil
          return
        }
      #endif
      if !healthOnboardingCompleted { presentedSheet = .healthOnboarding }
    }
    // Keep modal content outside the tab navigation stacks' presentation environment.
    .sheet(item: $presentedSheet, onDismiss: finishSheet) { sheet in
      switch sheet {
      case .healthOnboarding:
        HealthOnboardingView {
          healthOnboardingCompleted = true
          presentedSheet = nil
        }
      case .settings:
        SettingsView()
      case .checkIn(let draft):
        if let recoveryIntegration {
          RecoveryCheckInView(
            repository: recoveryIntegration.repository,
            suggestedMuscles: recoveryIntegration.suggestedMuscles(), draft: draft)
        }
      }
    }
  }

  private func finishSheet() {
    let completion = sheetDismissal
    sheetDismissal = nil
    completion?()
  }
}
