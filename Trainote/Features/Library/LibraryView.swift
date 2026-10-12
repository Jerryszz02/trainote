import SwiftData
import SwiftUI

enum LibrarySection: String, CaseIterable, Identifiable {
  case exercises = "动作"
  case routines = "训练模板"
  case foods = "饮食"

  var id: Self { self }
  var title: String {
    switch self {
    case .exercises: L10n.text("core.exercises.259")
    case .routines: L10n.text("core.routines")
    case .foods: L10n.text("core.nutrition")
    }
  }
}

struct LibraryView: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @State private var selectedSection: LibrarySection

  init(initialSection: LibrarySection = .exercises) {
    _selectedSection = State(initialValue: initialSection)
  }

  var body: some View {
    VStack(spacing: 0) {
      Group {
        if dynamicTypeSize.isAccessibilitySize {
          sectionPicker.pickerStyle(.menu)
        } else {
          sectionPicker.pickerStyle(.segmented)
        }
      }
      .accessibilityIdentifier("library.section")
      .padding(.horizontal)
      .padding(.vertical, 10)

      switch selectedSection {
      case .exercises:
        ExerciseLibraryView()
      case .routines:
        RoutinesView()
      case .foods:
        FoodLibraryView()
      }
    }
    .navigationTitle(L10n.text("core.library"))
  }

  private var sectionPicker: some View {
    Picker(L10n.text("core.library.category"), selection: $selectedSection) {
      ForEach(LibrarySection.allCases) { section in
        Text(section.title).tag(section)
      }
    }
  }
}

private struct ExerciseLibraryView: View {
  @Environment(ExerciseCatalog.self) private var catalog
  @State private var query = ""
  @State private var bodyPart: String?
  @State private var equipment: String?
  @State private var muscleGroup: String?

  private var results: [ExerciseCatalogItem] {
    catalog.filtered(
      query: query,
      bodyPart: bodyPart,
      equipment: equipment,
      muscleGroup: muscleGroup
    )
  }

  var body: some View {
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
          NavigationLink {
            ExerciseDetailView(item: item)
          } label: {
            ExerciseRow(item: item)
          }
          .accessibilityIdentifier("exerciseLibrary.item.\(item.id)")
        }
        .listStyle(.plain)
      }
    }
    .searchable(text: $query, prompt: L10n.text("core.search.1.324.exercises"))
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
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
            Button(L10n.text("core.clear.filters"), role: .destructive) {
              bodyPart = nil
              equipment = nil
              muscleGroup = nil
            }
          }
        } label: {
          Label(L10n.text("core.filter"), systemImage: "line.3.horizontal.decrease.circle")
        }
      }
    }
  }
}
