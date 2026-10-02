import Foundation
import SceneKit
import simd

/// Original, compact ring profiles are the asset; no downloaded anatomy meshes or textures.
struct BodyMapAsset: Decodable {
  let version: Int
  let meshes: [Mesh]

  struct Mesh: Decodable {
    let name: String
    let muscle: MuscleID?
    let rings: [Ring]
    let facing: Float?
  }

  struct Ring: Decodable {
    let center: [Float]
    let radius: [Float]
  }

  enum AssetError: Error { case missingResource, invalidGeometry }

  static func load(bundle: Bundle = .main) throws -> Self {
    let url =
      bundle.url(forResource: "body-map-v1", withExtension: "json", subdirectory: "BodyMap")
      ?? bundle.url(forResource: "body-map-v1", withExtension: "json")
    guard let url else { throw AssetError.missingResource }
    let asset = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
    try asset.validate()
    return asset
  }

  func validate() throws {
    guard version == 1, (1...150).contains(meshes.count),
      Set(meshes.map(\.name)).count == meshes.count,
      Set(meshes.compactMap(\.muscle)) == Set(MuscleID.allCases)
    else { throw AssetError.invalidGeometry }
    for mesh in meshes {
      guard (3...24).contains(mesh.rings.count), !mesh.name.isEmpty,
        mesh.facing.map({ $0 == 1 || $0 == -1 }) ?? true
      else { throw AssetError.invalidGeometry }
      var lastY = -Float.infinity
      for ring in mesh.rings {
        guard ring.center.count == 3, ring.radius.count == 2,
          ring.center.allSatisfy({ $0.isFinite && abs($0) <= 3 }),
          ring.radius.allSatisfy({ $0.isFinite && $0 > 0 && $0 <= 1 }),
          ring.center[1] > lastY
        else { throw AssetError.invalidGeometry }
        lastY = ring.center[1]
      }
    }
  }
}

/// Closed, curved volumes: Catmull–Rom interpolated elliptical cross-sections and triangle caps.
/// The compact control profiles (not spheres or 2D overlays) define the anatomical silhouette.
enum BodyMapGeometry {
  struct MeshData {
    let positions: [SIMD3<Float>]
    let normals: [SIMD3<Float>]
    let indices: [UInt32]

    var geometry: SCNGeometry {
      let vertices = positions.map { SCNVector3($0.x, $0.y, $0.z) }
      let normalVectors = normals.map { SCNVector3($0.x, $0.y, $0.z) }
      return SCNGeometry(
        sources: [.init(vertices: vertices), .init(normals: normalVectors)],
        elements: [.init(indices: indices, primitiveType: .triangles)])
    }
  }

  static func make(_ mesh: BodyMapAsset.Mesh, radialSegments: Int = 24, subdivisions: Int = 4)
    -> MeshData
  {
    let slices = max(8, radialSegments)
    let steps = max(1, subdivisions)
    var positions = [SIMD3<Float>]()
    let rings = mesh.rings
    for i in 0..<((rings.count - 1) * steps + 1) {
      let segment = min(i / steps, rings.count - 2)
      let t = Float(i - segment * steps) / Float(steps)
      let a = rings[max(0, segment - 1)]
      let b = rings[segment]
      let c = rings[segment + 1]
      let d = rings[min(rings.count - 1, segment + 2)]
      func interpolate(_ values: [Float]) -> Float {
        let a = values[0]
        let b = values[1]
        let c = values[2]
        let d = values[3]
        return 0.5
          * ((2 * b) + (-a + c) * t
            + (2 * a - 5 * b + 4 * c - d) * t * t
            + (-a + 3 * b - 3 * c + d) * t * t * t)
      }
      let center = (0..<3).map { axis in
        interpolate([a.center[axis], b.center[axis], c.center[axis], d.center[axis]])
      }
      let radius = (0..<2).map { axis in
        max(0.0005, interpolate([a.radius[axis], b.radius[axis], c.radius[axis], d.radius[axis]]))
      }
      for j in 0..<slices {
        let angle = Float(j) * 2 * .pi / Float(slices)
        positions.append(
          SIMD3(
            center[0] + radius[0] * cos(angle), center[1], center[2] + radius[1] * sin(angle)))
      }
    }
    let ringCount = positions.count / slices
    var indices = [UInt32]()
    for i in 0..<(ringCount - 1) {
      for j in 0..<slices {
        let a = UInt32(i * slices + j)
        let b = UInt32(i * slices + (j + 1) % slices)
        let c = UInt32((i + 1) * slices + j)
        let d = UInt32((i + 1) * slices + (j + 1) % slices)
        indices += [a, c, b, b, c, d]
      }
    }
    let bottom = UInt32(positions.count)
    let top = bottom + 1
    positions.append(SIMD3(rings[0].center[0], rings[0].center[1], rings[0].center[2]))
    let last = rings[rings.count - 1]
    positions.append(SIMD3(last.center[0], last.center[1], last.center[2]))
    for j in 0..<slices {
      let next = (j + 1) % slices
      indices += [bottom, UInt32(j), UInt32(next)]
      indices += [
        top, UInt32((ringCount - 1) * slices + next), UInt32((ringCount - 1) * slices + j),
      ]
    }
    var normals = [SIMD3<Float>](repeating: .zero, count: positions.count)
    for i in stride(from: 0, to: indices.count, by: 3) {
      let a = Int(indices[i])
      let b = Int(indices[i + 1])
      let c = Int(indices[i + 2])
      let normal = simd_cross(positions[b] - positions[a], positions[c] - positions[a])
      normals[a] += normal
      normals[b] += normal
      normals[c] += normal
    }
    normals = normals.map { simd_length_squared($0) > 0 ? simd_normalize($0) : SIMD3(0, 1, 0) }
    return MeshData(positions: positions, normals: normals, indices: indices)
  }
}
