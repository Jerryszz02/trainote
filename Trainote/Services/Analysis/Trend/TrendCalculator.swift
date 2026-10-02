import Foundation

/// Pure calculator for B/F and ReportSnapshotBuilder. No cache, clock, storage, or network reads.
struct TrendCalculator: TrendCalculating {
  let rules: TrendRules
  init(rules: TrendRules = .init()) { self.rules = rules }

  func calculate(_ input: AnalysisInput) throws -> TrendResult {
    guard input.schemaVersion == AnalysisContract.schemaVersion else {
      throw AnalysisFailure.unsupportedVersion
    }
    guard let calendar = TrendCalendar(identifier: input.calendarTimeZone),
      ManualRecordValidation.date(input.asOf)
    else { throw AnalysisFailure.invalidInput }
    let today = calendar.start(input.asOf)
    let tomorrow = calendar.adding(days: 1, to: today)
    let window = AnalysisWindow(
      start: calendar.adding(days: -rules.slopeWindowDays, to: today), end: today)
    let dietWindow = AnalysisWindow(
      start: calendar.adding(days: -rules.dietWindowDays, to: today), end: today)
    let days = try TrendWeightSeries.days(input: input, calendar: calendar, rules: rules)
    let points = TrendWeightSeries.points(days: days, rules: rules)
    let usable = days.filter(\.isUsable)
    let fitting = usable.filter { window.contains($0.date) }
    let slope = TrendWeightSeries.weeklySlope(fitting)
    let medianWeight = TrendWeightSeries.median(fitting.map(\.value))
    let rate = slope.flatMap { slope in medianWeight.map { slope / $0 * 100 } }
    var facts: [MetricFact] = []
    func fact(
      _ metric: String, _ value: Double?, _ unit: MetricUnit,
      window: AnalysisWindow, dependencies: [SourceDependency] = [],
      sources: [DataSource] = [], quality: [DataQualityFlag] = []
    ) throws -> MetricFact {
      var fact = MetricFact(
        id: "", metric: metric, value: value, unit: unit, window: window,
        sources: Array(Set(sources)).sorted {
          ($0.identifier, $0.version ?? "") < ($1.identifier, $1.version ?? "")
        },
        dependencies: Array(Set(dependencies)).sorted {
          ($0.kind.rawValue, $0.id) < ($1.kind.rawValue, $1.id)
        }, quality: quality)
      fact.id = "trend.\(metric)." + (try AnalysisFingerprint.digest(fact)).prefix(20)
      facts.append(fact)
      return fact
    }
    for day in days {
      _ = try fact(
        "weight.representative", day.value, .kilograms,
        window: .init(
          start: calendar.start(day.date),
          end: calendar.adding(days: 1, to: calendar.start(day.date))),
        dependencies: day.dependencies, sources: day.samples.map(\.source), quality: day.quality)
    }
    let weightDependencies = usable.flatMap(\.dependencies)
    let weightSources = usable.flatMap { $0.samples.map(\.source) }
    let latestWeight = points.last { $0.smoothedKilograms != nil }?.smoothedKilograms
    let weightFact = try fact(
      "weight.smoothed", latestWeight, .kilograms,
      window: .init(start: days.first.map { calendar.start($0.date) } ?? today, end: tomorrow),
      dependencies: weightDependencies, sources: weightSources,
      quality: latestWeight == nil ? [.missing] : [.estimated])
    let fitQuality: [DataQualityFlag] =
      fitting.count < rules.minimumWeightDays ? [.insufficientHistory] : []
    _ = try fact(
      "weight.weeklyChange", slope, .kilogramsPerWeek, window: window,
      dependencies: fitting.flatMap(\.dependencies),
      sources: fitting.flatMap { $0.samples.map(\.source) }, quality: fitQuality)
    let rateFact = try fact(
      "weight.weeklyChangePercent", rate, .percentPerWeek, window: window,
      dependencies: fitting.flatMap(\.dependencies),
      sources: fitting.flatMap { $0.samples.map(\.source) }, quality: fitQuality)
    let nutrition = try validNutrition(input.nutrition, calendar: calendar)
    let complete = nutrition.filter { entry in
      entry.isComplete && calendar.date(entry.localDate).map(dietWindow.contains) == true
    }
    let dietDependencies: [SourceDependency] = complete.flatMap(\.logIDs).map {
      .init(kind: .manualRecord, id: $0.uuidString)
    }
    let completeFact = try fact(
      "diet.completeDays", Double(complete.count), .count,
      window: dietWindow, dependencies: dietDependencies,
      sources: complete.isEmpty ? [] : [.manual],
      quality: complete.count < rules.minimumCompleteDietDays ? [.partial] : [])
    let averageIntake =
      complete.isEmpty ? nil : complete.map(\.totals.calories).reduce(0, +) / Double(complete.count)
    _ = try fact(
      "diet.calibratedIntakeReference", averageIntake, .kilocalories,
      window: dietWindow, dependencies: dietDependencies,
      sources: complete.isEmpty ? [] : [.manual],
      quality: complete.isEmpty ? [.missing] : [.estimated])
    // This is an observed intake reference; it is deliberately not an inferred TDEE.
    func result(_ hold: TrendHoldReason?, proposal: GoalProposal? = nil) -> TrendResult {
      .init(
        inputFingerprint: input.inputFingerprint, points: points,
        weeklyChangeKilograms: slope, weeklyChangePercent: rate,
        proposal: proposal, holdReason: hold, facts: facts, calculationVersion: rules.version)
    }
    if input.preferences.goalMode == .manual { return result(.manualMode) }
    if input.preferences.pausedUntil.map({ $0 > input.asOf }) == true { return result(.paused) }
    guard let profile = input.profile, profile.isActive,
      let height = profile.heightCentimeters, let sex = profile.formulaSex,
      let activity = profile.activityLevel, let direction = profile.goalDirection,
      profile.trainingDaysPerWeek != nil
    else { return result(.missingProfile) }
    try ManualRecordValidation.validate(profile)
    let year = calendar.calendar.component(.year, from: input.asOf)
    guard let age = profile.ageYears ?? profile.birthYear.map({ year - $0 }) else {
      return result(.missingProfile)
    }
    guard profile.isAdultGeneralFitness != nil else { return result(.missingProfile) }
    guard profile.isAdultGeneralFitness == true, rules.formulaAgeRange.contains(age) else {
      return result(.safetyBoundary)
    }
    guard let weight = latestWeight, let latestDay = usable.last else {
      return result(
        input.health.statuses.contains { $0.type == .bodyMass && $0.state == .failed }
          ? .readFailed : .insufficientWeights)
    }
    guard latestDay.date >= calendar.adding(days: -rules.reviewDays, to: today) else {
      return result(.insufficientWeights)
    }
    guard days.last?.isUsable != false else { return result(.requiresReview) }
    if weightSources.contains(where: { $0.kind == .healthKit }),
      input.health.statuses.contains(where: { $0.type == .bodyMass && $0.state == .failed })
    {
      return result(.readFailed)
    }
    let bmi = weight / pow(height / 100, 2)
    guard rules.generalFitnessBMI.contains(bmi) else { return result(.safetyBoundary) }
    let ree = 10 * weight + 6.25 * height - 5 * Double(age) + (sex == .male ? 5 : -161)
    let prior = ree * rules.activityFactor(activity)
    guard ree.isFinite, ree > 0 else { return result(.safetyBoundary) }
    let profileDependency = SourceDependency(kind: .manualRecord, id: profile.id.uuidString)
    let baselineDependencies = [profileDependency, .init(kind: .metricFact, id: weightFact.id)]
    let priorFact = try fact(
      "energy.initialEstimate", prior, .kilocalories,
      window: .init(start: today, end: tomorrow), dependencies: baselineDependencies,
      sources: weightSources + [.manual], quality: [.estimated])
    let history = TrendHistory.ordered(input.goalHistory.filter { $0.effectiveAt <= input.asOf })
    for revision in history { try ManualRecordValidation.validate(revision) }
    if let latest = history.last, latest.targets != input.currentManualTargets {
      return result(.requiresReview)
    }
    let analysisHistory = history.filter {
      $0.calculationVersion == rules.version && $0.reversesRevisionID == nil
    }
    let current = history.last?.targets ?? input.currentManualTargets
    if let current { try ManualRecordValidation.validate(current) }
    let targetRate = profile.targetWeeklyChangePercent ?? rules.targetRate(direction)
    // Explicit rates outside this initial general-fitness policy require manual review.
    guard targetRate.isFinite, rules.permits(rate: targetRate, direction: direction)
    else { return result(.safetyBoundary) }
    let targetFact = try fact(
      "weight.targetWeeklyChangePercent", targetRate, .percentPerWeek,
      window: .init(start: today, end: tomorrow), dependencies: [profileDependency],
      sources: [.manual])
    var reasonIDs = [weightFact.id, priorFact.id, targetFact.id]
    var calories = prior * rules.initialMultiplier(direction)
    let protein = weight * rules.proteinPerKilogram(direction)
    if let first = analysisHistory.first {
      // Shared v1 DTO has no historical profile snapshot. Never silently reconstruct it using a changed profile.
      if profile.updatedAt > first.createdAt { return result(.requiresReview) }
      guard let last = history.last, let current else { return result(.requiresReview) }
      if input.asOf < calendar.adding(days: rules.reviewDays, to: last.effectiveAt) {
        return result(last.reversesRevisionID == nil ? .baselineBuilding : .paused)
      }
      guard input.asOf >= calendar.adding(days: rules.reviewDays, to: profile.updatedAt) else {
        return result(.baselineBuilding)
      }
      // Complete calendar-day windows exclude the current unfinished day.
      let previousWeek = AnalysisWindow(
        start: calendar.adding(days: -14, to: today),
        end: calendar.adding(days: -7, to: today))
      let recentWeek = AnalysisWindow(start: previousWeek.end, end: today)
      guard fitting.count >= rules.minimumWeightDays,
        let firstWeight = fitting.first, let lastWeight = fitting.last,
        lastWeight.date.timeIntervalSince(firstWeight.date) / 86_400 >= rules.minimumSpanDays,
        fitting.filter({ previousWeek.contains($0.date) }).count >= rules.minimumWeightDaysPerWeek,
        fitting.filter({ recentWeek.contains($0.date) }).count >= rules.minimumWeightDaysPerWeek,
        let rate
      else { return result(.insufficientWeights) }
      guard complete.count >= rules.minimumCompleteDietDays else { return result(.incompleteDiet) }
      var correspondingTargets: [Double] = []
      var targetDependencies: [SourceDependency] = []
      for entry in complete {
        let dayEnd = calendar.adding(days: 1, to: calendar.date(entry.localDate)!)
          .addingTimeInterval(-0.001)
        guard let target = TrendHistory.effective(at: dayEnd, history: history) else {
          return result(.baselineBuilding)
        }
        correspondingTargets.append(target.targets.calories)
        targetDependencies.append(.init(kind: .manualRecord, id: target.id.uuidString))
      }
      let averageTarget = correspondingTargets.reduce(0, +) / Double(correspondingTargets.count)
      let adherence = averageIntake! / averageTarget - 1
      let adherenceFact = try fact(
        "diet.targetDifferencePercent", adherence * 100, .percent,
        window: dietWindow, dependencies: dietDependencies + targetDependencies, sources: [.manual])
      reasonIDs += [rateFact.id, completeFact.id, adherenceFact.id]
      guard abs(adherence) <= rules.adherenceTolerance + 1e-10 else {
        return result(.requiresReview)
      }
      let difference = targetRate - rate
      guard abs(difference) > rules.rateTolerance(direction) + 1e-10 else {
        return result(.unchanged)
      }
      let step = min(rules.maximumStepCalories, current.calories * rules.maximumStepFraction)
      calories = current.calories + (difference > 0 ? step : -step)
      // The first unrounded proposal preserves the formula prior as long as its profile is unchanged.
      let initialPrior = first.targets.calories / rules.initialMultiplier(direction)
      guard calories >= max(ree, initialPrior * rules.minimumPriorFraction) else {
        return result(.safetyBoundary)
      }
    } else if !history.isEmpty {
      // Existing manual revisions have real effective dates: recent edits get their full review period.
      if let last = history.last,
        input.asOf < calendar.adding(days: rules.reviewDays, to: last.effectiveAt)
      {
        return result(.baselineBuilding)
      }
    }
    guard calories >= max(ree, prior * rules.minimumPriorFraction),
      let targets = TrendNutrition.targets(
        calories: calories, protein: protein, fatFraction: rules.fatFraction)
    else { return result(.safetyBoundary) }
    // Whole input fingerprints include asOf/read bookkeeping. Proposal identity instead hashes the
    // normalized trend evidence and the effective local day, so reopening never creates a new adjustment.
    struct ProposalEvidence: Encodable {
      var effectiveAt: Date
      var timeZone: String
      var version: String
      var profile: BodyProfileValue
      var facts: [MetricFact]
      var history: [NutritionGoalRevisionValue]
      var targets: NutritionTargets
      var previous: NutritionTargets?
    }
    let evidence = ProposalEvidence(
      effectiveAt: today, timeZone: input.calendarTimeZone,
      version: rules.version, profile: profile, facts: facts, history: history,
      targets: targets, previous: current)
    let id = "trend-" + (try AnalysisFingerprint.digest(evidence))
    if history.contains(where: { $0.proposalID == id }) { return result(.unchanged) }
    return result(
      nil,
      proposal: .init(
        id: id, effectiveAt: today, targets: targets,
        previousTargets: current, reasonFactIDs: reasonIDs, calculationVersion: rules.version))
  }

  private func validNutrition(_ nutrition: [DailyNutrition], calendar: TrendCalendar) throws
    -> [DailyNutrition]
  {
    let inZone = nutrition.filter { calendar.matches($0.timeZoneIdentifier) }
    guard Set(inZone.map(\.localDate)).count == inZone.count else {
      throw AnalysisFailure.invalidInput
    }
    for day in inZone {
      guard calendar.date(day.localDate) != nil,
        [day.totals.calories, day.totals.carbohydrates, day.totals.protein, day.totals.fat]
          .allSatisfy({ $0.isFinite && $0 >= 0 })
      else { throw AnalysisFailure.invalidInput }
    }
    return inZone.sorted { $0.localDate < $1.localDate }
  }
}
