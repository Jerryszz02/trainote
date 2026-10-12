import Foundation

/// Media uses exact catalog IDs; names and related variations never inherit a demonstration.
struct ExerciseMediaCatalog {
  struct Entry: Decodable, Equatable {
    let exerciseID: String
    let video: String
    let poster: String
    let attribution: String
  }

  enum Availability {
    case available(entry: Entry, videoURL: URL, posterURL: URL)
    case notCollected
    case unavailable
  }

  private let entries: [Entry]
  private let resourceURL: (String) -> URL?

  init(bundle: Bundle = .main) {
    let resolve: (String) -> URL? = { filename in
      let name = (filename as NSString).deletingPathExtension
      let ext = (filename as NSString).pathExtension
      return bundle.url(forResource: name, withExtension: ext, subdirectory: "ExerciseMedia")
        ?? bundle.url(forResource: name, withExtension: ext)
    }
    resourceURL = resolve
    entries = resolve("catalog.json").flatMap { try? Data(contentsOf: $0) }
      .flatMap { try? JSONDecoder().decode([Entry].self, from: $0) } ?? []
  }

  init(entries: [Entry], resourceURL: @escaping (String) -> URL?) {
    self.entries = entries
    self.resourceURL = resourceURL
  }

  func availability(for exerciseID: String) -> Availability {
    let matches = entries.filter { $0.exerciseID == exerciseID }
    guard !matches.isEmpty else { return .notCollected }
    guard matches.count == 1, let entry = matches.first,
      Self.validFilename(entry.video, extension: "mp4"),
      Self.validFilename(entry.poster, extension: "png"),
      let videoURL = resourceURL(entry.video), let posterURL = resourceURL(entry.poster),
      Self.isReadableFile(videoURL), Self.isReadableFile(posterURL)
    else { return .unavailable }
    return .available(entry: entry, videoURL: videoURL, posterURL: posterURL)
  }

  private static func validFilename(_ filename: String, extension ext: String) -> Bool {
    let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-_.")
    return !filename.isEmpty && !filename.contains("..")
      && filename.unicodeScalars.allSatisfy { allowed.contains($0) }
      && (filename as NSString).pathExtension == ext
  }

  private static func isReadableFile(_ url: URL) -> Bool {
    guard url.isFileURL, FileManager.default.isReadableFile(atPath: url.path),
      let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
    else { return false }
    return values.isRegularFile == true && (values.fileSize ?? 0) > 0
  }
}
