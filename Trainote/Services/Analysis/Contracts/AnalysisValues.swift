import Foundation

/// Wire and calculation boundaries contain values only, never SwiftData or HealthKit objects.
enum AnalysisContract {
  static let schemaVersion = 1
}

enum SetRole: String, Codable, CaseIterable, Sendable { case unknown, warmup, working }
enum DataQualityFlag: String, Codable, Sendable {
  case missing, insufficientHistory, partial, estimated, unknownExercise, unknownRIR
  case unknownSetRole, stale, readFailed, sourceConflict, requiresReview
}
enum AnalysisFailure: String, Error, Codable, Sendable {
  case unavailable, disconnected, readFailed, storageFailed, invalidInput, cancelled
  case consentRequired, consentChanged, unsupportedVersion, staleSnapshot
}
enum MetricUnit: String, Codable, Sendable {
  case kilograms, centimeters, kilocalories, grams, seconds, milliseconds, beatsPerMinute
  case count, percent, score, kilogramsPerWeek, percentPerWeek, none
}
struct AnalysisWindow: Codable, Equatable, Hashable, Sendable {
  var start: Date
  var end: Date
  func contains(_ date: Date) -> Bool { date >= start && date < end }
}
enum DataSourceKind: String, Codable, Sendable { case manual, healthKit, calculation }
struct DataSource: Codable, Equatable, Hashable, Sendable {
  var kind: DataSourceKind
  /// Stable source identifier; not a person's name or user-entered note.
  var identifier: String
  var version: String? = nil
  static let manual = DataSource(kind: .manual, identifier: "trainote.manual")
}
struct SourceDependency: Codable, Equatable, Hashable, Sendable {
  enum Kind: String, Codable, Sendable { case manualRecord, healthSample, metricFact }
  var kind: Kind
  var id: String
  var healthType: HealthDataType? = nil
}
struct DataCoverage: Codable, Equatable, Sendable {
  var field: String
  var observedDays: Int
  var expectedDays: Int
  var quality: [DataQualityFlag] = []
}
struct MetricFact: Codable, Equatable, Identifiable, Sendable {
  var id: String
  var metric: String
  var value: Double?
  var unit: MetricUnit
  var window: AnalysisWindow
  var sources: [DataSource]
  /// Includes transitive health dependencies when derived. Rebuild before a new AI report.
  var dependencies: [SourceDependency] = []
  var quality: [DataQualityFlag] = []
}

enum FormulaSex: String, Codable, Sendable { case male, female }
enum GoalDirection: String, Codable, Sendable { case maintain, lose, gain }
enum ActivityLevel: String, Codable, Sendable { case sedentary, light, moderate, high }
enum GoalMode: String, Codable, Sendable { case manual, suggested, automatic }
enum GoalRevisionOrigin: String, Codable, Sendable { case manual, suggested, automatic }
enum OverallFeeling: String, Codable, Sendable { case good, normal, tired }
enum SleepFeeling: String, Codable, Sendable { case good, normal, poor }
enum SorenessLevel: String, Codable, Sendable { case none, mild, significant }

