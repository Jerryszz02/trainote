import SceneKit
import UIKit
import simd

@MainActor
final class BodyMapScene {
  let scene = SCNScene()
  let body = SCNNode()
  let camera = SCNNode()
  let asset: BodyMapAsset
  private(set) var nodes: [BodyMapMuscle: [SCNNode]] = [:]
  private var materials: [BodyMapMuscle: SCNMaterial] = [:]
  private var anchors: [Anchor] = []
  private(set) var triangleCount = 0

  struct Anchor {
    let muscle: BodyMapMuscle
    let position: SCNVector3
    let normal: SCNVector3
  }

  struct ProjectedAnchor {
    let muscle: BodyMapMuscle
    let point: CGPoint
  }

  init(asset: BodyMapAsset) {
    self.asset = asset
    scene.rootNode.addChildNode(body)
    let neutral = SCNMaterial()
    neutral.lightingModel = .physicallyBased
    neutral.diffuse.contents = UIColor(red: 0.57, green: 0.62, blue: 0.66, alpha: 1)
    neutral.roughness.contents = 0.78
    neutral.metalness.contents = 0.02
    for muscle in BodyMapMuscle.allCases {
      let material = SCNMaterial()
      material.lightingModel = .physicallyBased
      material.roughness.contents = 0.66
      material.metalness.contents = 0.03
      materials[muscle] = material
    }
    for mesh in asset.meshes {
      let data = BodyMapGeometry.make(mesh)
      triangleCount += data.indices.count / 3
      let geometry = data.geometry
      geometry.materials = [mesh.muscle.flatMap { materials[$0] } ?? neutral]
      let node = SCNNode(geometry: geometry)
      node.name = mesh.name
      body.addChildNode(node)
      guard let muscle = mesh.muscle else { continue }
      nodes[muscle, default: []].append(node)
      // Several points around a volume allow the labels to follow side views too.
      let ring = mesh.rings.max(by: { $0.radius[0] * $0.radius[1] < $1.radius[0] * $1.radius[1] })!
      for i in 0..<8 {
        let angle = Float(i) * .pi / 4
        let normal = simd_normalize(SIMD3(cos(angle) / ring.radius[0], 0, sin(angle) / ring.radius[1]))
        anchors.append(Anchor(
          muscle: muscle,
          position: SCNVector3(
            ring.center[0] + ring.radius[0] * cos(angle), ring.center[1],
            ring.center[2] + ring.radius[1] * sin(angle)),
          normal: SCNVector3(normal.x, normal.y, normal.z)))
      }
    }
    camera.camera = SCNCamera()
    camera.camera?.usesOrthographicProjection = true
    camera.camera?.orthographicScale = 1.01
    camera.camera?.zNear = 0.1
    camera.camera?.zFar = 12
    camera.position = SCNVector3(0, 0.94, 4)
    scene.rootNode.addChildNode(camera)
    light(type: .ambient, intensity: 470, color: .white, position: SCNVector3(0, 2, 3))
    light(type: .directional, intensity: 920, color: .white, position: SCNVector3(-2, 4, 4))
    light(type: .directional, intensity: 430, color: UIColor(white: 0.92, alpha: 1), position: SCNVector3(3, 1, 2))
    light(type: .directional, intensity: 700, color: .white, position: SCNVector3(0, 3, -3))
  }

  private func light(type: SCNLight.LightType, intensity: CGFloat, color: UIColor, position: SCNVector3) {
    let node = SCNNode()
    node.light = SCNLight()
    node.light?.type = type
    node.light?.intensity = intensity
    node.light?.color = color
    node.position = position
    node.look(at: SCNVector3(0, 1, 0))
    scene.rootNode.addChildNode(node)
  }

  func update(input: BodyMapRenderInput) {
    for region in input.regions {
      let material = materials[region.muscle]!
      material.diffuse.contents = region.color
      let selected = input.selected == region.muscle
      material.emission.contents = selected ? region.color.withAlphaComponent(0.22) : UIColor.black
      material.roughness.contents = selected ? 0.48 : 0.66
    }
  }

