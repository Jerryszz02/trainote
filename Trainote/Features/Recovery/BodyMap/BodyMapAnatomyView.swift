import SwiftUI
import UIKit

/// Offline anatomical illustrations with independently selectable native vector muscle masks.
struct BodyMapAnatomyAsset: Decodable {
  let version: Int
  let width: Double
  let height: Double
  let masks: [Mask]

  struct Mask: Decodable {
    let id: String
    let muscle: MuscleID
    let side: String
    let commands: [[Double]]

    var path: CGPath {
      let path = CGMutablePath()
      for command in commands {
        switch Int(command[0]) {
        case 0: path.closeSubpath()
        case 1: path.move(to: CGPoint(x: command[1], y: command[2]))
        case 2: path.addLine(to: CGPoint(x: command[1], y: command[2]))
        case 3:
          path.addCurve(to: CGPoint(x: command[5], y: command[6]),
            control1: CGPoint(x: command[1], y: command[2]),
            control2: CGPoint(x: command[3], y: command[4]))
        default: break
        }
      }
      return path
    }
  }

  enum AssetError: Error { case missingResource, invalidMasks }

  static func resource(_ name: String, extension suffix: String, bundle: Bundle = .main) -> URL? {
    bundle.url(forResource: name, withExtension: suffix, subdirectory: "BodyMap")
      ?? bundle.url(forResource: name, withExtension: suffix)
  }

  static func load(bundle: Bundle = .main) throws -> Self {
    guard let url = resource("anatomy-masks", extension: "json", bundle: bundle) else {
      throw AssetError.missingResource
    }
    let asset = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
    try asset.validate()
    return asset
  }

  func validate() throws {
    guard version == 1, width.isFinite, height.isFinite, width > 0, height > 0,
      masks.count <= 100, Set(masks.map(\.muscle)) == Set(MuscleID.allCases),
      Set(masks.map(\.side)) == Set(["front", "back"]),
      Set(masks.map { "\($0.side).\($0.id)" }).count == masks.count
    else { throw AssetError.invalidMasks }
    for mask in masks {
      guard !mask.commands.isEmpty, mask.commands.first?.first == 1 else {
        throw AssetError.invalidMasks
      }
      for command in mask.commands {
        guard let kind = command.first, [0.0, 1, 2, 3].contains(kind),
          command.count == (kind == 0 ? 1 : kind == 3 ? 7 : 3),
          command.allSatisfy({ $0.isFinite && abs($0) < 2000 })
        else { throw AssetError.invalidMasks }
      }
      let bounds = mask.path.boundingBoxOfPath
      guard !bounds.isEmpty, bounds.minX >= 0, bounds.minY >= 0,
        bounds.maxX <= width, bounds.maxY <= height
      else { throw AssetError.invalidMasks }
    }
  }

  func paths(side: String) -> [MuscleID: CGPath] {
    var paths: [MuscleID: CGMutablePath] = [:]
    for mask in masks where mask.side == side {
      let path = paths[mask.muscle] ?? CGMutablePath()
      path.addPath(mask.path)
      paths[mask.muscle] = path
    }
    return paths.mapValues { $0 as CGPath }
  }
}

struct BodyMapAnatomyView: UIViewRepresentable {
  let input: BodyMapRenderInput
  let onSelect: (MuscleID) -> Void
  let onUnavailable: () -> Void

  func makeUIView(context: Context) -> BodyMapAnatomyContainer {
    let view = BodyMapAnatomyContainer()
    if !view.isAvailable { DispatchQueue.main.async { onUnavailable() } }
    return view
  }

  func updateUIView(_ view: BodyMapAnatomyContainer, context: Context) {
    view.configure(input: input, onSelect: onSelect)
  }

  static func dismantleUIView(_ view: BodyMapAnatomyContainer, coordinator: ()) {
    view.onSelect = nil
  }
}

private final class AnatomyMuscleButton: UIButton {
  var musclePath = CGPath(rect: .zero, transform: nil)
  override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
    musclePath.contains(point)
  }
}

