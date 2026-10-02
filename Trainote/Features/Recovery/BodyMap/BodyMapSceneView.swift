import Metal
import SceneKit
import SwiftUI

struct BodyMapSceneView: UIViewRepresentable {
  let input: BodyMapRenderInput
  let viewpoint: BodyMapViewpoint
  let viewpointRevision: Int
  let policy: BodyMapDisplayPolicy
  let active: Bool
  let onSelect: (BodyMapMuscle) -> Void
  let onUnavailable: () -> Void

  func makeUIView(context: Context) -> BodyMapSceneContainer {
    let view = BodyMapSceneContainer()
    if view.model == nil {
      // Do not mutate SwiftUI state in make/updateUIView.
      DispatchQueue.main.async { onUnavailable() }
    }
    return view
  }

  func updateUIView(_ view: BodyMapSceneContainer, context: Context) {
    view.onSelect = onSelect
    view.configure(input: input, policy: policy, active: active)
    if view.viewpointRevision != viewpointRevision {
      view.viewpointRevision = viewpointRevision
      view.rotate(to: viewpoint.angle)
    }
  }

  static func dismantleUIView(_ view: BodyMapSceneContainer, coordinator: ()) {
    view.sceneView.isPlaying = false
    view.sceneView.scene = nil
    view.onSelect = nil
  }
}

@MainActor
final class BodyMapSceneContainer: UIView, UIGestureRecognizerDelegate {
  let sceneView = SCNView()
  private(set) var model: BodyMapScene?
  private var input = BodyMapRenderInput(regions: [])
  private var buttons: [BodyMapMuscle: UIButton] = [:]
  private var lines: [BodyMapMuscle: CAShapeLayer] = [:]
  private var panStartAngle: Float = 0
  var viewpointRevision: Int?
  var onSelect: ((BodyMapMuscle) -> Void)?

  override init(frame: CGRect) {
    super.init(frame: frame)
    guard MTLCreateSystemDefaultDevice() != nil, let asset = try? BodyMapAsset.load() else { return }
    let model = BodyMapScene(asset: asset)
    self.model = model
    model.update(input: input)
    sceneView.scene = model.scene
    sceneView.pointOfView = model.camera
    sceneView.backgroundColor = .clear
    sceneView.rendersContinuously = false
    sceneView.isPlaying = false
    sceneView.antialiasingMode = .multisampling4X
    sceneView.accessibilityIdentifier = "bodyMap.scene"
    sceneView.isAccessibilityElement = true
    sceneView.accessibilityLabel = "可旋转的三维人体"
    sceneView.accessibilityValue = "前面"
    sceneView.accessibilityHint = "左右拖动旋转，或使用前面、背面按钮。肌群列表提供相同内容。"
    addSubview(sceneView)
    let pan = UIPanGestureRecognizer(target: self, action: #selector(drag(_:)))
    pan.delegate = self
    sceneView.addGestureRecognizer(pan)
    let tap = UITapGestureRecognizer(target: self, action: #selector(tap(_:)))
    tap.require(toFail: pan)
    sceneView.addGestureRecognizer(tap)
    for muscle in BodyMapMuscle.allCases {
      let line = CAShapeLayer()
      line.fillColor = UIColor.clear.cgColor
      line.lineWidth = 1
      layer.addSublayer(line)
      lines[muscle] = line
      let button = UIButton(type: .system)
      button.titleLabel?.numberOfLines = 2
      button.titleLabel?.textAlignment = .center
      button.titleLabel?.font = .systemFont(ofSize: 11, weight: .medium)
      button.layer.cornerRadius = 9
      button.layer.borderWidth = 1
      button.backgroundColor = .secondarySystemGroupedBackground
      button.accessibilityIdentifier = "bodyMap.label.\(muscle.rawValue)"
      button.addAction(UIAction { [weak self] _ in self?.onSelect?(muscle) }, for: .touchUpInside)
      addSubview(button)
      buttons[muscle] = button
    }
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func layoutSubviews() {
    super.layoutSubviews()
    sceneView.frame = bounds
    // Leave room for the full A-pose on narrow containers without cropping the hands.
    model?.camera.camera?.orthographicScale = Double(max(1.01, bounds.height / max(1, bounds.width) * 0.57))
    updateLabels()
  }

  func configure(input: BodyMapRenderInput, policy: BodyMapDisplayPolicy, active: Bool) {
    if self.input != input {
      self.input = input
      model?.update(input: input)
    }
    sceneView.preferredFramesPerSecond = policy.framesPerSecond
    sceneView.antialiasingMode = policy == .economical ? .none : .multisampling4X
    sceneView.isPlaying = false
    sceneView.rendersContinuously = false
    isUserInteractionEnabled = active
    updateLabels()
  }

  func rotate(to angle: Float) {
    guard angle.isFinite else { return }
    model?.body.eulerAngles.y = angle.truncatingRemainder(dividingBy: 2 * .pi)
    let facing = cos(angle)
    sceneView.accessibilityValue = facing > 0.85 ? "前面" : facing < -0.85 ? "背面" : "侧面"
    updateLabels()
  }

  @objc private func drag(_ gesture: UIPanGestureRecognizer) {
    if gesture.state == .began { panStartAngle = model?.body.eulerAngles.y ?? 0 }
    let delta = Float(gesture.translation(in: sceneView).x) * 0.012
    rotate(to: panStartAngle + delta)
  }

  override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
    guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
    let velocity = pan.velocity(in: self)
    return abs(velocity.x) > abs(velocity.y)
  }

  @objc private func tap(_ gesture: UITapGestureRecognizer) {
    guard let muscle = model?.hit(at: gesture.location(in: sceneView), in: sceneView) else { return }
    onSelect?(muscle)
  }

  func updateLabels() {
    guard let model else { return }
    let labels = BodyMapLabelLayout.arrange(anchors: model.projectedAnchors(in: sceneView), bounds: bounds)
    let visible = Set(labels.map(\.muscle))
    for muscle in BodyMapMuscle.allCases {
      buttons[muscle]?.isHidden = !visible.contains(muscle)
      lines[muscle]?.isHidden = !visible.contains(muscle)
    }
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    for item in labels {
      let region = input[item.muscle]
      let selected = input.selected == item.muscle
      let button = buttons[item.muscle]!
      button.frame = item.frame
      let score = region.displayedScore.map(String.init) ?? "—"
      button.setTitle("\(selected ? "✓ " : "")\(region.muscle.title)  \(score)\n\(region.status)", for: .normal)
      button.setTitleColor(.label, for: .normal)
      button.layer.borderColor = selected ? UIColor.label.cgColor : region.color.withAlphaComponent(0.5).cgColor
      button.layer.borderWidth = selected ? 2 : 1
      button.accessibilityLabel = region.accessibilityText
      button.accessibilityHint = "查看肌群详情"
      button.accessibilityTraits = selected ? [.button, .selected] : [.button]
      let left = item.frame.midX < bounds.midX
      let endpoint = CGPoint(x: left ? item.frame.maxX : item.frame.minX, y: item.frame.midY)
      let elbow = CGPoint(x: endpoint.x + (left ? 9 : -9), y: endpoint.y)
      let path = UIBezierPath()
      path.move(to: item.anchor)
      path.addLine(to: elbow)
      path.addLine(to: endpoint)
      let line = lines[item.muscle]!
      line.path = path.cgPath
      line.strokeColor = UIColor.secondaryLabel.withAlphaComponent(0.7).cgColor
      line.lineDashPattern = region.score == nil ? [3, 3] : nil
      line.lineWidth = selected ? 2 : 0.8
    }
    CATransaction.commit()
  }
}
