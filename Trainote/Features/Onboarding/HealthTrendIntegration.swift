import Foundation
import Observation

/// Entering the module and changing target mode are separate explicit user choices.
@MainActor
@Observable
final class HealthTrendIntegration {
  let model: TrendViewModel
  let calculator: TrendCalculator
  private let defaults: UserDefaults
  private let enabledKey = "health.trends.v1.enabled"
  private(set) var isEnabled: Bool

  init(
    repository: any AnalysisRepository, health: (any HealthDataProviding)?,
    defaults: UserDefaults = .standard
  ) {
    self.defaults = defaults
    isEnabled = defaults.bool(forKey: enabledKey)
    calculator = TrendCalculator()
    model = TrendViewModel(repository: repository, health: health, calculator: calculator)
  }

  func enableWeeklySuggestions() {
    model.setMode(.suggested)
    guard model.errorMessage == nil, model.records.preferences.goalMode == .suggested else {
      return
    }
    enterWithoutChangingMode()
  }

  func enterWithoutChangingMode() {
    defaults.set(true, forKey: enabledKey)
    isEnabled = true
  }

  func refreshAfterHealthSync() {
    if isEnabled { model.reload() }
  }
}
