import Foundation

enum ManualRecordValidation {
  static func date(_ value: Date) -> Bool {
    (-2_208_988_800...7_258_118_400).contains(value.timeIntervalSince1970)
  }
  static func day(_ value: String, zone: String) -> Bool {
    guard value.count == 10, let timeZone = TimeZone(identifier: zone) else { return false }
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = timeZone
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.isLenient = false
    guard let date = formatter.date(from: value) else { return false }
    return formatter.string(from: date) == value
  }
  static func validate(_ value: BodyProfileValue) throws {
    guard valid(value.heightCentimeters, in: 50...300),
      value.birthYear.map({ (1900...2200).contains($0) }) != false,
      value.ageYears.map({ (0...130).contains($0) }) != false,
      value.birthYear == nil || value.ageYears == nil,
      valid(value.targetWeeklyChangePercent, in: -5...5),
      value.trainingDaysPerWeek.map({ (0...7).contains($0) }) != false,
      valid(value.bodyFatPercent, in: 1...80), valid(value.waistCentimeters, in: 20...300),
      date(value.updatedAt)
    else { throw AnalysisFailure.invalidInput }
  }
  static func validate(_ value: ManualWeightValue) throws {
    guard valid(value.kilograms, in: 1...1000), date(value.measuredAt), date(value.createdAt),
      date(value.updatedAt), value.updatedAt >= value.createdAt,
      TimeZone(identifier: value.timeZoneIdentifier) != nil
    else { throw AnalysisFailure.invalidInput }
  }
  static func validate(_ value: CheckInValue) throws {
    guard day(value.localDate, zone: value.timeZoneIdentifier), date(value.updatedAt),
      Set(value.muscleFeedback.map(\.muscleID)).count == value.muscleFeedback.count,
      Set(value.muscleFeedback.map(\.id)).count == value.muscleFeedback.count,
      value.muscleFeedback.allSatisfy({ date($0.recordedAt) })
    else { throw AnalysisFailure.invalidInput }
  }
  static func validate(_ value: DietCompletenessValue) throws {
    guard day(value.localDate, zone: value.timeZoneIdentifier), date(value.confirmedAt),
      !value.foodLogFingerprint.isEmpty, value.foodLogFingerprint.count <= 128
    else {
      throw AnalysisFailure.invalidInput
    }
  }
  static func validate(_ value: NutritionTargets) throws {
    guard value.calories > 0,
      [value.calories, value.carbohydrates, value.protein, value.fat].allSatisfy({
        $0.isFinite && (0...100_000).contains($0)
      })
    else { throw AnalysisFailure.invalidInput }
  }
  static func validate(_ value: NutritionGoalRevisionValue) throws {
    try validate(value.targets)
    guard date(value.effectiveAt), date(value.createdAt), value.id != value.reversesRevisionID,
      value.proposalID?.isEmpty != true, (value.proposalID?.count ?? 0) <= 256,
      (value.calculationVersion?.count ?? 0) <= 128,
      value.origin == .manual || (value.proposalID != nil && value.calculationVersion != nil)
    else { throw AnalysisFailure.invalidInput }
  }
  static func validate(_ value: AnalysisPreferencesValue) throws {
    guard value.pausedUntil.map(date) != false,
      (value.preferredWeightSourceID?.count ?? 0) <= 255,
      value.preferredHealthSourceIDs.count <= 100,
      Set(value.preferredHealthSourceIDs).count == value.preferredHealthSourceIDs.count,
      value.preferredHealthSourceIDs.allSatisfy({ !$0.isEmpty && $0.count <= 255 }),
      value.weightSelections.count <= 10_000,
      Set(value.weightSelections.map { $0.localDate + "|" + $0.timeZoneIdentifier }).count
        == value.weightSelections.count,
      value.weightSelections.allSatisfy({
        day($0.localDate, zone: $0.timeZoneIdentifier) && $0.source.kind != .calculation
          && !$0.source.identifier.isEmpty && $0.source.identifier.count <= 255
      }),
      value.lastCheckInPromptDate.map({ day($0, zone: "UTC") }) != false
    else { throw AnalysisFailure.invalidInput }
  }
  private static func valid(_ value: Double?, in range: ClosedRange<Double>) -> Bool {
    value.map { $0.isFinite && range.contains($0) } ?? true
  }
}
