import Foundation
import SwiftData

/// Explicit export allowlist. Health samples, anchors, permissions, credentials and reports cannot appear here.
struct HealthManualBackup: Codable {
  var profiles: [BodyProfileValue]
  var weights: [ManualWeightValue]
  var checkIns: [CheckInValue]
  var dietCompleteness: [DietCompletenessValue]
  var goalRevisions: [NutritionGoalRevisionValue]
  var preferences: AnalysisPreferencesValue?

  var topIDs: Set<UUID> {
    Set(
      profiles.map(\.id) + weights.map(\.id) + checkIns.map(\.id)
        + dietCompleteness.map(\.id) + goalRevisions.map(\.id)
        + (preferences == nil ? [] : [AnalysisPreferences.singletonID]))
  }
  var childIDs: Set<UUID> { Set(checkIns.flatMap { $0.muscleFeedback.map(\.id) }) }
  var count: Int {
    profiles.count + weights.count + checkIns.count + dietCompleteness.count + goalRevisions.count
      + checkIns.reduce(0) { $0 + $1.muscleFeedback.count } + (preferences == nil ? 0 : 1)
  }
  @MainActor
  static func read(_ context: ModelContext) throws -> Self {
    let records = try SwiftDataAnalysisRepository.read(context)
    return .init(
      profiles: records.profiles, weights: records.weights, checkIns: records.checkIns,
      dietCompleteness: records.dietCompleteness, goalRevisions: records.goalRevisions,
      preferences: try context.fetch(FetchDescriptor<AnalysisPreferences>()).first?.value())
  }
  func matchingTypeIDs(_ existing: Self) -> Set<UUID> {
    var result = Set(profiles.map(\.id)).intersection(existing.profiles.map(\.id))
    result.formUnion(Set(weights.map(\.id)).intersection(existing.weights.map(\.id)))
    result.formUnion(Set(checkIns.map(\.id)).intersection(existing.checkIns.map(\.id)))
    result.formUnion(
      Set(dietCompleteness.map(\.id)).intersection(existing.dietCompleteness.map(\.id)))
    result.formUnion(Set(goalRevisions.map(\.id)).intersection(existing.goalRevisions.map(\.id)))
    if preferences != nil && existing.preferences != nil {
      result.insert(AnalysisPreferences.singletonID)
    }
    return result
  }
  func validate(ids: inout Set<UUID>) throws {
    func check(_ id: UUID) throws {
      guard ids.insert(id).inserted else { throw BackupArchiveError.invalid("存在重复 ID。") }
    }
    guard profiles.filter(\.isActive).count <= 1,
      Set(checkIns.map { $0.localDate + "|" + $0.timeZoneIdentifier }).count == checkIns.count,
      Set(dietCompleteness.map { $0.localDate + "|" + $0.timeZoneIdentifier }).count
        == dietCompleteness.count
    else { throw BackupArchiveError.invalid("档案或每日记录冲突。") }
    let proposals = goalRevisions.compactMap(\.proposalID)
    guard Set(proposals).count == proposals.count else {
      throw BackupArchiveError.invalid("目标建议重复。")
    }
    do {
      for item in profiles {
        try check(item.id)
        try ManualRecordValidation.validate(item)
      }
      for item in weights {
        try check(item.id)
        try ManualRecordValidation.validate(item)
      }
      for item in checkIns {
        try check(item.id)
        try ManualRecordValidation.validate(item)
        for feedback in item.muscleFeedback { try check(feedback.id) }
      }
      for item in dietCompleteness {
        try check(item.id)
        try ManualRecordValidation.validate(item)
      }
      for item in goalRevisions {
        try check(item.id)
        try ManualRecordValidation.validate(item)
        guard
          item.reversesRevisionID == nil
            || goalRevisions.contains(where: { $0.id == item.reversesRevisionID })
        else { throw AnalysisFailure.invalidInput }
      }
      if let preferences {
        try check(AnalysisPreferences.singletonID)
        try ManualRecordValidation.validate(preferences)
      }
    } catch { throw BackupArchiveError.invalid("健康手动记录字段无效或 ID 重复。") }
  }
  func preflight(existing: Self) throws {
    let newProfiles = profiles.filter { incoming in
      !existing.profiles.contains { $0.id == incoming.id }
    }
    guard !newProfiles.contains(where: \.isActive) || !existing.profiles.contains(where: \.isActive)
    else {
      throw BackupArchiveError.invalid("本机已有活动档案，无法导入另一个活动档案。")
    }
    for incoming in checkIns where !existing.checkIns.contains(where: { $0.id == incoming.id }) {
      guard
        !existing.checkIns.contains(where: {
          $0.localDate == incoming.localDate
            && $0.timeZoneIdentifier == incoming.timeZoneIdentifier
        })
      else {
        throw BackupArchiveError.invalid("同一天的体感记录冲突。")
      }
    }
    for incoming in dietCompleteness
    where !existing.dietCompleteness.contains(where: { $0.id == incoming.id }) {
      guard
        !existing.dietCompleteness.contains(where: {
          $0.localDate == incoming.localDate
            && $0.timeZoneIdentifier == incoming.timeZoneIdentifier
        })
      else {
        throw BackupArchiveError.invalid("同一天的饮食完整标记冲突。")
      }
    }
    for incoming in goalRevisions
    where !existing.goalRevisions.contains(where: { $0.id == incoming.id }) {
      guard
        incoming.proposalID == nil
          || !existing.goalRevisions.contains(where: { $0.proposalID == incoming.proposalID })
      else { throw BackupArchiveError.invalid("目标建议与本机记录冲突。") }
    }
  }
  @MainActor
  func insert(into context: ModelContext, existingIDs: Set<UUID>) throws -> (
    inserted: Int, skipped: Int
  ) {
    var inserted = 0
    var skipped = 0
    func add<T: PersistentModel>(_ id: UUID, count: Int = 1, make: () throws -> T) throws {
      if existingIDs.contains(id) {
        skipped += count
      } else {
        context.insert(try make())
        inserted += count
      }
    }
    for item in profiles { try add(item.id) { BodyProfile(value: item) } }
    for item in weights { try add(item.id) { BodyWeightEntry(value: item) } }
    for item in checkIns {
      try add(item.id, count: 1 + item.muscleFeedback.count) {
        let record = DailyCheckIn(value: item)
        record.muscleFeedback.forEach { $0.checkIn = record }
        return record
      }
    }
    for item in dietCompleteness { try add(item.id) { DietLogCompleteness(value: item) } }
    for item in goalRevisions { try add(item.id) { NutritionGoalRevision(value: item) } }
    if let preferences {
      try add(AnalysisPreferences.singletonID) { try AnalysisPreferences(value: preferences) }
    }
    return (inserted, skipped)
  }
}
