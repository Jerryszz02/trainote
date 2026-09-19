import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Versioned, value-only backup format. SwiftData models deliberately never conform to Codable.
struct BackupArchive: Codable {
  static let schemaVersion = 1
  static let maxBytes = 20 * 1024 * 1024
  static let maxObjects = 100_000

  struct Counts: Codable, Equatable {
    var workouts: Int = 0
    var routines: Int = 0
    var foodPresets: Int = 0
    var mealTemplates: Int = 0
    var foodLogs: Int = 0
    var nutritionGoals: Int = 0
    var childObjects: Int = 0
    var total: Int {
      workouts + routines + foodPresets + mealTemplates + foodLogs + nutritionGoals + childObjects
    }
  }

  var schemaVersion: Int
  var createdAt: Date
  var workouts: [WorkoutDTO]
  var routines: [RoutineDTO]
  var foodPresets: [FoodPresetDTO]
  var mealTemplates: [MealTemplateDTO]
  var foodLogs: [FoodLogDTO]
  var nutritionGoals: [NutritionGoalDTO]
  var counts: Counts {
    Counts(
      workouts: workouts.count, routines: routines.count, foodPresets: foodPresets.count,
      mealTemplates: mealTemplates.count, foodLogs: foodLogs.count,
      nutritionGoals: nutritionGoals.count,
      childObjects: workouts.reduce(0) {
        $0 + $1.exercises.reduce(0) { $0 + 1 + $1.strengthSets.count + $1.cardioEntries.count }
      } + routines.reduce(0) { $0 + $1.exercises.count }
        + mealTemplates.reduce(0) { $0 + $1.items.count })
  }
}

struct BackupDocument: FileDocument {
  static var readableContentTypes: [UTType] { [.json] }
  var data: Data
  init(data: Data = Data()) { self.data = data }
  init(configuration: ReadConfiguration) throws {
    data = configuration.file.regularFileContents ?? Data()
  }
  func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
    FileWrapper(regularFileWithContents: data)
  }
}

struct WorkoutDTO: Codable {
  var id: UUID
  var title: String
  var startedAt: Date
  var endedAt: Date?
  var statusRaw: String
  var notes: String
  var routineNameSnapshot: String?
  var restEndsAt: Date?
  var exercises: [WorkoutExerciseDTO]
}
struct WorkoutExerciseDTO: Codable {
  var id: UUID
  var sourceExerciseID: String
  var nameEnSnapshot: String
  var nameZhSnapshot: String
  var orderIndex: Int
  var trackingModeRaw: String
  var notes: String
  var strengthSets: [StrengthSetDTO]
  var cardioEntries: [CardioEntryDTO]
}
struct StrengthSetDTO: Codable {
  var id: UUID
  var orderIndex: Int
  var weightKilograms: Double
  var repetitions: Int
  var durationSeconds: Int
  var isCompleted: Bool
}
struct CardioEntryDTO: Codable {
  var id: UUID
  var durationSeconds: Int
  var distanceKilometers: Double
  var calories: Double
}
struct RoutineDTO: Codable {
  var id: UUID
  var name: String
  var notes: String
  var createdAt: Date
  var updatedAt: Date
  var exercises: [RoutineExerciseDTO]
}
struct RoutineExerciseDTO: Codable {
  var id: UUID
  var sourceExerciseID: String
  var nameEnSnapshot: String
  var nameZhSnapshot: String
  var orderIndex: Int
  var trackingModeRaw: String
  var defaultSetCount: Int
  var defaultRepetitions: Int
  var defaultWeightKilograms: Double
  var defaultDurationSeconds: Int
  var defaultDistanceKilometers: Double
}
struct FoodPresetDTO: Codable {
  var id: UUID
  var name: String
  var servingDescription: String
  var caloriesPerServing: Double
  var carbohydratesPerServing: Double
  var proteinPerServing: Double
  var fatPerServing: Double
  var createdAt: Date
  var updatedAt: Date
}
struct MealTemplateDTO: Codable {
  var id: UUID
  var name: String
  var notes: String
  var createdAt: Date
  var updatedAt: Date
  var items: [MealTemplateItemDTO]
}
struct MealTemplateItemDTO: Codable {
  var id: UUID
  var orderIndex: Int
  var nameSnapshot: String
  var servingDescriptionSnapshot: String
  var quantity: Double
  var caloriesPerServing: Double
  var carbohydratesPerServing: Double
  var proteinPerServing: Double
  var fatPerServing: Double
}
extension MealTemplateItemDTO {
  fileprivate var isValid: Bool {
    !nameSnapshot.trimmed.isEmpty && !servingDescriptionSnapshot.trimmed.isEmpty
      && quantity.isFinite && quantity > 0
      && [caloriesPerServing, carbohydratesPerServing, proteinPerServing, fatPerServing].allSatisfy
      { $0.isValidNonnegativeNumber && ($0 * quantity).isValidNonnegativeNumber }
  }
}
struct FoodLogDTO: Codable {
  var id: UUID
  var loggedAt: Date
  var mealTypeRaw: String
  var name: String
  var servingDescription: String
  var quantity: Double
  var calories: Double
  var carbohydrates: Double
  var protein: Double
  var fat: Double
  var sourcePresetID: UUID?
  var sourceMealTemplateID: UUID?
}
struct NutritionGoalDTO: Codable {
  var id: UUID
  var calories: Double
  var carbohydrates: Double
  var protein: Double
  var fat: Double
  var updatedAt: Date
}

