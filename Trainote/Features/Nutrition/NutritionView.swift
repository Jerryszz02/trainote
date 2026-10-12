import SwiftData
import SwiftUI
import UIKit

private enum NutritionSheet: Identifiable {
  case addOptions
  case entry(FoodLogEntry?)
  case recentPicker
  case presetPicker
  case mealPicker
  case copyPicker

  var id: String {
    switch self {
    case .addOptions: "add-options"
    case .entry(let entry): "entry-\(entry?.id.uuidString ?? "new")"
    case .recentPicker: "recent-picker"
    case .presetPicker: "preset-picker"
    case .mealPicker: "meal-picker"
    case .copyPicker: "copy-picker"
    }
  }
}

/// 数字键盘上的“完成”按钮，Nutrition 与资料库表单共用。
struct NutritionKeyboardDoneToolbar: ToolbarContent {
  var body: some ToolbarContent {
    ToolbarItemGroup(placement: .keyboard) {
      Spacer()
      Button(L10n.text("core.done")) {
        UIApplication.shared.sendAction(
          #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
      }
    }
  }
}

struct NutritionView: View {
  @Environment(\.modelContext) private var modelContext

  @Query(sort: \FoodLogEntry.loggedAt, order: .reverse)
  private var entries: [FoodLogEntry]
  @Query private var dietConfirmations: [DietLogCompleteness]

  @State private var selectedDate = Date.now
  @State private var presentedSheet: NutritionSheet?
  @State private var pendingDeletion: FoodLogEntry?
  @State private var actionErrorMessage: L10n.Message?
  @State private var showEmptyDietConfirmation = false

  let addRequest: Int

  private var dayEntries: [FoodLogEntry] {
    entries.filter { Calendar.current.isDate($0.loggedAt, inSameDayAs: selectedDate) }
  }

  private var dayTotals: NutritionValues {
    NutritionMath.totals(of: dayEntries)
  }

  private var selectedDayKey: String {
    AnalysisFingerprint.localDate(selectedDate, timeZone: .current)
  }

  private var confirmedToday: Bool {
    guard let fingerprint = try? AnalysisFingerprint.foodLogs(dayEntries) else { return false }
    return dietConfirmations.contains {
      $0.localDate == selectedDayKey && $0.timeZoneIdentifier == TimeZone.current.identifier
        && $0.foodLogFingerprint == fingerprint
    }
  }

