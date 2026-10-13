import SceneKit
import UIKit
import XCTest

#if BODY_MAP_PREVIEW
  @testable import BodyMapPreview
#else
  @testable import Trainote
#endif

@MainActor
final class BodyMapTests: XCTestCase {
  func testFormalContractAdapterPreservesStateSelectionAndRestrictions() {
    var presentation = BodyMapFixtures.populated
    presentation.muscles = [
      .init(muscleID: .chest, score: 100, state: .unknown),
      .init(muscleID: .back, score: 88, state: .low, isSelected: true),
      .init(muscleID: .shoulders, score: 90, state: .ready, hasPain: true),
      .init(muscleID: .glutes, score: nil, state: .unknown, hasMovementLimitation: true),
      .init(muscleID: .quads, score: 0, state: .low),
    ]
    let input = BodyMapRenderInput(presentation: presentation)
    XCTAssertNil(input[.chest].score)
    XCTAssertEqual(input[.back].score, 88)
    // Render the supplied state, do not re-classify it.
    XCTAssertEqual(input[.back].status, L10n.text("health.bodymaprenderinput.prioritize.recovery.41ef55"))
    XCTAssertEqual(input.selected, .back)
    XCTAssertEqual(input[.shoulders].status, L10n.text("health.bodymaprenderinput.pain.reported.508f5b"))
    XCTAssertTrue(input[.shoulders].isLimited)
    XCTAssertEqual(input[.glutes].status, L10n.text("health.bodymaprenderinput.waiting.for.records.e0d73f", L10n.text("health.bodymaprenderinput.limited.movement.4b936a")))
    XCTAssertEqual(input[.quads].displayedScore, 0)
    XCTAssertEqual(input.regions.count, 11)
    XCTAssertNil(input[.hamstrings].score)
  }

  func testUnknownZeroRoundingAndInvalidNumbersRemainDistinct() {
    let unknown = BodyMapRegion(muscle: .chest, score: nil, status: "状态较好")
    let zero = BodyMapRegion(muscle: .chest, score: 0, status: "优先恢复")
    XCTAssertNil(unknown.displayedScore)
    XCTAssertEqual(unknown.status, L10n.text("health.bodymaprenderinput.waiting.for.records.dda84c"))
    XCTAssertEqual(zero.displayedScore, 0)
    XCTAssertNotEqual(unknown.color, zero.color)
    for value in [Double.nan, .infinity, -.infinity, -1, 101] {
      XCTAssertNil(BodyMapRegion(muscle: .chest, score: value, status: "").displayedScore)
    }
    for (raw, expected) in [(0.0, 0), (2.49, 0), (2.5, 5), (72.0, 70), (83.0, 85), (99.0, 100)] {
      XCTAssertEqual(BodyMapRegion(muscle: .chest, score: raw, status: "").displayedScore, expected)
    }
    XCTAssertEqual(BodyMapRenderInput(regions: []).regions.count, 11)
    XCTAssertTrue(BodyMapRenderInput(regions: []).isEmpty)
    XCTAssertFalse(BodyMapRenderInput(regions: [zero]).isEmpty)
  }

  func testAnatomyMasksCoverElevenMusclesWithFiniteInBoundsNativePaths() throws {
    let asset = try BodyMapAnatomyAsset.load()
    XCTAssertEqual(asset.masks.count, 18)
    XCTAssertEqual(Set(asset.masks.map(\.muscle)), Set(MuscleID.allCases))
    XCTAssertEqual(asset.width / asset.height, 1365.0 / 2048.0, accuracy: 0.00001)
    for side in ["front", "back"] {
      let url = try XCTUnwrap(BodyMapAnatomyAsset.resource("anatomy-\(side)", extension: "png"))
      XCTAssertNotNil(UIImage(contentsOfFile: url.path))
      for path in asset.paths(side: side).values {
        XCTAssertFalse(path.isEmpty)
        XCTAssertTrue(CGRect(x: 0, y: 0, width: asset.width, height: asset.height)
          .contains(path.boundingBoxOfPath))
      }
    }
    XCTAssertNotNil(asset.paths(side: "front")[.chest])
    XCTAssertNotNil(asset.paths(side: "back")[.hamstrings])
    XCTAssertNil(asset.paths(side: "front")[.glutes])
  }

