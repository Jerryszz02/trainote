import SwiftUI

/// Rendering-only surface. The parent owns selection and opens its own detail presentation.
struct BodyMapRendererView: View {
  let input: BodyMapRenderInput
  let onSelect: (MuscleID) -> Void
  var constrainedPolicy: BodyMapDisplayPolicy? = nil

  @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.colorScheme) private var colorScheme
  @State private var showsList = false
  @State private var shows3D = false
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
        Text(L10n.text("health.bodymaprendererview.muscle.recovery.index.a6164e")).font(.headline)
        Spacer()
        if policy != .list {
          Button {
            showsList.toggle()
          } label: {
            Label(
              showsList ? L10n.text("health.bodymaprendererview.body.map.f7851a") : L10n.text("health.bodymaprendererview.muscle.list.82c206"), systemImage: showsList ? "figure.stand" : "list.bullet"
            )
            .frame(minHeight: 44)
          }
          .font(.subheadline)
          .accessibilityIdentifier("bodyMap.toggleList")
        }
      }
      if input.isEmpty {
        Label(L10n.text("health.bodymaprendererview.waiting.for.records.dda84c"), systemImage: "questionmark.circle")
          .font(.subheadline).foregroundStyle(Color(uiColor: .label).opacity(0.75))
        Text(L10n.text("health.bodymaprendererview.muscle.status.appears.here.after.you.18800f"))
          .font(.caption).foregroundStyle(Color(uiColor: .label).opacity(0.75))
      }
      if policy == .list || showsList {
        if policy == .list {
          Text(L10n.text("health.bodymaprendererview.showing.a.muscle.list.tap.to.a28dec"))
            .font(.caption).foregroundStyle(Color(uiColor: .label).opacity(0.75))
            .accessibilityIdentifier("bodyMap.fallback")
        }
        muscleList
      } else {
        Picker(L10n.text("health.bodymaprendererview.body.display.mode.087fc2"), selection: $shows3D) {
          Text(L10n.text("health.bodymaprendererview.muscle.map.5badd3")).tag(false)
          Text(L10n.text("health.bodymaprendererview.3d.rotation.754d6c")).tag(true)
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("bodyMap.displayMode")
        if shows3D {
          HStack(spacing: 12) {
            Button {
              setViewpoint(.front)
            } label: {
              Text(L10n.text("health.bodymaprendererview.front.9c61cc")).frame(minHeight: 32)
            }
            .accessibilityIdentifier("bodyMap.front")
            Button {
              setViewpoint(.back)
            } label: {
              Text(L10n.text("health.bodymaprendererview.back.2d9ca5")).frame(minHeight: 32)
            }
            .accessibilityIdentifier("bodyMap.back")
            Spacer()
            Label(L10n.text("health.bodymaprendererview.drag.left.or.right.to.rotate.50627a"), systemImage: "rotate.3d")
              .font(.caption).foregroundStyle(Color(uiColor: .label).opacity(0.75))
          }
          .buttonStyle(.bordered)
          BodyMapSceneView(
            input: input, viewpoint: viewpoint, viewpointRevision: viewpointRevision,
            policy: policy, active: scenePhase == .active,
            onSelect: onSelect, onUnavailable: { rendererAvailable = false }
          )
          .frame(height: 430)
          .background(
            Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18)
          )
          .clipShape(RoundedRectangle(cornerRadius: 18))
        } else {
          BodyMapAnatomyView(input: input, onSelect: onSelect,
            onUnavailable: { rendererAvailable = false })
            .frame(height: 330)
            .clipShape(RoundedRectangle(cornerRadius: 18))
          HStack {
            Text(L10n.text("health.bodymaprendererview.front.70c219")).frame(maxWidth: .infinity)
            Text(L10n.text("health.bodymaprendererview.back.2d9ca5")).frame(maxWidth: .infinity)
          }
          .font(.caption).foregroundStyle(.secondary)
        }
        if let selected = input.selected {
          let region = input[selected]
          HStack {
            Image(systemName: region.isLimited ? "exclamationmark.triangle.fill" : "checkmark.circle.fill").foregroundStyle(Color(region.color))
            Text("\(selected.bodyMapTitle) · \(region.scoreText) · \(region.status)")
              .font(.subheadline)
          }
          .accessibilityElement(children: .combine)
          .accessibilityIdentifier("bodyMap.selection")
        }
        legend
      }
    }
    .tint(.primary)
    .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
      lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    }
    .onReceive(
      NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification)
    ) { _ in
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
            Image(
              systemName: region.isLimited
                ? "exclamationmark.triangle"
                : region.score == nil ? "questionmark.circle" : "circle.fill"
            )
            .font(.system(size: 18))
            .foregroundStyle(Color(region.color))
            .frame(width: 20)
            VStack(alignment: .leading, spacing: 3) {
              Text(region.muscle.bodyMapTitle).font(.body.weight(.medium))
              Text(region.status).font(.subheadline).foregroundStyle(
                Color(uiColor: .label).opacity(0.8))
            }
            Spacer(minLength: 8)
            Text(region.scoreText).monospacedDigit()
            if input.selected == region.muscle {
              Image(systemName: "checkmark").font(.system(size: 18, weight: .semibold))
            }
          }
          .foregroundStyle(.primary)
          .padding(.vertical, 12)
          .frame(minHeight: 52)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(region.accessibilityText)
        .accessibilityHint(L10n.text("health.bodymaprendererview.view.muscle.details.7376b2"))
        .accessibilityAddTraits(input.selected == region.muscle ? .isSelected : [])
        .accessibilityIdentifier("bodyMap.row.\(region.muscle.rawValue)")
        if region.muscle != .calves { Divider() }
      }
    }
  }

  private var legend: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 14) {
        Label {
          Text(L10n.text("health.bodymaprendererview.low.b9ee25"))
        } icon: {
          Image(systemName: "circle.fill").foregroundStyle(
            colorScheme == .dark
              ? Color(red: 0.96, green: 0.40, blue: 0.34)
              : Color(red: 0.68, green: 0.18, blue: 0.15))
        }
        Image(systemName: "arrow.right").foregroundStyle(Color(uiColor: .label).opacity(0.75))
        Label {
          Text(L10n.text("health.bodymaprendererview.high.b096b3"))
        } icon: {
          Image(systemName: "circle.fill").foregroundStyle(
            colorScheme == .dark
              ? Color(red: 0.25, green: 0.80, blue: 0.55)
              : Color(red: 0.10, green: 0.42, blue: 0.28))
        }
        Label(L10n.text("health.bodymaprendererview.unknown.d9c32a"), systemImage: "questionmark.circle").foregroundStyle(
          Color(uiColor: .label).opacity(0.75))
      }
      Label(shows3D ? L10n.text("health.bodymaprendererview.pain.or.limited.movement.amber.indicator.1dac3f") : L10n.text("health.bodymaprendererview.pain.or.limited.movement.amber.dashed.96740a"),
        systemImage: "exclamationmark.triangle")
        .foregroundStyle(Color(uiColor: .label).opacity(0.8))
      Text(L10n.text("health.bodymaprendererview.scores.shown.in.steps.of.5.d1d719"))
        .foregroundStyle(Color(uiColor: .label).opacity(0.75))
    }
    .font(.caption)
  }

  private func setViewpoint(_ value: BodyMapViewpoint) {
    viewpoint = value
    viewpointRevision += 1
  }
}