  var body: some View {
    List {
      Section {
        NavigationLink(L10n.text("core.favorite.foods.and.saved.meals"), destination: LibraryView(initialSection: .foods))
          .accessibilityIdentifier("nutrition.library")
      }
      Section {
        DatePicker(
          L10n.text("core.record.date"),
          selection: $selectedDate,
          displayedComponents: .date
        )
        .datePickerStyle(.compact)
      }

      daySummarySection

      ForEach(MealType.allCases) { mealType in
        mealSection(mealType)
      }

      if dayEntries.isEmpty {
        ContentUnavailableView(
          L10n.text("core.no.food.records.on.this.day"),
          systemImage: "fork.knife.circle",
          description: Text(L10n.text("core.tap.the.plus.button.at.the.top.right.to.log.food.directly.reuse.recent.records.choose"))
        )
        .frame(maxWidth: .infinity)
      }
    }
    .localizationTestControls()
    .navigationTitle(L10n.text("core.nutrition"))
    .onChange(of: addRequest, initial: true) { _, newValue in
      if newValue > 0 {
        selectedDate = .now
        presentedSheet = .addOptions
      }
    }
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button {
          presentedSheet = .addOptions
        } label: {
          Label(L10n.text("core.add.food"), systemImage: "plus")
        }
        .accessibilityIdentifier("nutrition.add")
        .accessibilityLabel(L10n.text("core.add.food"))
      }
    }
    .sheet(
      isPresented: Binding(
        get: { presentedSheet != nil },
        set: { if !$0 { presentedSheet = nil } }
      )
    ) {
      if let sheet = presentedSheet {
        switch sheet {
        case .addOptions:
          AddFoodOptionsSheet { presentedSheet = $0 }
        case .entry(let entry):
          FoodEntryEditor(date: selectedDate, entry: entry)
        case .recentPicker:
          RecentFoodPickerSheet(selectedDate: selectedDate)
        case .presetPicker:
          FoodPresetLogSheet(selectedDate: selectedDate)
        case .mealPicker:
          MealTemplateLogSheet(selectedDate: selectedDate)
        case .copyPicker:
          CopyMealSheet(selectedDate: selectedDate)
        }
      }
    }
    .alert(L10n.text("core.delete.this.food.record"), isPresented: deletionAlertBinding, presenting: pendingDeletion) { entry in
      Button(L10n.text("core.delete"), role: .destructive) {
        delete(entry)
      }
      Button(L10n.text("core.cancel"), role: .cancel) { pendingDeletion = nil }
    } message: { _ in
      Text(L10n.text("core.nutrition.totals.for.this.day.will.update.immediately"))
    }
    .alert(L10n.text("core.action.failed"), isPresented: actionErrorBinding) {
      Button(L10n.text("core.ok.201"), role: .cancel) { actionErrorMessage = nil }
    } message: {
      Text(actionErrorMessage?.text ?? "")
    }
    .confirmationDialog(
      L10n.text("core.no.food.records.on.this.day.279"), isPresented: $showEmptyDietConfirmation, titleVisibility: .visible
    ) {
      Button(L10n.text("core.confirm.no.intake.and.mark.complete")) { confirmSelectedDay() }
      Button(L10n.text("core.keep.logging"), role: .cancel) {}
    } message: {
      Text(L10n.text("core.missing.records.are.not.automatically.treated.as.0.kcal.use.this.only.when.you.confir"))
    }
  }

  private var daySummarySection: some View {
    Section(L10n.text("core.daily.nutrition")) {
      summaryRow(L10n.text("core.calories.284"), value: dayTotals.calories, unit: "kcal")
      summaryRow(L10n.text("core.carbs"), value: dayTotals.carbohydrates, unit: "g")
      summaryRow(L10n.text("core.protein"), value: dayTotals.protein, unit: "g")
      summaryRow(L10n.text("core.fat"), value: dayTotals.fat, unit: "g")
      if !dayEntries.isEmpty && dayTotals.isAllZero {
        Text(L10n.text("core.no.nutrition.values.in.this.day.s.records"))
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      if confirmedToday {
        Label(L10n.text("core.food.records.for.this.date.confirmed.complete"), systemImage: "checkmark.circle.fill")
          .foregroundStyle(.green)
          .accessibilityIdentifier("nutrition.dietComplete")
      } else {
        Button(L10n.text("core.confirm.food.records.for.this.date.are.complete")) {
          if dayEntries.isEmpty { showEmptyDietConfirmation = true }
          else { confirmSelectedDay() }
        }
        .disabled(selectedDayKey > AnalysisFingerprint.localDate(.now, timeZone: .current))
        .accessibilityIdentifier("nutrition.confirmDiet")
        Text(L10n.text("core.confirm.again.after.editing.food.records.trends.include.only.the.14.days.through.yest"))
          .font(.caption).foregroundStyle(.secondary)
      }
    }
  }

  private func summaryRow(_ title: String, value: Double, unit: String) -> some View {
    LabeledContent(title) {
      Text("\(NutritionFormatting.number(value)) \(unit)")
        .monospacedDigit()
        .foregroundStyle(value == 0 ? .secondary : .primary)
    }
  }

  @ViewBuilder
  private func mealSection(_ mealType: MealType) -> some View {
    let mealEntries = dayEntries.filter { $0.mealType == mealType }
    if !mealEntries.isEmpty {
      let totals = NutritionMath.totals(of: mealEntries)
      Section {
        ForEach(mealEntries) { entry in
          Button {
            presentedSheet = .entry(entry)
          } label: {
            FoodLogRow(entry: entry)
              .frame(maxWidth: .infinity, alignment: .leading)
              .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .swipeActions {
            Button(L10n.text("core.delete"), role: .destructive) { pendingDeletion = entry }
          }
        }
      } header: {
        HStack {
          Label(mealType.title, systemImage: mealType.systemImage)
          Spacer()
          if totals.isAllZero {
            Text(L10n.text("core.nutrition.values.not.entered"))
          } else {
            Text("\(NutritionFormatting.number(totals.calories, fraction: 0)) kcal")
              .monospacedDigit()
          }
        }
      }
    }
  }

  private var deletionAlertBinding: Binding<Bool> {
    Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } })
  }

  private var actionErrorBinding: Binding<Bool> {
    Binding(get: { actionErrorMessage != nil }, set: { if !$0 { actionErrorMessage = nil } })
  }

  private func delete(_ entry: FoodLogEntry) {
    modelContext.delete(entry)
    do {
      try modelContext.save()
      pendingDeletion = nil
    } catch {
      modelContext.rollback()
      pendingDeletion = nil
      actionErrorMessage = L10n.Message(resolving: { L10n.text("core.delete.failed.please.try.again" , String(describing: error.localizedDescription)) })
    }
  }

  private func confirmSelectedDay() {
    do {
      let fingerprint = try AnalysisFingerprint.foodLogs(dayEntries)
      let zone = TimeZone.current.identifier
      let existing = dietConfirmations.first {
        $0.localDate == selectedDayKey && $0.timeZoneIdentifier == zone
      }
      let value = DietCompletenessValue(
        id: existing?.id ?? UUID(), localDate: selectedDayKey,
        timeZoneIdentifier: zone, confirmedAt: .now, foodLogFingerprint: fingerprint)
      try ManualRecordValidation.validate(value)
      if let existing { existing.apply(value) }
      else { modelContext.insert(DietLogCompleteness(value: value)) }
      try modelContext.save()
    } catch {
      modelContext.rollback()
      actionErrorMessage = L10n.Message(resolving: { L10n.text("core.could.not.confirm.complete.food.records.please.try.again") })
    }
  }
}

private struct AddFoodOptionsSheet: View {
  @Environment(\.dismiss) private var dismiss

  let onSelect: (NutritionSheet) -> Void

  var body: some View {
    NavigationStack {
      List {
        Section {
          optionButton(
            L10n.text("core.log.directly"), systemImage: "square.and.pencil",
            detail: L10n.text("core.enter.food.and.nutrition.manually"), accessibilityIdentifier: "nutrition.add.direct"
          ) { onSelect(.entry(nil)) }
          optionButton(
            L10n.text("core.recent.records"), systemImage: "clock.arrow.circlepath",
            detail: L10n.text("core.choose.a.food.you.ve.logged.and.adjust.the.portion"), accessibilityIdentifier: "nutrition.add.recent"
          ) { onSelect(.recentPicker) }
          optionButton(
            L10n.text("core.favorite.foods"), systemImage: "star.fill",
            detail: L10n.text("core.quickly.log.a.favorite.food"), accessibilityIdentifier: "nutrition.add.preset"
          ) { onSelect(.presetPicker) }
          optionButton(
            L10n.text("core.saved.meals"), systemImage: "list.bullet.rectangle",
            detail: L10n.text("core.log.a.full.meal.and.adjust.each.portion"), accessibilityIdentifier: "nutrition.add.meal"
          ) { onSelect(.mealPicker) }
          optionButton(
            L10n.text("core.copy.a.meal"), systemImage: "doc.on.doc",
            detail: L10n.text("core.copy.a.meal.from.another.date"), accessibilityIdentifier: "nutrition.add.copy"
          ) { onSelect(.copyPicker) }
        } footer: {
          Text(L10n.text("core.every.option.shows.a.nutrition.preview.before.saving"))
        }
      }
      .localizationTestControls()
    .navigationTitle(L10n.text("core.add.food"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(L10n.text("core.cancel")) { dismiss() }
            .accessibilityIdentifier("nutrition.add.cancel")
        }
      }
    }
  }

