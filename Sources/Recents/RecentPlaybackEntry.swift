import Foundation

struct RecentPlaybackEntry: Codable, Identifiable {
  struct SubtitleSelection: Codable, Hashable {
    enum Source: String, Codable {
      case autoDetected
      case manual
      case remoteDownloaded
    }

    let filePath: String
    var bookmarkData: Data?
    let displayName: String
    let source: Source

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
  }

  let filePath: String
  var bookmarkData: Data?
  var lastPlaybackPosition: TimeInterval
  var duration: TimeInterval
  var lastOpenedAt: Date
  var fileSize: Int64?
  var contentModificationDate: Date?
  var selectedSubtitle: SubtitleSelection?

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

  var progressDetailText: String {
    if lastPlaybackPosition <= 0 {
      return "Start from beginning"
    }

    let resumeText = lastPlaybackPosition.playbackText
    if duration > 0 {
      let durationText = duration.playbackText
      return "Resume at \(resumeText) of \(durationText)"
    }

    return "Resume at \(resumeText)"
  }

  static func normalizedPath(for url: URL) -> String {
    url.standardizedFileURL.path
  }
}
