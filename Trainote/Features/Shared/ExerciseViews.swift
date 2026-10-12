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
            Label(L10n.text("core.exercise.catalog.failed.to.load"), systemImage: "exclamationmark.triangle")
          } description: {
            Text(errorMessage)
          } actions: {
            Button(L10n.text("core.retry")) { catalog.load() }
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
      .searchable(text: $query, prompt: L10n.text("core.search.chinese.or.english.names.muscles.or.equipment"))
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(L10n.text("core.cancel")) { dismiss() }
        }
        ToolbarItem(placement: .topBarTrailing) {
          filterMenu
        }
      }
    }
  }

  private var filterMenu: some View {
    Menu {
      Menu(L10n.text("core.body.part")) {
        Button(L10n.text("core.all")) { bodyPart = nil }
        ForEach(catalog.bodyParts, id: \.self) { value in
          Button(ExerciseLabel.bodyPart(value)) { bodyPart = value }
        }
      }
      Menu(L10n.text("core.equipment")) {
        Button(L10n.text("core.all")) { equipment = nil }
        ForEach(catalog.equipmentTypes, id: \.self) { value in
          Button(ExerciseLabel.equipment(value)) { equipment = value }
        }
      }
      Menu(L10n.text("core.muscle.group")) {
        Button(L10n.text("core.all")) { muscleGroup = nil }
        ForEach(catalog.muscleGroups, id: \.self) { value in
          Button(ExerciseLabel.muscleGroup(value)) { muscleGroup = value }
        }
      }
      if bodyPart != nil || equipment != nil || muscleGroup != nil {
        Divider()
        Button(L10n.text("core.clear.filters"), role: .destructive) {
          bodyPart = nil
          equipment = nil
          muscleGroup = nil
        }
      }
    } label: {
      Label(
        L10n.text("core.filter"),
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
        ExerciseAnimationView(exerciseID: item.id)
      }

      Section {
        VStack(alignment: .leading, spacing: 6) {
          Text(item.displayName).font(.title2.bold())
        }
        .padding(.vertical, 4)
      }

      Section(L10n.text("core.classification")) {
        LabeledContent(L10n.text("core.body.part"), value: ExerciseLabel.bodyPart(item.bodyPart))
        LabeledContent(L10n.text("core.equipment"), value: ExerciseLabel.equipment(item.equipment))
        LabeledContent(L10n.text("core.target.muscle"), value: ExerciseLabel.muscle(item.target))
        LabeledContent(L10n.text("core.primary.muscle.group"), value: ExerciseLabel.muscleGroup(item.muscleGroup))
        if !item.secondaryMuscles.isEmpty {
          LabeledContent(L10n.text("core.secondary.muscles"), value: item.secondaryMuscles.map(ExerciseLabel.muscle).joined(separator: L10n.language == .english ? ", " : "、"))
        }
      }

      Section(L10n.text("core.instructions")) {
        ForEach(Array(item.displaySteps.enumerated()), id: \.offset) { index, step in
          instructionRow(index: index, text: step)
        }
        DisclosureGroup(L10n.text("core.other.instructions")) {
          Text(L10n.language == .english ? item.nameZh : item.nameEn)
          ForEach(Array((L10n.language == .english ? item.stepsZh : item.stepsEn).enumerated()), id: \.offset) { index, step in
            instructionRow(index: index, text: step)
          }
        }
      }

      Section {
        Text(L10n.text("core.data.from.hasaneyldrm.exercises.dataset.trainote.does.not.include.gym.visual.images.o"))
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
    }
    .navigationTitle(L10n.text("core.exercise.details"))
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

/// Segmented labels stay readable at accessibility text sizes without replacing view state.
struct CoreAdaptivePickerStyle: ViewModifier {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  func body(content: Content) -> some View {
    if dynamicTypeSize.isAccessibilitySize {
      content.pickerStyle(.menu)
    } else {
      content.pickerStyle(.segmented)
    }
  }
}
