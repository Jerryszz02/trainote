import SwiftUI

/// Rendering-only surface. The parent owns selection and opens its own detail presentation.
struct BodyMapRendererView: View {
  let input: BodyMapRenderInput
  let onSelect: (BodyMapMuscle) -> Void
  var constrainedPolicy: BodyMapDisplayPolicy? = nil

  @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Environment(\.scenePhase) private var scenePhase
  @State private var showsList = false
  @State private var rendererAvailable = true
  @State private var viewpoint: BodyMapViewpoint = .front
  @State private var viewpointRevision = 0
  @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
  @State private var thermalState = ProcessInfo.processInfo.thermalState

  private var policy: BodyMapDisplayPolicy {
    let automatic = BodyMapDisplayPolicy.resolve(
      voiceOver: voiceOver, largeText: dynamicTypeSize.isAccessibilitySize,
      lowPower: lowPower, thermalState: thermalState, rendererAvailable: rendererAvailable)
    if automatic == .list || constrainedPolicy == .list { return .list }
    return constrainedPolicy == .economical ? .economical : automatic
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("肌群恢复指数").font(.headline)
        Spacer()
        if policy != .list {
          Button(showsList ? "3D 人体" : "肌群列表", systemImage: showsList ? "figure.stand" : "list.bullet") {
            showsList.toggle()
          }
          .font(.subheadline)
          .accessibilityIdentifier("bodyMap.toggleList")
        }
      }
      if input.isEmpty {
        Label("待建立记录", systemImage: "questionmark.circle")
          .font(.subheadline).foregroundStyle(.secondary)
        Text("记录训练后，肌群状态会显示在这里。")
          .font(.caption).foregroundStyle(.secondary)
      }
      if policy == .list || showsList {
        if policy == .list {
          Text("以肌群列表显示，点按查看详情。")
            .font(.caption).foregroundStyle(.secondary)
            .accessibilityIdentifier("bodyMap.fallback")
        }
        muscleList
      } else {
        HStack(spacing: 12) {
          Button("前面") { setViewpoint(.front) }
            .accessibilityIdentifier("bodyMap.front")
          Button("背面") { setViewpoint(.back) }
            .accessibilityIdentifier("bodyMap.back")
          Spacer()
          Label("左右拖动旋转", systemImage: "rotate.3d")
            .font(.caption).foregroundStyle(.secondary)
        }
        .buttonStyle(.bordered)
        BodyMapSceneView(
          input: input, viewpoint: viewpoint, viewpointRevision: viewpointRevision,
          policy: policy, active: scenePhase == .active,
          onSelect: onSelect, onUnavailable: { rendererAvailable = false })
          .frame(height: 430)
          .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
          .clipShape(RoundedRectangle(cornerRadius: 18))
        if let selected = input.selected {
          let region = input[selected]
          HStack {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Color(region.color))
            Text("\(selected.title) · \(region.scoreText) · \(region.status)")
              .font(.subheadline)
          }
          .accessibilityElement(children: .combine)
          .accessibilityIdentifier("bodyMap.selection")
        }
        legend
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
      lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    }
    .onReceive(NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification)) { _ in
      thermalState = ProcessInfo.processInfo.thermalState
    }
    .onChange(of: scenePhase) { _, phase in
      if phase == .active {
        lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        thermalState = ProcessInfo.processInfo.thermalState
      }
    }
  }

  private var muscleList: some View {
    VStack(spacing: 0) {
      ForEach(input.regions) { region in
        Button {
          onSelect(region.muscle)
        } label: {
          HStack(alignment: .center, spacing: 12) {
            Image(systemName: region.score == nil ? "questionmark.circle" : "circle.fill")
              .foregroundStyle(Color(region.color))
              .frame(width: 20)
            VStack(alignment: .leading, spacing: 3) {
              Text(region.muscle.title).font(.body.weight(.medium))
              Text(region.status).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(region.scoreText).monospacedDigit()
            if input.selected == region.muscle { Image(systemName: "checkmark") }
          }
          .foregroundStyle(.primary)
          .padding(.vertical, 12)
          .frame(minHeight: 52)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(region.accessibilityText)
        .accessibilityHint("查看肌群详情")
        .accessibilityAddTraits(input.selected == region.muscle ? .isSelected : [])
        .accessibilityIdentifier("bodyMap.row.\(region.muscle.rawValue)")
        if region.muscle != .calves { Divider() }
      }
    }
    .accessibilityIdentifier("bodyMap.list")
  }

  private var legend: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 14) {
        Label("低", systemImage: "circle.fill").foregroundStyle(Color(BodyMapRegion(muscle: .chest, score: 0, status: "").color))
        Image(systemName: "arrow.right").foregroundStyle(.secondary)
        Label("高", systemImage: "circle.fill").foregroundStyle(Color(BodyMapRegion(muscle: .chest, score: 100, status: "").color))
        Label("未知", systemImage: "questionmark.circle").foregroundStyle(.secondary)
      }
      Text("分数按 5 分显示 · 点按肌群查看详情")
        .foregroundStyle(.secondary)
    }
    .font(.caption)
  }

  private func setViewpoint(_ value: BodyMapViewpoint) {
    viewpoint = value
    viewpointRevision += 1
  }
}
