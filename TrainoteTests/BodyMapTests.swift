import SceneKit
import XCTest

#if BODY_MAP_PREVIEW
  @testable import BodyMapPreview
#else
  @testable import Trainote
#endif

@MainActor
final class BodyMapTests: XCTestCase {
  func testUnknownZeroRoundingAndInvalidNumbersRemainDistinct() {
    let unknown = BodyMapRegion(muscle: .chest, score: nil, status: "状态较好")
    let zero = BodyMapRegion(muscle: .chest, score: 0, status: "优先恢复")
    XCTAssertNil(unknown.displayedScore)
    XCTAssertEqual(unknown.status, "待建立记录")
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
      let x = data.positions.map(\.x), y = data.positions.map(\.y), z = data.positions.map(\.z)
      XCTAssertGreaterThan(x.max()! - x.min()!, 0.001)
      XCTAssertGreaterThan(y.max()! - y.min()!, 0.001)
      XCTAssertGreaterThan(z.max()! - z.min()!, 0.001)
      // A closed 2-manifold: every undirected edge belongs to exactly two triangles.
      var edges: [String: Int] = [:]
      for i in stride(from: 0, to: data.indices.count, by: 3) {
        let triangle = Array(data.indices[i..<(i + 3)])
        for j in 0..<3 {
          let a = triangle[j], b = triangle[(j + 1) % 3]
          edges["\(min(a, b))-\(max(a, b))", default: 0] += 1
        }
      }
      XCTAssertTrue(edges.values.allSatisfy { $0 == 2 }, mesh.name)
    }
    XCTAssertLessThan(triangles, 65_000)
    let scene = BodyMapScene(asset: asset)
    XCTAssertEqual(Set(scene.nodes.keys), Set(BodyMapMuscle.allCases))
    for muscle in BodyMapMuscle.allCases {
      XCTAssertGreaterThanOrEqual(scene.nodes[muscle]!.count, 2)
    }
  }

  func testAssetRejectsBadProfilesBeforeGeometryGeneration() throws {
    let good = try BodyMapAsset.load()
    let mesh = good.meshes[0]
    let broken = BodyMapAsset.Mesh(name: mesh.name, muscle: mesh.muscle, rings: [
      .init(center: [0, 1, 0], radius: [0.1, 0.1]),
      .init(center: [0, 1, 0], radius: [0.1, 0.1]),
      .init(center: [0, 0, 0], radius: [0.1, 0.1]),
    ], facing: nil)
    XCTAssertThrowsError(try BodyMapAsset(version: 1, meshes: [broken] + good.meshes.dropFirst()).validate())
    XCTAssertThrowsError(try BodyMapAsset(version: 2, meshes: good.meshes).validate())
  }

  func testProjectionAndNearestHitCoverBothSidesWithoutSelectingThroughBody() throws {
    let model = BodyMapScene(asset: try BodyMapAsset.load())
    let view = SCNView(frame: CGRect(x: 0, y: 0, width: 370, height: 430))
    view.scene = model.scene
    view.pointOfView = model.camera
    var visible = Set<BodyMapMuscle>()
    for angle: Float in [0, .pi / 2, .pi, -.pi / 2] {
      model.body.eulerAngles.y = angle
      let anchors = model.projectedAnchors(in: view)
      visible.formUnion(anchors.map(\.muscle))
      for anchor in anchors { XCTAssertEqual(model.hit(at: anchor.point, in: view), anchor.muscle) }
      let labels = BodyMapLabelLayout.arrange(anchors: anchors, bounds: view.bounds)
      for label in labels { XCTAssertTrue(view.bounds.contains(label.frame), label.muscle.rawValue) }
      for (i, label) in labels.enumerated() {
        for other in labels.dropFirst(i + 1) { XCTAssertFalse(label.frame.intersects(other.frame)) }
      }
    }
    XCTAssertEqual(visible, Set(BodyMapMuscle.allCases))
    model.body.eulerAngles.y = 0
    XCTAssertFalse(model.projectedAnchors(in: view).contains { [.glutes, .hamstrings, .back].contains($0.muscle) })
    XCTAssertNil(model.hit(at: CGPoint(x: 2, y: 2), in: view))
  }

  func testPerformanceAndAccessibilityPolicies() {
    func policy(voiceOver: Bool = false, largeText: Bool = false, lowPower: Bool = false,
      thermal: ProcessInfo.ThermalState = .nominal, available: Bool = true) -> BodyMapDisplayPolicy {
      .resolve(voiceOver: voiceOver, largeText: largeText, lowPower: lowPower,
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

  func testSceneConstructionPerformance() throws {
    let asset = try BodyMapAsset.load()
    measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
      autoreleasepool { _ = BodyMapScene(asset: asset) }
    }
  }
}
