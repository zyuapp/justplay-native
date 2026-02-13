import Foundation

struct PlaybackState {
  var isPlaying: Bool
  var currentTime: TimeInterval
  var duration: TimeInterval
  var rate: Float
  var volume: Float
  var isMuted: Bool

  static let initial = PlaybackState(
    isPlaying: false,
    currentTime: 0,
    duration: 0,
    rate: 1.0,
    volume: 1.0,
    isMuted: false
  )
}
