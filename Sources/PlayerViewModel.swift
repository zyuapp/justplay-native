import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
final class PlayerViewModel: ObservableObject {
  @Published private(set) var playbackState: PlaybackState = .initial
  @Published private(set) var currentURL: URL?
  @Published private(set) var statusMessage = "Drop an MP4 or MKV file, or open one from the menu."
  @Published private(set) var recentEntries: [RecentPlaybackEntry]
  @Published private(set) var archivedEntries: [RecentPlaybackEntry]
  @Published private(set) var subtitleText: String?
  @Published private(set) var activeSubtitleFileName: String?
  @Published private(set) var availableSubtitleTracks: [SubtitleTrackOption] = []
  @Published private(set) var selectedSubtitleTrackID: String?
  @Published private(set) var subtitleTimelineCues: [SubtitleCue] = []
  @Published private(set) var activeSubtitleCueIndex: Int?

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
    selectedSubtitleTrackID != nil
  }

  private let recentPlaybackStore: RecentPlaybackStore
  private let noteRecentDocumentURL: (URL) -> Void
  private let supportedFileExtensions = Set(["mp4", "m4v", "mkv"])
  private let maxRecentEntries = 50

  private var loadedSubtitleTracks: [LoadedSubtitleTrack] = []
  private var subtitleCues: [SubtitleCue] = []
  private var pendingResumeSeek: TimeInterval?
  private var shouldPrimePlaybackForResume = false
  private var shouldPauseAfterResumeSeek = false
  private var pendingPausedSeekTime: TimeInterval?
  private let pausedSeekConfirmationTolerance: TimeInterval = 0.35
  private var currentOpenedAt = Date()

  private var playbackProgressTimer: Timer?
  private var appWillTerminateObserver: NSObjectProtocol?

  init(
    engine: PlaybackEngine = PlaybackEngineFactory.makeDefaultEngine(),
    recentPlaybackStore: RecentPlaybackStore = RecentPlaybackStore(),
    enableProgressPersistenceTimer: Bool = true,
    observeApplicationWillTerminate: Bool = true,
    restorePreviousSessionOnLaunch: Bool = true,
    noteRecentDocumentURL: ((URL) -> Void)? = nil
  ) {
    self.engine = engine
    self.recentPlaybackStore = recentPlaybackStore
    self.noteRecentDocumentURL = noteRecentDocumentURL ?? { url in
      NSDocumentController.shared.noteNewRecentDocumentURL(url)
    }

    let storedState = recentPlaybackStore.loadState()
    recentEntries = storedState.recentEntries
    archivedEntries = storedState.archivedEntries

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
    self.engine.setNativeSubtitleRenderingEnabled(true)

    if enableProgressPersistenceTimer {
      startPlaybackProgressTimer()
    }

    if observeApplicationWillTerminate {
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

    if restorePreviousSessionOnLaunch {
      restoreMostRecentPlaybackSessionIfAvailable()
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
    shouldPrimePlaybackForResume = false
    shouldPauseAfterResumeSeek = false
    pendingPausedSeekTime = nil

    let resumePosition = resumePosition(for: normalizedURL)
    pendingResumeSeek = resumePosition
    if !autoplay, resumePosition != nil {
      shouldPrimePlaybackForResume = true
    }

    if resumePosition != nil {
      statusMessage = "\(normalizedURL.lastPathComponent) (resuming)"
    } else {
      statusMessage = normalizedURL.lastPathComponent
    }

    resetSubtitleStateForCurrentVideo()
    loadAutoDetectedSubtitle(for: normalizedURL)
    restorePersistedSubtitleSelection(for: normalizedURL)

    engine.load(url: normalizedURL, autoplay: autoplay)
    noteRecentDocumentURL(normalizedURL)

    let seedDuration = existingEntry(for: normalizedURL)?.duration ?? 0
    upsertRecentEntry(
      for: normalizedURL,
      position: resumePosition ?? 0,
      duration: seedDuration,
      openedAt: currentOpenedAt
    )
  }

  func openPanel() {
    VideoOpenPanel.present()
  }

  func openRecent(_ entry: RecentPlaybackEntry) {
    open(url: entry.resolvedURL)
  }

  func removeRecent(_ entry: RecentPlaybackEntry) {
    guard entry.filePath != currentFilePath else {
      return
    }

    recentEntries.removeAll { $0.filePath == entry.filePath }
    archivedEntries.removeAll { $0.filePath == entry.filePath }
    archivedEntries.append(entry)
    archivedEntries.sort { $0.lastOpenedAt > $1.lastOpenedAt }
    saveRecentsState()
  }

  func restoreArchivedRecent(_ entry: RecentPlaybackEntry) {
    archivedEntries.removeAll { $0.filePath == entry.filePath }
    recentEntries.removeAll { $0.filePath == entry.filePath }
    recentEntries.append(entry)
    recentEntries.sort { $0.lastOpenedAt > $1.lastOpenedAt }
    saveRecentsState()
  }

  func deleteArchivedRecentPermanently(_ entry: RecentPlaybackEntry) {
    archivedEntries.removeAll { $0.filePath == entry.filePath }
    saveRecentsState()
  }

  func selectSubtitleTrack(_ trackID: String) {
    guard let track = loadedSubtitleTracks.first(where: { $0.id == trackID }) else {
      return
    }

    activateSubtitleTrack(track)
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
    guard let selectedSubtitleTrackID else {
      clearActiveSubtitleTrack()
      return
    }

    loadedSubtitleTracks.removeAll { $0.id == selectedSubtitleTrackID }
    refreshSubtitleTrackOptions()

    if let nextTrack = loadedSubtitleTracks.first {
      activateSubtitleTrack(nextTrack)
    } else {
      clearActiveSubtitleTrack()
    }

    persistCurrentPlaybackProgress(force: true)
  }

  func seekToSubtitleCue(at index: Int) {
    guard subtitleTimelineCues.indices.contains(index) else {
      return
    }

    seek(to: subtitleTimelineCues[index].start, persistImmediately: true)
  }

  func togglePlayPause() {
    if playbackState.isPlaying {
      engine.pause()
    } else {
      engine.play()
    }
  }

  func skipForward() {
    skip(by: 10)
  }

  func skipBackward() {
    skip(by: -10)
  }

  func seek(to seconds: Double, persistImmediately: Bool = false) {
    let clampedSeconds: TimeInterval
    if playbackState.duration > 0 {
      clampedSeconds = min(max(seconds, 0), playbackState.duration)
    } else {
      clampedSeconds = max(seconds, 0)
    }

    pendingResumeSeek = nil
    shouldPrimePlaybackForResume = false
    shouldPauseAfterResumeSeek = false
    if playbackState.isPlaying {
      pendingPausedSeekTime = nil
    } else {
      pendingPausedSeekTime = clampedSeconds
    }

    engine.seek(to: clampedSeconds)
    playbackState.currentTime = clampedSeconds
    updateSubtitleText(for: clampedSeconds)

    if persistImmediately {
      persistCurrentPlaybackProgress(force: true, overridePosition: clampedSeconds)
    }
  }

  private func isSupported(url: URL) -> Bool {
    supportedFileExtensions.contains(url.pathExtension.lowercased())
  }

  private func restoreMostRecentPlaybackSessionIfAvailable() {
    guard let entry = recentEntries.first else {
      return
    }

    let url = entry.resolvedURL.standardizedFileURL
    guard
      FileManager.default.fileExists(atPath: url.path),
      isSupported(url: url)
    else {
      return
    }

    open(url: url, autoplay: false)
  }

  private func handlePlaybackStateChange(_ state: PlaybackState) {
    var resolvedState = state

    if let pendingPausedSeekTime {
      if resolvedState.isPlaying {
        self.pendingPausedSeekTime = nil
      } else if abs(resolvedState.currentTime - pendingPausedSeekTime) <= pausedSeekConfirmationTolerance {
        self.pendingPausedSeekTime = nil
      } else {
        resolvedState.currentTime = pendingPausedSeekTime
      }
    }

    playbackState = resolvedState
    applyPendingResumeSeekIfNeeded(with: resolvedState)
    updateSubtitleText(for: playbackState.currentTime)
  }

  private func handlePlaybackDidFinish() {
    clearResumePositionForCurrentFile()
  }

  private func applyPendingResumeSeekIfNeeded(with state: PlaybackState) {
    guard let pendingResumeSeek else {
      return
    }

    let seekTarget: TimeInterval
    if state.duration > 0 {
      seekTarget = min(max(pendingResumeSeek, 0), max(state.duration - 1, 0))
    } else {
      seekTarget = max(pendingResumeSeek, 0)
    }

    guard seekTarget > 0 else {
      self.pendingResumeSeek = nil
      shouldPrimePlaybackForResume = false
      shouldPauseAfterResumeSeek = false
      return
    }

    let tolerance: TimeInterval = 0.35
    if abs(state.currentTime - seekTarget) <= tolerance {
      self.pendingResumeSeek = nil

      if shouldPauseAfterResumeSeek {
        shouldPauseAfterResumeSeek = false
        engine.pause()
      }

      return
    }

    engine.seek(to: seekTarget)
    playbackState.currentTime = seekTarget

    if shouldPrimePlaybackForResume, !state.isPlaying {
      shouldPrimePlaybackForResume = false
      shouldPauseAfterResumeSeek = true
      engine.play()
    }
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

  private func skip(by interval: TimeInterval) {
    let projectedPosition = playbackState.currentTime + interval
    engine.skip(by: interval)
    persistCurrentPlaybackProgress(force: true, overridePosition: projectedPosition)
  }

  private func persistCurrentPlaybackProgress(force: Bool = false, overridePosition: TimeInterval? = nil) {
    guard let currentURL else {
      return
    }

    let duration = max(playbackState.duration, existingEntry(for: currentURL)?.duration ?? 0)
    let currentTime = max(overridePosition ?? playbackState.currentTime, 0)

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

    let selectedSubtitle = currentSubtitleSelection()

    if let index = recentEntries.firstIndex(where: { $0.filePath == normalizedPath }) {
      var existing = recentEntries[index]
      existing.bookmarkData = bookmarkData ?? existing.bookmarkData
      existing.lastPlaybackPosition = clampedPosition
      existing.duration = max(existing.duration, clampedDuration)
      existing.lastOpenedAt = openedAt
      existing.fileSize = resourceValues?.fileSize.map(Int64.init) ?? existing.fileSize
      existing.contentModificationDate = resourceValues?.contentModificationDate ?? existing.contentModificationDate
      existing.selectedSubtitle = selectedSubtitle
      recentEntries[index] = existing
    } else {
      let entry = RecentPlaybackEntry(
        filePath: normalizedPath,
        bookmarkData: bookmarkData,
        lastPlaybackPosition: clampedPosition,
        duration: clampedDuration,
        lastOpenedAt: openedAt,
        fileSize: resourceValues?.fileSize.map(Int64.init),
        contentModificationDate: resourceValues?.contentModificationDate,
        selectedSubtitle: selectedSubtitle
      )
      recentEntries.append(entry)
    }

    recentEntries.sort { $0.lastOpenedAt > $1.lastOpenedAt }
    if recentEntries.count > maxRecentEntries {
      recentEntries = Array(recentEntries.prefix(maxRecentEntries))
    }

    archivedEntries.removeAll { $0.filePath == normalizedPath }
    saveRecentsState()
  }

  private func saveRecentsState() {
    let state = RecentPlaybackStore.State(
      recentEntries: recentEntries,
      archivedEntries: archivedEntries
    )
    recentPlaybackStore.saveState(state)
  }

  private func existingEntry(for url: URL) -> RecentPlaybackEntry? {
    let normalizedPath = RecentPlaybackEntry.normalizedPath(for: url)
    return recentEntries.first { $0.filePath == normalizedPath }
  }

  private func resumePosition(for url: URL) -> TimeInterval? {
    guard let entry = existingEntry(for: url) else {
      return nil
    }

    guard entry.lastPlaybackPosition > 0 else {
      return nil
    }

    if entry.duration > 0 {
      let progress = entry.lastPlaybackPosition / entry.duration
      if progress >= 0.98 {
        return nil
      }

      let cappedPosition = min(entry.lastPlaybackPosition, max(entry.duration - 1, 0))
      return cappedPosition > 0 ? cappedPosition : nil
    }

    return entry.lastPlaybackPosition
  }

  private func resetSubtitleStateForCurrentVideo() {
    loadedSubtitleTracks = []
    availableSubtitleTracks = []
    clearActiveSubtitleTrack()
  }

  private func restorePersistedSubtitleSelection(for videoURL: URL) {
    guard let selection = existingEntry(for: videoURL)?.selectedSubtitle else {
      return
    }

    let subtitleURL = selection.resolvedURL
    guard FileManager.default.fileExists(atPath: subtitleURL.path) else {
      return
    }

    loadSubtitle(from: subtitleURL, source: subtitleSource(from: selection.source), shouldAnnounce: false)
  }

  private func loadAutoDetectedSubtitle(for videoURL: URL) {
    guard let sidecarURL = sidecarSubtitleURL(for: videoURL) else {
      return
    }

    loadSubtitle(from: sidecarURL, source: .autoDetected, shouldAnnounce: false)
  }

  private func loadSubtitle(from subtitleURL: URL, source: SubtitleSource, shouldAnnounce: Bool = true) {
    do {
      let parsedCues = try SRTParser.parse(url: subtitleURL)
      guard !parsedCues.isEmpty else {
        throw SubtitleError.emptyTrack
      }

      let standardizedURL = subtitleURL.standardizedFileURL
      let track = LoadedSubtitleTrack(
        id: subtitleTrackID(for: standardizedURL, source: source),
        source: source,
        url: standardizedURL,
        displayName: standardizedURL.lastPathComponent,
        cues: parsedCues
      )

      if let index = loadedSubtitleTracks.firstIndex(where: { $0.id == track.id }) {
        loadedSubtitleTracks[index] = track
      } else {
        loadedSubtitleTracks.append(track)
      }

      refreshSubtitleTrackOptions()
      activateSubtitleTrack(track)

      guard shouldAnnounce else {
        return
      }

      if source == .manual {
        statusMessage = "Loaded subtitle: \(track.displayName)"
      }

    } catch {
      if source == .manual {
        statusMessage = "Unable to read subtitle file."
      }
    }
  }

  private func activateSubtitleTrack(_ track: LoadedSubtitleTrack) {
    engine.setNativeSubtitleRenderingEnabled(false)
    subtitleCues = track.cues
    subtitleTimelineCues = track.cues
    activeSubtitleFileName = track.displayName
    selectedSubtitleTrackID = track.id
    subtitlesEnabled = true
    updateSubtitleText(for: playbackState.currentTime)
    persistCurrentPlaybackProgress(force: true)
  }

  private func clearActiveSubtitleTrack() {
    engine.setNativeSubtitleRenderingEnabled(true)
    subtitleCues = []
    subtitleTimelineCues = []
    activeSubtitleCueIndex = nil
    subtitleText = nil
    activeSubtitleFileName = nil
    selectedSubtitleTrackID = nil
  }

  private func refreshSubtitleTrackOptions() {
    availableSubtitleTracks = loadedSubtitleTracks.map {
      SubtitleTrackOption(
        id: $0.id,
        displayName: $0.displayName,
        sourceLabel: $0.source.displayName
      )
    }
  }

  private func currentSubtitleSelection() -> RecentPlaybackEntry.SubtitleSelection? {
    guard
      let selectedSubtitleTrackID,
      let track = loadedSubtitleTracks.first(where: { $0.id == selectedSubtitleTrackID })
    else {
      return nil
    }

    let bookmarkData = try? track.url.bookmarkData(
      options: .minimalBookmark,
      includingResourceValuesForKeys: nil,
      relativeTo: nil
    )

    return RecentPlaybackEntry.SubtitleSelection(
      filePath: track.url.path,
      bookmarkData: bookmarkData,
      displayName: track.displayName,
      source: persistedSubtitleSource(from: track.source)
    )
  }

  private func subtitleSource(from source: RecentPlaybackEntry.SubtitleSelection.Source) -> SubtitleSource {
    switch source {
    case .autoDetected:
      return .autoDetected
    case .manual:
      return .manual
    case .remoteDownloaded:
      return .manual
    }
  }

  private func persistedSubtitleSource(from source: SubtitleSource) -> RecentPlaybackEntry.SubtitleSelection.Source {
    switch source {
    case .autoDetected:
      return .autoDetected
    case .manual:
      return .manual
    }
  }

  private func subtitleTrackID(for url: URL, source: SubtitleSource) -> String {
    "\(source.rawValue)::\(url.path)"
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
    activeSubtitleCueIndex = activeSubtitleCueIndex(at: time)

    guard subtitlesEnabled else {
      subtitleText = nil
      return
    }

    guard !subtitleCues.isEmpty else {
      subtitleText = nil
      return
    }

    guard let activeSubtitleCueIndex else {
      subtitleText = nil
      return
    }

    subtitleText = subtitleCues[activeSubtitleCueIndex].text
  }

  private func activeSubtitleCueIndex(at time: TimeInterval) -> Int? {
    guard !subtitleCues.isEmpty else {
      return nil
    }

    var lowerBound = 0
    var upperBound = subtitleCues.count - 1

    while lowerBound <= upperBound {
      let middleIndex = lowerBound + ((upperBound - lowerBound) / 2)
      let cue = subtitleCues[middleIndex]

      if time < cue.start {
        upperBound = middleIndex - 1
      } else if time > cue.end {
        lowerBound = middleIndex + 1
      } else {
        return middleIndex
      }
    }

    return nil
  }

  private func subtitleContentTypes() -> [UTType] {
    if let srtType = UTType(filenameExtension: "srt") {
      return [srtType, .plainText]
    }

    return [.plainText]
  }

}

private extension PlayerViewModel {
  struct LoadedSubtitleTrack: Identifiable {
    let id: String
    let source: SubtitleSource
    let url: URL
    let displayName: String
    let cues: [SubtitleCue]
  }

  enum SubtitleSource: String {
    case autoDetected
    case manual

    var displayName: String {
      switch self {
      case .autoDetected:
        return "Auto"
      case .manual:
        return "Imported"
      }
    }
  }

  enum SubtitleError: Error {
    case emptyTrack
    case unreadableTrack
  }
}
