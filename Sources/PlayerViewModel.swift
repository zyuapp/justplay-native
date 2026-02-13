import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
final class PlayerViewModel: ObservableObject {
  @Published private(set) var playbackState: PlaybackState = .initial
  @Published private(set) var currentURL: URL?
  @Published private(set) var statusMessage = "Drop an MP4 or MKV file, or open one from the menu."
  @Published private(set) var recentEntries: [RecentPlaybackEntry]
  @Published private(set) var subtitleText: String?
  @Published private(set) var activeSubtitleFileName: String?

  @Published var subtitlesEnabled = true {
    didSet {
      updateSubtitleText(for: playbackState.currentTime)
    }
  }

  @Published var playbackRate: Double = 1.0 {
    didSet {
      engine.setRate(Float(playbackRate))
    }
  }

  @Published var volume: Double = 1.0 {
    didSet {
      engine.setVolume(Float(volume))
    }
  }

  @Published var isMuted = false {
    didSet {
      engine.setMuted(isMuted)
    }
  }

  let engine: PlaybackEngine

  var currentFilePath: String? {
    currentURL.map(RecentPlaybackEntry.normalizedPath(for:))
  }

  var hasSubtitleTrack: Bool {
    !subtitleCues.isEmpty
  }

  private let recentPlaybackStore: RecentPlaybackStore
  private let supportedFileExtensions = Set(["mp4", "m4v", "mkv"])
  private let maxRecentEntries = 50

  private var subtitleCues: [SubtitleCue] = []
  private var pendingResumeSeek: TimeInterval?
  private var currentOpenedAt = Date()

  private var playbackProgressTimer: Timer?
  private var appWillTerminateObserver: NSObjectProtocol?