enum BackupArchiveError: LocalizedError, Equatable {
  case tooLarge
  case invalid(String)
  case unsupportedVersion(Int)
  case activeWorkoutConflict
  var errorDescription: String {
    switch self {
    case .tooLarge: "备份文件过大。"
    case .invalid(let s): "备份无效：\(s)"
    case .unsupportedVersion(let v): "不支持的备份版本：\(v)。"
    case .activeWorkoutConflict: "当前已有进行中的训练，无法恢复另一个进行中的训练。"
    }
  }
}

struct BackupImportResult: Equatable {
  var inserted: Int
  var skipped: Int
  var counts: BackupArchive.Counts
}

enum BackupArchiveService {
  private static let encoder: JSONEncoder = {
    let e = JSONEncoder()
    e.dateEncodingStrategy = .iso8601
    e.outputFormatting = [.prettyPrinted, .sortedKeys]
    return e
  }()
  private static let decoder: JSONDecoder = {
    let d = JSONDecoder()
    d.dateDecodingStrategy = .iso8601
    return d
  }()

  static func export(context: ModelContext) throws -> Data {
    try context.save()
    let archive = BackupArchive(
      schemaVersion: 1, createdAt: .now,
      workouts: try context.fetch(FetchDescriptor<Workout>()).map(workout),
      routines: try context.fetch(FetchDescriptor<Routine>()).map(routine),
      foodPresets: try context.fetch(FetchDescriptor<FoodPreset>()).map(foodPreset),
      mealTemplates: try context.fetch(FetchDescriptor<MealTemplate>()).map(mealTemplate),
      foodLogs: try context.fetch(FetchDescriptor<FoodLogEntry>()).map(foodLog),
      nutritionGoals: try context.fetch(FetchDescriptor<NutritionGoal>()).map(nutritionGoal))
    try validate(archive)
    let data = try encoder.encode(archive)
    guard data.count <= BackupArchive.maxBytes, archive.counts.total <= BackupArchive.maxObjects
    else { throw BackupArchiveError.tooLarge }
    return data
  }

  static func decode(_ data: Data) throws -> BackupArchive {
    guard data.count <= BackupArchive.maxBytes else { throw BackupArchiveError.tooLarge }
    let archive: BackupArchive
    do { archive = try decoder.decode(BackupArchive.self, from: data) } catch {
      throw BackupArchiveError.invalid("JSON 格式或字段不正确。")
    }
    guard archive.schemaVersion == BackupArchive.schemaVersion else {
      throw BackupArchiveError.unsupportedVersion(archive.schemaVersion)
    }
    try validate(archive)
    return archive
  }

