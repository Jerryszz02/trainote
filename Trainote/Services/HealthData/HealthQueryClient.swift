import Foundation
import HealthKit

@MainActor
protocol HealthQueryClient {
  var isAvailable: Bool { get }
  func requestAuthorization() async throws
  func changes(type: HealthDataType, anchor: Data?, since: Date) async throws -> HealthAnchorBatch
  func samples(type: HealthDataType, window: AnalysisWindow) async throws -> [HealthSample]
  func activityFacts(
    type: HealthDataType, window: AnalysisWindow, timeZone: TimeZone,
    preferredSources: [String]
  ) async throws -> [MetricFact]
  func observe(_ onChange: @escaping (HealthDataType, @escaping () -> Void) -> Void) async throws
  func stopObserving()
}

@MainActor
final class AppleHealthQueryClient: HealthQueryClient {
  private let store = HKHealthStore()
  private var observers: [HKObserverQuery] = []
  private var activeQueries: [UUID: (HKQuery, () -> Void)] = [:]
  private var observationGeneration = UUID()

  private func execute<Value>(_ make: (@escaping (Result<Value, Error>) -> Void) -> HKQuery)
    async throws -> Value
  {
    let id = UUID()
    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        let query = make { result in
          Task { @MainActor in
            guard let (query, _) = self.activeQueries.removeValue(forKey: id) else { return }
            self.store.stop(query)
            continuation.resume(with: result)
          }
        }
        activeQueries[id] = (query, { continuation.resume(throwing: CancellationError()) })
        if Task.isCancelled { cancelQuery(id) } else { store.execute(query) }
      }
    } onCancel: {
      Task { @MainActor in self.cancelQuery(id) }
    }
  }
  private func cancelQuery(_ id: UUID) {
    guard let (query, cancel) = activeQueries.removeValue(forKey: id) else { return }
    store.stop(query)
    cancel()
  }
  var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

  static func sampleType(_ type: HealthDataType) -> HKSampleType {
    switch type {
    case .bodyMass: HKQuantityType(.bodyMass)
    case .sleep: HKCategoryType(.sleepAnalysis)
    case .restingHeartRate: HKQuantityType(.restingHeartRate)
    case .heartRateVariabilitySDNN: HKQuantityType(.heartRateVariabilitySDNN)
    case .steps: HKQuantityType(.stepCount)
    case .activeEnergy: HKQuantityType(.activeEnergyBurned)
    case .workout: HKObjectType.workoutType()
    }
  }
  func requestAuthorization() async throws {
    guard isAvailable else { throw AnalysisFailure.unavailable }
    // No write types. Completion says the request finished, not that reads were granted.
    try await store.requestAuthorization(
      toShare: [], read: Set(HealthDataType.allCases.map(Self.sampleType)))
  }
  func changes(type: HealthDataType, anchor: Data?, since: Date) async throws -> HealthAnchorBatch {
    let decoded = try anchor.map {
      try NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: $0)
    }
    let predicate = HKQuery.predicateForSamples(withStart: since, end: nil, options: [])
    return try await execute { finish in
      let query = HKAnchoredObjectQuery(
        type: Self.sampleType(type), predicate: predicate,
        anchor: decoded ?? nil, limit: HKObjectQueryNoLimit
      ) { _, samples, deleted, next, error in
        if let error {
          finish(.failure(error))
          return
        }
        guard let next else {
          finish(.failure(AnalysisFailure.readFailed))
          return
        }
        do {
          let data = try NSKeyedArchiver.archivedData(
            withRootObject: next, requiringSecureCoding: true)
          finish(
            .success(
              .init(
                type: type,
                added: (samples ?? []).compactMap { Self.convert($0, type: type) },
                deletedIDs: (deleted ?? []).map(\.uuid), newAnchor: data, queriedAt: .now)))
        } catch { finish(.failure(error)) }
      }
      return query
    }
  }
  func samples(type: HealthDataType, window: AnalysisWindow) async throws -> [HealthSample] {
    let predicate = HKQuery.predicateForSamples(
      withStart: window.start, end: window.end, options: [])
    return try await execute { finish in
      let query = HKSampleQuery(
        sampleType: Self.sampleType(type), predicate: predicate,
        limit: HKObjectQueryNoLimit, sortDescriptors: nil
      ) { _, samples, error in
        if let error {
          finish(.failure(error))
          return
        }
        finish(.success((samples ?? []).compactMap { Self.convert($0, type: type) }))
      }
      return query
    }
  }
  func activityFacts(
    type: HealthDataType, window: AnalysisWindow, timeZone: TimeZone,
    preferredSources: [String]
  ) async throws -> [MetricFact] {
    guard let quantity = Self.sampleType(type) as? HKQuantityType,
      type == .steps || type == .activeEnergy
    else { throw AnalysisFailure.invalidInput }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    let anchor = calendar.startOfDay(for: window.start)
    let predicate = HKQuery.predicateForSamples(
      withStart: window.start, end: window.end, options: [])
    return try await execute { finish in
      let query = HKStatisticsCollectionQuery(
        quantityType: quantity, quantitySamplePredicate: predicate,
        options: [.cumulativeSum, .separateBySource], anchorDate: anchor,
        intervalComponents: DateComponents(calendar: calendar, timeZone: timeZone, day: 1))
      query.initialResultsHandler = { _, collection, error in
        if let error {
          finish(.failure(error))
          return
        }
        guard let collection else {
          finish(.failure(AnalysisFailure.readFailed))
          return
        }
        var facts: [MetricFact] = []
        collection.enumerateStatistics(from: window.start, to: window.end) { statistics, _ in
          let sources = (statistics.sources ?? []).sorted { lhs, rhs in
            let a = preferredSources.firstIndex(of: lhs.bundleIdentifier) ?? Int.max
            let b = preferredSources.firstIndex(of: rhs.bundleIdentifier) ?? Int.max
            return a == b ? lhs.bundleIdentifier < rhs.bundleIdentifier : a < b
          }
          guard let source = sources.first, let quantity = statistics.sumQuantity(for: source)
          else { return }
          let unit: HKUnit = type == .steps ? .count() : .kilocalorie()
          let day = AnalysisFingerprint.localDate(statistics.startDate, timeZone: timeZone)
          facts.append(
            .init(
              id: "health.\(type.rawValue).\(day)", metric: type.rawValue,
              value: quantity.doubleValue(for: unit), unit: type == .steps ? .count : .kilocalories,
              window: .init(
                start: max(statistics.startDate, window.start),
                end: min(statistics.endDate, window.end)),
              sources: [.init(kind: .healthKit, identifier: source.bundleIdentifier)],
              quality: sources.count > 1 ? [.sourceConflict] : []))
        }
        finish(.success(facts))
      }
      return query
    }
  }
  func observe(_ onChange: @escaping (HealthDataType, @escaping () -> Void) -> Void) async throws {
    guard observers.isEmpty else { return }
    let generation = observationGeneration
    var backgroundError: Error?
    for type in HealthDataType.allCases {
      guard generation == observationGeneration else { throw AnalysisFailure.cancelled }
      let sampleType = Self.sampleType(type)
      let query = HKObserverQuery(sampleType: sampleType, predicate: nil) { _, completion, error in
        guard error == nil else {
          completion()
          return
        }
        Task { @MainActor in onChange(type, completion) }
      }
      observers.append(query)
      store.execute(query)
      // Background delivery is opportunistic; foreground refresh remains available on failure.
      do { try await store.enableBackgroundDelivery(for: sampleType, frequency: .hourly) } catch {
        backgroundError = backgroundError ?? error
      }
    }
    guard generation == observationGeneration else { throw AnalysisFailure.cancelled }
    if let backgroundError { throw backgroundError }
  }
  func stopObserving() {
    observationGeneration = UUID()
    for id in Array(activeQueries.keys) { cancelQuery(id) }
    observers.forEach { store.stop($0) }
    observers.removeAll()
    // Already queued callbacks are guarded by the consent lease in HealthDataService.
    store.disableAllBackgroundDelivery { _, _ in }
  }
  private nonisolated static func convert(_ sample: HKSample, type: HealthDataType) -> HealthSample?
  {
    let revision = sample.sourceRevision
    let source = HealthSource(
      bundleIdentifier: revision.source.bundleIdentifier, name: revision.source.name,
      version: revision.version, productType: revision.productType)
    var value = HealthSample(
      id: sample.uuid, type: type, start: sample.startDate, end: sample.endDate,
      value: nil, unit: .none, source: source,
      timeZoneIdentifier: sample.metadata?[HKMetadataKeyTimeZone] as? String)
    if let quantity = sample as? HKQuantitySample {
      let unit: HKUnit
      switch type {
      case .bodyMass:
        unit = .gramUnit(with: .kilo)
        value.unit = .kilograms
      case .restingHeartRate:
        unit = .count().unitDivided(by: .minute())
        value.unit = .beatsPerMinute
      case .heartRateVariabilitySDNN:
        unit = .secondUnit(with: .milli)
        value.unit = .milliseconds
        value.definition = "SDNN"
        value.measurementContext = "unspecified"
      case .steps:
        unit = .count()
        value.unit = .count
      case .activeEnergy:
        unit = .kilocalorie()
        value.unit = .kilocalories
      default: return nil
      }
      value.value = quantity.quantity.doubleValue(for: unit)
    } else if let category = sample as? HKCategorySample, type == .sleep {
      value.unit = .seconds
      switch HKCategoryValueSleepAnalysis(rawValue: category.value) {
      case .inBed: value.sleepStage = .inBed
      case .awake: value.sleepStage = .awake
      case .asleepUnspecified: value.sleepStage = .asleepUnspecified
      case .asleepCore: value.sleepStage = .core
      case .asleepDeep: value.sleepStage = .deep
      case .asleepREM: value.sleepStage = .rem
      default: return nil
      }
    } else if let workout = sample as? HKWorkout {
      value.value = workout.duration
      value.unit = .seconds
      value.workoutActivityCode = workout.workoutActivityType.rawValue
    } else {
      return nil
    }
    return value
  }
}