  func testNativeAnatomySelectionCallsParentAndKeepsUnknownAndPainSemantics() throws {
    let view = BodyMapAnatomyContainer(frame: CGRect(x: 0, y: 0, width: 370, height: 330))
    XCTAssertNotNil(view.asset)
    var selected: MuscleID?
    let input = BodyMapRenderInput(regions: [
      .init(muscle: .shoulders, score: nil, status: "疼痛反馈", isLimited: true)
    ], selected: .chest)
    view.configure(input: input, onSelect: { selected = $0 })
    view.layoutIfNeeded()
    let chest = try XCTUnwrap(view.subviews.compactMap { $0 as? UIButton }
      .first { $0.accessibilityIdentifier == "bodyMap.label.chest" })
    XCTAssertTrue(chest.accessibilityLabel?.contains(L10n.text("health.bodymaprenderinput.unknown.d9c32a")) ?? false)
    XCTAssertTrue(chest.accessibilityTraits.contains(.selected))
    XCTAssertTrue(chest.point(inside: CGPoint(x: chest.bounds.width * 0.25,
      y: chest.bounds.height * 0.5), with: nil))
    XCTAssertFalse(chest.point(inside: CGPoint(x: -20, y: -20), with: nil))
    chest.sendActions(for: .touchUpInside)
    XCTAssertEqual(selected, .chest)
    let shoulder = try XCTUnwrap(view.subviews.compactMap { $0 as? UIButton }
      .first { $0.accessibilityIdentifier == "bodyMap.label.shoulders" })
    XCTAssertTrue(shoulder.accessibilityLabel?.contains("疼痛反馈") ?? false)
    BodyMapAnatomyView.dismantleUIView(view, coordinator: ())
    selected = nil
    chest.sendActions(for: .touchUpInside)
    XCTAssertNil(selected)
  }

  func testAnatomySmallAndDisconnectedMasksHaveExpandedTouchAreasWithoutFillingGaps() {
    let small = CGPath(rect: CGRect(x: 20, y: 20, width: 8, height: 10), transform: nil)
    let target = BodyMapAnatomyHitTarget(path: small)
    XCTAssertGreaterThanOrEqual(target.frame.width, 44)
    XCTAssertGreaterThanOrEqual(target.frame.height, 44)
    let nearby = CGPoint(x: 15, y: 25)
    XCTAssertFalse(small.contains(nearby))
    XCTAssertTrue(target.contains(nearby))
    XCTAssertEqual(target.distance(to: nearby), 5, accuracy: 0.01)
    XCTAssertFalse(target.contains(CGPoint(x: -20, y: -20)))

    let pair = CGMutablePath()
    pair.addRect(CGRect(x: 0, y: 0, width: 8, height: 10))
    pair.addRect(CGRect(x: 100, y: 0, width: 8, height: 10))
    let paired = BodyMapAnatomyHitTarget(path: pair)
    XCTAssertTrue(paired.contains(CGPoint(x: -15, y: 5)))
    XCTAssertTrue(paired.contains(CGPoint(x: 123, y: 5)))
    XCTAssertFalse(paired.contains(CGPoint(x: 54, y: 5)))
  }

  func testAnatomyOverlappingTouchAreasChooseNearestOriginalMaskInsteadOfSubviewOrder() {
    let left = BodyMapAnatomyHitTarget(path:
      CGPath(rect: CGRect(x: 20, y: 20, width: 8, height: 10), transform: nil))
    let right = BodyMapAnatomyHitTarget(path:
      CGPath(rect: CGRect(x: 38, y: 20, width: 8, height: 10), transform: nil))
    let overlap = CGPoint(x: 35, y: 25)
    XCTAssertTrue(left.contains(overlap))
    XCTAssertTrue(right.contains(overlap))
    XCTAssertEqual(BodyMapAnatomyHitTarget.closest(to: overlap, among: [left, right]), 1)
    XCTAssertEqual(BodyMapAnatomyHitTarget.closest(to: overlap, among: [right, left]), 0)
    // An actual muscle remains preferred when another muscle's expanded target overlaps it.
    let insideLeft = CGPoint(x: 25, y: 25)
    XCTAssertTrue(right.contains(insideLeft))
    XCTAssertEqual(BodyMapAnatomyHitTarget.closest(to: insideLeft, among: [right, left]), 1)
    XCTAssertNil(BodyMapAnatomyHitTarget.closest(to: CGPoint(x: 100, y: 100), among: [left, right]))
  }

