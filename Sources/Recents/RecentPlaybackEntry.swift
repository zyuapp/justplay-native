import Foundation

struct RecentPlaybackEntry: Codable, Identifiable {
  let filePath: String
  var bookmarkData: Data?
  var lastPlaybackPosition: TimeInterval
  var duration: TimeInterval
  var lastOpenedAt: Date
  var fileSize: Int64?
  var contentModificationDate: Date?

  var id: String {
    filePath
  }

  var displayName: String {
    URL(fileURLWithPath: filePath).lastPathComponent
  }

  var resolvedURL: URL {
    guard let bookmarkData else {
      return URL(fileURLWithPath: filePath)
    }

    var isStale = false
    if let url = try? URL(
      resolvingBookmarkData: bookmarkData,
      options: [.withoutUI],
      relativeTo: nil,
      bookmarkDataIsStale: &isStale
    ) {
      return url
    }

    return URL(fileURLWithPath: filePath)
  }

  var progress: Double {
    guard duration > 0 else { return 0 }
    return min(max(lastPlaybackPosition / duration, 0), 1)
  }

  static func normalizedPath(for url: URL) -> String {
    url.standardizedFileURL.path
  }
}