  static func importData(_ data: Data, into container: ModelContainer) throws -> BackupImportResult
  {
    let archive = try decode(data)
    let isolated = ModelContext(container)
    isolated.autosaveEnabled = false
    let existingWorkouts = try isolated.fetch(FetchDescriptor<Workout>())
    let existingRoutines = try isolated.fetch(FetchDescriptor<Routine>())
    let existingPresets = try isolated.fetch(FetchDescriptor<FoodPreset>())
    let existingTemplates = try isolated.fetch(FetchDescriptor<MealTemplate>())
    let existingLogs = try isolated.fetch(FetchDescriptor<FoodLogEntry>())
    let existingGoals = try isolated.fetch(FetchDescriptor<NutritionGoal>())
    if archive.workouts.contains(where: { incoming in
      incoming.statusRaw == WorkoutStatus.inProgress.rawValue
        && !existingWorkouts.contains { $0.id == incoming.id }
    })
      && existingWorkouts.contains(where: { $0.status == .inProgress })
    {
      throw BackupArchiveError.activeWorkoutConflict
    }
    let existingIDs = Set(
      existingWorkouts.map(\.id) + existingRoutines.map(\.id) + existingPresets.map(\.id)
        + existingTemplates.map(\.id) + existingLogs.map(\.id) + existingGoals.map(\.id))
    var childIDs = Set<UUID>()
    for workout in existingWorkouts {
      for exercise in workout.exercises {
        childIDs.insert(exercise.id)
        childIDs.formUnion(exercise.strengthSets.map(\.id))
        childIDs.formUnion(exercise.cardioEntries.map(\.id))
      }
    }
    for routine in existingRoutines { childIDs.formUnion(routine.exercises.map(\.id)) }
    for template in existingTemplates { childIDs.formUnion(template.items.map(\.id)) }
    var incomingTopIDs = Set(archive.workouts.map(\.id))
    incomingTopIDs.formUnion(archive.routines.map(\.id))
    incomingTopIDs.formUnion(archive.foodPresets.map(\.id))
    incomingTopIDs.formUnion(archive.mealTemplates.map(\.id))
    incomingTopIDs.formUnion(archive.foodLogs.map(\.id))
    incomingTopIDs.formUnion(archive.nutritionGoals.map(\.id))
    var incomingChildIDs = Set<UUID>()
    for workout in archive.workouts where !existingIDs.contains(workout.id) {
      for exercise in workout.exercises {
        incomingChildIDs.insert(exercise.id)
        incomingChildIDs.formUnion(exercise.strengthSets.map(\.id))
        incomingChildIDs.formUnion(exercise.cardioEntries.map(\.id))
      }
    }
    for routine in archive.routines where !existingIDs.contains(routine.id) {
      incomingChildIDs.formUnion(routine.exercises.map(\.id))
    }
    for template in archive.mealTemplates where !existingIDs.contains(template.id) {
      incomingChildIDs.formUnion(template.items.map(\.id))
    }
    var matchingTypeIDs = Set(archive.workouts.map(\.id)).intersection(existingWorkouts.map(\.id))
    matchingTypeIDs.formUnion(
      Set(archive.routines.map(\.id)).intersection(existingRoutines.map(\.id)))
    matchingTypeIDs.formUnion(
      Set(archive.foodPresets.map(\.id)).intersection(existingPresets.map(\.id)))
    matchingTypeIDs.formUnion(
      Set(archive.mealTemplates.map(\.id)).intersection(existingTemplates.map(\.id)))
    matchingTypeIDs.formUnion(Set(archive.foodLogs.map(\.id)).intersection(existingLogs.map(\.id)))
    matchingTypeIDs.formUnion(
      Set(archive.nutritionGoals.map(\.id)).intersection(existingGoals.map(\.id)))
    guard incomingTopIDs.intersection(existingIDs) == matchingTypeIDs,
      incomingTopIDs.isDisjoint(with: childIDs),
      incomingChildIDs.isDisjoint(with: childIDs.union(existingIDs))
    else { throw BackupArchiveError.invalid("记录 ID 与本机的其他对象冲突。") }
    var inserted = 0
    var skipped = 0
    for d in archive.workouts {
      let count =
        1 + d.exercises.reduce(0) { $0 + 1 + $1.strengthSets.count + $1.cardioEntries.count }
      if existingIDs.contains(d.id) {
        skipped += count
      } else {
        let w = make(d)
        isolated.insert(w)
        inserted += count
      }
    }
    for d in archive.routines {
      let count = 1 + d.exercises.count
      if existingIDs.contains(d.id) {
        skipped += count
      } else {
        isolated.insert(make(d))
        inserted += count
      }
    }
    for d in archive.foodPresets {
      if existingIDs.contains(d.id) {
        skipped += 1
      } else {
        isolated.insert(make(d))
        inserted += 1
      }
    }
    for d in archive.mealTemplates {
      let count = 1 + d.items.count
      if existingIDs.contains(d.id) {
        skipped += count
      } else {
        isolated.insert(make(d))
        inserted += count
      }
    }
    for d in archive.foodLogs {
      if existingIDs.contains(d.id) {
        skipped += 1
      } else {
        isolated.insert(make(d))
        inserted += 1
      }
    }
    for d in archive.nutritionGoals {
      if existingIDs.contains(d.id) {
        skipped += 1
      } else {
        isolated.insert(make(d))
        inserted += 1
      }
    }
    do { try isolated.save() } catch {
      isolated.rollback()
      throw error
    }
    return BackupImportResult(inserted: inserted, skipped: skipped, counts: archive.counts)
  }

