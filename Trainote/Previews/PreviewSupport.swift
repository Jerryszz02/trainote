import SwiftData
import SwiftUI

@MainActor
private enum PreviewFixtures {
  static let exercise = ExerciseCatalogItem(
    id: "0025",
    nameEn: "barbell bench press",
    nameZh: "杠铃卧推",
    bodyPart: "chest",
    equipment: "barbell",
    target: "pectorals",
    muscleGroup: "triceps",
    secondaryMuscles: ["triceps", "shoulders"],
    instructionsEn: "Lower the bar with control and press it back up.",
    instructionsZh: "控制杠铃下放至胸部，然后推回起始位置。",
    stepsEn: ["Lie on the bench.", "Lower the bar.", "Press upward."],
    stepsZh: ["躺在长凳上。", "控制杠铃下放。", "向上推起杠铃。"]
  )

  static var container: ModelContainer {
    try! PersistenceController.makeContainer(inMemory: true)
  }
}

#Preview("空白 App") {
  AppShell()
    .environment(ExerciseCatalog(items: [PreviewFixtures.exercise]))
    .modelContainer(PreviewFixtures.container)
}

#Preview("动作详情") {
  NavigationStack {
    ExerciseDetailView(item: PreviewFixtures.exercise)
  }
}