  private func optionButton(
    _ title: String,
    systemImage: String,
    detail: String,
    accessibilityIdentifier: String,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      HStack(spacing: 12) {
        Image(systemName: systemImage)
          .foregroundStyle(.tint)
          .frame(width: 24)
        VStack(alignment: .leading, spacing: 3) {
          Text(title)
          Text(detail)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier(accessibilityIdentifier)
  }
}

private struct FoodLogRow: View {
  let entry: FoodLogEntry

  private var nutrition: NutritionValues {
    NutritionValues(
      calories: entry.calories,
      carbohydrates: entry.carbohydrates,
      protein: entry.protein,
      fat: entry.fat
    )
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 5) {
      HStack {
        Text(entry.name).font(.body.weight(.medium))
        Spacer()
        Text("\(NutritionFormatting.number(entry.calories, fraction: 0)) kcal")
          .font(.subheadline.monospacedDigit())
      }
      Text(
        "\(NutritionFormatting.number(entry.quantity, fraction: 2)) × \(entry.servingDescription)"
      )
      .font(.caption)
      .foregroundStyle(.secondary)
      if nutrition.isAllZero {
        Text(L10n.text("core.nutrition.values.not.entered"))
          .font(.caption2)
          .foregroundStyle(.orange)
      } else {
        Text(
          L10n.text("core.carbs.g.protein.g.fat.g" , String(describing: NutritionFormatting.number(entry.carbohydrates)), String(describing: NutritionFormatting.number(entry.protein)), String(describing: NutritionFormatting.number(entry.fat)))
        )
        .font(.caption2)
        .foregroundStyle(.tertiary)
      }
    }
    .contentShape(Rectangle())
    .accessibilityElement(children: .combine)
  }
}

private struct FoodEntryEditor: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext

  let entry: FoodLogEntry?

  @State private var draft: FoodNutritionDraft
  @State private var mealType: MealType
  @State private var loggedAt: Date
  @State private var saveAsPreset = false
  @State private var errorMessage: L10n.Message?

  init(date: Date, entry: FoodLogEntry?) {
    self.entry = entry
    if let entry {
      _draft = State(initialValue: .fromEntry(entry))
      _mealType = State(initialValue: entry.mealType)
      _loggedAt = State(initialValue: entry.loggedAt)
    } else {
      _draft = State(initialValue: FoodNutritionDraft())
      _mealType = State(initialValue: MealType.defaultForTime())
      _loggedAt = State(initialValue: date.withCurrentTime())
    }
  }

  private var isValid: Bool { draft.isValid }

