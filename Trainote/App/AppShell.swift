import SwiftUI

enum AppTab: Hashable {
  case today
  case training
  case nutrition
  case library
}

struct AppShell: View {
  @State private var selectedTab: AppTab = .today
  @State private var startWorkoutRequest = 0
  @State private var logFoodRequest = 0
  @State private var templatesRequest = 0

  var body: some View {
    TabView(selection: $selectedTab) {
      NavigationStack {
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
            selectedTab = .library
            templatesRequest += 1
          }
        )
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
        LibraryView(templatesRequest: templatesRequest)
      }
      .tabItem { Label("资料库", systemImage: "books.vertical.fill") }
      .tag(AppTab.library)
    }
    .tint(.accentColor)
  }
}
