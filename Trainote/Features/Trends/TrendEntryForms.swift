import SwiftUI

struct TrendProfileForm: View {
  @Environment(\.dismiss) private var dismiss
  let model: TrendViewModel
  @State private var profile: BodyProfileValue
  @State private var height = ""
  @State private var age = ""
  @State private var useSuggested = false
  @State private var validationMessage: String?
  @State private var inputLocale = L10n.locale

  init(model: TrendViewModel) {
    self.model = model
    let value = model.input?.profile ?? .init(id: UUID(), updatedAt: model.now())
    _profile = State(initialValue: value)
    _height = State(initialValue: value.heightCentimeters.map { String(format: "%.0f", locale: L10n.locale, $0) } ?? "")
    let currentYear = model.calendar.calendar.component(.year, from: model.now())
    _age = State(
      initialValue: (value.ageYears ?? value.birthYear.map { currentYear - $0 }).map(String.init)
        ?? "")
    _useSuggested = State(initialValue: model.input?.profile == nil)
  }
  var body: some View {
    NavigationStack {
      Form {
        Section(L10n.text("health.trendentryforms.details.needed.for.calculation.c30175")) {
          TextField(L10n.text("health.trendentryforms.height.cm.034d28"), text: $height).keyboardType(.decimalPad)
            .accessibilityIdentifier("trend.profile.height")
          TextField(L10n.text("health.trendentryforms.age.28c02e"), text: $age).keyboardType(.numberPad)
            .accessibilityIdentifier("trend.profile.age")
          Picker(L10n.text("health.trendentryforms.sex.parameter.used.by.the.formula.4b1cf6"), selection: $profile.formulaSex) {
            Text(L10n.text("health.trendentryforms.leave.blank.for.now.8a0e34")).tag(Optional<FormulaSex>.none)
            Text(L10n.text("health.trendentryforms.male.parameter.bcc5f3")).tag(Optional(FormulaSex.male))
            Text(L10n.text("health.trendentryforms.female.parameter.98a7e6")).tag(Optional(FormulaSex.female))
          }
          Picker(L10n.text("health.trendentryforms.activity.level.cc69e0"), selection: $profile.activityLevel) {
            Text(L10n.text("health.trendentryforms.leave.blank.for.now.8a0e34")).tag(Optional<ActivityLevel>.none)
            Text(L10n.text("health.trendentryforms.sedentary.746954")).tag(Optional(ActivityLevel.sedentary))
            Text(L10n.text("health.trendentryforms.light.activity.4ca50d")).tag(Optional(ActivityLevel.light))
            Text(L10n.text("health.trendentryforms.moderate.activity.52a8b4")).tag(Optional(ActivityLevel.moderate))
            Text(L10n.text("health.trendentryforms.high.activity.7ba775")).tag(Optional(ActivityLevel.high))
          }
          Text(L10n.text("health.trendentryforms.activity.level.includes.daily.activity.and.6c52e3"))
            .font(.caption).foregroundStyle(.secondary)
          Picker(L10n.text("health.trendentryforms.training.days.per.week.abc26a"), selection: $profile.trainingDaysPerWeek) {
            Text(L10n.text("health.trendentryforms.leave.blank.for.now.8a0e34")).tag(Optional<Int>.none)
            ForEach(0...7, id: \.self) { Text(L10n.text("health.trendentryforms.days.d26a55", $0)).tag(Optional($0)) }
          }
        }
        Section(L10n.text("health.trendentryforms.body.goal.47f1d8")) {
          Picker(L10n.text("health.trendentryforms.goal.direction.4a9679"), selection: $profile.goalDirection) {
            Text(L10n.text("health.trendentryforms.leave.blank.for.now.8a0e34")).tag(Optional<GoalDirection>.none)
            Text(L10n.text("health.trendentryforms.maintain.weight.0da638")).tag(Optional(GoalDirection.maintain))
            Text(L10n.text("health.trendentryforms.lose.fat.170fab")).tag(Optional(GoalDirection.lose))
            Text(L10n.text("health.trendentryforms.gain.muscle.5ea5b9")).tag(Optional(GoalDirection.gain))
          }
          Picker(L10n.text("health.trendentryforms.eligibility.for.general.suggestions.99a3db"), selection: $profile.isAdultGeneralFitness) {
            Text(L10n.text("health.trendentryforms.not.confirmed.yet.0cb1a6")).tag(Optional<Bool>.none)
            Text(L10n.text("health.trendentryforms.adult.everyday.fitness.with.no.special.705c61")).tag(Optional(true))
            Text(L10n.text("health.trendentryforms.special.needs.or.unsure.d580ef")).tag(Optional(false))
          }
          Text(L10n.text("health.trendentryforms.for.pregnancy.breastfeeding.medical.conditions.or.7c0329"))
            .font(.caption).foregroundStyle(.secondary)
          if model.input?.profile == nil {
            Toggle(L10n.text("health.trendentryforms.use.suggestion.mode.after.saving.i.c29444"), isOn: $useSuggested)
          }
        }
        if let validationMessage { Text(L10n.text(validationMessage)).foregroundStyle(.red) }
      }
      .navigationTitle(L10n.text("health.trendentryforms.body.details.and.goals.704565"))
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button(L10n.text("health.trendentryforms.cancel.4d0b46")) { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button(L10n.text("health.trendentryforms.save.fadf24")) { save() }.accessibilityIdentifier("trend.profile.save")
        }
      }
    }
  }
  private func save() {
    guard height.isEmpty || DecimalInput.parse(height, locale: inputLocale) != nil, age.isEmpty || Int(age) != nil else {
      validationMessage = "health.trendentryforms.enter.a.valid.height.and.age.5b4353"
      return
    }
    profile.heightCentimeters = DecimalInput.parse(height, locale: inputLocale)
    profile.ageYears = Int(age)
    profile.birthYear = nil
    if profile.goalDirection != model.input?.profile?.goalDirection {
      profile.targetWeeklyChangePercent = nil
    }
    if var original = model.input?.profile {
      original.updatedAt = profile.updatedAt
      if original != profile { profile.updatedAt = model.now() }
    } else {
      profile.updatedAt = model.now()
    }
    do { try ManualRecordValidation.validate(profile) } catch {
      validationMessage = "health.trendentryforms.check.the.numeric.ranges.in.your.fb8b30"
      return
    }
    model.errorMessage = nil
    if model.saveProfile(profile) {
      if useSuggested { model.setMode(.suggested) }
      dismiss()
    } else {
      validationMessage = model.errorMessageKey
    }
  }
}