final class BodyMapAnatomyContainer: UIView {
  let asset = try? BodyMapAnatomyAsset.load()
  var isAvailable: Bool { asset != nil && images.count == 2 }
  var onSelect: ((MuscleID) -> Void)?
  private var input = BodyMapRenderInput(regions: [])
  private var images: [String: UIImage] = [:]
  private var paths: [String: [MuscleID: CGPath]] = [:]
  private var buttons: [String: AnatomyMuscleButton] = [:]

  override init(frame: CGRect) {
    super.init(frame: frame)
    backgroundColor = .white
    accessibilityIdentifier = "bodyMap.anatomy"
    guard let asset else { return }
    for side in ["front", "back"] {
      if let url = BodyMapAnatomyAsset.resource("anatomy-\(side)", extension: "png") {
        images[side] = UIImage(contentsOfFile: url.path)
      }
      paths[side] = asset.paths(side: side)
      for muscle in MuscleID.allCases where paths[side]?[muscle] != nil {
        let button = AnatomyMuscleButton(type: .custom)
        button.accessibilityIdentifier = "bodyMap.label.\(muscle.rawValue)"
        button.accessibilityHint = "查看肌群详情"
        button.addAction(UIAction { [weak self] _ in self?.onSelect?(muscle) }, for: .touchUpInside)
        addSubview(button)
        buttons["\(side).\(muscle.rawValue)"] = button
      }
    }
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  func configure(input: BodyMapRenderInput, onSelect: @escaping (MuscleID) -> Void) {
    self.input = input
    self.onSelect = onSelect
    for side in ["front", "back"] {
      for region in input.regions {
        let button = buttons["\(side).\(region.muscle.rawValue)"]
        button?.accessibilityLabel = region.accessibilityText
        button?.accessibilityTraits = input.selected == region.muscle ? [.button, .selected] : .button
      }
    }
    setNeedsDisplay()
  }

  private func transform(side: String) -> CGAffineTransform {
    guard let asset else { return .identity }
    let half = bounds.width / 2
    let scale = min((half - 8) / asset.width, bounds.height / asset.height)
    return CGAffineTransform(a: scale, b: 0, c: 0, d: scale,
      tx: (side == "front" ? 0 : half) + (half - asset.width * scale) / 2,
      ty: (bounds.height - asset.height * scale) / 2)
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    for side in ["front", "back"] {
      for (muscle, path) in paths[side] ?? [:] {
        var transform = transform(side: side)
        let projected = path.copy(using: &transform)!
        let button = buttons["\(side).\(muscle.rawValue)"]!
        button.frame = projected.boundingBoxOfPath
        var local = CGAffineTransform(translationX: -button.frame.minX, y: -button.frame.minY)
        button.musclePath = projected.copy(using: &local)!
      }
    }
    setNeedsDisplay()
  }

  override func draw(_ rect: CGRect) {
    guard let asset, let context = UIGraphicsGetCurrentContext() else { return }
    for side in ["front", "back"] {
      context.saveGState()
      context.concatenate(transform(side: side))
      images[side]?.draw(in: CGRect(x: 0, y: 0, width: asset.width, height: asset.height))
      for muscle in MuscleID.allCases {
        guard let path = paths[side]?[muscle] else { continue }
        let region = input[muscle]
        // Unknown retains the neutral anatomical shading; limitations still show amber.
        if region.score != nil || region.isLimited {
          context.setBlendMode(.multiply)
          context.setFillColor(region.color.withAlphaComponent(0.64).cgColor)
          context.addPath(path)
          context.fillPath()
        }
        context.setBlendMode(.normal)
        if input.selected == muscle || region.isLimited {
          context.setStrokeColor((region.isLimited ? UIColor.systemOrange : UIColor.black).cgColor)
          context.setLineWidth(input.selected == muscle ? 2.5 : 1.6)
          context.setLineDash(phase: 0, lengths: region.isLimited ? [3, 2] : [])
          context.addPath(path)
          context.strokePath()
        }
      }
      context.restoreGState()
    }
  }
}
