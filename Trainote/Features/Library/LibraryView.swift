import SwiftData
import SwiftUI

private enum LibrarySection: String, CaseIterable, Identifiable {
  case exercises = "动作"
  case routines = "Routine"
  case foods = "饮食"

  var id: Self { self }
}

struct LibraryView: View {
  @State private var selectedSection: LibrarySection = .exercises

  var body: some View {
    VStack(spacing: 0) {
      Picker("资料类型", selection: $selectedSection) {
        ForEach(LibrarySection.allCases) { section in
          Text(section.rawValue).tag(section)
        }
      }
      .pickerStyle(.segmented)
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
    .navigationTitle("资料库")
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
          NavigationLink {
            ExerciseDetailView(item: item)
          } label: {
            ExerciseRow(item: item)
          }
        }
        .listStyle(.plain)
      }
    }
    .searchable(text: $query, prompt: "搜索 1,324 个动作")
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
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
            Button("清除筛选", role: .destructive) {
              bodyPart = nil
              equipment = nil
              muscleGroup = nil
            }
          }
        } label: {
          Label("筛选", systemImage: "line.3.horizontal.decrease.circle")
        }
      }
    }
  }
}
