import AVFoundation
import XCTest
import UIKit

@testable import Trainote

@MainActor
final class ExerciseMediaTests: XCTestCase {
  func testBundledSampleOnlyMatchesExactPushUpIDAndHasPlayableVideo() async throws {
    let catalog = ExerciseMediaCatalog()
    guard case .available(let entry, let video, let poster) = catalog.availability(for: "0662") else {
      return XCTFail("俯卧撑样片及海报必须随 App 离线打包")
    }
    XCTAssertEqual(entry.exerciseID, "0662")
    XCTAssertNotNil(UIImage(contentsOfFile: poster.path))
    let asset = AVURLAsset(url: video)
    let playable = try await asset.load(.isPlayable)
    let tracks = try await asset.loadTracks(withMediaType: .video)
    XCTAssertTrue(playable)
    XCTAssertFalse(tracks.isEmpty)

    let exerciseCatalog = ExerciseCatalog()
    await exerciseCatalog.load()
    let exercises = exerciseCatalog.items
    XCTAssertFalse(exercises.isEmpty)
    for exercise in exercises where exercise.id != "0662" {
      guard case .notCollected = catalog.availability(for: exercise.id) else {
        return XCTFail("样片不能映射至变式或其他动作：\(exercise.id)")
      }
    }
    guard case .notCollected = catalog.availability(for: "push-up") else {
      return XCTFail("动作名称不能用作媒体 ID")
    }
  }

  func testMissingResourcesAndInvalidFilenamesReturnUnavailable() {
    let missing = ExerciseMediaCatalog(entries: [sampleEntry()], resourceURL: { _ in nil })
    guard case .unavailable = missing.availability(for: "0662") else {
      return XCTFail("缺失资源应展示文字回退")
    }

    for name in ["../push-up.mp4", "https://example.com/video.mp4", "push-up.mov", "/push-up.mp4"] {
      var lookupCount = 0
      let catalog = ExerciseMediaCatalog(entries: [sampleEntry(video: name)]) { _ in
        lookupCount += 1
        return nil
      }
      guard case .unavailable = catalog.availability(for: "0662") else {
        return XCTFail("只应允许白名单本地 mp4 文件名：\(name)")
      }
      XCTAssertEqual(lookupCount, 0)
    }
  }

  func testDuplicateMappingAndEmptyFilesAreRejected() throws {
    let duplicate = ExerciseMediaCatalog(entries: [sampleEntry(), sampleEntry()], resourceURL: { _ in nil })
    guard case .unavailable = duplicate.availability(for: "0662") else {
      return XCTFail("重复映射应回退，不能任意选择素材")
    }
    let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try Data().write(to: temporary)
    defer { try? FileManager.default.removeItem(at: temporary) }
    let empty = ExerciseMediaCatalog(entries: [sampleEntry()], resourceURL: { _ in temporary })
    guard case .unavailable = empty.availability(for: "0662") else {
      return XCTFail("空素材必须回退")
    }
  }

  func testBrokenVideoStopsAndReportsFailure() async throws {
    let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try Data("broken video".utf8).write(to: temporary)
    defer { try? FileManager.default.removeItem(at: temporary) }
    let playback = ExerciseAnimationPlayback()
    playback.prepare(url: temporary, autoplay: true)
    for _ in 0..<100 {
      if playback.hasFailed { break }
      try await Task.sleep(for: .milliseconds(100))
    }
    XCTAssertTrue(playback.hasFailed)
    XCTAssertNil(playback.player)
    XCTAssertFalse(playback.isPlaying)
  }

  func testStaticStartExplicitPlaybackPauseAndRelease() async throws {
    guard case .available(_, let video, _) = ExerciseMediaCatalog().availability(for: "0662") else {
      return XCTFail("缺少离线样片")
    }
    let playback = ExerciseAnimationPlayback()
    playback.prepare(url: video, autoplay: false)
    for _ in 0..<100 {
      if playback.isReady || playback.hasFailed { break }
      try await Task.sleep(for: .milliseconds(100))
    }
    guard playback.isReady else {
      playback.stop()
      return XCTFail("有效离线样片应等待 looper 完成异步入队后就绪")
    }
    XCTAssertFalse(playback.hasFailed)
    XCTAssertFalse(playback.isPlaying)
    XCTAssertFalse(playback.hasStarted)
    playback.toggle()
    XCTAssertTrue(playback.isPlaying)
    XCTAssertTrue(playback.hasStarted)
    XCTAssertTrue(playback.player?.isMuted == true)
    playback.pause()
    XCTAssertFalse(playback.isPlaying)
    XCTAssertTrue(playback.hasStarted, "暂停保留当前帧")
    playback.stop()
    XCTAssertNil(playback.player)
    XCTAssertFalse(playback.isReady)
    XCTAssertFalse(playback.hasStarted)
  }

  func testLeavingWhileLoadingDoesNotCreateLatePlayer() async throws {
    guard case .available(_, let video, _) = ExerciseMediaCatalog().availability(for: "0662") else {
      return XCTFail("缺少离线样片")
    }
    let playback = ExerciseAnimationPlayback()
    playback.prepare(url: video, autoplay: true)
    playback.stop()
    try await Task.sleep(for: .milliseconds(250))
    XCTAssertNil(playback.player)
    XCTAssertFalse(playback.isPlaying)
    XCTAssertFalse(playback.isReady)
  }

  private func sampleEntry(video: String = "push-up.mp4") -> ExerciseMediaCatalog.Entry {
    .init(exerciseID: "0662", video: video, poster: "push-up-poster.png", attribution: "CC0")
  }
}
