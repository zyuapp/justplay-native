import AppKit
import Foundation

protocol PlaybackEngine: AnyObject {
  var stateDidChange: ((PlaybackState) -> Void)? { get set }
  var playbackDidFinish: (() -> Void)? { get set }

  func makeVideoView() -> NSView
  func load(url: URL, autoplay: Bool)
  func play()
  func pause()
  func seek(to time: TimeInterval)
  func skip(by interval: TimeInterval)
  func setRate(_ rate: Float)
  func setVolume(_ volume: Float)
  func setMuted(_ muted: Bool)
  func setNativeSubtitleRenderingEnabled(_ enabled: Bool)
}
