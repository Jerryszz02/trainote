import SceneKit
import UIKit

/// Local synthetic preview instrumentation only; this file is outside the production target.
@MainActor
enum BodyMapPerformanceProbe {
  static func run() async -> String {
    guard
      let window = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
        .flatMap(\.windows).first(where: \.isKeyWindow),
      let container = findContainer(in: window)
    else { return "No renderer" }
    let frames = FrameCounter()
    container.sceneView.delegate = frames
    let rate = container.sceneView.preferredFramesPerSecond
    let start = CACurrentMediaTime()
    var peakMemory = footprintMB()
    // Five seconds of actual scene redraws, after a one-second warmup.
    for index in 0..<(rate * 6) {
      if index == rate { frames.reset() }
      container.rotate(to: Float(index) / Float(rate) * .pi / 2)
      peakMemory = max(peakMemory, footprintMB())
      let next = start + Double(index + 1) / Double(rate)
      let delay = max(0, next - CACurrentMediaTime())
      try? await Task.sleep(for: .seconds(delay))
    }
    let times = frames.times
    let intervals = zip(times.dropFirst(), times).map { ($0 - $1) * 1000 }.sorted()
    let fps = times.count > 1 ? Double(times.count - 1) / (times.last! - times.first!) : 0
    let p95 =
      intervals.isEmpty
      ? 0 : intervals[min(intervals.count - 1, Int(Double(intervals.count) * 0.95))]
    try? await Task.sleep(for: .milliseconds(200))
    frames.reset()
    try? await Task.sleep(for: .seconds(2))
    let idleFrames = frames.times.count
    container.sceneView.delegate = nil
    return String(
      format: "target=%d fps=%.1f p95=%.1fms frames=%d peak=%.1fMiB idle=%d",
      rate, fps, p95, times.count, peakMemory, idleFrames)
  }

  private static func findContainer(in view: UIView) -> BodyMapSceneContainer? {
    if let container = view as? BodyMapSceneContainer { return container }
    return view.subviews.lazy.compactMap { findContainer(in: $0) }.first
  }

  private static func footprintMB() -> Double {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(
      MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
    let status = withUnsafeMutablePointer(to: &info) { pointer in
      pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { pointer in
        task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), pointer, &count)
      }
    }
    return status == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : 0
  }
}

private final class FrameCounter: NSObject, SCNSceneRendererDelegate {
  private let lock = NSLock()
  private var timestamps: [Double] = []
  var times: [Double] {
    lock.lock()
    defer { lock.unlock() }
    return timestamps
  }
  func reset() {
    lock.lock()
    timestamps.removeAll(keepingCapacity: true)
    lock.unlock()
  }
  func renderer(
    _ renderer: any SCNSceneRenderer, didRenderScene scene: SCNScene, atTime time: TimeInterval
  ) {
    lock.lock()
    timestamps.append(CACurrentMediaTime())
    lock.unlock()
  }
}
