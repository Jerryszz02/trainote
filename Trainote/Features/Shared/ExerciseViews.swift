import SwiftUI

struct ExercisePickerView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(ExerciseCatalog.self) private var catalog

  @State private var query = ""
  @State private var bodyPart: String?
  @State private var equipment: String?
  @State private var muscleGroup: String?

  let title: String
  let onSelect: (ExerciseCatalogItem) -> Void

  private var results: [ExerciseCatalogItem] {
    catalog.filtered(
      query: query,
      bodyPart: bodyPart,
      equipment: equipment,
      muscleGroup: muscleGroup
    )
  }

  var body: some View {
    NavigationStack {
      Group {
        if let errorMessage = catalog.errorMessage {
          ContentUnavailableView {
            Label("动作目录加载失败", systemImage: "exclamationmark.triangle")
          } description: {
            Text(errorMessage)
          } actions: {
            Button("重试") { catalog.load() }
          }
        } else if results.isEmpty {
          ContentUnavailableView.search(text: query)
        } else {
          List(results) { item in
            Button {
              onSelect(item)
              dismiss()
            } label: {
              ExerciseRow(item: item)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("exercisePicker.item.\(item.id)")
          }
          .listStyle(.plain)
        }
      }
      .navigationTitle(title)
      .navigationBarTitleDisplayMode(.inline)
      .searchable(text: $query, prompt: "搜索中英文名称、肌群或器械")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("取消") { dismiss() }
        }
        ToolbarItem(placement: .topBarTrailing) {
          filterMenu
        }
      }
    }
  }

  private var filterMenu: some View {
    Menu {
      Menu("身体部位") {
        Button("全部") { bodyPart = nil }
        ForEach(catalog.bodyParts, id: \.self) { value in
          Button(ExerciseLabel.bodyPart(value)) { bodyPart = value }
        }
      }
      Menu("器械") {
        Button("全部") { equipment = nil }
        ForEach(catalog.equipmentTypes, id: \.self) { value in
          Button(ExerciseLabel.equipment(value)) { equipment = value }
        }
      }
      Menu("肌群") {
        Button("全部") { muscleGroup = nil }
        ForEach(catalog.muscleGroups, id: \.self) { value in
          Button(value) { muscleGroup = value }
        }
      }
      if bodyPart != nil || equipment != nil || muscleGroup != nil {
        Divider()
        Button("清除筛选", role: .destructive) {
          bodyPart = nil
          equipment = nil
          muscleGroup = nil
        }
      }
    } label: {
      Label(
        "筛选",
        systemImage: bodyPart == nil && equipment == nil && muscleGroup == nil
          ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
    }
  }
}

struct ExerciseRow: View {
  let item: ExerciseCatalogItem

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: item.defaultTrackingMode.systemImage)
        .font(.title3)
        .foregroundStyle(.tint)
        .frame(width: 34, height: 34)
        .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 3) {
        Text(item.displayName)
          .font(.body.weight(.medium))
        Text(item.nameEn)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
        Text(
          "\(ExerciseLabel.bodyPart(item.bodyPart)) · \(ExerciseLabel.equipment(item.equipment))"
        )
        .font(.caption2)
        .foregroundStyle(.tertiary)
      }
    }
    .contentShape(Rectangle())
    .accessibilityElement(children: .combine)
  }
}

struct ExerciseDetailView: View {
  let item: ExerciseCatalogItem

  var body: some View {
    List {
      Section {
        VStack(alignment: .leading, spacing: 6) {
          Text(item.displayName).font(.title2.bold())
          Text(item.nameEn).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
      }

      Section("分类") {
        LabeledContent("身体部位", value: ExerciseLabel.bodyPart(item.bodyPart))
        LabeledContent("器械", value: ExerciseLabel.equipment(item.equipment))
        LabeledContent("目标肌肉", value: item.target)
        LabeledContent("主要协同肌群", value: item.muscleGroup)
        if !item.secondaryMuscles.isEmpty {
          LabeledContent("辅助肌群", value: item.secondaryMuscles.joined(separator: "、"))
        }
      }

      Section("中文说明") {
        ForEach(Array(item.stepsZh.enumerated()), id: \.offset) { index, step in
          instructionRow(index: index, text: step)
        }
      }

      Section("English Instructions") {
        ForEach(Array(item.stepsEn.enumerated()), id: \.offset) { index, step in
          instructionRow(index: index, text: step)
        }
      }

      Section {
        Text("数据来自 hasaneyldrm/exercises-dataset。Trainote 未包含 Gym visual 图片或 GIF。")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
    }
    .navigationTitle("动作详情")
    .navigationBarTitleDisplayMode(.inline)
  }

  private func instructionRow(index: Int, text: String) -> some View {
    HStack(alignment: .top, spacing: 12) {
      Text("\(index + 1)")
        .font(.caption.bold())
        .foregroundStyle(.white)
        .frame(width: 24, height: 24)
        .background(.tint, in: Circle())
      Text(text)
    }
    .padding(.vertical, 2)
  }
}
