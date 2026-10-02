import XCTest

@testable import Trainote

enum TrendTestData {
  static let now = ISO8601DateFormatter().date(from: "2026-10-03T12:00:00Z")!
  static let calendar = TrendCalendar(identifier: "UTC")!
  static func date(_ day: Int, hour: Int = 8) -> Date {
    calendar.adding(days: day, to: calendar.start(now)).addingTimeInterval(Double(hour) * 3600)
  }
  static func targets(_ calories: Double = 2300) -> NutritionTargets {
    TrendNutrition.targets(calories: calories, protein: 140)!
  }
  static func weight(
    _ day: Int, value: Double = 70, index: Int? = nil,
    source: DataSource = .manual
  ) -> WeightSample {
    .init(
      id: AnalysisFixtures.id(index ?? 1000 + day + 100), measuredAt: date(day), kilograms: value,
      timeZoneIdentifier: "UTC", source: source)
  }
  static func input(rateKgPerDay: Double = 0, cold: Bool = false) -> AnalysisInput {
    let history = NutritionGoalRevisionValue(
      id: AnalysisFixtures.id(1500),
      effectiveAt: calendar.start(date(-40)), targets: targets(), origin: .suggested,
      proposalID: "initial-fixture", calculationVersion: TrendRules().version, createdAt: date(-40))
    return .init(
      asOf: now, calendarTimeZone: "UTC", inputFingerprint: "fixed-fixture",
      profile: .init(
        id: AnalysisFixtures.id(1501), heightCentimeters: 175, ageYears: 30,
        formulaSex: .male, activityLevel: .moderate, goalDirection: .lose,
        trainingDaysPerWeek: 3, isAdultGeneralFitness: true, updatedAt: date(-60)),
      nutrition: (-14 ... -1).map { day in
        .init(
          localDate: calendar.key(date(day)), timeZoneIdentifier: "UTC", totals: targets(),
          logIDs: [AnalysisFixtures.id(1600 + day)], logFingerprint: "log-\(day)", isComplete: true)
      },
      weights: (cold ? [0] : Array(-21...0)).map { day in
        weight(day, value: 70 + Double(day + 21) * rateKgPerDay)
      },
      health: .empty(window: .init(start: date(-90), end: now)),
      goalHistory: cold ? [] : [history], currentManualTargets: targets(),
      preferences: .init(goalMode: .suggested))
  }
}

