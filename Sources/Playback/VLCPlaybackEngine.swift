#if canImport(VLCKit)
import AppKit
import Foundation
import VLCKit

final class VLCPlaybackEngine: NSObject, PlaybackEngine {
  var stateDidChange: ((PlaybackState) -> Void)?
  var playbackDidFinish: (() -> Void)?

  private let mediaPlayer: VLCMediaPlayer
  private let videoView: VLCVideoView

  private var preferredRate: Float = 1.0
  private var currentVolume: Float = 1.0
  private var isMuted = false
  private var nativeSubtitlePolicy = VLCNativeSubtitlePolicy()

  override init() {
    mediaPlayer = VLCMediaPlayer()
    videoView = VLCVideoView(frame: .zero)

    super.init()

    videoView.autoresizingMask = [.width, .height]
    mediaPlayer.drawable = videoView
    mediaPlayer.delegate = self

    applyVolumeSettings()
    emitState()
  }

  func makeVideoView() -> NSView {
    videoView
  }

  func load(url: URL, autoplay: Bool) {
    let media = VLCMedia(url: url)
    mediaPlayer.media = media
    nativeSubtitlePolicy.mediaDidLoad()

    if autoplay {
      mediaPlayer.play()
    }

    mediaPlayer.rate = preferredRate
    applyVolumeSettings()
    reconcileNativeSubtitleRendering()
    emitState()
  }

  func play() {
    mediaPlayer.play()
    mediaPlayer.rate = preferredRate
    emitState()
  }

  func pause() {
    mediaPlayer.pause()
    emitState()
  }

  func seek(to time: TimeInterval) {
    guard time.isFinite else { return }
    let clampedTime = max(time, 0)
    mediaPlayer.time = VLCTime(int: Int32(clampedTime * 1000))
    emitState()
  }

  func skip(by interval: TimeInterval) {
    let currentMilliseconds = mediaPlayer.time.intValue
    let newMilliseconds = max(Double(currentMilliseconds) + (interval * 1000), 0)
    mediaPlayer.time = VLCTime(int: Int32(newMilliseconds))
    emitState()
  }

  func setRate(_ rate: Float) {
    preferredRate = max(0.5, min(rate, 2.0))
    mediaPlayer.rate = preferredRate
    emitState()
  }

  func setVolume(_ volume: Float) {
    currentVolume = max(0, min(volume, 1))
    applyVolumeSettings()
    emitState()
  }

  func setMuted(_ muted: Bool) {
    isMuted = muted
    applyVolumeSettings()
    emitState()
  }

  func setNativeSubtitleRenderingEnabled(_ enabled: Bool) {
    let wasEnabled = nativeSubtitlePolicy.isNativeRenderingEnabled
    let commands = nativeSubtitlePolicy.setNativeRenderingEnabled(
      enabled,
      currentTrackIndex: mediaPlayer.currentVideoSubTitleIndex
    )

    guard wasEnabled != nativeSubtitlePolicy.isNativeRenderingEnabled else {
      return
    }

    applyNativeSubtitleCommands(commands)
    emitState()
  }

  private func applyVolumeSettings() {
    mediaPlayer.audio?.isMuted = isMuted
    mediaPlayer.audio?.volume = Int32(currentVolume * 100)
  }

  private func reconcileNativeSubtitleRendering() {
    let commands = nativeSubtitlePolicy.reconcile(currentTrackIndex: mediaPlayer.currentVideoSubTitleIndex)
    applyNativeSubtitleCommands(commands)
  }

  private func applyNativeSubtitleCommands(_ commands: [VLCNativeSubtitleCommand]) {
    for command in commands {
      switch command {
      case let .setTrack(trackIndex):
        if mediaPlayer.currentVideoSubTitleIndex != trackIndex {
          mediaPlayer.currentVideoSubTitleIndex = trackIndex
        }
      }
    }
  }

  private func emitState() {
    let currentMilliseconds = mediaPlayer.time.intValue
    let currentTime = max(Double(currentMilliseconds) / 1000, 0)

    let durationMilliseconds = mediaPlayer.media?.length.intValue ?? 0
    let duration = max(Double(durationMilliseconds) / 1000, 0)

    let state = PlaybackState(
      isPlaying: mediaPlayer.isPlaying,
      currentTime: currentTime,
      duration: duration,
      rate: preferredRate,
      volume: currentVolume,
      isMuted: isMuted
    )

    stateDidChange?(state)
  }
}

extension VLCPlaybackEngine: VLCMediaPlayerDelegate {
  func mediaPlayerStateChanged(_ aNotification: Notification) {
    reconcileNativeSubtitleRendering()
    emitState()

    if mediaPlayer.state == .ended {
      playbackDidFinish?()
    }
  }

  func mediaPlayerTimeChanged(_ aNotification: Notification) {
    reconcileNativeSubtitleRendering()
    emitState()
  }
}
#endif
