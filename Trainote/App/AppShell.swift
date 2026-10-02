import SwiftUI

enum AppTab: Hashable {
  case today
  case training
  case nutrition
  case trends
  case recovery
}

struct AppShell: View {
  @State private var selectedTab: AppTab = .today
  @State private var startWorkoutRequest = 0
  @State private var logFoodRequest = 0
  @State private var todayPath: [LibrarySection] = []
  @State private var showHealthOnboarding = false
  @AppStorage("health.onboarding.v1.completed") private var healthOnboardingCompleted = false
  var analysisDestinations: HealthAnalysisDestinations = .pending
  var recoveryIntegration: HealthRecoveryIntegration? = nil

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
          recoveryIntegration: recoveryIntegration
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
        analysisDestinations.recovery()
      }
      .tabItem { Label("恢复", systemImage: "figure.stand") }
      .tag(AppTab.recovery)
    }
    .tint(.accentColor)
    #if DEBUG
      .preferredColorScheme(ProcessInfo.processInfo.arguments.contains("-ui-testing-dark") ? .dark : nil)
    #endif
    .task {
      #if DEBUG
        if ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("-ui-testing") }) {
          showHealthOnboarding = ProcessInfo.processInfo.arguments.contains("-health-onboarding")
          return
        }
      #endif
      showHealthOnboarding = !healthOnboardingCompleted
    }
    .sheet(isPresented: $showHealthOnboarding) {
      HealthOnboardingView {
        healthOnboardingCompleted = true
        showHealthOnboarding = false
      }
    }
  }
}
