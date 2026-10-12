import Foundation
import Observation

struct ExerciseCatalogDocument: Decodable, Sendable {
  let source: ExerciseCatalogSource
  let exercises: [ExerciseCatalogItem]
}

struct ExerciseCatalogSource: Decodable, Hashable, Sendable {
  let repository: String
  let commit: String
  let license: String
}

struct ExerciseCatalogItem: Codable, Identifiable, Hashable, Sendable {
  let id: String
  let nameEn: String
  let nameZh: String
  let bodyPart: String
  let equipment: String
  let target: String
  let muscleGroup: String
  let secondaryMuscles: [String]
  let instructionsEn: String
  let instructionsZh: String
  let stepsEn: [String]
  let stepsZh: [String]
  var recommendedTrackingMode: TrackingMode? = nil

  var displayName: String { nameZh.trimmed.isEmpty ? nameEn : nameZh }

  var searchText: String {
    ([nameZh, nameEn, bodyPart, equipment, target, muscleGroup] + secondaryMuscles)
      .joined(separator: " ")
      .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
  }

  var defaultTrackingMode: TrackingMode { recommendedTrackingMode ?? (bodyPart == "cardio" ? .cardio : .strength) }
}

// Value-only snapshot: construction may run on the cooperative background executor.
// No ModelContext, observable UI state, or mutable shared cache crosses this boundary.
struct ExerciseCatalogIndex: Sendable {
  let items: [ExerciseCatalogItem]
  let source: ExerciseCatalogSource?
  let bodyParts: [String]
  let equipmentTypes: [String]
  let muscleGroups: [String]
  private let searchTexts: [String]
  private let muscles: [Set<String>]
  private let locale: Locale

  init(
    items: [ExerciseCatalogItem], source: ExerciseCatalogSource? = nil,
    locale: Locale = .current
  ) {
    self.items = items
    self.source = source
    self.locale = locale
    bodyParts = Array(Set(items.map(\.bodyPart))).sorted()
    equipmentTypes = Array(Set(items.map(\.equipment))).sorted()
    muscles = items.map { Set([$0.target, $0.muscleGroup] + $0.secondaryMuscles) }
    muscleGroups = Array(Set(muscles.flatMap { $0 }.filter { !$0.trimmed.isEmpty })).sorted()
    searchTexts = items.map { item in
      // Fixed bilingual aliases are independent of the selected presentation language.
      let aliases = [Self.bodyPartAliases[item.bodyPart], Self.equipmentAliases[item.equipment]]
        .compactMap { $0 }
      return ([item.nameZh, item.nameEn, item.bodyPart, item.equipment, item.target,
        item.muscleGroup] + item.secondaryMuscles + aliases)
        .joined(separator: " ")
        .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: locale)
    }
  }

  func filtered(query: String, bodyPart: String?, equipment: String?, muscleGroup: String?)
    -> [ExerciseCatalogItem]
  {
    let normalized = query.trimmed.folding(
      options: [.caseInsensitive, .diacriticInsensitive], locale: locale)
    return items.indices.compactMap { index in
      let item = items[index]
      guard (bodyPart == nil || item.bodyPart == bodyPart),
        (equipment == nil || item.equipment == equipment),
        (muscleGroup.map { muscles[index].contains($0) } ?? true),
        (normalized.isEmpty || searchTexts[index].localizedStandardContains(normalized))
      else { return nil }
      return item
    }
  }

  static func read(catalogURL: URL?, modesURL: URL?, locale: Locale) throws -> Self {
    guard let catalogURL, let modesURL else { throw CatalogError.resourceMissing }
    let document = try JSONDecoder().decode(
      ExerciseCatalogDocument.self, from: Data(contentsOf: catalogURL))
    guard document.exercises.count == 1324 else {
      throw CatalogError.unexpectedCount(document.exercises.count)
    }
    let ids = Set(document.exercises.map(\.id))
    guard ids.count == document.exercises.count else { throw CatalogError.duplicateIDs }
    let modes = try JSONDecoder().decode(
      [String: TrackingMode].self, from: Data(contentsOf: modesURL))
    guard Set(modes.keys) == ids else { throw CatalogError.trackingModesIncomplete }
    return Self(items: document.exercises.map { item in
      var result = item
      result.recommendedTrackingMode = modes[item.id]
      return result
    }, source: document.source, locale: locale)
  }

  private static let bodyPartAliases = [
    "back": "背部", "cardio": "有氧", "chest": "胸部", "lower arms": "前臂",
    "lower legs": "小腿", "neck": "颈部", "shoulders": "肩部", "upper arms": "上臂",
    "upper legs": "大腿", "waist": "腰腹",
  ]
  private static let equipmentAliases = [
    "body weight": "自重", "dumbbell": "哑铃", "barbell": "杠铃", "cable": "绳索",
    "band": "弹力带", "kettlebell": "壶铃", "smith machine": "史密斯机",
    "stability ball": "健身球", "leverage machine": "固定器械",
  ]
}