struct TrendWeightForm: View {
  @Environment(\.dismiss) private var dismiss
  let model: TrendViewModel
  let entry: ManualWeightValue?
  @State private var recordID: UUID
  @State private var date: Date
  @State private var kilograms: String
  @State private var validationMessage: String?
  @State private var inputLocale = L10n.locale

  init(model: TrendViewModel, entry: ManualWeightValue? = nil) {
    self.model = model
    self.entry = entry
    _recordID = State(initialValue: entry?.id ?? UUID())
    _date = State(initialValue: entry?.measuredAt ?? model.now())
    _kilograms = State(initialValue: entry.map { String(format: "%.1f", locale: L10n.locale, $0.kilograms) } ?? "")
  }
  var body: some View {
    NavigationStack {
      Form {
        DatePicker(L10n.text("health.trendentryforms.weigh.in.time.61905f"), selection: $date, in: ...model.now())
        TextField(L10n.text("health.trendentryforms.weight.kg.7df6f0"), text: $kilograms).keyboardType(.decimalPad)
          .accessibilityIdentifier("trend.weight.kilograms")
        Text(L10n.text("health.trendentryforms.this.is.a.manual.record.edit.8a757d"))
          .font(.caption).foregroundStyle(.secondary)
        if let validationMessage { Text(L10n.text(validationMessage)).foregroundStyle(.red) }
      }
      .navigationTitle(entry == nil ? L10n.text("health.trendentryforms.record.weight.158001") : L10n.text("health.trendentryforms.edit.weight.1a3a47"))
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button(L10n.text("health.trendentryforms.cancel.4d0b46")) { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button(L10n.text("health.trendentryforms.save.fadf24")) {
            guard let value = DecimalInput.parse(kilograms, locale: inputLocale), value.isFinite, (1...1000).contains(value) else {
              validationMessage = "health.trendentryforms.enter.a.valid.weight.in.kilograms.7c4573"
              return
            }
            model.errorMessage = nil
            if model.saveWeight(id: recordID, date: date, kilograms: value) {
              dismiss()
            } else {
              validationMessage = model.errorMessageKey
            }
          }.accessibilityIdentifier("trend.weight.save")
        }
      }
    }
  }
}

