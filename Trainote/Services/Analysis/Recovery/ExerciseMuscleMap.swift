import Foundation

/// Review status is independent of tracking mode. Unreviewed mappings never create load.
struct ExerciseMuscleMap: Decodable, Sendable {
  enum Status: String, Decodable, Sendable { case mapped, pendingReview, notApplicable }
  struct Entry: Decodable, Sendable {
    var exerciseID: String
    var status: Status
    var primary: [MuscleID]
    var secondary: [MuscleID]
    var reason: String

    var weights: [MuscleID: Double] {
      guard status == .mapped else { return [:] }
      var result: [MuscleID: Double] = [:]
      for muscle in secondary { result[muscle] = 0.5 }
      for muscle in primary { result[muscle] = 1 }
      return result
    }
  }
  var version: String
  var entries: [Entry]
  var byID: [String: Entry] {
    Dictionary(uniqueKeysWithValues: entries.map { ($0.exerciseID, $0) })
  }

  static func load(bundle: Bundle = .main) throws -> Self {
    guard let url = bundle.url(forResource: "ExerciseMuscleMap", withExtension: "json") else {
      throw AnalysisFailure.unavailable
    }
    let result = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
    guard result.version == "exercise-muscles-v0.1", result.entries.count == 1324,
      Set(result.entries.map(\.exerciseID)).count == result.entries.count,
      result.entries.allSatisfy({ $0.status != .mapped || !$0.primary.isEmpty })
    else { throw AnalysisFailure.invalidInput }
    return result
  }
}