  var body: some View {
    NavigationStack {
      Form {
        Section(L10n.text("core.food")) {
          TextField(L10n.text("core.name"), text: $draft.name)
            .accessibilityIdentifier("nutrition.entry.name")
          Picker(
            L10n.text("core.nutrition.basis"),
            selection: Binding(get: { draft.inputMode }, set: { draft.changeInputMode(to: $0) })
          ) {
            ForEach(PortionInputMode.allCases) { Text($0.title).tag($0) }
          }
          .modifier(CoreAdaptivePickerStyle())
          .accessibilityIdentifier("nutrition.entry.basis")
          if draft.inputMode == .perServing {
            TextField(L10n.text("core.portion.description"), text: $draft.servingDescription)
              .accessibilityIdentifier("nutrition.entry.serving")
          } else {
            LabeledContent(L10n.text("core.portion.description")) {
              Text(FoodPortionMath.per100gServingDescription)
                .foregroundStyle(.secondary)
            }
          }
          LabeledContent(draft.inputMode.amountTitle) {
            StableNumberField("1", value: $draft.amount, format: .number.precision(.fractionLength(0...2)).locale(L10n.locale))
              .keyboardType(.decimalPad)
              .multilineTextAlignment(.trailing)
              .accessibilityIdentifier("nutrition.entry.amount")
          }
          Picker(L10n.text("core.meal"), selection: $mealType) {
            ForEach(MealType.allCases) { Text($0.title).tag($0) }
          }
          DatePicker(
            L10n.text("core.record.time"),
            selection: $loggedAt,
            displayedComponents: [.date, .hourAndMinute]
          )
          .accessibilityIdentifier("nutrition.entry.loggedAt")
        }

        Section {
          LabeledContent(L10n.text("core.calories"), value: "\(NutritionFormatting.number(draft.perUnit.calories)) kcal")
            .accessibilityIdentifier("nutrition.entry.perUnit.calories")
          perUnitField(L10n.text("core.carbs"), nutrient: .carbohydrates, unit: "g")
          perUnitField(L10n.text("core.protein"), nutrient: .protein, unit: "g")
          perUnitField(L10n.text("core.fat"), nutrient: .fat, unit: "g")
        } header: {
          Text(draft.inputMode.nutrientSectionTitle)
        } footer: {
          Text(NutritionMath.calorieCalculationNote)
        }

        Section {
          LabeledContent(L10n.text("core.calories"), value: "\(NutritionFormatting.number(draft.totals.calories)) kcal")
            .accessibilityIdentifier("nutrition.entry.total.calories")
          totalField(L10n.text("core.carbs"), nutrient: .carbohydrates, unit: "g")
          totalField(L10n.text("core.protein"), nutrient: .protein, unit: "g")
          totalField(L10n.text("core.fat"), nutrient: .fat, unit: "g")
          Text(previewText)
            .font(.footnote)
            .foregroundStyle(.secondary)
        } header: {
          Text(L10n.text("core.nutrition.totals.for.this.entry.editable"))
        } footer: {
          Text(L10n.text("core.changing.the.portion.scales.nutrition.using.the.current.unit.values.after.editing.tot"))
        }

        if entry == nil {
          Section {
            Toggle(L10n.text("core.also.save.as.a.favorite.food"), isOn: $saveAsPreset)
              .accessibilityIdentifier("nutrition.entry.savePreset")
          } footer: {
            Text(L10n.text("core.favorite.food.will.be.saved" , String(describing: draft.inputMode == .per100g ? L10n.text("core.per.100.grams") : L10n.text("core.per.serving"))))
          }
        }
      }
      .localizationTestControls()
    .navigationTitle(entry == nil ? L10n.text("core.log.food") : L10n.text("core.edit.food.record"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(L10n.text("core.cancel")) { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button(L10n.text("core.save"), action: save)
            .disabled(!isValid)
            .accessibilityIdentifier("nutrition.entry.save")
        }
        NutritionKeyboardDoneToolbar()
      }
      .alert(L10n.text("core.save.failed"), isPresented: errorBinding) {
        Button(L10n.text("core.ok.201"), role: .cancel) { errorMessage = nil }
      } message: {
        Text(errorMessage?.text ?? "")
      }
    }
  }

  private var previewText: String {
    let totals = draft.totals
    guard totals.isFinite else { return L10n.text("core.totals.preview.values.are.out.of.range.check.your.input") }
    return
      L10n.text("core.totals.preview.kcal.carbs.g.protein.g.fat.g" , String(describing: NutritionFormatting.number(totals.calories)), String(describing: NutritionFormatting.number(totals.carbohydrates)), String(describing: NutritionFormatting.number(totals.protein)), String(describing: NutritionFormatting.number(totals.fat)))
  }

  private func perUnitField(_ title: String, nutrient: NutrientKind, unit: String) -> some View {
    LabeledContent(title) {
      HStack {
        StableNumberField(
          "0",
          value: Binding(
            get: { draft.perUnit.value(for: nutrient) },
            set: { draft.perUnit.setValue($0, for: nutrient) }
          ),
          format: .number.precision(.fractionLength(0...2)).locale(L10n.locale)
        )
        .keyboardType(.decimalPad)
        .multilineTextAlignment(.trailing)
        .accessibilityIdentifier("nutrition.entry.perUnit.\(nutrient.rawValue)")
        Text(unit).foregroundStyle(.secondary)
      }
    }
  }

  private func totalField(_ title: String, nutrient: NutrientKind, unit: String) -> some View {
    LabeledContent(title) {
      HStack {
        StableNumberField(
          "0",
          value: Binding(
            get: { draft.totals.value(for: nutrient) },
            set: { draft.setTotal(nutrient, to: $0) }
          ),
          format: .number.precision(.fractionLength(0...2)).locale(L10n.locale)
        )
        .keyboardType(.decimalPad)
        .multilineTextAlignment(.trailing)
        .accessibilityIdentifier("nutrition.entry.total.\(nutrient.rawValue)")
        Text(unit).foregroundStyle(.secondary)
      }
    }
  }

  private var errorBinding: Binding<Bool> {
    Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
  }

  private func save() {
    guard draft.isValid else {
      errorMessage = L10n.Message(resolving: { L10n.text("core.check.the.name.portion.and.nutrition.values.values.must.be.finite.and.nonnegative.and") })
      return
    }
    let totals = draft.totals
    let quantity = draft.canonicalQuantity

    if let entry {
      let original = FoodLogEditorSnapshot(entry: entry)
      entry.loggedAt = loggedAt
      entry.mealType = mealType
      entry.name = draft.name.trimmed
      entry.servingDescription = draft.canonicalServingDescription
      entry.quantity = quantity
      entry.calories = totals.calories
      entry.carbohydrates = totals.carbohydrates
      entry.protein = totals.protein
      entry.fat = totals.fat
      do {
        try modelContext.save()
        dismiss()
      } catch {
        original.restore(into: entry)
        errorMessage = L10n.Message(resolving: { L10n.text("core.save.failed.your.changes.are.still.in.the.form.please.try.again" , String(describing: error.localizedDescription)) })
      }
    } else {
      let newEntry = draft.makeEntry(loggedAt: loggedAt, mealType: mealType)
      modelContext.insert(newEntry)
      var insertedPreset: FoodPreset?
      if saveAsPreset {
        let preset = FoodPreset(
          name: draft.name.trimmed,
          servingDescription: draft.canonicalServingDescription,
          caloriesPerServing: draft.perUnit.calories,
          carbohydratesPerServing: draft.perUnit.carbohydrates,
          proteinPerServing: draft.perUnit.protein,
          fatPerServing: draft.perUnit.fat
        )
        modelContext.insert(preset)
        insertedPreset = preset
      }
      do {
        try modelContext.save()
        dismiss()
      } catch {
        modelContext.delete(newEntry)
        if let insertedPreset { modelContext.delete(insertedPreset) }
        errorMessage = L10n.Message(resolving: { L10n.text("core.save.failed.your.input.is.still.in.the.form.please.try.again" , String(describing: error.localizedDescription)) })
      }
    }
  }
}

private struct FoodLogEditorSnapshot {
  let loggedAt: Date
  let mealTypeRaw: String
  let name: String
  let servingDescription: String
  let quantity: Double
  let calories: Double
  let carbohydrates: Double
  let protein: Double
  let fat: Double

