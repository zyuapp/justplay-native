import Foundation
import XCTest
@testable import JustPlay

@MainActor
final class PlayerViewModelProgressTests: XCTestCase {
  private var cleanupURLs: [URL] = []

  override func tearDown() {
    let fileManager = FileManager.default

    for url in cleanupURLs {
      try? fileManager.removeItem(at: url)
    }

    cleanupURLs.removeAll()
    super.tearDown()
  }

  func testResumeSeekIsAppliedWhenSavedProgressIsValid() async throws {
    let videoURL = try makeVideoFile(named: "resume-valid")
    let store = makeStore()
    seedState(
      in: store,
      recentEntries: [
        makeEntry(url: videoURL, position: 120, duration: 300)
      ]
    )

    let engine = TestPlaybackEngine()
    let viewModel = makeViewModel(engine: engine, store: store, restorePreviousSessionOnLaunch: false)

    viewModel.open(url: videoURL)
    XCTAssertTrue(viewModel.statusMessage.contains("(resuming)"))

    engine.emitState(playbackState(isPlaying: true, currentTime: 0, duration: 300))
    await drainMainActorTasks()

    XCTAssertTrue(engine.events.contains { event in
      guard case let .seek(time) = event else {
        return false
      }

      return abs(time - 120) < 0.001
    })
    XCTAssertEqual(viewModel.playbackState.currentTime, 120, accuracy: 0.001)
  }

  func testResumeSeekIsSkippedForNearCompleteProgress() async throws {
    let videoURL = try makeVideoFile(named: "resume-near-end")
    let store = makeStore()
    seedState(
      in: store,
      recentEntries: [
        makeEntry(url: videoURL, position: 294, duration: 300)
      ]
    )

    let engine = TestPlaybackEngine()
    let viewModel = makeViewModel(engine: engine, store: store, restorePreviousSessionOnLaunch: false)

    viewModel.open(url: videoURL)
    engine.emitState(playbackState(isPlaying: true, currentTime: 0, duration: 300))
    await drainMainActorTasks()

    XCTAssertFalse(viewModel.statusMessage.contains("(resuming)"))
    XCTAssertFalse(engine.events.contains { event in
      if case .seek = event {
        return true
      }

      return false
    })
  }

  func testSkipActionsPersistImmediatelyAndClampToDuration() async throws {
    let videoURL = try makeVideoFile(named: "skip-clamp")
    let store = makeStore()
    let engine = TestPlaybackEngine()
    let viewModel = makeViewModel(engine: engine, store: store, restorePreviousSessionOnLaunch: false)

    viewModel.open(url: videoURL)
    engine.emitState(playbackState(isPlaying: true, currentTime: 95, duration: 100))
    await drainMainActorTasks()

    viewModel.skipForward()
    XCTAssertEqual(entry(for: videoURL, in: viewModel.recentEntries)?.lastPlaybackPosition ?? -1, 100, accuracy: 0.001)

    viewModel.skipBackward()
    XCTAssertEqual(entry(for: videoURL, in: viewModel.recentEntries)?.lastPlaybackPosition ?? -1, 85, accuracy: 0.001)

    XCTAssertTrue(engine.events.contains(.skip(10)))
    XCTAssertTrue(engine.events.contains(.skip(-10)))
  }

  func testPlaybackFinishClearsResumePosition() async throws {
    let videoURL = try makeVideoFile(named: "finish-clears")
    let store = makeStore()
    let engine = TestPlaybackEngine()
    let viewModel = makeViewModel(engine: engine, store: store, restorePreviousSessionOnLaunch: false)

    viewModel.open(url: videoURL)
    engine.emitState(playbackState(isPlaying: true, currentTime: 80, duration: 200))
    await drainMainActorTasks()

    viewModel.seek(to: 80, persistImmediately: true)
    XCTAssertEqual(entry(for: videoURL, in: viewModel.recentEntries)?.lastPlaybackPosition ?? -1, 80, accuracy: 0.001)

    engine.emitPlaybackDidFinish()
    await drainMainActorTasks()

    XCTAssertEqual(entry(for: videoURL, in: viewModel.recentEntries)?.lastPlaybackPosition ?? -1, 0, accuracy: 0.001)
  }