final class TrendCalculatorTests: XCTestCase {
  let calculator = TrendCalculator()
  func testColdStartUsesFormulaAndKeepsInternalMacroPrecision() throws {
    let result = try calculator.calculate(TrendTestData.input(cold: true))
    let proposal = try XCTUnwrap(result.proposal)
    XCTAssertEqual(proposal.targets.calories, 1648.75 * 1.6 * 0.85, accuracy: 1e-8)
    XCTAssertEqual(proposal.targets.protein, 140)
    XCTAssertEqual(
      proposal.targets.calories,
      proposal.targets.protein * 4
        + proposal.targets.carbohydrates * 4 + proposal.targets.fat * 9, accuracy: 1e-8)
    let display = TrendNutrition.displayed(proposal.targets)
    XCTAssertLessThanOrEqual(
      abs(
        display.calories - 4 * display.protein
          - 4 * display.carbohydrates - 9 * display.fat), 13.5)
    XCTAssertNil(result.holdReason)
  }
  func testLossTooFastRaisesAndTooSlowLowersCalories() throws {
    let fast = try calculator.calculate(TrendTestData.input(rateKgPerDay: -0.08))
    let slow = try calculator.calculate(TrendTestData.input(rateKgPerDay: -0.02))
    XCTAssertEqual(try XCTUnwrap(fast.proposal).targets.calories, 2400)
    XCTAssertEqual(try XCTUnwrap(slow.proposal).targets.calories, 2200)
    XCTAssertLessThan(try XCTUnwrap(fast.weeklyChangePercent), -0.65)
    XCTAssertGreaterThan(try XCTUnwrap(slow.weeklyChangePercent), -0.35)
  }
  func testMaintainAndGainDirectionsAndTolerance() throws {
    var maintain = TrendTestData.input()
    maintain.profile?.goalDirection = .maintain
    XCTAssertEqual(try calculator.calculate(maintain).holdReason, .unchanged)
    var gain = TrendTestData.input()
    gain.profile?.goalDirection = .gain
    XCTAssertEqual(try XCTUnwrap(calculator.calculate(gain).proposal).targets.calories, 2400)
    let withinLoss = try calculator.calculate(TrendTestData.input(rateKgPerDay: -0.05))
    XCTAssertEqual(withinLoss.holdReason, .unchanged)
  }
  func testDailyRepresentativeSelectsOneSourceMorningAndExplicitRead() throws {
    var input = TrendTestData.input(cold: true)
    let source = DataSource(kind: .healthKit, identifier: "fixture.scale")
    input.preferences.preferredWeightSourceID = source.identifier
    var early = TrendTestData.weight(0, value: 69, index: 1801, source: source)
    early.measuredAt = TrendTestData.date(0, hour: 6)
    var later = TrendTestData.weight(0, value: 72, index: 1802, source: source)
    later.measuredAt = TrendTestData.date(0, hour: 10)
    input.weights += [early, later]
    var result = try calculator.calculate(input)
    XCTAssertEqual(result.points.count, 1)
    XCTAssertEqual(result.points[0].observedKilograms, 69)
    XCTAssertEqual(result.points[0].sampleIDs, [early.id])
    input.weights[0].isUserSelected = true
    result = try calculator.calculate(input)
    XCTAssertEqual(result.points[0].observedKilograms, 70)
    XCTAssertEqual(result.points[0].sampleIDs, [input.weights[0].id])
  }
  func testMedianWithoutMorningAndExplicitPreferencesReference() throws {
    var input = TrendTestData.input(cold: true)
    input.asOf = TrendTestData.date(0, hour: 23)
    input.weights = [70.0, 71, 79].enumerated().map { index, kg in
      var sample = TrendTestData.weight(0, value: kg, index: 1850 + index)
      sample.measuredAt = TrendTestData.date(0, hour: 15 + index)
      return sample
    }
    XCTAssertEqual(try calculator.calculate(input).points[0].observedKilograms, 71)
    input.preferences.weightSelections = [
      .init(
        localDate: TrendTestData.calendar.key(input.asOf),
        timeZoneIdentifier: "UTC", sampleID: input.weights[0].id, source: .manual)
    ]
    XCTAssertEqual(try calculator.calculate(input).points[0].observedKilograms, 70)
  }
  func testEMAUsesElapsedTimeAndMissingDaysAreNotZero() throws {
    var input = TrendTestData.input(cold: true)
    input.weights = [TrendTestData.weight(-7, value: 70), TrendTestData.weight(0, value: 72)]
    let result = try calculator.calculate(input)
    XCTAssertEqual(result.points.count, 2)
    XCTAssertEqual(
      try XCTUnwrap(result.points.last?.smoothedKilograms), 70 + (1 - exp(-1)) * 2, accuracy: 1e-8)
  }
  func testSlopeUsesTimeGapsAndRobustMedian() throws {
    var input = TrendTestData.input()
    let offsets = [-21, -18, -15, -14, -12, -10, -7, -5, -3, -1]
    input.weights = offsets.map { TrendTestData.weight($0, value: 70 + Double($0 + 21) * 0.02) }
    let result = try calculator.calculate(input)
    XCTAssertEqual(try XCTUnwrap(result.weeklyChangeKilograms), 0.14, accuracy: 1e-8)
    XCTAssertNotNil(result.proposal)
    input.weights[4].kilograms = 110
    let outlier = try calculator.calculate(input)
    XCTAssertEqual(try XCTUnwrap(outlier.weeklyChangeKilograms), 0.14, accuracy: 1e-8)
    XCTAssertEqual(outlier.points.count, offsets.count)
    XCTAssertNil(outlier.points[4].smoothedKilograms)
    XCTAssertTrue(
      outlier.facts.contains {
        $0.metric == "weight.representative" && $0.quality.contains(.requiresReview)
      })
  }
  func testSparseWeightsDietMissingAndWindowDistributionHold() throws {
    var input = TrendTestData.input()
    input.weights = [TrendTestData.weight(-20), TrendTestData.weight(-1)]
    XCTAssertEqual(try calculator.calculate(input).holdReason, .insufficientWeights)
    input = TrendTestData.input()
    input.nutrition.removeLast(3)
    XCTAssertEqual(try calculator.calculate(input).holdReason, .incompleteDiet)
    input = TrendTestData.input()
    input.weights.removeAll {
      $0.measuredAt >= TrendTestData.date(-6) && $0.measuredAt < TrendTestData.date(-1)
    }
    XCTAssertEqual(try calculator.calculate(input).holdReason, .insufficientWeights)
  }
  func testNoDietNeverMeansNoIntakeAndExplicitZeroDayIsPreserved() throws {
    var input = TrendTestData.input()
    input.nutrition = []
    let result = try calculator.calculate(input)
    XCTAssertNil(result.facts.first { $0.metric == "diet.calibratedIntakeReference" }?.value)
    XCTAssertEqual(result.holdReason, .incompleteDiet)
    input = TrendTestData.input()
    input.nutrition[0].totals = .init(calories: 0, carbohydrates: 0, protein: 0, fat: 0)
    let zero = try calculator.calculate(input)
    XCTAssertEqual(
      try XCTUnwrap(zero.facts.first { $0.metric == "diet.calibratedIntakeReference" }?.value),
      2300 * 13.0 / 14, accuracy: 1e-8)
  }
  func testAdherenceUsesHistoricalTargetAndDoesNotBackfillLegacyGoal() throws {
    var input = TrendTestData.input()
    input.nutrition[0].totals.calories = 10000
    XCTAssertEqual(try calculator.calculate(input).holdReason, .requiresReview)
    input = TrendTestData.input()
    input.goalHistory[0].effectiveAt = TrendTestData.date(-10)
    XCTAssertEqual(try calculator.calculate(input).holdReason, .baselineBuilding)
    XCTAssertNil(TrendHistory.effective(at: TrendTestData.date(-20), history: input.goalHistory))
  }
  func testModesPauseWeeklyCadenceAndChangedProfile() throws {
    var input = TrendTestData.input()
    input.preferences.goalMode = .manual
    XCTAssertEqual(try calculator.calculate(input).holdReason, .manualMode)
    input.preferences.goalMode = .automatic
    XCTAssertNotNil(try calculator.calculate(input).proposal)
    input.preferences.pausedUntil = TrendTestData.date(1)
    XCTAssertEqual(try calculator.calculate(input).holdReason, .paused)
    input.preferences.pausedUntil = nil
    input.goalHistory[0].effectiveAt = TrendTestData.date(-6)
    XCTAssertEqual(try calculator.calculate(input).holdReason, .baselineBuilding)
    input = TrendTestData.input()
    input.profile?.updatedAt = TrendTestData.date(-1)
    XCTAssertEqual(try calculator.calculate(input).holdReason, .requiresReview)
  }
  func testSafetyAndMissingInputsHaveExplicitHolds() throws {
    var input = TrendTestData.input(cold: true)
    input.profile?.isAdultGeneralFitness = nil
    XCTAssertEqual(try calculator.calculate(input).holdReason, .missingProfile)
    input.profile?.isAdultGeneralFitness = false
    XCTAssertEqual(try calculator.calculate(input).holdReason, .safetyBoundary)
    input.profile?.isAdultGeneralFitness = true
    input.profile?.ageYears = 16
    XCTAssertEqual(try calculator.calculate(input).holdReason, .safetyBoundary)
    input.profile?.ageYears = 30
    input.weights[0].kilograms = 140
    XCTAssertEqual(try calculator.calculate(input).holdReason, .safetyBoundary)
    input.weights = []
    input.health.statuses = [.init(type: .bodyMass, state: .failed, queriedAt: input.asOf)]
    XCTAssertEqual(try calculator.calculate(input).holdReason, .readFailed)
    XCTAssertNil(TrendNutrition.targets(calories: 500, protein: 200))
  }
  func testInitialPriorFloorAndStepLimitAreEnforced() throws {
    var input = TrendTestData.input()
    let later = NutritionGoalRevisionValue(
      id: AnalysisFixtures.id(1900), effectiveAt: TrendTestData.date(-10),
      targets: TrendTestData.targets(2200), origin: .suggested, proposalID: "second",
      calculationVersion: TrendRules().version,
      createdAt: TrendTestData.date(-10))
    input.goalHistory.append(later)
    input.currentManualTargets = later.targets
    XCTAssertEqual(try calculator.calculate(input).holdReason, .safetyBoundary)
  }
  func testSameEvidenceProducesSameProposalAcrossReopenAndInputOrder() throws {
    var input = TrendTestData.input()
    let first = try calculator.calculate(input)
    XCTAssertEqual(try calculator.calculate(input), first)
    input.inputFingerprint = "different-clock-bookkeeping"
    input.asOf.addTimeInterval(120)
    input.weights.reverse()
    input.nutrition.reverse()
    XCTAssertEqual(try calculator.calculate(input).proposal?.id, first.proposal?.id)
  }
  func testCrossTimezoneDaysAndDSTUseExplicitAnalysisZone() throws {
    var input = TrendTestData.input(cold: true)
    input.calendarTimeZone = "Asia/Shanghai"
    var first = TrendTestData.weight(-1, value: 70)
    first.measuredAt = ISO8601DateFormatter().date(from: "2026-10-02T17:00:00Z")!
    first.timeZoneIdentifier = "America/Los_Angeles"
    input.weights = [first, TrendTestData.weight(0, value: 71)]
    XCTAssertEqual(try calculator.calculate(input).points.count, 1)
    let calendar = TrendCalendar(identifier: "America/Los_Angeles")!
    let before = calendar.date("2026-03-08")!
    XCTAssertEqual(calendar.adding(days: 1, to: before).timeIntervalSince(before), 23 * 3600)
  }
  func testDependenciesCarryHealthSampleReferencesAndRemovedHealthIsRebuilt() throws {
    var input = TrendTestData.input(cold: true)
    input.weights[0].source = .init(kind: .healthKit, identifier: "fixture.scale")
    let result = try calculator.calculate(input)
    let weight = try XCTUnwrap(result.facts.first { $0.metric == "weight.smoothed" })
    XCTAssertEqual(weight.dependencies.first?.kind, .healthSample)
    XCTAssertEqual(weight.dependencies.first?.id, input.weights[0].id.uuidString)
    let estimate = try XCTUnwrap(result.facts.first { $0.metric == "energy.initialEstimate" })
    XCTAssertTrue(estimate.dependencies.contains { $0.kind == .metricFact && $0.id == weight.id })
    input.weights = []
    let withoutHealth = try calculator.calculate(input)
    XCTAssertNil(withoutHealth.proposal)
    XCTAssertFalse(
      withoutHealth.facts.contains { $0.dependencies.contains { $0.kind == .healthSample } })
  }
  func testWatchEnergyDoesNotChangeTargetsAndInvalidInputIsRejected() throws {
    var input = TrendTestData.input(cold: true)
    let target = try calculator.calculate(input).proposal?.targets
    input.health.facts = [
      .init(
        id: "watch", metric: "activeEnergy", value: 900, unit: .kilocalories,
        window: input.health.window, sources: [])
    ]
    XCTAssertEqual(try calculator.calculate(input).proposal?.targets, target)
    input.weights.append(input.weights[0])
    XCTAssertEqual(try calculator.calculate(input).points.count, 1)
    input.weights[1].kilograms = 80
    XCTAssertThrowsError(try calculator.calculate(input))
  }

