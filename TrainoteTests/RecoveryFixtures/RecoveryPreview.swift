#if RECOVERY_PREVIEW
  import SwiftData
  import SwiftUI

  @main
  @MainActor
  struct RecoveryPreviewApp: App {
    let repository: SwiftDataAnalysisRepository
    let service: RecoveryService
    init() {
      let container = try! PersistenceController.makeContainer(inMemory: true)
      repository = SwiftDataAnalysisRepository(container: container)
      let defaults = UserDefaults(suiteName: "trainote.recovery.preview")!
      service = try! RecoveryService(calibration: .init(defaults: defaults))
      let now = Date.now
      if !ProcessInfo.processInfo.arguments.contains("-fixture-empty") {
        let workout = Workout(
          title: "合成卧推", startedAt: now.addingTimeInterval(-49 * 3600),
          endedAt: now.addingTimeInterval(-48 * 3600), status: .completed)
        let exercise = WorkoutExercise(
          sourceExerciseID: "0025", nameEnSnapshot: "Bench", nameZhSnapshot: "卧推",
          orderIndex: 0, trackingMode: .strength)
        exercise.strengthSets = (0..<4).map { index in
          let set = StrengthSet(
            orderIndex: index, weightKilograms: 60, repetitions: 8,
            isCompleted: true, rir: 2, setRole: .working)
          set.exercise = exercise
          return set
        }
        exercise.workout = workout
        workout.exercises = [exercise]
        container.mainContext.insert(workout)
        try! container.mainContext.save()
      }
    }
    var body: some Scene {
      WindowGroup {
        NavigationStack {
          RecoveryView(
            repository: repository, healthData: nil, calculator: service,
            resetCalibration: { service.calibration.reset(at: .now) })
        }
      }
    }
  }
#endif
