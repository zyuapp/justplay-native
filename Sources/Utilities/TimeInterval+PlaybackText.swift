import Foundation

extension TimeInterval {
  var playbackText: String {
    guard isFinite else { return "00:00" }

    let totalSeconds = max(Int(rounded(.down)), 0)
    let hours = totalSeconds / 3600
    let minutes = (totalSeconds % 3600) / 60
    let remainderSeconds = totalSeconds % 60

    if hours > 0 {
      return String(format: "%d:%02d:%02d", hours, minutes, remainderSeconds)
    }

    return String(format: "%02d:%02d", minutes, remainderSeconds)
  }
}