  func testFivePercentCapAndExactlySevenDaysBetweenReviews() throws {
    var input = TrendTestData.input()
    input.profile?.heightCentimeters = 160
    input.profile?.formulaSex = .female
    input.profile?.activityLevel = .light
    input.weights = (-21...0).map {
      TrendTestData.weight($0, value: 54 - Double($0 + 21) * 0.07)
    }
    input.goalHistory[0].targets = TrendTestData.targets(1500)
    input.currentManualTargets = input.goalHistory[0].targets
    for index in input.nutrition.indices { input.nutrition[index].totals.calories = 1500 }
    let result = try calculator.calculate(input)
    XCTAssertEqual(try XCTUnwrap(result.proposal).targets.calories, 1575)
    var recent = input.goalHistory[0]
    recent.id = AnalysisFixtures.id(2400)
    recent.proposalID = "seven-day-review"
    recent.effectiveAt = TrendTestData.calendar.adding(days: -7, to: input.asOf)
    recent.createdAt = recent.effectiveAt
    input.goalHistory.append(recent)
    XCTAssertNotNil(try calculator.calculate(input).proposal)
    input.asOf.addTimeInterval(-1)
    XCTAssertEqual(try calculator.calculate(input).holdReason, .baselineBuilding)
  }

  func testNonFiniteAndFutureWeightsNeverEnterChartOrSlope() throws {
    var input = TrendTestData.input(cold: true)
    input.weights += [
      TrendTestData.weight(-2, value: .nan),
      TrendTestData.weight(-1, value: .infinity),
      TrendTestData.weight(1, value: 99),
    ]
    let result = try calculator.calculate(input)
    XCTAssertEqual(result.points.count, 1)
    XCTAssertEqual(result.points[0].observedKilograms, 70)
    XCTAssertNil(result.weeklyChangeKilograms)
  }