  private static func validate(_ a: BackupArchive) throws {
    guard a.createdAt.isReasonable else { throw BackupArchiveError.invalid("创建时间不合理。") }
    guard a.counts.total <= BackupArchive.maxObjects else { throw BackupArchiveError.tooLarge }
    guard a.workouts.filter({ $0.statusRaw == WorkoutStatus.inProgress.rawValue }).count <= 1 else {
      throw BackupArchiveError.invalid("备份中不能有多个进行中的训练。")
    }
    var ids = Set<UUID>()
    func unique(_ id: UUID) throws {
      guard ids.insert(id).inserted else { throw BackupArchiveError.invalid("存在重复 ID。") }
    }
    for w in a.workouts {
      try unique(w.id)
      guard !w.title.trimmed.isEmpty, WorkoutStatus(rawValue: w.statusRaw) != nil,
        w.startedAt.isReasonable, w.endedAt?.isReasonable != false,
        w.restEndsAt?.isReasonable != false
      else { throw BackupArchiveError.invalid("训练字段不完整。") }
      for e in w.exercises { try validate(e, ids: &ids) }
      if w.statusRaw == WorkoutStatus.completed.rawValue {
        guard let end = w.endedAt, end >= w.startedAt, make(w).hasValidResult else {
          throw BackupArchiveError.invalid("已完成训练缺少有效结果或结束时间。")
        }
      }
    }
    for r in a.routines {
      try unique(r.id)
      guard !r.name.trimmed.isEmpty, r.createdAt.isReasonable, r.updatedAt.isReasonable else {
        throw BackupArchiveError.invalid("训练计划字段不完整。")
      }
      for e in r.exercises {
        try unique(e.id)
        guard !e.sourceExerciseID.trimmed.isEmpty, !e.nameEnSnapshot.trimmed.isEmpty,
          !e.nameZhSnapshot.trimmed.isEmpty, (0..<BackupArchive.maxObjects).contains(e.orderIndex),
          TrackingMode(rawValue: e.trackingModeRaw) != nil, e.hasValidDefaults
        else { throw BackupArchiveError.invalid("训练计划动作无效。") }
      }
    }
    for p in a.foodPresets {
      try unique(p.id)
      guard !p.name.trimmed.isEmpty, !p.servingDescription.trimmed.isEmpty, p.numbersValid,
        p.createdAt.isReasonable, p.updatedAt.isReasonable
      else { throw BackupArchiveError.invalid("食物字段无效。") }
    }
    for t in a.mealTemplates {
      try unique(t.id)
      guard !t.name.trimmed.isEmpty, t.createdAt.isReasonable, t.updatedAt.isReasonable else {
        throw BackupArchiveError.invalid("固定餐字段无效。")
      }
      for i in t.items {
        try unique(i.id)
        guard i.isValid, (0..<BackupArchive.maxObjects).contains(i.orderIndex) else {
          throw BackupArchiveError.invalid("固定餐项目无效。")
        }
      }
    }
    for f in a.foodLogs {
      try unique(f.id)
      guard MealType(rawValue: f.mealTypeRaw) != nil, !f.name.trimmed.isEmpty,
        !f.servingDescription.trimmed.isEmpty, f.loggedAt.isReasonable,
        f.quantity.isFinite && f.quantity > 0,
        [f.calories, f.carbohydrates, f.protein, f.fat].allSatisfy({ $0.isValidNonnegativeNumber })
      else { throw BackupArchiveError.invalid("饮食记录无效。") }
    }
    for g in a.nutritionGoals {
      try unique(g.id)
      guard
        [g.calories, g.carbohydrates, g.protein, g.fat].allSatisfy({ $0.isValidNonnegativeNumber })
          && g.calories > 0 && g.updatedAt.isReasonable
      else { throw BackupArchiveError.invalid("营养目标无效。") }
    }
  }
  private static func validate(_ e: WorkoutExerciseDTO, ids: inout Set<UUID>) throws {
    try requireUnique(e.id, &ids)
    guard !e.sourceExerciseID.trimmed.isEmpty, !e.nameEnSnapshot.trimmed.isEmpty,
      !e.nameZhSnapshot.trimmed.isEmpty, (0..<BackupArchive.maxObjects).contains(e.orderIndex),
      TrackingMode(rawValue: e.trackingModeRaw) != nil
    else { throw BackupArchiveError.invalid("训练动作字段无效。") }
    for s in e.strengthSets {
      try requireUnique(s.id, &ids)
      guard (0..<BackupArchive.maxObjects).contains(s.orderIndex),
        s.weightKilograms.isFinite && (0...10_000).contains(s.weightKilograms),
        (0...100_000).contains(s.repetitions), (0...604_800).contains(s.durationSeconds)
      else { throw BackupArchiveError.invalid("训练组数值无效。") }
    }
    for c in e.cardioEntries {
      try requireUnique(c.id, &ids)
      guard c.durationSeconds >= 0 && c.durationSeconds <= 604_800,
        c.distanceKilometers.isFinite && (0...10_000).contains(c.distanceKilometers),
        c.calories.isFinite && (0...100_000).contains(c.calories)
      else { throw BackupArchiveError.invalid("有氧数值无效。") }
    }
  }
  private static func requireUnique(_ id: UUID, _ ids: inout Set<UUID>) throws {
    guard ids.insert(id).inserted else { throw BackupArchiveError.invalid("存在重复 ID。") }
  }
}