  init(entry: FoodLogEntry) {
    loggedAt = entry.loggedAt
    mealTypeRaw = entry.mealTypeRaw
    name = entry.name
    servingDescription = entry.servingDescription
    quantity = entry.quantity
    calories = entry.calories
    carbohydrates = entry.carbohydrates
    protein = entry.protein
    fat = entry.fat
  }

  func restore(into entry: FoodLogEntry) {
    entry.loggedAt = loggedAt
    entry.mealTypeRaw = mealTypeRaw
    entry.name = name
    entry.servingDescription = servingDescription
    entry.quantity = quantity
    entry.calories = calories
    entry.carbohydrates = carbohydrates
    entry.protein = protein
    entry.fat = fat
  }
}

/// 预设 / 最近记录共用的份量表单。
private struct FoodPortionFields: View {
  @Binding var draft: FoodNutritionDraft
  @Binding var mealType: MealType
  @Binding var loggedAt: Date

  var body: some View {
    Section(L10n.text("core.record.details")) {
      LabeledContent(L10n.text("core.nutrition.basis")) {
        Text(draft.inputMode == .per100g ? L10n.text("core.per.100.grams") : draft.canonicalServingDescription)
          .foregroundStyle(.secondary)
      }
      LabeledContent(draft.inputMode.amountTitle) {
        StableNumberField("0", value: $draft.amount, format: .number.precision(.fractionLength(0...2)).locale(L10n.locale))
          .keyboardType(.decimalPad)
          .multilineTextAlignment(.trailing)
          .accessibilityIdentifier("nutrition.portion.amount")
      }
      Picker(L10n.text("core.meal"), selection: $mealType) {
        ForEach(MealType.allCases) { Text($0.title).tag($0) }
      }
      DatePicker(
        L10n.text("core.record.time"),
        selection: $loggedAt,
        displayedComponents: [.date, .hourAndMinute]
      )
    }
    Section(L10n.text("core.nutrition.totals.preview")) {
      previewRow(L10n.text("core.calories.284"), value: draft.totals.calories, unit: "kcal")
      previewRow(L10n.text("core.carbs"), value: draft.totals.carbohydrates, unit: "g")
      previewRow(L10n.text("core.protein"), value: draft.totals.protein, unit: "g")
      previewRow(L10n.text("core.fat"), value: draft.totals.fat, unit: "g")
    }
  }

  private func previewRow(_ title: String, value: Double, unit: String) -> some View {
    LabeledContent(title) {
      Text("\(NutritionFormatting.number(value)) \(unit)")
        .monospacedDigit()
    }
  }
}

/// Search belongs to food selection; the quantity editor keeps its primary action visible.
private struct FoodSelectionSearch: ViewModifier {
  @Binding var query: String
  let isSelecting: Bool
  let prompt: String

  @ViewBuilder
  func body(content: Content) -> some View {
    if isSelecting {
      content.searchable(text: $query, prompt: prompt)
    } else {
      content
    }
  }
}

private struct FoodPresetLogSheet: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext

  @Query(sort: \FoodPreset.name)
  private var presets: [FoodPreset]

  let selectedDate: Date

  @State private var searchText = ""
  @State private var activePreset: FoodPreset?
  @State private var draft = FoodNutritionDraft()
  @State private var mealType = MealType.defaultForTime()
  @State private var loggedAt = Date.now
  @State private var errorMessage: L10n.Message?

  private var filteredPresets: [FoodPreset] {
    let normalized = searchText.trimmed.lowercased()
    guard !normalized.isEmpty else { return presets }
    return presets.filter {
      $0.name.lowercased().contains(normalized)
        || $0.servingDescription.lowercased().contains(normalized)
    }
  }