struct TrendWeightRecordsView: View {
  let model: TrendViewModel
  @State private var editing: ManualWeightValue?
  @State private var deletion: UUID?
  var body: some View {
    List {
      Section(L10n.text("health.trendentryforms.preferred.source.8cbeb9")) {
        Picker(
          L10n.text("health.trendentryforms.prefer.8c9728"),
          selection: Binding(
            get: {
              model.input?.preferences.preferredWeightSourceID ?? ""
            }, set: { model.preferSource($0.isEmpty ? nil : $0) })
        ) {
          Text(L10n.text("health.trendentryforms.automatic.manual.first.ea8efd")).tag("")
          ForEach(
            Array(Set(model.input?.weights.map { $0.source.identifier } ?? [])).sorted(), id: \.self
          ) {
            Text($0 == DataSource.manual.identifier ? L10n.text("health.trendentryforms.manual.2a4a4d") : $0).tag($0)
          }
        }
      }
      ForEach((model.input?.weights ?? []).sorted { $0.measuredAt > $1.measuredAt }) { sample in
        Section {
          LabeledContent(
            sample.measuredAt.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(L10n.locale)),
            value: String(format: "%.1f kg", locale: L10n.locale, sample.kilograms))
          Text(sample.source.kind == .manual ? L10n.text("health.trendentryforms.manual.records.d98299") : L10n.text("health.trendentryforms.apple.health.1c3cac", String(sample.source.identifier)))
            .font(.caption).foregroundStyle(.secondary)
          Text(L10n.text("health.trendentryforms.record.time.zone.cfb447", String(sample.timeZoneIdentifier))).font(.caption).foregroundStyle(.secondary)
          if sample.isUserSelected { Label(L10n.text("health.trendentryforms.selected.as.the.representative.daily.reading.89ad96"), systemImage: "checkmark") }
          if model.result?.points.contains(where: {
            $0.sampleIDs.contains(sample.id) && $0.smoothedKilograms == nil
          }) == true {
            Text(L10n.text("health.trendentryforms.outlier.awaiting.review.excluded.from.trend.92e23e")).foregroundStyle(.orange)
          }
          Button(L10n.text("health.trendentryforms.use.as.the.representative.daily.reading.20df50")) { model.selectWeight(sample) }
          if sample.source.kind == .manual,
            let manual = model.records.weights.first(where: { $0.id == sample.id })
          {
            Button(L10n.text("health.trendentryforms.edit.a7f814")) { editing = manual }
            Button(L10n.text("health.trendentryforms.delete.3755f5"), role: .destructive) { deletion = sample.id }
          }
        }
      }
    }
    .navigationTitle(L10n.text("health.trendentryforms.weight.records.and.sources.4351f2"))
    .sheet(item: $editing) { TrendWeightForm(model: model, entry: $0) }
    .confirmationDialog(
      L10n.text("health.trendentryforms.delete.this.manual.weight.record.c08a84"),
      isPresented: Binding(
        get: { deletion != nil },
        set: {
          if !$0 { deletion = nil }
        }), titleVisibility: .visible
    ) {
      Button(L10n.text("health.trendentryforms.delete.3755f5"), role: .destructive) {
        if let deletion { model.deleteWeight(deletion) }
        deletion = nil
      }
      Button(L10n.text("health.trendentryforms.cancel.4d0b46"), role: .cancel) { deletion = nil }
    }
  }
}
