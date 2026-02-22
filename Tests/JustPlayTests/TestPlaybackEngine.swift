import AppKit
import Foundation
@testable import JustPlay

final class TestPlaybackEngine: PlaybackEngine {
  enum Event: Equatable {
    case load(path: String, autoplay: Bool)
    case play
    case pause
    case seek(TimeInterval)
    case skip(TimeInterval)
    case setRate(Float)
    case setVolume(Float)
    case setMuted(Bool)
    case setNativeSubtitleRenderingEnabled(Bool)
  }

  var stateDidChange: ((PlaybackState) -> Void)?
  var playbackDidFinish: (() -> Void)?

  private(set) var events: [Event] = []

  func makeVideoView() -> NSView {
    NSView(frame: .zero)
  }

  func load(url: URL, autoplay: Bool) {
    events.append(.load(path: url.standardizedFileURL.path, autoplay: autoplay))
  }

  func play() {
    events.append(.play)
  }

  func pause() {
    events.append(.pause)
  }

  func seek(to time: TimeInterval) {
    events.append(.seek(time))
  }

  func skip(by interval: TimeInterval) {
    events.append(.skip(interval))
  }

  func setRate(_ rate: Float) {
    events.append(.setRate(rate))
  }

  func setVolume(_ volume: Float) {
    events.append(.setVolume(volume))
  }

  func setMuted(_ muted: Bool) {
    events.append(.setMuted(muted))
  }

  func setNativeSubtitleRenderingEnabled(_ enabled: Bool) {
    events.append(.setNativeSubtitleRenderingEnabled(enabled))
  }

  func emitState(_ state: PlaybackState) {
    stateDidChange?(state)
  }

  func emitPlaybackDidFinish() {
    playbackDidFinish?()
  }
}
