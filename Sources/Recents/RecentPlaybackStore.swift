import Foundation

final class RecentPlaybackStore {
  struct State {
    let recentEntries: [RecentPlaybackEntry]
    let archivedEntries: [RecentPlaybackEntry]
  }

  private struct Payload: Decodable {
    let schemaVersion: Int
    let entries: [RecentPlaybackEntry]
    let archivedEntries: [RecentPlaybackEntry]

    private enum CodingKeys: String, CodingKey {
      case schemaVersion
      case entries
      case archivedEntries
    }

    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
      entries = try container.decode([RecentPlaybackEntry].self, forKey: .entries)
      archivedEntries = try container.decodeIfPresent([RecentPlaybackEntry].self, forKey: .archivedEntries) ?? []
    }
  }

  private struct SavePayload: Encodable {
    let schemaVersion: Int
    let entries: [RecentPlaybackEntry]
    let archivedEntries: [RecentPlaybackEntry]
  }

  private let fileManager: FileManager
  private let fileURL: URL

  private let encoder = JSONEncoder()
  private let decoder = JSONDecoder()

  init(
    fileManager: FileManager = .default,
    bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "com.justplay"
  ) {
    self.fileManager = fileManager
    self.fileURL = Self.makeFileURL(fileManager: fileManager, bundleIdentifier: bundleIdentifier)

    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601

    decoder.dateDecodingStrategy = .iso8601

    migrateLegacyStoreIfNeeded(from: "com.justplay.native")
  }

  func loadState() -> State {
    guard let data = try? Data(contentsOf: fileURL) else {
      return State(recentEntries: [], archivedEntries: [])
    }

    guard let payload = try? decoder.decode(Payload.self, from: data) else {
      return State(recentEntries: [], archivedEntries: [])
    }

    let sortedRecentEntries = payload.entries.sorted { $0.lastOpenedAt > $1.lastOpenedAt }
    let sortedArchivedEntries = payload.archivedEntries.sorted { $0.lastOpenedAt > $1.lastOpenedAt }
    return State(recentEntries: sortedRecentEntries, archivedEntries: sortedArchivedEntries)
  }

  func saveState(_ state: State) {
    let sortedRecentEntries = state.recentEntries.sorted { $0.lastOpenedAt > $1.lastOpenedAt }
    let sortedArchivedEntries = state.archivedEntries.sorted { $0.lastOpenedAt > $1.lastOpenedAt }
    let payload = SavePayload(schemaVersion: 2, entries: sortedRecentEntries, archivedEntries: sortedArchivedEntries)

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

  private func migrateLegacyStoreIfNeeded(from legacyBundleIdentifier: String) {
    let legacyFileURL = Self.makeFileURL(fileManager: fileManager, bundleIdentifier: legacyBundleIdentifier)

    guard legacyFileURL != fileURL else {
      return
    }

    guard fileManager.fileExists(atPath: legacyFileURL.path) else {
      return
    }

    guard !fileManager.fileExists(atPath: fileURL.path) else {
      return
    }

    do {
      try createDirectoryIfNeeded()
      try fileManager.copyItem(at: legacyFileURL, to: fileURL)
    } catch {
      return
    }
  }
}