  init(
    engine: PlaybackEngine = AVFoundationPlaybackEngine(),
    recentPlaybackStore: RecentPlaybackStore = RecentPlaybackStore()
  ) {
    self.engine = engine
    self.recentPlaybackStore = recentPlaybackStore
    recentEntries = recentPlaybackStore.loadEntries()

    self.engine.stateDidChange = { [weak self] state in
      Task { @MainActor in
        self?.handlePlaybackStateChange(state)
      }
    }

    self.engine.playbackDidFinish = { [weak self] in
      Task { @MainActor in
        self?.handlePlaybackDidFinish()
      }
    }

    self.engine.setRate(Float(playbackRate))
    self.engine.setVolume(Float(volume))
    self.engine.setMuted(isMuted)

    startPlaybackProgressTimer()
    appWillTerminateObserver = NotificationCenter.default.addObserver(
      forName: NSApplication.willTerminateNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor in
        self?.persistCurrentPlaybackProgress(force: true)
      }
    }
  }

  deinit {
    playbackProgressTimer?.invalidate()

    if let appWillTerminateObserver {
      NotificationCenter.default.removeObserver(appWillTerminateObserver)
    }
  }

  func open(url: URL, autoplay: Bool = true) {
    let normalizedURL = url.standardizedFileURL

    guard isSupported(url: normalizedURL) else {
      statusMessage = "Unsupported file type: .\(url.pathExtension.lowercased())"
      return
    }

    currentURL = normalizedURL
    currentOpenedAt = Date()

    let resumePosition = resumePosition(for: normalizedURL)
    pendingResumeSeek = resumePosition

    if resumePosition != nil {
      statusMessage = "\(normalizedURL.lastPathComponent) (resuming)"
    } else {
      statusMessage = normalizedURL.lastPathComponent
    }

    engine.load(url: normalizedURL, autoplay: autoplay)
    NSDocumentController.shared.noteNewRecentDocumentURL(normalizedURL)

    let seedDuration = existingEntry(for: normalizedURL)?.duration ?? 0
    upsertRecentEntry(
      for: normalizedURL,
      position: resumePosition ?? 0,
      duration: seedDuration,
      openedAt: currentOpenedAt
    )

    loadAutoDetectedSubtitle(for: normalizedURL)
  }

  func openPanel() {
    VideoOpenPanel.present()
  }

  func openRecent(_ entry: RecentPlaybackEntry) {
    open(url: entry.resolvedURL)
  }

  func openSubtitlePanel() {
    let panel = NSOpenPanel()
    panel.title = "Add Subtitle"
    panel.prompt = "Add"
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false
    panel.canChooseFiles = true
    panel.allowedContentTypes = subtitleContentTypes()

    guard panel.runModal() == .OK, let subtitleURL = panel.url else {
      return
    }

    loadSubtitle(from: subtitleURL, source: .manual)
  }

  func removeSubtitleTrack() {
    subtitleCues = []
    subtitleText = nil
    activeSubtitleFileName = nil
  }

  func togglePlayPause() {
    if playbackState.isPlaying {
      engine.pause()
    } else {
      engine.play()
    }
  }

  func skipForward() {
    engine.skip(by: 10)
  }

  func skipBackward() {
    engine.skip(by: -10)
  }

  func seek(to seconds: Double) {
    engine.seek(to: seconds)
  }

  private func isSupported(url: URL) -> Bool {
    supportedFileExtensions.contains(url.pathExtension.lowercased())
  }

  private func handlePlaybackStateChange(_ state: PlaybackState) {
    playbackState = state
    applyPendingResumeSeekIfNeeded(with: state)
    updateSubtitleText(for: state.currentTime)
  }

  private func handlePlaybackDidFinish() {
    clearResumePositionForCurrentFile()
  }

  private func applyPendingResumeSeekIfNeeded(with state: PlaybackState) {
    guard
      let pendingResumeSeek,
      state.duration > 0
    else {
      return
    }

    let clampedSeek = min(max(pendingResumeSeek, 0), max(state.duration - 1, 0))
    self.pendingResumeSeek = nil

    guard clampedSeek > 0 else {
      return
    }

    engine.seek(to: clampedSeek)
  }

  private func startPlaybackProgressTimer() {
    let timer = Timer(timeInterval: 5.0, repeats: true) { [weak self] _ in
      Task { @MainActor in
        self?.persistCurrentPlaybackProgress()
      }
    }

    RunLoop.main.add(timer, forMode: .common)
    playbackProgressTimer = timer
  }

  private func persistCurrentPlaybackProgress(force: Bool = false) {
    guard let currentURL else {
      return
    }

    let duration = max(playbackState.duration, existingEntry(for: currentURL)?.duration ?? 0)
    let currentTime = max(playbackState.currentTime, 0)

    if duration <= 0 && !force {
      return
    }

    upsertRecentEntry(
      for: currentURL,
      position: currentTime,
      duration: duration,
      openedAt: currentOpenedAt
    )
  }

  private func clearResumePositionForCurrentFile() {
    guard let currentURL else {
      return
    }

    let duration = max(playbackState.duration, existingEntry(for: currentURL)?.duration ?? 0)

    upsertRecentEntry(
      for: currentURL,
      position: 0,
      duration: duration,
      openedAt: currentOpenedAt
    )
  }

  private func upsertRecentEntry(
    for url: URL,
    position: TimeInterval,
    duration: TimeInterval,
    openedAt: Date
  ) {
    let normalizedPath = RecentPlaybackEntry.normalizedPath(for: url)
    let resourceValues = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])

    let bookmarkData = try? url.bookmarkData(
      options: .minimalBookmark,
      includingResourceValuesForKeys: nil,
      relativeTo: nil
    )

    let clampedDuration = max(duration, 0)
    let clampedPosition: TimeInterval
    if clampedDuration > 0 {
      clampedPosition = min(max(position, 0), clampedDuration)
    } else {
      clampedPosition = max(position, 0)
    }

    if let index = recentEntries.firstIndex(where: { $0.filePath == normalizedPath }) {
      var existing = recentEntries[index]
      existing.bookmarkData = bookmarkData ?? existing.bookmarkData
      existing.lastPlaybackPosition = clampedPosition
      existing.duration = max(existing.duration, clampedDuration)
      existing.lastOpenedAt = openedAt
      existing.fileSize = resourceValues?.fileSize.map(Int64.init) ?? existing.fileSize
      existing.contentModificationDate = resourceValues?.contentModificationDate ?? existing.contentModificationDate
      recentEntries[index] = existing
    } else {
      let entry = RecentPlaybackEntry(
        filePath: normalizedPath,
        bookmarkData: bookmarkData,
        lastPlaybackPosition: clampedPosition,
        duration: clampedDuration,
        lastOpenedAt: openedAt,
        fileSize: resourceValues?.fileSize.map(Int64.init),
        contentModificationDate: resourceValues?.contentModificationDate
      )
      recentEntries.append(entry)
    }

    recentEntries.sort { $0.lastOpenedAt > $1.lastOpenedAt }
    if recentEntries.count > maxRecentEntries {
      recentEntries = Array(recentEntries.prefix(maxRecentEntries))
    }

    recentPlaybackStore.saveEntries(recentEntries)
  }

  private func existingEntry(for url: URL) -> RecentPlaybackEntry? {
    let normalizedPath = RecentPlaybackEntry.normalizedPath(for: url)
    return recentEntries.first { $0.filePath == normalizedPath }
  }

  private func resumePosition(for url: URL) -> TimeInterval? {
    guard let entry = existingEntry(for: url) else {
      return nil
    }

    guard entry.duration > 0 else {
      return nil
    }

    let progress = entry.lastPlaybackPosition / entry.duration
    if progress >= 0.98 {
      return nil
    }

    guard entry.lastPlaybackPosition > 0 else {
      return nil
    }

    return entry.lastPlaybackPosition
  }

  private func loadAutoDetectedSubtitle(for videoURL: URL) {
    guard let sidecarURL = sidecarSubtitleURL(for: videoURL) else {
      removeSubtitleTrack()
      return
    }

    loadSubtitle(from: sidecarURL, source: .autoDetected)
  }

  private func loadSubtitle(from subtitleURL: URL, source: SubtitleSource) {
    do {
      let parsedCues = try SRTParser.parse(url: subtitleURL)
      guard !parsedCues.isEmpty else {
        throw SubtitleError.emptyTrack
      }

      subtitleCues = parsedCues
      activeSubtitleFileName = subtitleURL.lastPathComponent
      subtitlesEnabled = true
      updateSubtitleText(for: playbackState.currentTime)

      if source == .manual {
        statusMessage = "Loaded subtitle: \(subtitleURL.lastPathComponent)"
      }
    } catch {
      removeSubtitleTrack()

      if source == .manual {
        statusMessage = "Unable to read subtitle file."
      }
    }
  }

  private func sidecarSubtitleURL(for videoURL: URL) -> URL? {
    let directoryURL = videoURL.deletingLastPathComponent()
    let baseName = videoURL.deletingPathExtension().lastPathComponent.lowercased()

    guard let fileURLs = try? FileManager.default.contentsOfDirectory(
      at: directoryURL,
      includingPropertiesForKeys: nil,
      options: [.skipsHiddenFiles]
    ) else {
      return nil
    }

    return fileURLs.first {
      $0.pathExtension.lowercased() == "srt"
        && $0.deletingPathExtension().lastPathComponent.lowercased() == baseName
    }
  }

  private func updateSubtitleText(for time: TimeInterval) {
    guard subtitlesEnabled else {
      subtitleText = nil
      return
    }

    guard !subtitleCues.isEmpty else {
      subtitleText = nil
      return
    }

    subtitleText = subtitleCues.first { $0.contains(time) }?.text
  }

  private func subtitleContentTypes() -> [UTType] {
    if let srtType = UTType(filenameExtension: "srt") {
      return [srtType, .plainText]
    }

    return [.plainText]
  }
}

private extension PlayerViewModel {
  enum SubtitleSource {
    case autoDetected
    case manual
  }

  enum SubtitleError: Error {
    case emptyTrack
  }
}
