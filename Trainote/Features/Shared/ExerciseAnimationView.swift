import AVFoundation
import SwiftUI
import UIKit

struct ExerciseAnimationView: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.scenePhase) private var scenePhase
  @StateObject private var playback = ExerciseAnimationPlayback()

  let exerciseID: String
  private let media = ExerciseMediaCatalog()

  var body: some View {
    switch media.availability(for: exerciseID) {
    case .notCollected:
      Text("此动作暂未收录动态演示，可查看下方动作说明。")
        .font(.footnote)
        .foregroundStyle(.secondary)
        .accessibilityIdentifier("exerciseAnimation.notCollected")
    case .unavailable:
      unavailableMessage
    case .available(let entry, let videoURL, let posterURL):
      if playback.hasFailed {
        unavailableMessage
      } else {
        VStack(alignment: .leading, spacing: 8) {
          ZStack(alignment: .bottomTrailing) {
            Color(.secondarySystemGroupedBackground)
            if let poster = UIImage(contentsOfFile: posterURL.path) {
              Image(uiImage: poster).resizable().scaledToFit()
            }
            if let player = playback.player, playback.hasStarted {
              ExercisePlayerSurface(player: player)
                .accessibilityHidden(true)
            }
            Button {
              playback.toggle()
            } label: {
              Label(playback.isPlaying ? "暂停演示" : "播放演示",
                    systemImage: playback.isPlaying ? "pause.fill" : "play.fill")
                .font(.caption.weight(.semibold))
                .padding(10)
                .background(.regularMaterial, in: Capsule())
            }
            .padding(10)
            .disabled(!playback.isReady)
            .accessibilityIdentifier("exerciseAnimation.toggle")
            .accessibilityValue(playback.isReady ? (playback.isPlaying ? "播放中" : "已暂停") : "准备中")
          }
          .frame(height: 210)
          .clipShape(RoundedRectangle(cornerRadius: 12))
          Text("动作演示 · 胸部、肱三头肌")
            .font(.caption.weight(.medium))
          Text(entry.attribution)
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .onAppear {
          playback.prepare(url: videoURL, autoplay: !reduceMotion && scenePhase == .active)
        }
        .onDisappear { playback.stop() }
        .onChange(of: scenePhase) { _, phase in
          if phase != .active { playback.pause() }
        }
        .onChange(of: reduceMotion) { _, reduced in
          if reduced { playback.pause() }
        }
      }
    }
  }

  private var unavailableMessage: some View {
    Text("动作演示暂时无法播放，请查看下方动作说明。")
      .font(.footnote)
      .foregroundStyle(.secondary)
      .accessibilityIdentifier("exerciseAnimation.unavailable")
  }
}

@MainActor
final class ExerciseAnimationPlayback: ObservableObject {
  @Published private(set) var player: AVQueuePlayer?
  @Published private(set) var isPlaying = false
  @Published private(set) var isReady = false
  @Published private(set) var hasFailed = false
  @Published private(set) var hasStarted = false

  private var looper: AVPlayerLooper?
  private var currentItemObservation: NSKeyValueObservation?
  private var statusObservation: NSKeyValueObservation?
  private var loadTask: Task<Void, Never>?
  private var timeoutTask: Task<Void, Never>?
  private var generation = UUID()
  private var shouldAutoplay = false

  func prepare(url: URL, autoplay: Bool) {
    stop()
    hasFailed = false
    shouldAutoplay = autoplay
    let current = generation
    timeoutTask = Task { [weak self] in
      try? await Task.sleep(for: .seconds(8))
      guard !Task.isCancelled, let self, self.generation == current, !self.isReady else { return }
      self.fail()
    }
    loadTask = Task { [weak self] in
      do {
        let asset = AVURLAsset(url: url)
        guard try await asset.load(.isPlayable) else {
          self?.fail(ifGeneration: current)
          return
        }
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard !tracks.isEmpty, !Task.isCancelled,
          let self, self.generation == current else {
          self?.fail(ifGeneration: current)
          return
        }
        let item = AVPlayerItem(asset: asset)
        let queue = AVQueuePlayer()
        queue.isMuted = true
        self.player = queue
        // The looper enqueues its copies asynchronously. A nil current item while it
        // prepares is normal; observe the queue instead of failing before it is ready.
        self.currentItemObservation = queue.observe(\.currentItem, options: [.initial, .new]) {
          [weak self, weak queue] _, _ in
          Task { @MainActor [weak self, weak queue] in
            guard let self, let queue, self.generation == current else { return }
            self.observeStatus(of: queue.currentItem, generation: current)
          }
        }
        self.looper = AVPlayerLooper(player: queue, templateItem: item)
      } catch {
        self?.fail(ifGeneration: current)
      }
    }
  }

  private func observeStatus(of item: AVPlayerItem?, generation current: UUID) {
    statusObservation?.invalidate()
    statusObservation = nil
    guard let item else { return }
    statusObservation = item.observe(\.status, options: [.initial, .new]) {
      [weak self] observed, _ in
      let status = observed.status
      Task { @MainActor [weak self, weak observed] in
        guard let self, self.generation == current,
          let observed, self.player?.currentItem === observed else { return }
        switch status {
        case .readyToPlay:
          self.isReady = true
          self.timeoutTask?.cancel()
          if self.shouldAutoplay { self.toggle() }
        case .failed: self.fail()
        default: break
        }
      }
    }
  }

  func toggle() {
    guard isReady, let player else { return }
    if isPlaying { pause() } else {
      shouldAutoplay = false
      player.play()
      hasStarted = true
      isPlaying = true
    }
  }

  func pause() {
    shouldAutoplay = false
    player?.pause()
    isPlaying = false
  }

  func stop() {
    generation = UUID()
    loadTask?.cancel()
    timeoutTask?.cancel()
    loadTask = nil
    timeoutTask = nil
    currentItemObservation?.invalidate()
    currentItemObservation = nil
    statusObservation?.invalidate()
    statusObservation = nil
    pause()
    looper?.disableLooping()
    looper = nil
    player?.removeAllItems()
    player = nil
    isReady = false
    hasStarted = false
  }

  private func fail(ifGeneration expected: UUID? = nil) {
    if let expected, expected != generation { return }
    stop()
    hasFailed = true
  }
}

private struct ExercisePlayerSurface: UIViewRepresentable {
  let player: AVPlayer

  func makeUIView(context: Context) -> PlayerView {
    let view = PlayerView()
    view.layerPlayer.videoGravity = .resizeAspect
    view.layerPlayer.player = player
    return view
  }

  func updateUIView(_ uiView: PlayerView, context: Context) {
    uiView.layerPlayer.player = player
  }

  static func dismantleUIView(_ uiView: PlayerView, coordinator: ()) {
    uiView.layerPlayer.player = nil
  }

  final class PlayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var layerPlayer: AVPlayerLayer { layer as! AVPlayerLayer }
  }
}