  func testAnatomyContainerSmallTargetsReachFortyFourPointsAndRouteNearbyTapsAfterResize() throws {
    let view = BodyMapAnatomyContainer(frame: CGRect(x: 0, y: 0, width: 370, height: 330))
    let asset = try XCTUnwrap(view.asset)
    var selected: MuscleID?
    view.configure(input: BodyMapRenderInput(regions: []), onSelect: { selected = $0 })
    for width in [CGFloat(370), 320] {
      view.frame.size.width = width
      view.setNeedsLayout()
      view.layoutIfNeeded()
      let buttons = view.subviews.compactMap { $0 as? UIButton }
      for muscle in [MuscleID.back, .calves] {
        for button in buttons where button.accessibilityIdentifier == "bodyMap.label.\(muscle.rawValue)" {
          XCTAssertGreaterThanOrEqual(button.bounds.width, 44)
          XCTAssertGreaterThanOrEqual(button.bounds.height, 44)
        }
      }
      // The front trapezius is ~11 points high at 370pt width. Tap just outside its original
      // upper mask, still in its enlarged target, through the container's UIKit hitTest.
      let scale = (width / 2 - 8) / asset.width
      var projection = CGAffineTransform(a: scale, b: 0, c: 0, d: scale,
        tx: (width / 2 - asset.width * scale) / 2,
        ty: (330 - asset.height * scale) / 2)
      let original = try XCTUnwrap(asset.paths(side: "front")[.back]?.copy(using: &projection))
      let box = original.boundingBoxOfPath
      XCTAssertLessThan(box.height, 15)
      let nearby = CGPoint(x: box.midX, y: box.minY - 5)
      XCTAssertFalse(original.contains(nearby))
      let hit = try XCTUnwrap(view.hitTest(nearby, with: nil) as? UIButton)
      XCTAssertEqual(hit.accessibilityIdentifier, "bodyMap.label.back")
      hit.sendActions(for: .touchUpInside)
      XCTAssertEqual(selected, .back)
    }
    XCTAssertTrue(view.hitTest(CGPoint(x: 1, y: 1), with: nil) === view)
    XCTAssertNil(view.hitTest(CGPoint(x: -10, y: -10), with: nil))
  }

  func testAnatomyRejectsMalformedCommandsBeforeDrawing() throws {
    let asset = try BodyMapAnatomyAsset.load()
    let mask = asset.masks[0]
    let malformed = BodyMapAnatomyAsset.Mask(id: mask.id, muscle: mask.muscle,
      side: mask.side, commands: [[1, .nan, 1]])
    XCTAssertThrowsError(try BodyMapAnatomyAsset(version: 1, width: asset.width,
      height: asset.height, masks: [malformed] + asset.masks.dropFirst()).validate())
    XCTAssertThrowsError(try BodyMapAnatomyAsset(version: 1, width: 0,
      height: asset.height, masks: asset.masks).validate())
  }

