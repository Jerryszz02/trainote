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
  var recommendedTrackingMode: TrackingMode? = nil

  var displayName: String { L10n.name(zh: nameZh, en: nameEn) }
  var displaySteps: [String] {
    let preferred = L10n.language == .simplifiedChinese ? stepsZh : stepsEn
    return preferred.isEmpty ? (L10n.language == .simplifiedChinese ? stepsEn : stepsZh) : preferred
  }
  var displayInstructions: String { L10n.name(zh: instructionsZh, en: instructionsEn) }

  var searchText: String {
    ([nameZh, nameEn, bodyPart, equipment, target, muscleGroup]
      + secondaryMuscles + ([bodyPart, equipment, target, muscleGroup] + secondaryMuscles).flatMap(ExerciseLabel.searchAliases))
      .joined(separator: " ")
      .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
  }

  var defaultTrackingMode: TrackingMode { recommendedTrackingMode ?? (bodyPart == "cardio" ? .cardio : .strength) }
}

@MainActor
@Observable
final class ExerciseCatalog {
  private(set) var items: [ExerciseCatalogItem] = []
  private(set) var source: ExerciseCatalogSource?
  private var loadError: Error?
  var errorMessage: String? { loadError?.localizedDescription }

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
      guard let modesURL = bundle.url(forResource: "ExerciseTrackingModes", withExtension: "json") else {
        throw CatalogError.resourceMissing
      }
      let modes = try JSONDecoder().decode([String: TrackingMode].self, from: Data(contentsOf: modesURL))
      guard Set(modes.keys) == Set(document.exercises.map(\.id)) else {
        throw CatalogError.trackingModesIncomplete
      }
      items = document.exercises.map { item in
        var result = item
        result.recommendedTrackingMode = modes[item.id]
        return result
      }
      source = document.source
      loadError = nil
    } catch {
      items = []
      source = nil
      loadError = error
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
  case trackingModesIncomplete

  var errorDescription: String? {
    switch self {
    case .resourceMissing:
      L10n.text("catalog.missing")
    case .unexpectedCount(let count):
      L10n.text("catalog.count", count)
    case .duplicateIDs:
      L10n.text("catalog.duplicate")
    case .trackingModesIncomplete:
      L10n.text("catalog.incomplete")
    }
  }
}

enum ExerciseLabel {
  private static let keys: [String: String] = [
    "upper body ergometer": "exercise.label.upper_body_ergometer",
    "rear deltoids": "exercise.label.rear_deltoids",
    "latissimus dorsi": "exercise.label.latissimus_dorsi",
    "inner thighs": "exercise.label.inner_thighs",
    "groin": "exercise.label.groin",
    "grip muscles": "exercise.label.grip_muscles",
    "deltoids": "exercise.label.deltoids",
    "brachialis": "exercise.label.brachialis",
    "ankle stabilizers": "exercise.label.ankle_stabilizers",
    "abdominals": "exercise.label.abdominals",
    "abductors": "exercise.label.abductors",
    "abs": "exercise.label.abs",
    "adductors": "exercise.label.adductors",
    "ankles": "exercise.label.ankles",
    "assisted": "exercise.label.assisted",
    "back": "exercise.label.back",
    "band": "exercise.label.band",
    "barbell": "exercise.label.barbell",
    "biceps": "exercise.label.biceps",
    "body weight": "exercise.label.body_weight",
    "bosu ball": "exercise.label.bosu_ball",
    "cable": "exercise.label.cable",
    "calves": "exercise.label.calves",
    "cardio": "exercise.label.cardio",
    "cardiovascular system": "exercise.label.cardiovascular_system",
    "chest": "exercise.label.chest",
    "core": "exercise.label.core",
    "delts": "exercise.label.delts",
    "dumbbell": "exercise.label.dumbbell",
    "elliptical machine": "exercise.label.elliptical_machine",
    "ez barbell": "exercise.label.ez_barbell",
    "feet": "exercise.label.feet",
    "forearms": "exercise.label.forearms",
    "glutes": "exercise.label.glutes",
    "hammer": "exercise.label.hammer",
    "hamstrings": "exercise.label.hamstrings",
    "hands": "exercise.label.hands",
    "hip flexors": "exercise.label.hip_flexors",
    "kettlebell": "exercise.label.kettlebell",
    "lats": "exercise.label.lats",
    "levator scapulae": "exercise.label.levator_scapulae",
    "leverage machine": "exercise.label.leverage_machine",
    "lower abs": "exercise.label.lower_abs",
    "lower arms": "exercise.label.lower_arms",
    "lower back": "exercise.label.lower_back",
    "lower legs": "exercise.label.lower_legs",
    "medicine ball": "exercise.label.medicine_ball",
    "neck": "exercise.label.neck",
    "obliques": "exercise.label.obliques",
    "olympic barbell": "exercise.label.olympic_barbell",
    "pectorals": "exercise.label.pectorals",
    "quadriceps": "exercise.label.quadriceps",
    "quads": "exercise.label.quads",
    "resistance band": "exercise.label.resistance_band",
    "rhomboids": "exercise.label.rhomboids",
    "roller": "exercise.label.roller",
    "rope": "exercise.label.rope",
    "rotator cuff": "exercise.label.rotator_cuff",
    "serratus anterior": "exercise.label.serratus_anterior",
    "shins": "exercise.label.shins",
    "shoulders": "exercise.label.shoulders",
    "skierg machine": "exercise.label.skierg_machine",
    "sled machine": "exercise.label.sled_machine",
    "smith machine": "exercise.label.smith_machine",
    "soleus": "exercise.label.soleus",
    "spine": "exercise.label.spine",
    "stability ball": "exercise.label.stability_ball",
    "stationary bike": "exercise.label.stationary_bike",
    "stepmill machine": "exercise.label.stepmill_machine",
    "sternocleidomastoid": "exercise.label.sternocleidomastoid",
    "tire": "exercise.label.tire",
    "trap bar": "exercise.label.trap_bar",
    "trapezius": "exercise.label.trapezius",
    "traps": "exercise.label.traps",
    "triceps": "exercise.label.triceps",
    "upper arms": "exercise.label.upper_arms",
    "upper back": "exercise.label.upper_back",
    "upper chest": "exercise.label.upper_chest",
    "upper legs": "exercise.label.upper_legs",
    "waist": "exercise.label.waist",
    "weighted": "exercise.label.weighted",
    "wheel roller": "exercise.label.wheel_roller",
    "wrist extensors": "exercise.label.wrist_extensors",
    "wrist flexors": "exercise.label.wrist_flexors",
    "wrists": "exercise.label.wrists",
  ]
  static func bodyPart(_ value: String) -> String { label(value) }
  static func equipment(_ value: String) -> String { label(value) }
  static func muscleGroup(_ value: String) -> String { label(value) }
  static func muscle(_ value: String) -> String { label(value) }
  static func label(_ value: String) -> String { keys[value].map { L10n.text($0) } ?? value }
  private static let aliases: [String: [String]] = keys.mapValues { key in
    [L10n.render(key, arguments: [], language: .english),
      L10n.render(key, arguments: [], language: .simplifiedChinese)]
  }
  static func searchAliases(_ value: String) -> [String] { [value] + (aliases[value] ?? []) }
}