struct BodyProfileValue: Codable, Equatable, Identifiable, Sendable {
  var id: UUID
  var isActive: Bool = true
  var heightCentimeters: Double? = nil
  var birthYear: Int? = nil
  var ageYears: Int? = nil
  var formulaSex: FormulaSex? = nil
  var activityLevel: ActivityLevel? = nil
  var goalDirection: GoalDirection? = nil
  var targetWeeklyChangePercent: Double? = nil
  var trainingDaysPerWeek: Int? = nil
  var bodyFatPercent: Double? = nil
  var waistCentimeters: Double? = nil
  /// A positive explicit eligibility answer is required by automatic calculators.
  var isAdultGeneralFitness: Bool? = nil
  var updatedAt: Date
}
struct ManualWeightValue: Codable, Equatable, Identifiable, Sendable {
  var id: UUID
  var measuredAt: Date
  var kilograms: Double
  var timeZoneIdentifier: String
  var createdAt: Date
  var updatedAt: Date
}
struct WeightSample: Codable, Equatable, Identifiable, Sendable {
  var id: UUID
  var measuredAt: Date
  var kilograms: Double
  var timeZoneIdentifier: String
  var source: DataSource
  var isUserSelected: Bool = false
}
struct MuscleFeedbackValue: Codable, Equatable, Identifiable, Sendable {
  var id: UUID
  var muscleID: MuscleID
  var soreness: SorenessLevel? = nil
  var hasPain: Bool? = nil
  var hasMovementLimitation: Bool? = nil
  var recordedAt: Date
}
struct CheckInValue: Codable, Equatable, Identifiable, Sendable {
  var id: UUID
  /// yyyy-MM-dd in the recorded timezone. Never silently move a historical answer on travel.
  var localDate: String
  var timeZoneIdentifier: String
  var feeling: OverallFeeling? = nil
  var sleepFeeling: SleepFeeling? = nil
  var muscleFeedback: [MuscleFeedbackValue] = []
  var updatedAt: Date
}
struct DietCompletenessValue: Codable, Equatable, Identifiable, Sendable {
  var id: UUID
  var localDate: String
  var timeZoneIdentifier: String
  var confirmedAt: Date
  var foodLogFingerprint: String
}
struct NutritionTargets: Codable, Equatable, Sendable {
  var calories: Double
  var carbohydrates: Double
  var protein: Double
  var fat: Double
}
struct NutritionGoalRevisionValue: Codable, Equatable, Identifiable, Sendable {
  var id: UUID
  var effectiveAt: Date
  var targets: NutritionTargets
  var origin: GoalRevisionOrigin
  var proposalID: String? = nil
  var calculationVersion: String? = nil
  var reversesRevisionID: UUID? = nil
  var createdAt: Date
}
struct WeightSelection: Codable, Equatable, Sendable {
  var localDate: String
  var timeZoneIdentifier: String
  var sampleID: UUID
  var source: DataSource
}
struct AnalysisPreferencesValue: Codable, Equatable, Sendable {
  var goalMode: GoalMode = .manual
  var pausedUntil: Date? = nil
  var preferredWeightSourceID: String? = nil
  var preferredHealthSourceIDs: [String] = []
  var weightSelections: [WeightSelection] = []
  var checkInPromptsEnabled: Bool = true
  var lastCheckInPromptDate: String? = nil
  var weeklyReviewEnabled: Bool = true
}
struct AnalysisSet: Codable, Equatable, Identifiable, Sendable {
  var id: UUID
  var orderIndex: Int
  var weightKilograms: Double
  var repetitions: Int
  var durationSeconds: Int
  var isCompleted: Bool
  var rir: Int? = nil
  var role: SetRole = .unknown
}
struct AnalysisExercise: Codable, Equatable, Identifiable, Sendable {
  var id: UUID
  var sourceExerciseID: String
  var trackingMode: String
  var sets: [AnalysisSet]
  var cardioDurationSeconds: Int = 0
}
struct AnalysisWorkout: Codable, Equatable, Identifiable, Sendable {
  var id: UUID
  var startedAt: Date
  var endedAt: Date?
  var isCompleted: Bool
  var routineName: String? = nil
  var exercises: [AnalysisExercise]
}
struct DailyNutrition: Codable, Equatable, Sendable {
  var localDate: String
  var timeZoneIdentifier: String
  var totals: NutritionTargets
  var logIDs: [UUID]
  var logFingerprint: String
  var isComplete: Bool
}
struct AnalysisInput: Codable, Equatable, Sendable {
  var schemaVersion: Int = AnalysisContract.schemaVersion
  var asOf: Date
  var calendarTimeZone: String
  var inputFingerprint: String
  var profile: BodyProfileValue? = nil
  var workouts: [AnalysisWorkout] = []
  var nutrition: [DailyNutrition] = []
  var weights: [WeightSample] = []
  var health: HealthSummary
  var checkIns: [CheckInValue] = []
  var goalHistory: [NutritionGoalRevisionValue] = []
  /// Existing manual target is preserved without inventing pre-upgrade target history.
  var currentManualTargets: NutritionTargets? = nil
  var preferences: AnalysisPreferencesValue = .init()
  var coverage: [DataCoverage] = []
}

