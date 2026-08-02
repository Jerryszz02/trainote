import SwiftData
import SwiftUI

struct SettingsView: View {
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      Form {
        Section("饮食管理") {
          NavigationLink("每日营养目标") {
            NutritionGoalEditor()
          }
        }

        Section("单位") {
          LabeledContent("重量", value: "公斤 (kg)")
          LabeledContent("距离", value: "公里 (km)")
        }

        Section("关于") {
          NavigationLink("Trainote 与数据来源") {
            AboutView()
          }
        }
      }
      .navigationTitle("设置")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("完成") { dismiss() }
        }
      }
    }
  }
}

struct NutritionGoalEditor: View {
  @Environment(\.modelContext) private var modelContext

  @Query(sort: \NutritionGoal.updatedAt, order: .reverse)
  private var goals: [NutritionGoal]

  @State private var calories = 2_000.0
  @State private var carbohydrates = 250.0
  @State private var protein = 150.0
  @State private var fat = 65.0
  @State private var loadedExistingGoal = false
  @State private var saved = false

  private var isValid: Bool {
    calories.isFinite && calories > 0
      && carbohydrates.isValidNonnegativeNumber
      && protein.isValidNonnegativeNumber
      && fat.isValidNonnegativeNumber
  }

  var body: some View {
    Form {
      Section("每日目标") {
        nutrientField("卡路里", value: $calories, unit: "kcal")
        nutrientField("碳水", value: $carbohydrates, unit: "g")
        nutrientField("蛋白质", value: $protein, unit: "g")
        nutrientField("脂肪", value: $fat, unit: "g")
      }

      Section {
        Text("目标由你手动设置。Trainote 不会根据身体数据自动生成饮食建议。")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
    }
    .navigationTitle("营养目标")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .confirmationAction) {
        Button(saved ? "已保存" : "保存", action: save)
          .disabled(!isValid)
          .accessibilityIdentifier("goal.save")
      }
    }
    .task { loadExistingGoalIfNeeded() }
  }

  private func nutrientField(_ title: String, value: Binding<Double>, unit: String) -> some View {
    LabeledContent(title) {
      HStack(spacing: 6) {
        TextField("0", value: value, format: .number.precision(.fractionLength(0...1)))
          .keyboardType(.decimalPad)
          .multilineTextAlignment(.trailing)
          .frame(minWidth: 80)
        Text(unit).foregroundStyle(.secondary)
      }
    }
  }

  private func loadExistingGoalIfNeeded() {
    guard !loadedExistingGoal else { return }
    loadedExistingGoal = true
    guard let goal = goals.first else { return }
    calories = goal.calories
    carbohydrates = goal.carbohydrates
    protein = goal.protein
    fat = goal.fat
  }

  private func save() {
    guard isValid else { return }
    if let goal = goals.first {
      goal.calories = calories
      goal.carbohydrates = carbohydrates
      goal.protein = protein
      goal.fat = fat
      goal.updatedAt = .now
    } else {
      modelContext.insert(
        NutritionGoal(
          calories: calories,
          carbohydrates: carbohydrates,
          protein: protein,
          fat: fat
        )
      )
    }
    for duplicate in goals.dropFirst() {
      modelContext.delete(duplicate)
    }
    try? modelContext.save()
    saved = true
  }
}

struct AboutView: View {
  @Environment(ExerciseCatalog.self) private var catalog

  private let privacyURL = URL(string: "https://jerryszz02.github.io/trainote/privacy/")!
  private let supportURL = URL(string: "https://jerryszz02.github.io/trainote/support/")!

  private var versionText: String {
    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
    return [version, build.map { "(\($0))" }].compactMap { $0 }.joined(separator: " ")
  }

  var body: some View {
    List {
      Section("Trainote") {
        LabeledContent("版本", value: versionText)
        Text("训练和饮食记录只保存在本机。Trainote 不上传内容，也不提供医疗或专业训练建议。")
      }

      Section("隐私与支持") {
        Link("隐私政策", destination: privacyURL)
          .accessibilityIdentifier("about.privacy")
        Link("帮助与反馈", destination: supportURL)
          .accessibilityIdentifier("about.support")
      }

      Section("动作数据") {
        LabeledContent("动作数量", value: "\(catalog.items.count)")
        if let source = catalog.source {
          LabeledContent("固定提交", value: String(source.commit.prefix(8)))
          Text(source.license)
            .font(.footnote)
          if let url = URL(string: source.repository) {
            Link("打开数据集仓库", destination: url)
          }
        }
        Text("仅使用 MIT 许可覆盖的动作元数据和说明文字。Gym visual 图片与 GIF 未包含在 App 中。")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
    }
    .navigationTitle("关于")
    .navigationBarTitleDisplayMode(.inline)
  }
}
