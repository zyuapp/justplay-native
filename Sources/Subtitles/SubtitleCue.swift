import Foundation

struct SubtitleCue: Hashable {
  let start: TimeInterval
  let end: TimeInterval
  let text: String

  func contains(_ time: TimeInterval) -> Bool {
    time >= start && time <= end
  }
}