@MainActor
@Observable
final class ExerciseCatalog {
  private var index: ExerciseCatalogIndex?
  private(set) var errorMessage: String?
  @ObservationIgnored private var loadTask: Task<Void, Never>?
  @ObservationIgnored private let loader: @Sendable () throws -> ExerciseCatalogIndex

  // Initialization does not read/decode the resource or build an index on MainActor.
  init(bundle: Bundle = .main) {
    let catalogURL = bundle.url(forResource: "ExerciseCatalog", withExtension: "json")
    let modesURL = bundle.url(forResource: "ExerciseTrackingModes", withExtension: "json")
    let locale = Locale.current
    loader = {
      try ExerciseCatalogIndex.read(catalogURL: catalogURL, modesURL: modesURL, locale: locale)
    }
  }

  init(items: [ExerciseCatalogItem], source: ExerciseCatalogSource? = nil) {
    let prepared = ExerciseCatalogIndex(items: items, source: source)
    index = prepared
    loader = { prepared }
  }

  init(loader: @escaping @Sendable () throws -> ExerciseCatalogIndex) {
    self.loader = loader
  }

  var items: [ExerciseCatalogItem] { index?.items ?? [] }
  var source: ExerciseCatalogSource? { index?.source }
  var isLoading: Bool { index == nil && errorMessage == nil }
  var bodyParts: [String] { index?.bodyParts ?? [] }
  var equipmentTypes: [String] { index?.equipmentTypes ?? [] }
  var muscleGroups: [String] { index?.muscleGroups ?? [] }

  // App root, picker, and library share a single in-flight load. A disappearing
  // caller does not cancel the shared preparation needed by the other consumers.
  func load() async {
    if let loadTask { await loadTask.value; return }
    guard index == nil else { return }
    errorMessage = nil
    let loader = loader
    let task = Task {
      do {
        let prepared = try await Task.detached(priority: .userInitiated) {
          try loader()
        }.value
        index = prepared
      } catch {
        errorMessage = error.localizedDescription
      }
      loadTask = nil
    }
    loadTask = task
    await task.value
  }

  func filtered(
    query: String,
    bodyPart: String? = nil,
    equipment: String? = nil,
    muscleGroup: String? = nil
  ) -> [ExerciseCatalogItem] {
    index?.filtered(
      query: query, bodyPart: bodyPart, equipment: equipment, muscleGroup: muscleGroup) ?? []
  }
}

enum CatalogError: LocalizedError {
  case resourceMissing
  case unexpectedCount(Int)
  case duplicateIDs
  case trackingModesIncomplete

  var errorDescription: String? {
    switch self {
    case .resourceMissing:
      "找不到离线动作目录。"
    case .unexpectedCount(let count):
      "动作目录应包含 1,324 条记录，实际为 \(count) 条。"
    case .duplicateIDs:
      "动作目录包含重复 ID。"
    case .trackingModesIncomplete:
      "动作记录方式目录不完整，请更新 App。"
    }
  }
}

enum ExerciseLabel {
  static func bodyPart(_ value: String) -> String {
    [
      "back": "背部", "cardio": "有氧", "chest": "胸部", "lower arms": "前臂",
      "lower legs": "小腿", "neck": "颈部", "shoulders": "肩部", "upper arms": "上臂",
      "upper legs": "大腿", "waist": "腰腹",
    ][value] ?? value
  }

  static func equipment(_ value: String) -> String {
    [
      "body weight": "自重", "dumbbell": "哑铃", "barbell": "杠铃", "cable": "绳索",
      "band": "弹力带", "kettlebell": "壶铃", "smith machine": "史密斯机",
      "stability ball": "健身球", "leverage machine": "固定器械",
    ][value] ?? value
  }
}