  var body: some View {
    NavigationStack {
      List {
        if let preset = activePreset {
          Section(L10n.text("core.selected.food")) {
            VStack(alignment: .leading, spacing: 3) {
              Text(preset.name)
              Text(preset.servingDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Button(L10n.text("core.choose.again")) {
              activePreset = nil
            }
            .accessibilityIdentifier("nutrition.preset.reselect")
          }
          FoodPortionFields(draft: $draft, mealType: $mealType, loggedAt: $loggedAt)
          Section {
            Text(
              FoodPortionMath.isPer100g(preset.servingDescription)
                ? L10n.text("core.this.favorite.food.uses.values.per.100.grams.enter.the.actual.weight.in.grams")
                : L10n.text("core.enter.the.number.of.servings.nutrition.will.scale.automatically")
            )
          }
        } else {
          Section(L10n.text("core.favorite.foods")) {
            if presets.isEmpty {
              Text(L10n.text("core.no.favorite.foods.yet.create.one.in.the.library"))
                .foregroundStyle(.secondary)
            } else if filteredPresets.isEmpty {
              Text(L10n.text("core.no.matching.favorite.foods.320"))
                .foregroundStyle(.secondary)
            } else {
              ForEach(filteredPresets) { preset in
                Button {
                  select(preset)
                } label: {
                  VStack(alignment: .leading, spacing: 3) {
                    Text(preset.name)
                    Text(
                      "\(preset.servingDescription) · \(NutritionFormatting.number(preset.caloriesPerServing, fraction: 0)) kcal"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                  }
                  .frame(maxWidth: .infinity, alignment: .leading)
                  .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("foodPreset.log.\(preset.id.uuidString)")
              }
            }
          }
        }
      }
      .modifier(
        FoodSelectionSearch(query: $searchText, isSelecting: activePreset == nil, prompt: L10n.text("core.search.favorite.foods"))
      )
      .accessibilityIdentifier("nutrition.preset.search")
      .localizationTestControls()
    .navigationTitle(activePreset == nil ? L10n.text("core.favorite.foods") : L10n.text("core.log.favorite.food"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(L10n.text("core.cancel")) { dismiss() }
        }
        if let preset = activePreset {
          ToolbarItem(placement: .confirmationAction) {
            Button(L10n.text("core.log")) { log(preset) }
              .disabled(!draft.isValid)
              .accessibilityIdentifier("nutrition.preset.log")
          }
        }
        NutritionKeyboardDoneToolbar()
      }
      .alert(L10n.text("core.save.failed"), isPresented: errorBinding) {
        Button(L10n.text("core.ok.201"), role: .cancel) { errorMessage = nil }
      } message: {
        Text(errorMessage?.text ?? "")
      }
    }
  }

  private var errorBinding: Binding<Bool> {
    Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
  }

  private func select(_ preset: FoodPreset) {
    activePreset = preset
    draft = .fromPreset(preset)
    mealType = .defaultForTime()
    loggedAt = selectedDate.withCurrentTime()
  }

  private func log(_ preset: FoodPreset) {
    guard draft.isValid else {
      errorMessage = L10n.Message(resolving: { L10n.text("core.check.the.portion.it.must.be.finite.and.greater.than.0") })
      return
    }
    let entry = draft.makeEntry(loggedAt: loggedAt, mealType: mealType)
    modelContext.insert(entry)
    do {
      try modelContext.save()
      dismiss()
    } catch {
      modelContext.delete(entry)
      errorMessage = L10n.Message(resolving: { L10n.text("core.save.failed.please.try.again" , String(describing: error.localizedDescription)) })
    }
  }
}

private struct RecentFoodPickerSheet: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext

  @Query(sort: \FoodLogEntry.loggedAt, order: .reverse)
  private var entries: [FoodLogEntry]

  let selectedDate: Date

  @State private var searchText = ""
  @State private var activeItem: RecentFoodItem?
  @State private var draft = FoodNutritionDraft()
  @State private var mealType = MealType.defaultForTime()
  @State private var loggedAt = Date.now
  @State private var errorMessage: L10n.Message?

  private var recentItems: [RecentFoodItem] {
    RecentFoodItem.deduplicated(from: entries).filter { $0.matches(searchText) }
  }

  var body: some View {
    NavigationStack {
      List {
        if let item = activeItem {
          Section(L10n.text("core.selected.food")) {
            VStack(alignment: .leading, spacing: 3) {
              Text(item.name)
              Text(item.servingDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Button(L10n.text("core.choose.again")) { activeItem = nil }
              .accessibilityIdentifier("nutrition.recent.reselect")
          }
          FoodPortionFields(draft: $draft, mealType: $mealType, loggedAt: $loggedAt)
          Section {
            Text(L10n.text("core.saving.creates.a.new.independent.record.the.original.history.will.remain.unchanged"))
          }
        } else {
          Section(L10n.text("core.recent.records")) {
            if recentItems.isEmpty {
              Text(L10n.text("core.no.reusable.historical.records.yet"))
                .foregroundStyle(.secondary)
            } else {
              ForEach(recentItems) { item in
                Button {
                  select(item)
                } label: {
                  VStack(alignment: .leading, spacing: 3) {
                    Text(item.name)
                    Text(
                      L10n.text("core.approx.kcal" , item.servingDescription, String(describing: NutritionFormatting.number(item.perUnit.calories, fraction: 0)), String(describing: FoodPortionMath.isPer100g(item.servingDescription) ? L10n.text("core.100") : L10n.text("core.servings")))
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                  }
                  .frame(maxWidth: .infinity, alignment: .leading)
                  .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("nutrition.recent.item.\(item.id)")
              }
            }
          }
        }
      }
      .modifier(
        FoodSelectionSearch(query: $searchText, isSelecting: activeItem == nil, prompt: L10n.text("core.search.recent.records"))
      )
      .accessibilityIdentifier("nutrition.recent.search")
      .localizationTestControls()
    .navigationTitle(activeItem == nil ? L10n.text("core.recent.records") : L10n.text("core.log.recent.food"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(L10n.text("core.cancel")) { dismiss() }
        }
        if let item = activeItem {
          ToolbarItem(placement: .confirmationAction) {
            Button(L10n.text("core.log")) { log(item) }
              .disabled(!draft.isValid)
              .accessibilityIdentifier("nutrition.recent.log")
          }
        }
        NutritionKeyboardDoneToolbar()
      }
      .alert(L10n.text("core.save.failed"), isPresented: errorBinding) {
        Button(L10n.text("core.ok.201"), role: .cancel) { errorMessage = nil }
      } message: {
        Text(errorMessage?.text ?? "")
      }
    }
  }

  private var errorBinding: Binding<Bool> {
    Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
  }

  private func select(_ item: RecentFoodItem) {
    activeItem = item
    draft = .fromRecent(item)
    mealType = .defaultForTime()
    loggedAt = selectedDate.withCurrentTime()
  }

  private func log(_ item: RecentFoodItem) {
    guard draft.isValid else {
      errorMessage = L10n.Message(resolving: { L10n.text("core.check.the.portion.it.must.be.finite.and.greater.than.0") })
      return
    }
    let entry = draft.makeEntry(loggedAt: loggedAt, mealType: mealType)
    modelContext.insert(entry)
    do {
      try modelContext.save()
      dismiss()
    } catch {
      modelContext.delete(entry)
      errorMessage = L10n.Message(resolving: { L10n.text("core.save.failed.please.try.again" , String(describing: error.localizedDescription)) })
    }
  }
}

private struct MealTemplateLogSheet: View {
  @ScaledMetric(relativeTo: .body) private var quantityWidth = 72.0
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext

  @Query(sort: \MealTemplate.name)
  private var templates: [MealTemplate]

  let selectedDate: Date

  @State private var activeTemplate: MealTemplate?
  @State private var quantities: [UUID: Double] = [:]
  @State private var mealType = MealType.defaultForTime()
  @State private var loggedAt = Date.now
  @State private var errorMessage: L10n.Message?

  var body: some View {
    NavigationStack {
      List {
        if let template = activeTemplate {
          Section(L10n.text("core.record.details")) {
            Picker(L10n.text("core.meal"), selection: $mealType) {
              ForEach(MealType.allCases) { Text($0.title).tag($0) }
            }.accessibilityIdentifier("nutrition.meal.type")
            DatePicker(
              L10n.text("core.record.time"),
              selection: $loggedAt,
              displayedComponents: [.date, .hourAndMinute]
            )
          }

          Section(L10n.text("core.food.portions.adjust.separately")) {
            ForEach(template.sortedItems) { item in
              HStack {
                VStack(alignment: .leading, spacing: 3) {
                  Text(item.nameSnapshot)
                  Text(item.servingDescriptionSnapshot)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                StableNumberField(
                  L10n.text("core.quantity"),
                  value: quantityBinding(
                    for: item.id, fallback: item.quantity,
                    unitFactor: FoodPortionMath.isPer100g(item.servingDescriptionSnapshot) ? 100 : 1
                  ),
                  format: .number.precision(.fractionLength(0...2)).locale(L10n.locale)
                )
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: quantityWidth)
                .accessibilityIdentifier("nutrition.meal.quantity.\(item.id.uuidString)")
                Text(FoodPortionMath.isPer100g(item.servingDescriptionSnapshot) ? "g" : L10n.text("core.servings"))
                  .font(.caption).foregroundStyle(.secondary)
              }
            }
          }

          Section(L10n.text("core.nutrition.totals.preview.for.this.entry")) {
            previewRow(L10n.text("core.calories.284"), value: totals(for: template).calories, unit: "kcal")
            previewRow(L10n.text("core.carbs"), value: totals(for: template).carbohydrates, unit: "g")
            previewRow(L10n.text("core.protein"), value: totals(for: template).protein, unit: "g")
            previewRow(L10n.text("core.fat"), value: totals(for: template).fat, unit: "g")
          }

          Section {
            Button(L10n.text("core.log.this.meal")) { apply(template) }
              .accessibilityIdentifier("nutrition.meal.apply")
            Button(L10n.text("core.choose.a.different.saved.meal")) { activeTemplate = nil }
              .accessibilityIdentifier("nutrition.meal.reselect")
          }
        } else {
          Section(L10n.text("core.saved.meals")) {
            if templates.isEmpty {
              Text(L10n.text("core.no.saved.meals.yet.create.one.in.the.library"))
                .foregroundStyle(.secondary)
            } else {
              ForEach(templates) { template in
                Button {
                  select(template)
                } label: {
                  VStack(alignment: .leading, spacing: 3) {
                    Text(template.name)
                    Text(L10n.text("core.foods", template.items.count))
                      .font(.caption)
                      .foregroundStyle(.secondary)
                  }
                  .frame(maxWidth: .infinity, alignment: .leading)
                  .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(template.items.isEmpty)
                .accessibilityIdentifier("nutrition.meal.template.\(template.id.uuidString)")
              }
            }
          }
        }
      }
      .localizationTestControls()
    .navigationTitle(activeTemplate == nil ? L10n.text("core.log.saved.meal") : L10n.text("core.adjust.saved.meal.portions"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(L10n.text("core.cancel")) { dismiss() }
        }
        NutritionKeyboardDoneToolbar()
      }
      .alert(L10n.text("core.save.failed"), isPresented: errorBinding) {
        Button(L10n.text("core.ok.201"), role: .cancel) { errorMessage = nil }
      } message: {
        Text(errorMessage?.text ?? "")
      }
    }
  }

  private var errorBinding: Binding<Bool> {
    Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
  }

  private func select(_ template: MealTemplate) {
    activeTemplate = template
    quantities = Dictionary(
      uniqueKeysWithValues: template.sortedItems.map { ($0.id, $0.quantity) })
    mealType = .defaultForTime()
    loggedAt = selectedDate.withCurrentTime()
  }

  private func quantityBinding(for id: UUID, fallback: Double, unitFactor: Double) -> Binding<
    Double
  > {
    Binding(
      get: { (quantities[id] ?? fallback) * unitFactor },
      set: { quantities[id] = $0 / unitFactor }
    )
  }

  private func totals(for template: MealTemplate) -> NutritionValues {
    template.sortedItems.reduce(into: NutritionValues()) { result, item in
      let quantity = quantities[item.id] ?? item.quantity
      result =
        result
        + NutritionValues(
          calories: item.caloriesPerServing * quantity,
          carbohydrates: item.carbohydratesPerServing * quantity,
          protein: item.proteinPerServing * quantity,
          fat: item.fatPerServing * quantity
        )
    }
  }

  private func previewRow(_ title: String, value: Double, unit: String) -> some View {
    LabeledContent(title) {
      Text("\(NutritionFormatting.number(value)) \(unit)")
        .monospacedDigit()
    }
  }

  private func apply(_ template: MealTemplate) {
    let entries = FoodLogFactory.entries(
      from: template,
      quantities: quantities,
      mealType: mealType,
      loggedAt: loggedAt
    )
    guard !entries.isEmpty, entries.allSatisfy(\.isValid) else {
      errorMessage = L10n.Message(resolving: { L10n.text("core.a.food.has.an.invalid.quantity.check.and.try.again.quantities.must.be.finite.and.grea") })
      return
    }
    for entry in entries { modelContext.insert(entry) }
    do {
      try modelContext.save()
      dismiss()
    } catch {
      for entry in entries { modelContext.delete(entry) }
      errorMessage = L10n.Message(resolving: { L10n.text("core.save.failed.please.try.again" , String(describing: error.localizedDescription)) })
    }
  }
}

private struct CopyMealSheet: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext

  @Query(sort: \FoodLogEntry.loggedAt, order: .reverse)
  private var entries: [FoodLogEntry]

  let selectedDate: Date

  @State private var sourceDate = Calendar.current.date(byAdding: .day, value: -1, to: .now) ?? .now
  @State private var sourceMeal: MealType = .dinner
  @State private var targetMeal = MealType.defaultForTime()
  @State private var showConfirmation = false
  @State private var errorMessage: L10n.Message?

  private var sourceEntries: [FoodLogEntry] {
    entries.filter {
      Calendar.current.isDate($0.loggedAt, inSameDayAs: sourceDate) && $0.mealType == sourceMeal
    }
  }

  private var sourceTotals: NutritionValues {
    NutritionMath.totals(of: sourceEntries)
  }

  var body: some View {
    NavigationStack {
      List {
        Section(L10n.text("core.source.meal.to.copy")) {
          DatePicker(L10n.text("core.date"), selection: $sourceDate, displayedComponents: .date)
            .accessibilityIdentifier("nutrition.copy.sourceDate")
          HStack {
            Button(L10n.text("core.yesterday")) {
              sourceDate = Calendar.current.date(byAdding: .day, value: -1, to: .now) ?? .now
            }
            Spacer()
            Button(L10n.text("core.today.340")) { sourceDate = .now }.accessibilityIdentifier("nutrition.copy.today")
          }.buttonStyle(.borderless)
          Picker(L10n.text("core.meal"), selection: $sourceMeal) {
            ForEach(MealType.allCases) { Text($0.title).tag($0) }
          }.accessibilityIdentifier("nutrition.copy.sourceMeal")
        }

        Section(L10n.text("core.destination")) {
          LabeledContent(L10n.text("core.date")) {
            Text(selectedDate.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted).locale(L10n.locale)))
              .foregroundStyle(.secondary)
          }
          Picker(L10n.text("core.meal"), selection: $targetMeal) {
            ForEach(MealType.allCases) { Text($0.title).tag($0) }
          }.accessibilityIdentifier("nutrition.copy.targetMeal")
        }

        Section(L10n.text("core.preview")) {
          if sourceEntries.isEmpty {
            Text(L10n.text("core.no.records.to.copy.for.this.date.and.meal"))
              .foregroundStyle(.secondary)
          } else {
            LabeledContent(L10n.text("core.number.of.records")) {
              Text(L10n.text("core.entries", sourceEntries.count)).monospacedDigit()
            }
            previewRow(L10n.text("core.calories.284"), value: sourceTotals.calories, unit: "kcal")
            previewRow(L10n.text("core.carbs"), value: sourceTotals.carbohydrates, unit: "g")
            previewRow(L10n.text("core.protein"), value: sourceTotals.protein, unit: "g")
            previewRow(L10n.text("core.fat"), value: sourceTotals.fat, unit: "g")
            Text(L10n.text("core.copying.creates.new.records.and.preserves.their.source.information.original.records.r"))
              .font(.footnote)
              .foregroundStyle(.secondary)
          }
        }

        Section {
          Button(L10n.text("core.copy.to.destination.meal")) { showConfirmation = true }
            .disabled(sourceEntries.isEmpty)
            .accessibilityIdentifier("nutrition.copy.confirm")
        }
      }
      .localizationTestControls()
    .navigationTitle(L10n.text("core.copy.a.meal"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(L10n.text("core.cancel")) { dismiss() }
        }
      }
      .confirmationDialog(
        L10n.text("core.copy.records", sourceEntries.count),
        isPresented: $showConfirmation,
        titleVisibility: .visible
      ) {
        Button(L10n.text("core.copy")) { performCopy() }
        Button(L10n.text("core.cancel"), role: .cancel) {}
      } message: {
        Text(
          L10n.text("core.copy.to" , String(describing: selectedDate.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted).locale(L10n.locale))), String(describing: targetMeal.title))
        )
      }
      .alert(L10n.text("core.save.failed"), isPresented: errorBinding) {
        Button(L10n.text("core.ok.201"), role: .cancel) { errorMessage = nil }
      } message: {
        Text(errorMessage?.text ?? "")
      }
    }
  }

  private func previewRow(_ title: String, value: Double, unit: String) -> some View {
    LabeledContent(title) {
      Text("\(NutritionFormatting.number(value)) \(unit)")
        .monospacedDigit()
    }
  }

  private var errorBinding: Binding<Bool> {
    Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
  }

  private func performCopy() {
    let copies = FoodLogCopier.entries(
      copying: sourceEntries,
      to: selectedDate,
      mealType: targetMeal
    )
    guard !copies.isEmpty, copies.allSatisfy(\.isValid) else {
      errorMessage = L10n.Message(resolving: { L10n.text("core.a.record.has.invalid.data.and.cannot.be.copied") })
      return
    }
    for entry in copies { modelContext.insert(entry) }
    do {
      try modelContext.save()
      dismiss()
    } catch {
      for entry in copies { modelContext.delete(entry) }
      errorMessage = L10n.Message(resolving: { L10n.text("core.save.failed.please.try.again" , String(describing: error.localizedDescription)) })
    }
  }
}

extension Date {
  fileprivate func withCurrentTime(calendar: Calendar = .current) -> Date {
    FoodLogCopier.mergedDate(on: self, preservingTimeOf: .now, calendar: calendar)
  }
}