extension Date {
  fileprivate var isReasonable: Bool {
    timeIntervalSince1970 >= -2_208_988_800 && timeIntervalSince1970 <= 7_258_118_400
  }
}
extension FoodPresetDTO {
  fileprivate var numbersValid: Bool {
    [caloriesPerServing, carbohydratesPerServing, proteinPerServing, fatPerServing].allSatisfy {
      $0.isValidNonnegativeNumber
    }
  }
}

extension BackupArchiveService {
  fileprivate static func workout(_ x: Workout) -> WorkoutDTO {
    WorkoutDTO(
      id: x.id, title: x.title, startedAt: x.startedAt, endedAt: x.endedAt, statusRaw: x.statusRaw,
      notes: x.notes, routineNameSnapshot: x.routineNameSnapshot, restEndsAt: x.restEndsAt,
      exercises: x.exercises.map {
        WorkoutExerciseDTO(
          id: $0.id, sourceExerciseID: $0.sourceExerciseID, nameEnSnapshot: $0.nameEnSnapshot,
          nameZhSnapshot: $0.nameZhSnapshot, orderIndex: $0.orderIndex,
          trackingModeRaw: $0.trackingModeRaw, notes: $0.notes,
          strengthSets: $0.strengthSets.map {
            StrengthSetDTO(
              id: $0.id, orderIndex: $0.orderIndex, weightKilograms: $0.weightKilograms,
              repetitions: $0.repetitions, durationSeconds: $0.durationSeconds,
              isCompleted: $0.isCompleted)
          },
          cardioEntries: $0.cardioEntries.map {
            CardioEntryDTO(
              id: $0.id, durationSeconds: $0.durationSeconds,
              distanceKilometers: $0.distanceKilometers, calories: $0.calories)
          })
      })
  }
  fileprivate static func routine(_ x: Routine) -> RoutineDTO {
    RoutineDTO(
      id: x.id, name: x.name, notes: x.notes, createdAt: x.createdAt, updatedAt: x.updatedAt,
      exercises: x.exercises.map {
        RoutineExerciseDTO(
          id: $0.id, sourceExerciseID: $0.sourceExerciseID, nameEnSnapshot: $0.nameEnSnapshot,
          nameZhSnapshot: $0.nameZhSnapshot, orderIndex: $0.orderIndex,
          trackingModeRaw: $0.trackingModeRaw, defaultSetCount: $0.defaultSetCount,
          defaultRepetitions: $0.defaultRepetitions,
          defaultWeightKilograms: $0.defaultWeightKilograms,
          defaultDurationSeconds: $0.defaultDurationSeconds,
          defaultDistanceKilometers: $0.defaultDistanceKilometers)
      })
  }
  fileprivate static func foodPreset(_ x: FoodPreset) -> FoodPresetDTO {
    FoodPresetDTO(
      id: x.id, name: x.name, servingDescription: x.servingDescription,
      caloriesPerServing: x.caloriesPerServing, carbohydratesPerServing: x.carbohydratesPerServing,
      proteinPerServing: x.proteinPerServing, fatPerServing: x.fatPerServing,
      createdAt: x.createdAt, updatedAt: x.updatedAt)
  }
  fileprivate static func mealTemplate(_ x: MealTemplate) -> MealTemplateDTO {
    MealTemplateDTO(
      id: x.id, name: x.name, notes: x.notes, createdAt: x.createdAt, updatedAt: x.updatedAt,
      items: x.items.map {
        MealTemplateItemDTO(
          id: $0.id, orderIndex: $0.orderIndex, nameSnapshot: $0.nameSnapshot,
          servingDescriptionSnapshot: $0.servingDescriptionSnapshot, quantity: $0.quantity,
          caloriesPerServing: $0.caloriesPerServing,
          carbohydratesPerServing: $0.carbohydratesPerServing,
          proteinPerServing: $0.proteinPerServing, fatPerServing: $0.fatPerServing)
      })
  }
  fileprivate static func foodLog(_ x: FoodLogEntry) -> FoodLogDTO {
    FoodLogDTO(
      id: x.id, loggedAt: x.loggedAt, mealTypeRaw: x.mealTypeRaw, name: x.name,
      servingDescription: x.servingDescription, quantity: x.quantity, calories: x.calories,
      carbohydrates: x.carbohydrates, protein: x.protein, fat: x.fat,
      sourcePresetID: x.sourcePresetID, sourceMealTemplateID: x.sourceMealTemplateID)
  }
  fileprivate static func nutritionGoal(_ x: NutritionGoal) -> NutritionGoalDTO {
    NutritionGoalDTO(
      id: x.id, calories: x.calories, carbohydrates: x.carbohydrates, protein: x.protein,
      fat: x.fat, updatedAt: x.updatedAt)
  }
  fileprivate static func make(_ d: WorkoutDTO) -> Workout {
    let w = Workout(
      id: d.id, title: d.title, startedAt: d.startedAt, endedAt: d.endedAt,
      status: WorkoutStatus(rawValue: d.statusRaw)!, notes: d.notes,
      routineNameSnapshot: d.routineNameSnapshot)
    w.restEndsAt = d.restEndsAt
    w.exercises = d.exercises.map(make)
    w.exercises.forEach { $0.workout = w }
    return w
  }
  fileprivate static func make(_ d: WorkoutExerciseDTO) -> WorkoutExercise {
    let e = WorkoutExercise(
      id: d.id, sourceExerciseID: d.sourceExerciseID, nameEnSnapshot: d.nameEnSnapshot,
      nameZhSnapshot: d.nameZhSnapshot, orderIndex: d.orderIndex,
      trackingMode: TrackingMode(rawValue: d.trackingModeRaw)!, notes: d.notes)
    e.strengthSets = d.strengthSets.map {
      let s = StrengthSet(
        id: $0.id, orderIndex: $0.orderIndex, weightKilograms: $0.weightKilograms,
        repetitions: $0.repetitions, durationSeconds: $0.durationSeconds,
        isCompleted: $0.isCompleted)
      s.exercise = e
      return s
    }
    e.cardioEntries = d.cardioEntries.map {
      let c = CardioEntry(
        id: $0.id, durationSeconds: $0.durationSeconds, distanceKilometers: $0.distanceKilometers,
        calories: $0.calories)
      c.exercise = e
      return c
    }
    return e
  }
  fileprivate static func make(_ d: RoutineDTO) -> Routine {
    let r = Routine(
      id: d.id, name: d.name, notes: d.notes, createdAt: d.createdAt, updatedAt: d.updatedAt)
    r.exercises = d.exercises.map {
      let e = RoutineExercise(
        id: $0.id, sourceExerciseID: $0.sourceExerciseID, nameEnSnapshot: $0.nameEnSnapshot,
        nameZhSnapshot: $0.nameZhSnapshot, orderIndex: $0.orderIndex,
        trackingMode: TrackingMode(rawValue: $0.trackingModeRaw)!,
        defaultSetCount: $0.defaultSetCount, defaultRepetitions: $0.defaultRepetitions,
        defaultWeightKilograms: $0.defaultWeightKilograms,
        defaultDurationSeconds: $0.defaultDurationSeconds,
        defaultDistanceKilometers: $0.defaultDistanceKilometers)
      e.routine = r
      return e
    }
    return r
  }
  fileprivate static func make(_ d: FoodPresetDTO) -> FoodPreset {
    FoodPreset(
      id: d.id, name: d.name, servingDescription: d.servingDescription,
      caloriesPerServing: d.caloriesPerServing, carbohydratesPerServing: d.carbohydratesPerServing,
      proteinPerServing: d.proteinPerServing, fatPerServing: d.fatPerServing,
      createdAt: d.createdAt, updatedAt: d.updatedAt)
  }
  fileprivate static func make(_ d: MealTemplateDTO) -> MealTemplate {
    let t = MealTemplate(
      id: d.id, name: d.name, notes: d.notes, createdAt: d.createdAt, updatedAt: d.updatedAt)
    t.items = d.items.map {
      let i = MealTemplateItem(
        id: $0.id, orderIndex: $0.orderIndex, nameSnapshot: $0.nameSnapshot,
        servingDescriptionSnapshot: $0.servingDescriptionSnapshot, quantity: $0.quantity,
        caloriesPerServing: $0.caloriesPerServing,
        carbohydratesPerServing: $0.carbohydratesPerServing,
        proteinPerServing: $0.proteinPerServing, fatPerServing: $0.fatPerServing)
      i.template = t
      return i
    }
    return t
  }
  fileprivate static func make(_ d: FoodLogDTO) -> FoodLogEntry {
    FoodLogEntry(
      id: d.id, loggedAt: d.loggedAt, mealType: MealType(rawValue: d.mealTypeRaw)!, name: d.name,
      servingDescription: d.servingDescription, quantity: d.quantity, calories: d.calories,
      carbohydrates: d.carbohydrates, protein: d.protein, fat: d.fat,
      sourcePresetID: d.sourcePresetID, sourceMealTemplateID: d.sourceMealTemplateID)
  }
  fileprivate static func make(_ d: NutritionGoalDTO) -> NutritionGoal {
    NutritionGoal(
      id: d.id, calories: d.calories, carbohydrates: d.carbohydrates, protein: d.protein,
      fat: d.fat, updatedAt: d.updatedAt)
  }
}

extension RoutineExerciseDTO {
  fileprivate var hasValidDefaults: Bool {
    guard (1...100).contains(defaultSetCount), (0...100_000).contains(defaultRepetitions),
      defaultWeightKilograms.isFinite, (0...10_000).contains(defaultWeightKilograms),
      (0...604_800).contains(defaultDurationSeconds),
      defaultDistanceKilometers.isFinite, (0...10_000).contains(defaultDistanceKilometers)
    else { return false }
    return trackingModeRaw != TrackingMode.strength.rawValue
      && trackingModeRaw != TrackingMode.repetitions.rawValue || defaultRepetitions > 0
  }
}