  func testPausedSeekKeepsRequestedTimeUntilEngineConfirms() async throws {
    let videoURL = try makeVideoFile(named: "paused-seek")
    let store = makeStore()
    let engine = TestPlaybackEngine()
    let viewModel = makeViewModel(engine: engine, store: store, restorePreviousSessionOnLaunch: false)

    viewModel.open(url: videoURL)
    engine.emitState(playbackState(isPlaying: false, currentTime: 0, duration: 200))
    await drainMainActorTasks()

    viewModel.seek(to: 60)
    XCTAssertEqual(viewModel.playbackState.currentTime, 60, accuracy: 0.001)

    engine.emitState(playbackState(isPlaying: false, currentTime: 10, duration: 200))
    await drainMainActorTasks()
    XCTAssertEqual(viewModel.playbackState.currentTime, 60, accuracy: 0.001)

    engine.emitState(playbackState(isPlaying: false, currentTime: 60.2, duration: 200))
    await drainMainActorTasks()
    XCTAssertEqual(viewModel.playbackState.currentTime, 60.2, accuracy: 0.001)

    engine.emitState(playbackState(isPlaying: false, currentTime: 20, duration: 200))
    await drainMainActorTasks()
    XCTAssertEqual(viewModel.playbackState.currentTime, 20, accuracy: 0.001)
  }

  func testLaunchRestoresMostRecentSessionWithoutAutoplay() async throws {
    let videoURL = try makeVideoFile(named: "restore-launch")
    let store = makeStore()
    seedState(
      in: store,
      recentEntries: [
        makeEntry(url: videoURL, position: 42, duration: 120)
      ]
    )

    let engine = TestPlaybackEngine()
    let viewModel = makeViewModel(engine: engine, store: store, restorePreviousSessionOnLaunch: true)
    _ = viewModel

    XCTAssertTrue(engine.events.contains(.load(path: videoURL.path, autoplay: false)))

    engine.emitState(playbackState(isPlaying: false, currentTime: 0, duration: 120))
    await drainMainActorTasks()

    XCTAssertTrue(engine.events.contains { event in
      guard case let .seek(time) = event else {
        return false
      }

      return abs(time - 42) < 0.001
    })
    XCTAssertTrue(engine.events.contains(.play))

    engine.emitState(playbackState(isPlaying: true, currentTime: 42, duration: 120))
    await drainMainActorTasks()
    XCTAssertTrue(engine.events.contains(.pause))
  }

  private func makeViewModel(
    engine: TestPlaybackEngine,
    store: RecentPlaybackStore,
    restorePreviousSessionOnLaunch: Bool
  ) -> PlayerViewModel {
    PlayerViewModel(
      engine: engine,
      recentPlaybackStore: store,
      enableProgressPersistenceTimer: false,
      observeApplicationWillTerminate: false,
      restorePreviousSessionOnLaunch: restorePreviousSessionOnLaunch,
      noteRecentDocumentURL: { _ in }
    )
  }

  private func playbackState(isPlaying: Bool, currentTime: TimeInterval, duration: TimeInterval) -> PlaybackState {
    PlaybackState(
      isPlaying: isPlaying,
      currentTime: currentTime,
      duration: duration,
      rate: 1.0,
      volume: 1.0,
      isMuted: false
    )
  }

  private func entry(for url: URL, in entries: [RecentPlaybackEntry]) -> RecentPlaybackEntry? {
    let normalizedPath = url.standardizedFileURL.path
    return entries.first { $0.filePath == normalizedPath }
  }

  private func makeStore() -> RecentPlaybackStore {
    let bundleID = "com.justplay.tests.\(UUID().uuidString)"
    cleanupURLs.append(storeDirectoryURL(bundleIdentifier: bundleID))
    return RecentPlaybackStore(fileManager: .default, bundleIdentifier: bundleID)
  }

  private func storeDirectoryURL(bundleIdentifier: String) -> URL {
    let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? URL(fileURLWithPath: NSHomeDirectory())
      .appendingPathComponent("Library", isDirectory: true)
      .appendingPathComponent("Application Support", isDirectory: true)

    return appSupportURL.appendingPathComponent(bundleIdentifier, isDirectory: true)
  }

  private func seedState(in store: RecentPlaybackStore, recentEntries: [RecentPlaybackEntry]) {
    store.saveState(.init(recentEntries: recentEntries, archivedEntries: []))
  }

  private func makeEntry(url: URL, position: TimeInterval, duration: TimeInterval) -> RecentPlaybackEntry {
    RecentPlaybackEntry(
      filePath: url.standardizedFileURL.path,
      bookmarkData: nil,
      lastPlaybackPosition: position,
      duration: duration,
      lastOpenedAt: Date(),
      fileSize: nil,
      contentModificationDate: nil,
      selectedSubtitle: nil
    )
  }

  private func makeVideoFile(named baseName: String) throws -> URL {
    let directoryURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("JustPlayTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

    cleanupURLs.append(directoryURL)

    let fileURL = directoryURL.appendingPathComponent(baseName).appendingPathExtension("mp4")
    let created = FileManager.default.createFile(atPath: fileURL.path, contents: Data(), attributes: nil)
    XCTAssertTrue(created)
    return fileURL
  }

  private func drainMainActorTasks() async {
    for _ in 0..<10 {
      await Task.yield()
    }
  }
}