struct TrendPoint: Codable, Equatable, Sendable {
  var date: Date
  var observedKilograms: Double?
  var smoothedKilograms: Double?
  var sampleIDs: [UUID]
}
struct GoalProposal: Codable, Equatable, Identifiable, Sendable {
  var id: String
  var effectiveAt: Date
  var targets: NutritionTargets
  var previousTargets: NutritionTargets?
  var reasonFactIDs: [String]
  var calculationVersion: String
}
enum TrendHoldReason: String, Codable, Sendable {
  case missingProfile, insufficientWeights, incompleteDiet, baselineBuilding, manualMode
  case paused, safetyBoundary, requiresReview, unchanged, readFailed
}
struct TrendResult: Codable, Equatable, Sendable {
  var inputFingerprint: String
  var points: [TrendPoint]
  var weeklyChangeKilograms: Double?
  var weeklyChangePercent: Double?
  var proposal: GoalProposal?
  var holdReason: TrendHoldReason?
  var facts: [MetricFact]
  var calculationVersion: String
}
struct RecoveryInfluence: Codable, Equatable, Sendable {
  var code: String
  var factIDs: [String]
  var dependencies: [SourceDependency] = []
}
struct MuscleRecovery: Codable, Equatable, Identifiable, Sendable {
  var muscleID: MuscleID
  var score: Double?
  var state: RecoveryState
  var hasPain: Bool = false
  var hasMovementLimitation: Bool = false
  var lastTrainedAt: Date? = nil
  var influences: [RecoveryInfluence] = []
  var coverage: [DataCoverage] = []
  var id: MuscleID { muscleID }
}
struct RecoveryResult: Codable, Equatable, Sendable {
  var inputFingerprint: String
  var asOf: Date
  var muscles: [MuscleRecovery]
  var systemicState: RecoveryState
  var systemicFactIDs: [String]
  var facts: [MetricFact]
  var calculationVersion: String
}
enum RecommendationAction: String, Codable, Sendable {
  case keepPlan, reduceSets, increaseRIR, swapTrainingDay, rest, lightActivity, choosePlan,
    reviewNutrition
}
struct AllowedParameter: Codable, Equatable, Sendable {
  var name: String
  var minimum: Double
  var maximum: Double
  var unit: MetricUnit
}
struct RecommendationCandidate: Codable, Equatable, Identifiable, Sendable {
  var actionID: String
  var action: RecommendationAction
  var muscleIDs: [MuscleID]
  var reasonFactIDs: [String]
  var allowedParameters: [AllowedParameter] = []
  var exclusionCodes: [String] = []
  var dependencies: [SourceDependency] = []
  var id: String { actionID }
}

enum ReportType: String, Codable, Sendable { case today, trend, recovery, weekly }
struct ReportInput: Codable, Equatable, Sendable {
  var schemaVersion: Int = AnalysisContract.schemaVersion
  var reportType: ReportType
  var asOf: Date
  var inputFingerprint: String
  var facts: [MetricFact]
  var candidates: [RecommendationCandidate]
  var goalDirection: GoalDirection?
  var knowledgeVersion: String
  var calculationVersions: [String]
  var missingData: [String]
}
struct ReportObservation: Codable, Equatable, Sendable {
  var text: String
  var evidenceIDs: [String]
}
struct ReportRecommendation: Codable, Equatable, Sendable {
  var text: String
  var actionID: String
}
struct ReportResult: Codable, Equatable, Identifiable, Sendable {
  var reportID: String
  var inputFingerprint: String
  var model: String
  var promptVersion: String
  var schemaVersion: Int = AnalysisContract.schemaVersion
  var summary: String
  var observations: [ReportObservation]
  var recommendations: [ReportRecommendation]
  var generatedAt: Date
  var validUntil: Date
  var isLocalFallback: Bool
  var id: String { reportID }
}

protocol TrendCalculating { func calculate(_ input: AnalysisInput) throws -> TrendResult }
protocol RecoveryCalculating { func calculate(_ input: AnalysisInput) throws -> RecoveryResult }
protocol RecommendationProviding {
  func candidates(input: AnalysisInput, trend: TrendResult, recovery: RecoveryResult) throws
    -> [RecommendationCandidate]
}
protocol ReportGenerating { func generate(_ input: ReportInput) async throws -> ReportResult }

@MainActor
protocol AnalysisRepository {
  func manualRecords() throws -> ManualHealthRecords
  func saveProfile(_ value: BodyProfileValue) throws
  func saveWeight(_ value: ManualWeightValue) throws
  func deleteWeight(id: UUID) throws
  func saveCheckIn(_ value: CheckInValue) throws
  func confirmDiet(_ value: DietCompletenessValue) throws
  func appendGoalRevision(_ value: NutritionGoalRevisionValue) throws
  func goalRevisionState() throws -> GoalRevisionState
  func applyGoalRevision(_ request: ApplyGoalRevisionRequest) throws -> GoalRevisionApplicationResult
  func savePreferences(_ value: AnalysisPreferencesValue) throws
  func analysisInput(
    asOf: Date, window: AnalysisWindow, timeZone: TimeZone,
    health: HealthDataSnapshot
  ) throws -> AnalysisInput
}
struct ManualHealthRecords: Codable, Equatable, Sendable {
  var profiles: [BodyProfileValue] = []
  var weights: [ManualWeightValue] = []
  var checkIns: [CheckInValue] = []
  var dietCompleteness: [DietCompletenessValue] = []
  var goalRevisions: [NutritionGoalRevisionValue] = []
  var preferences: AnalysisPreferencesValue = .init()
}
