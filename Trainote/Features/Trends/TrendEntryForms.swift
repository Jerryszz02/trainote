import SwiftUI

struct TrendProfileForm: View {
  @Environment(\.dismiss) private var dismiss
  let model: TrendViewModel
  @State private var profile: BodyProfileValue
  @State private var height = ""
  @State private var age = ""
  @State private var useSuggested = false
  @State private var validationMessage: String?

  init(model: TrendViewModel) {
    self.model = model
    let value = model.input?.profile ?? .init(id: UUID(), updatedAt: model.now())
    _profile = State(initialValue: value)
    _height = State(initialValue: value.heightCentimeters.map { String(format: "%.0f", $0) } ?? "")
    let currentYear = model.calendar.calendar.component(.year, from: model.now())
    _age = State(
      initialValue: (value.ageYears ?? value.birthYear.map { currentYear - $0 }).map(String.init)
        ?? "")
    _useSuggested = State(initialValue: model.input?.profile == nil)
  }
  var body: some View {
    NavigationStack {
      Form {
        Section("计算所需资料") {
          TextField("身高（cm）", text: $height).keyboardType(.decimalPad)
            .accessibilityIdentifier("trend.profile.height")
          TextField("年龄", text: $age).keyboardType(.numberPad)
            .accessibilityIdentifier("trend.profile.age")
          Picker("公式使用的生理性别参数", selection: $profile.formulaSex) {
            Text("暂不填写").tag(Optional<FormulaSex>.none)
            Text("男性参数").tag(Optional(FormulaSex.male))
            Text("女性参数").tag(Optional(FormulaSex.female))
          }
          Picker("活动水平", selection: $profile.activityLevel) {
            Text("暂不填写").tag(Optional<ActivityLevel>.none)
            Text("久坐").tag(Optional(ActivityLevel.sedentary))
            Text("轻活动").tag(Optional(ActivityLevel.light))
            Text("中等活动").tag(Optional(ActivityLevel.moderate))
            Text("高活动").tag(Optional(ActivityLevel.high))
          }
          Text("活动水平包含日常活动和训练，不会再逐卡路里加回手表活动热量。")
            .font(.caption).foregroundStyle(.secondary)
          Picker("每周训练天数", selection: $profile.trainingDaysPerWeek) {
            Text("暂不填写").tag(Optional<Int>.none)
            ForEach(0...7, id: \.self) { Text("\($0) 天").tag(Optional($0)) }
          }
        }
        Section("身体目标") {
          Picker("目标方向", selection: $profile.goalDirection) {
            Text("暂不填写").tag(Optional<GoalDirection>.none)
            Text("维持体重").tag(Optional(GoalDirection.maintain))
            Text("减脂").tag(Optional(GoalDirection.lose))
            Text("增肌").tag(Optional(GoalDirection.gain))
          }
          Picker("通用建议适用条件", selection: $profile.isAdultGeneralFitness) {
            Text("暂不确认").tag(Optional<Bool>.none)
            Text("成年日常健身，无特殊营养需求").tag(Optional(true))
            Text("有特殊需求或不确定").tag(Optional(false))
          }
          Text("孕哺期、疾病管理或需特殊营养方案时，可继续记录并使用手动目标。")
            .font(.caption).foregroundStyle(.secondary)
          if model.input?.profile == nil {
            Toggle("保存后使用建议模式，由我采用", isOn: $useSuggested)
          }
        }
        if let validationMessage { Text(validationMessage).foregroundStyle(.red) }
      }
      .navigationTitle("身体资料与目标")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("保存") { save() }.accessibilityIdentifier("trend.profile.save")
        }
      }
    }
  }
  private func save() {
    guard height.isEmpty || Double(height) != nil, age.isEmpty || Int(age) != nil else {
      validationMessage = "请输入有效的身高和年龄。"
      return
    }
    profile.heightCentimeters = Double(height)
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
      validationMessage = "请检查资料中的数值范围。"
      return
    }
    model.errorMessage = nil
    if model.saveProfile(profile) {
      if useSuggested { model.setMode(.suggested) }
      dismiss()
    } else {
      validationMessage = model.errorMessage
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

  init(model: TrendViewModel, entry: ManualWeightValue? = nil) {
    self.model = model
    self.entry = entry
    _recordID = State(initialValue: entry?.id ?? UUID())
    _date = State(initialValue: entry?.measuredAt ?? model.now())
    _kilograms = State(initialValue: entry.map { String(format: "%.1f", $0.kilograms) } ?? "")
  }
  var body: some View {
    NavigationStack {
      Form {
        DatePicker("称重时间", selection: $date, in: ...model.now())
        TextField("体重（kg）", text: $kilograms).keyboardType(.decimalPad)
          .accessibilityIdentifier("trend.weight.kilograms")
        Text("此记录来源为手动。Apple 健康记录请在原来源中编辑。")
          .font(.caption).foregroundStyle(.secondary)
        if let validationMessage { Text(validationMessage).foregroundStyle(.red) }
      }
      .navigationTitle(entry == nil ? "记录体重" : "编辑体重")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("保存") {
            guard let value = Double(kilograms), value.isFinite, (1...1000).contains(value) else {
              validationMessage = "请输入有效的公斤数。"
              return
            }
            model.errorMessage = nil
            if model.saveWeight(id: recordID, date: date, kilograms: value) {
              dismiss()
            } else {
              validationMessage = model.errorMessage
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
      Section("常用来源") {
        Picker(
          "优先使用",
          selection: Binding(
            get: {
              model.input?.preferences.preferredWeightSourceID ?? ""
            }, set: { model.preferSource($0.isEmpty ? nil : $0) })
        ) {
          Text("自动选择（优先手动）").tag("")
          ForEach(
            Array(Set(model.input?.weights.map { $0.source.identifier } ?? [])).sorted(), id: \.self
          ) {
            Text($0 == DataSource.manual.identifier ? "手动" : $0).tag($0)
          }
        }
      }
      ForEach((model.input?.weights ?? []).sorted { $0.measuredAt > $1.measuredAt }) { sample in
        Section {
          LabeledContent(
            sample.measuredAt.formatted(date: .abbreviated, time: .shortened),
            value: String(format: "%.1f kg", sample.kilograms))
          Text(sample.source.kind == .manual ? "手动记录" : "Apple 健康 · \(sample.source.identifier)")
            .font(.caption).foregroundStyle(.secondary)
          Text("记录时区：\(sample.timeZoneIdentifier)").font(.caption).foregroundStyle(.secondary)
          if sample.isUserSelected { Label("已指定为当天代表读数", systemImage: "checkmark") }
          if model.result?.points.contains(where: {
            $0.sampleIDs.contains(sample.id) && $0.smoothedKilograms == nil
          }) == true {
            Text("异常值待复核，暂未用于趋势计算").foregroundStyle(.orange)
          }
          Button("作为当天代表读数") { model.selectWeight(sample) }
          if sample.source.kind == .manual,
            let manual = model.records.weights.first(where: { $0.id == sample.id })
          {
            Button("编辑") { editing = manual }
            Button("删除", role: .destructive) { deletion = sample.id }
          }
        }
      }
    }
    .navigationTitle("体重记录与来源")
    .sheet(item: $editing) { TrendWeightForm(model: model, entry: $0) }
    .confirmationDialog(
      "删除这条手动体重？",
      isPresented: Binding(
        get: { deletion != nil },
        set: {
          if !$0 { deletion = nil }
        }), titleVisibility: .visible
    ) {
      Button("删除", role: .destructive) {
        if let deletion { model.deleteWeight(deletion) }
        deletion = nil
      }
      Button("取消", role: .cancel) { deletion = nil }
    }
  }
}
