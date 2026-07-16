import Foundation
import Observation

struct ExerciseCatalogDocument: Decodable {
  let source: ExerciseCatalogSource
  let exercises: [ExerciseCatalogItem]
}

struct ExerciseCatalogSource: Decodable, Hashable {
  let repository: String
  let commit: String
  let license: String
}

struct ExerciseCatalogItem: Codable, Identifiable, Hashable {
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

  var displayName: String { nameZh.trimmed.isEmpty ? nameEn : nameZh }

  var searchText: String {
    ([nameZh, nameEn, bodyPart, equipment, target, muscleGroup] + secondaryMuscles)
      .joined(separator: " ")
      .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
  }

  var defaultTrackingMode: TrackingMode { bodyPart == "cardio" ? .cardio : .strength }
}

@MainActor
@Observable
final class ExerciseCatalog {
  private(set) var items: [ExerciseCatalogItem] = []
  private(set) var source: ExerciseCatalogSource?
  private(set) var errorMessage: String?

  init(bundle: Bundle = .main) {
    load(bundle: bundle)
  }

  init(items: [ExerciseCatalogItem], source: ExerciseCatalogSource? = nil) {
    self.items = items
    self.source = source
  }

  var bodyParts: [String] { Array(Set(items.map(\.bodyPart))).sorted() }
  var equipmentTypes: [String] { Array(Set(items.map(\.equipment))).sorted() }
  var muscleGroups: [String] {
    Array(
      Set(
        items.flatMap { item in
          [item.target, item.muscleGroup] + item.secondaryMuscles
        }.filter { !$0.trimmed.isEmpty }
      )
    ).sorted()
  }

  func load(bundle: Bundle = .main) {
    do {
      guard let url = bundle.url(forResource: "ExerciseCatalog", withExtension: "json") else {
        throw CatalogError.resourceMissing
      }
      let document = try JSONDecoder().decode(
        ExerciseCatalogDocument.self,
        from: Data(contentsOf: url)
      )
      guard document.exercises.count == 1324 else {
        throw CatalogError.unexpectedCount(document.exercises.count)
      }
      guard Set(document.exercises.map(\.id)).count == document.exercises.count else {
        throw CatalogError.duplicateIDs
      }
      items = document.exercises
      source = document.source
      errorMessage = nil
    } catch {
      items = []
      source = nil
      errorMessage = error.localizedDescription
    }
  }

  func filtered(
    query: String,
    bodyPart: String? = nil,
    equipment: String? = nil,
    muscleGroup: String? = nil
  ) -> [ExerciseCatalogItem] {
    let normalizedQuery = query.trimmed.folding(
      options: [.caseInsensitive, .diacriticInsensitive],
      locale: .current
    )
    return items.filter { item in
      (bodyPart == nil || item.bodyPart == bodyPart)
        && (equipment == nil || item.equipment == equipment)
        && (muscleGroup.map { item.muscles.contains($0) } ?? true)
        && (normalizedQuery.isEmpty || item.searchText.localizedStandardContains(normalizedQuery))
    }
  }
}

extension ExerciseCatalogItem {
  fileprivate var muscles: [String] { [target, muscleGroup] + secondaryMuscles }
}

enum CatalogError: LocalizedError {
  case resourceMissing
  case unexpectedCount(Int)
  case duplicateIDs

  var errorDescription: String? {
    switch self {
    case .resourceMissing:
      "找不到离线动作目录。"
    case .unexpectedCount(let count):
      "动作目录应包含 1,324 条记录，实际为 \(count) 条。"
    case .duplicateIDs:
      "动作目录包含重复 ID。"
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
