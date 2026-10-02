import Foundation

/// Fixed synthetic values for renderer development; no calculation or physiological claim.
enum BodyMapFixtures {
  static var populated: BodyMapPresentation {
    .init(muscles: MuscleID.allCases.enumerated().map { index, muscle in
      let scores: [Double?] = [42, 85, 65, 90, nil, 80, 88, 60, 45, 72, 95]
      let score = scores[index]
      return .init(muscleID: muscle, score: score,
                   state: score.map { $0 < 50 ? .low : ($0 < 80 ? .moderate : .ready) } ?? .unknown,
                   isSelected: muscle == .chest)
    }, asOf: Date(timeIntervalSince1970: 1_791_072_000), calculationVersion: "synthetic-fixture-v1")
  }
}
