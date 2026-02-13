import AppKit
import Foundation

@MainActor
final class PlayerViewModel: ObservableObject {
  @Published private(set) var playbackState: PlaybackState = .initial
  @Published private(set) var currentURL: URL?
  @Published private(set) var statusMessage = "Drop an MP4 or MKV file, or open one from the menu."

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

  private let supportedFileExtensions = Set(["mp4", "m4v", "mkv"])

  init(engine: PlaybackEngine = AVFoundationPlaybackEngine()) {
    self.engine = engine

    self.engine.stateDidChange = { [weak self] state in
      Task { @MainActor in
        self?.playbackState = state
      }
    }

    self.engine.setRate(Float(playbackRate))
    self.engine.setVolume(Float(volume))
    self.engine.setMuted(isMuted)
  }

  func open(url: URL, autoplay: Bool = true) {
    guard isSupported(url: url) else {
      statusMessage = "Unsupported file type: .\(url.pathExtension.lowercased())"
      return
    }

    currentURL = url
    statusMessage = url.lastPathComponent

    engine.load(url: url, autoplay: autoplay)
    NSDocumentController.shared.noteNewRecentDocumentURL(url)
  }

  func openPanel() {
    VideoOpenPanel.present()
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
}
