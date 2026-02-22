import AVKit
import Foundation

final class AVFoundationPlaybackEngine: PlaybackEngine {
  var stateDidChange: ((PlaybackState) -> Void)?
  var playbackDidFinish: (() -> Void)?

  private let player: AVPlayer
  private let playerView: AVPlayerView

  private var timeObserver: Any?
  private var statusObservation: NSKeyValueObservation?
  private var playbackEndObserver: NSObjectProtocol?

  private var preferredRate: Float = 1.0
  private var currentVolume: Float = 1.0
  private var isMuted = false
  private var latestSeekRequestID: UInt64 = 0
  private var isNativeSubtitleRenderingEnabled = true

  init() {
    player = AVPlayer()
    playerView = AVPlayerView()

    playerView.player = player
    playerView.controlsStyle = .none
    playerView.videoGravity = .resizeAspect
    playerView.showsFullScreenToggleButton = false

    setupObservers()
    emitState()
  }

  deinit {
    if let timeObserver {
      player.removeTimeObserver(timeObserver)
    }

    if let playbackEndObserver {
      NotificationCenter.default.removeObserver(playbackEndObserver)
    }

    statusObservation?.invalidate()
  }

  func makeVideoView() -> NSView {
    playerView
  }

  func load(url: URL, autoplay: Bool) {
    let item = AVPlayerItem(url: url)
    player.replaceCurrentItem(with: item)
    applyNativeSubtitleRenderingSelection(for: item)
    scheduleNativeSubtitleRenderingSelectionWhenReady(for: item)

    if autoplay {
      player.playImmediately(atRate: preferredRate)
    } else {
      player.pause()
    }

    emitState()
  }

  func play() {
    player.playImmediately(atRate: preferredRate)
    emitState()
  }

  func pause() {
    player.pause()
    emitState()
  }

  func seek(to time: TimeInterval) {
    guard time.isFinite else { return }
    latestSeekRequestID &+= 1
    let seekRequestID = latestSeekRequestID
    let target = CMTime(seconds: max(0, time), preferredTimescale: 600)
    player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
      guard
        let self,
        finished,
        seekRequestID == self.latestSeekRequestID
      else {
        return
      }

      self.emitState()
    }
  }

  func skip(by interval: TimeInterval) {
    let currentTime = player.currentTime().seconds
    seek(to: currentTime + interval)
  }

  func setRate(_ rate: Float) {
    preferredRate = max(0.5, min(rate, 2.0))

    if player.timeControlStatus == .playing {
      player.playImmediately(atRate: preferredRate)
    }

    emitState()
  }

  func setVolume(_ volume: Float) {
    currentVolume = max(0, min(volume, 1))
    player.volume = currentVolume
    emitState()
  }

  func setMuted(_ muted: Bool) {
    isMuted = muted
    player.isMuted = muted
    emitState()
  }

  func setNativeSubtitleRenderingEnabled(_ enabled: Bool) {
    isNativeSubtitleRenderingEnabled = enabled
    applyNativeSubtitleRenderingSelection()
  }

  private func setupObservers() {
    let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
    timeObserver = player.addPeriodicTimeObserver(
      forInterval: interval,
      queue: .main
    ) { [weak self] _ in
      self?.emitState()
    }

    statusObservation = player.observe(
      \.timeControlStatus,
      options: [.initial, .new]
    ) { [weak self] _, _ in
      self?.emitState()
    }

    playbackEndObserver = NotificationCenter.default.addObserver(
      forName: .AVPlayerItemDidPlayToEndTime,
      object: nil,
      queue: .main
    ) { [weak self] notification in
      guard
        let self,
        let item = notification.object as? AVPlayerItem,
        item == self.player.currentItem
      else {
        return
      }

      self.emitState()
      self.playbackDidFinish?()
    }
  }

  private func emitState() {
    let rawCurrentTime = player.currentTime().seconds
    let currentTime = rawCurrentTime.isFinite ? max(rawCurrentTime, 0) : 0

    let rawDuration = player.currentItem?.duration.seconds ?? 0
    let duration = rawDuration.isFinite ? max(rawDuration, 0) : 0

    let state = PlaybackState(
      isPlaying: player.timeControlStatus == .playing,
      currentTime: currentTime,
      duration: duration,
      rate: preferredRate,
      volume: currentVolume,
      isMuted: isMuted
    )

    stateDidChange?(state)
  }

  private func applyNativeSubtitleRenderingSelection(for item: AVPlayerItem? = nil) {
    guard
      let item = item ?? player.currentItem,
      let group = item.asset.mediaSelectionGroup(forMediaCharacteristic: .legible)
    else {
      return
    }

    if isNativeSubtitleRenderingEnabled {
      item.selectMediaOptionAutomatically(in: group)
    } else {
      item.select(nil, in: group)
    }
  }

  private func scheduleNativeSubtitleRenderingSelectionWhenReady(for item: AVPlayerItem) {
    Task { [weak self, weak item] in
      guard
        let self,
        let item
      else {
        return
      }

      _ = try? await item.asset.load(.availableMediaCharacteristicsWithMediaSelectionOptions)

      await MainActor.run {
        guard item == self.player.currentItem else {
          return
        }

        self.applyNativeSubtitleRenderingSelection(for: item)
      }
    }
  }
}
