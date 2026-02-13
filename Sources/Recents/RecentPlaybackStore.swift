import Foundation

final class RecentPlaybackStore {
  private struct Payload: Codable {
    let schemaVersion: Int
    let entries: [RecentPlaybackEntry]
  }

  private let fileManager: FileManager
  private let fileURL: URL

  private let encoder = JSONEncoder()
  private let decoder = JSONDecoder()

  init(
    fileManager: FileManager = .default,
    bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "com.justplay.native"
  ) {
    self.fileManager = fileManager
    self.fileURL = Self.makeFileURL(fileManager: fileManager, bundleIdentifier: bundleIdentifier)

    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601

    decoder.dateDecodingStrategy = .iso8601
  }

  func loadEntries() -> [RecentPlaybackEntry] {
    guard let data = try? Data(contentsOf: fileURL) else {
      return []
    }

    guard let payload = try? decoder.decode(Payload.self, from: data) else {
      return []
    }

    return payload.entries.sorted { $0.lastOpenedAt > $1.lastOpenedAt }
  }

  func saveEntries(_ entries: [RecentPlaybackEntry]) {
    let sortedEntries = entries.sorted { $0.lastOpenedAt > $1.lastOpenedAt }
    let payload = Payload(schemaVersion: 1, entries: sortedEntries)

    do {
      try createDirectoryIfNeeded()
      let data = try encoder.encode(payload)
      try data.write(to: fileURL, options: .atomic)
    } catch {
      return
    }
  }

  private func createDirectoryIfNeeded() throws {
    let directoryURL = fileURL.deletingLastPathComponent()
    if fileManager.fileExists(atPath: directoryURL.path) {
      return
    }

    try fileManager.createDirectory(
      at: directoryURL,
      withIntermediateDirectories: true
    )
  }

  private static func makeFileURL(
    fileManager: FileManager,
    bundleIdentifier: String
  ) -> URL {
    let fallback = URL(fileURLWithPath: NSHomeDirectory())
      .appendingPathComponent("Library", isDirectory: true)
      .appendingPathComponent("Application Support", isDirectory: true)

    let appSupportURL = (try? fileManager.url(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    )) ?? fallback

    return appSupportURL
      .appendingPathComponent(bundleIdentifier, isDirectory: true)
      .appendingPathComponent("recent-playback.v1.json")
  }
}