  func testAssetHasAllElevenGroupsAndClosedFiniteVolumes() throws {
    let asset = try BodyMapAsset.load()
    XCTAssertEqual(asset.meshes.count, 74)
    var triangles = 0
    for mesh in asset.meshes {
      let data = BodyMapGeometry.make(mesh)
      triangles += data.indices.count / 3
      XCTAssertTrue(data.positions.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite })
      XCTAssertTrue(data.normals.allSatisfy { abs(simd_length($0) - 1) < 0.001 })
      XCTAssertTrue(data.indices.allSatisfy { $0 < data.positions.count })
      let x = data.positions.map(\.x)
      let y = data.positions.map(\.y)
      let z = data.positions.map(\.z)
      XCTAssertGreaterThan(x.max()! - x.min()!, 0.001)
      XCTAssertGreaterThan(y.max()! - y.min()!, 0.001)
      XCTAssertGreaterThan(z.max()! - z.min()!, 0.001)
      // A closed 2-manifold: every undirected edge belongs to exactly two triangles.
      var edges: [String: Int] = [:]
      for i in stride(from: 0, to: data.indices.count, by: 3) {
        let triangle = Array(data.indices[i..<(i + 3)])
        for j in 0..<3 {
          let a = triangle[j]
          let b = triangle[(j + 1) % 3]
          edges["\(min(a, b))-\(max(a, b))", default: 0] += 1
        }
      }
      XCTAssertTrue(edges.values.allSatisfy { $0 == 2 }, mesh.name)
    }
    XCTAssertLessThan(triangles, 65_000)
    let scene = BodyMapScene(asset: asset)
    XCTAssertEqual(Set(scene.nodes.keys), Set(MuscleID.allCases))
    for muscle in MuscleID.allCases {
      XCTAssertGreaterThanOrEqual(scene.nodes[muscle]!.count, 2)
    }
  }

  func testAssetRejectsBadProfilesBeforeGeometryGeneration() throws {
    let good = try BodyMapAsset.load()
    let mesh = good.meshes[0]
    let broken = BodyMapAsset.Mesh(
      name: mesh.name, muscle: mesh.muscle,
      rings: [
        .init(center: [0, 1, 0], radius: [0.1, 0.1]),
        .init(center: [0, 1, 0], radius: [0.1, 0.1]),
        .init(center: [0, 0, 0], radius: [0.1, 0.1]),
      ], facing: nil)
    XCTAssertThrowsError(
      try BodyMapAsset(version: 1, meshes: [broken] + good.meshes.dropFirst()).validate())
    XCTAssertThrowsError(try BodyMapAsset(version: 2, meshes: good.meshes).validate())
  }

  func testProjectionAndNearestHitCoverBothSidesWithoutSelectingThroughBody() throws {
    let model = BodyMapScene(asset: try BodyMapAsset.load())
    let view = SCNView(frame: CGRect(x: 0, y: 0, width: 370, height: 430))
    view.scene = model.scene
    view.pointOfView = model.camera
    var visible = Set<MuscleID>()
    for step in 0..<24 {
      let angle = Float(step) * .pi / 12
      model.rotate(to: angle)
      let anchors = model.projectedAnchors(in: view)
      visible.formUnion(anchors.map(\.muscle))
      for anchor in anchors { XCTAssertEqual(model.hit(at: anchor.point, in: view), anchor.muscle) }
      let labels = BodyMapLabelLayout.arrange(anchors: anchors, bounds: view.bounds)
      for label in labels {
        XCTAssertTrue(view.bounds.contains(label.frame), label.muscle.rawValue)
      }
      for (i, label) in labels.enumerated() {
        for other in labels.dropFirst(i + 1) { XCTAssertFalse(label.frame.intersects(other.frame)) }
      }
    }
    XCTAssertEqual(visible, Set(MuscleID.allCases))
    model.rotate(to: 0)
    XCTAssertFalse(
      model.projectedAnchors(in: view).contains {
        [.glutes, .hamstrings, .back].contains($0.muscle)
      })
    XCTAssertNil(model.hit(at: CGPoint(x: 2, y: 2), in: view))
  }

  func testPerformanceAndAccessibilityPolicies() {
    func policy(
      voiceOver: Bool = false, largeText: Bool = false, lowPower: Bool = false,
      thermal: ProcessInfo.ThermalState = .nominal, available: Bool = true
    ) -> BodyMapDisplayPolicy {
      .resolve(
        voiceOver: voiceOver, largeText: largeText, lowPower: lowPower,
        thermalState: thermal, rendererAvailable: available)
    }
    XCTAssertEqual(policy(), .standard)
    XCTAssertEqual(policy(lowPower: true), .economical)
    XCTAssertEqual(policy(thermal: .fair), .economical)
    XCTAssertEqual(policy(voiceOver: true), .list)
    XCTAssertEqual(policy(largeText: true), .list)
    XCTAssertEqual(policy(thermal: .serious), .list)
    XCTAssertEqual(policy(thermal: .critical), .list)
    XCTAssertEqual(policy(available: false), .list)
    XCTAssertEqual(BodyMapDisplayPolicy.economical.framesPerSecond, 20)
  }

  func testDismantledContainerIgnoresLateUIKitLayoutAndUpdates() async throws {
    let container = BodyMapSceneContainer(frame: CGRect(x: 0, y: 0, width: 370, height: 430))
    let model = try XCTUnwrap(container.model)
    let label = try XCTUnwrap(container.subviews.compactMap { $0 as? UIButton }.first)
    var selections = 0
    container.onSelect = { _ in selections += 1 }
    container.layoutIfNeeded()
    XCTAssertFalse(model.projectedAnchors(in: container.sceneView).isEmpty)

    let lateUpdate = expectation(description: "Queued update after dismantling")
    DispatchQueue.main.async {
      container.configure(
        input: BodyMapRenderInput(presentation: BodyMapFixtures.populated),
        policy: .economical, active: true)
      container.rotate(to: .pi)
      container.updateLabels()
      label.sendActions(for: .touchUpInside)
      lateUpdate.fulfill()
    }
    BodyMapSceneView.dismantleUIView(container, coordinator: ())
    // UIKit may lay out a removed representable again during its parent's transition.
    container.bounds.size.width = 390
    container.setNeedsLayout()
    container.layoutIfNeeded()
    await fulfillment(of: [lateUpdate], timeout: 2)
    BodyMapSceneView.dismantleUIView(container, coordinator: ())
    XCTAssertTrue(container.isDismantled)
    XCTAssertNil(container.model)
    XCTAssertNil(container.onSelect)
    XCTAssertFalse(container.isUserInteractionEnabled)
    XCTAssertTrue(container.sceneView.gestureRecognizers?.allSatisfy { !$0.isEnabled } ?? false)
    XCTAssertNil(container.sceneView.scene)
    XCTAssertNil(container.sceneView.pointOfView)
    XCTAssertFalse(container.sceneView.isPlaying)
    XCTAssertFalse(container.sceneView.rendersContinuously)
    XCTAssertEqual(selections, 0)
    // A retained model must also reject calls made with its detached renderer.
    XCTAssertTrue(model.projectedAnchors(in: container.sceneView).isEmpty)
    XCTAssertNil(model.hit(at: CGPoint(x: 200, y: 120), in: container.sceneView))
  }

  func testProjectionRequiresAttachedSceneCameraAndViewport() throws {
    let model = BodyMapScene(asset: try BodyMapAsset.load())
    let view = SCNView(frame: CGRect(x: 0, y: 0, width: 370, height: 430))
    let point = CGPoint(x: 200, y: 120)
    XCTAssertTrue(model.projectedAnchors(in: view).isEmpty)
    XCTAssertNil(model.hit(at: point, in: view))
    view.scene = model.scene
    view.pointOfView = model.camera
    XCTAssertFalse(model.projectedAnchors(in: view).isEmpty)
    view.pointOfView = SCNNode()
    XCTAssertTrue(model.projectedAnchors(in: view).isEmpty)
    XCTAssertNil(model.hit(at: point, in: view))
    view.pointOfView = model.camera
    view.scene = SCNScene()
    XCTAssertTrue(model.projectedAnchors(in: view).isEmpty)
    XCTAssertNil(model.hit(at: point, in: view))
    view.scene = model.scene
    view.pointOfView = model.camera
    view.bounds = .zero
    XCTAssertTrue(model.projectedAnchors(in: view).isEmpty)
    XCTAssertNil(model.hit(at: point, in: view))
  }

  func testSceneConstructionPerformance() throws {
    let asset = try BodyMapAsset.load()
    measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
      autoreleasepool { _ = BodyMapScene(asset: asset) }
    }
  }
}
