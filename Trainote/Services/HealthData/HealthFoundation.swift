import Foundation
import Observation
import SwiftData

/// Foundation assembly for F. No authorization request or external call occurs on construction.
@MainActor
@Observable
final class HealthFoundation {
  let repository: SwiftDataAnalysisRepository
  let consent: LocalConsentStore?
  let healthData: HealthDataService?
  let setupFailure: AnalysisFailure?

  init(container: ModelContainer, localDirectory: URL = LocalHealthStorage.directory) {
    let repository = SwiftDataAnalysisRepository(container: container)
    self.repository = repository
    do {
      let consent = try LocalConsentStore(
        url: localDirectory.appendingPathComponent("consent.json"))
      let cache = try HealthCacheStore(
        url: localDirectory.appendingPathComponent("cache.json"),
        syncStart: Date.now.addingTimeInterval(-90 * 86_400))
      self.consent = consent
      healthData = HealthDataService(
        client: AppleHealthQueryClient(), cache: cache, consent: consent,
        preferences: { try repository.manualRecords().preferences })
      setupFailure = nil
    } catch {
      consent = nil
      healthData = nil
      setupFailure = .storageFailed
    }
  }
  func resume() async {
    guard consent?.record(for: .healthData)?.isGranted == true, let healthData else { return }
    try? await healthData.startObserving()
    try? await healthData.refresh()
  }
}