  func testConflictingCurrentProjectionHoldsInsteadOfOverwriting() throws {
    var input = TrendTestData.input()
    input.currentManualTargets = TrendTestData.targets(2100)
    XCTAssertEqual(try calculator.calculate(input).holdReason, .requiresReview)
  }

  func testFailedHealthReadHoldsHealthDerivedProposalButLeavesManualPathAvailable() throws {
    var input = TrendTestData.input(cold: true)
    input.health.statuses = [.init(type: .bodyMass, state: .failed, queriedAt: input.asOf)]
    XCTAssertNotNil(try calculator.calculate(input).proposal)
    input.weights[0].source = .init(kind: .healthKit, identifier: "fixture.scale")
    XCTAssertEqual(try calculator.calculate(input).holdReason, .readFailed)
  }

  func testIntakeComparesMeansOfTheSameHistoricalDays() throws {
    var input = TrendTestData.input()
    var next = input.goalHistory[0]
    next.id = AnalysisFixtures.id(2500)
    next.proposalID = "later-target"
    next.effectiveAt = TrendTestData.calendar.start(TrendTestData.date(-7))
    next.createdAt = next.effectiveAt
    next.targets = TrendTestData.targets(2400)
    input.goalHistory.append(next)
    input.currentManualTargets = next.targets
    for index in input.nutrition.indices {
      input.nutrition[index].totals.calories = index < 7 ? 2070 : 2640
    }
    let result = try calculator.calculate(input)
    let difference = try XCTUnwrap(
      result.facts.first { $0.metric == "diet.targetDifferencePercent" }?.value)
    XCTAssertEqual(difference, (2355.0 / 2350 - 1) * 100, accuracy: 1e-8)
  }
}
