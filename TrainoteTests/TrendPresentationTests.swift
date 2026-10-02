import SwiftData
import SwiftUI
import XCTest

@testable import Trainote

@MainActor
final class TrendPresentationTests: XCTestCase {
  func testTrendScreenRendersPopulatedAndEmptyFixturesAtAccessibilitySize() throws {
    let container = try PersistenceController.makeContainer(inMemory: true)
    let repository = SwiftDataAnalysisRepository(container: container)
    let model = TrendViewModel(
      repository: repository, now: { TrendTestData.now },
      timeZone: { TimeZone(secondsFromGMT: 0)! })
    model.reload()
    try capture(model: model, name: "trend-empty", accessibility: false)
    let fixture = TrendTestData.input()
    try repository.saveProfile(try XCTUnwrap(fixture.profile))
    try repository.savePreferences(fixture.preferences)
    for sample in fixture.weights {
      try repository.saveWeight(
        .init(
          id: sample.id, measuredAt: sample.measuredAt,
          kilograms: sample.kilograms, timeZoneIdentifier: "UTC", createdAt: sample.measuredAt,
          updatedAt: sample.measuredAt))
    }
    try repository.appendGoalRevision(fixture.goalHistory[0])
    let context = ModelContext(container)
    let target = TrendTestData.targets()
    context.insert(
      NutritionGoal(
        calories: target.calories, carbohydrates: target.carbohydrates,
        protein: target.protein, fat: target.fat))
    for day in -14 ... -1 {
      context.insert(
        FoodLogEntry(
          loggedAt: TrendTestData.date(day), mealType: .lunch,
          name: "合成全天摄入", servingDescription: "1 天", quantity: 1,
          calories: target.calories, carbohydrates: target.carbohydrates, protein: target.protein,
          fat: target.fat))
    }
    try context.save()
    model.reload()
    for day in -14 ... -1 { model.confirmDiet(on: TrendTestData.date(day)) }
    XCTAssertNotNil(model.result?.proposal)
    XCTAssertNil(model.errorMessage)
    try capture(model: model, name: "trend-populated", accessibility: false)
    try capture(model: model, name: "trend-accessibility", accessibility: true)
  }

  private func capture(model: TrendViewModel, name: String, accessibility: Bool) throws {
    let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
    let window = UIWindow(windowScene: scene)
    let host = UIHostingController(
      rootView: NavigationStack { TrendView(model: model) }
        .environment(\.dynamicTypeSize, accessibility ? .accessibility3 : .large))
    window.rootViewController = host
    window.makeKeyAndVisible()
    host.view.setNeedsLayout()
    host.view.layoutIfNeeded()
    RunLoop.main.run(until: Date.now.addingTimeInterval(0.5))
    XCTAssertGreaterThan(host.view.bounds.height, 0)
    let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
    let image = renderer.image { _ in
      window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
    }
    let attachment = XCTAttachment(image: image)
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
    func scrollView(in view: UIView) -> UIScrollView? {
      if let scroll = view as? UIScrollView, scroll.contentSize.height > scroll.bounds.height {
        return scroll
      }
      return view.subviews.compactMap { scrollView(in: $0) }.first
    }
    if let scroll = scrollView(in: host.view) {
      scroll.setContentOffset(
        CGPoint(x: 0, y: max(0, scroll.contentSize.height - scroll.bounds.height)), animated: false)
      RunLoop.main.run(until: Date.now.addingTimeInterval(0.3))
      let bottom = renderer.image { _ in
        window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
      }
      let bottomAttachment = XCTAttachment(image: bottom)
      bottomAttachment.name = name + "-bottom"
      bottomAttachment.lifetime = .keepAlways
      add(bottomAttachment)
    }
    window.isHidden = true
  }
}