  func muscle(for node: SCNNode) -> BodyMapMuscle? {
    guard let name = node.name, let prefix = name.split(separator: ".").first else { return nil }
    return BodyMapMuscle(rawValue: String(prefix))
  }

  func hit(at point: CGPoint, in view: SCNView) -> BodyMapMuscle? {
    // The first surface wins, including neutral surfaces. Never select through the torso.
    guard let first = view.hitTest(point, options: [.searchMode: SCNHitTestSearchMode.closest.rawValue]).first
    else { return nil }
    return muscle(for: first.node)
  }

  func projectedAnchors(in view: SCNView) -> [ProjectedAnchor] {
    guard view.bounds.width > 0, view.bounds.height > 0 else { return [] }
    var candidates: [BodyMapMuscle: [(point: CGPoint, quality: Float)]] = [:]
    for anchor in anchors {
      let worldNormal = body.convertVector(anchor.normal, to: nil)
      guard worldNormal.z > 0.45 else { continue }
      let world = body.convertPosition(anchor.position, to: nil)
      let projected = view.projectPoint(world)
      let point = CGPoint(x: CGFloat(projected.x), y: CGFloat(projected.y))
      guard (0...1).contains(projected.z), view.bounds.insetBy(dx: 1, dy: 1).contains(point)
      else { continue }
      // Prefer the outside half so leader lines avoid crossing the centre of the body.
      let side = abs(Float(point.x - view.bounds.midX)) / Float(view.bounds.width)
      let prefersLeft = BodyMapMuscle.allCases.firstIndex(of: anchor.muscle)! % 2 == 0
      let preferredSide: Float = (point.x < view.bounds.midX) == prefersLeft ? 0.35 : 0
      candidates[anchor.muscle, default: []].append((point, worldNormal.z + side * 0.6 + preferredSide))
    }
    return BodyMapMuscle.allCases.compactMap { muscle in
      guard let best = candidates[muscle]?.sorted(by: { $0.quality > $1.quality })
        .prefix(12).first(where: { hit(at: $0.point, in: view) == muscle }) else { return nil }
      return ProjectedAnchor(muscle: muscle, point: best.point)
    }
  }
}

/// Deterministic layout shared by the live overlay and regression tests.
enum BodyMapLabelLayout {
  struct Item {
    let muscle: BodyMapMuscle
    let anchor: CGPoint
    let frame: CGRect
  }

  static func arrange(anchors: [BodyMapScene.ProjectedAnchor], bounds: CGRect) -> [Item] {
    let height: CGFloat = 46
    let width = min(100, bounds.width * 0.255)
    let padding: CGFloat = 5
    var items = [Item]()
    for left in [true, false] {
      let column = anchors.filter { ($0.point.x < bounds.midX) == left }
        .sorted { $0.point.y == $1.point.y ? $0.muscle.rawValue < $1.muscle.rawValue : $0.point.y < $1.point.y }
      guard !column.isEmpty else { continue }
      var centers = column.map { max(padding + height / 2, $0.point.y) }
      for i in 1..<centers.count { centers[i] = max(centers[i], centers[i - 1] + height + 4) }
      let overflow = max(0, centers.last! + height / 2 + padding - bounds.height)
      centers = centers.map { $0 - overflow }
      if centers[0] < padding + height / 2 {
        for i in centers.indices { centers[i] = padding + height / 2 + CGFloat(i) * (height + 4) }
      }
      for (index, anchor) in column.enumerated() {
        let x = left ? padding : bounds.width - padding - width
        items.append(Item(
          muscle: anchor.muscle, anchor: anchor.point,
          frame: CGRect(x: x, y: centers[index] - height / 2, width: width, height: height)))
      }
    }
    return items
  }
}
