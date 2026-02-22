import Foundation

enum VLCNativeSubtitleCommand: Equatable {
  case setTrack(Int32)
}

struct VLCNativeSubtitlePolicy {
  private(set) var isNativeRenderingEnabled = true
  private var cachedNativeTrackIndex: Int32?

  mutating func mediaDidLoad() {
    cachedNativeTrackIndex = nil
  }

  mutating func setNativeRenderingEnabled(_ enabled: Bool, currentTrackIndex: Int32) -> [VLCNativeSubtitleCommand] {
    guard isNativeRenderingEnabled != enabled else {
      return []
    }

    isNativeRenderingEnabled = enabled
    return reconcile(currentTrackIndex: currentTrackIndex)
  }

  mutating func reconcile(currentTrackIndex: Int32) -> [VLCNativeSubtitleCommand] {
    if isNativeRenderingEnabled {
      return restoreNativeTrackIfNeeded(currentTrackIndex: currentTrackIndex)
    }

    return suppressNativeTrackIfNeeded(currentTrackIndex: currentTrackIndex)
  }

  private mutating func restoreNativeTrackIfNeeded(currentTrackIndex: Int32) -> [VLCNativeSubtitleCommand] {
    guard let cachedNativeTrackIndex else {
      return []
    }

    self.cachedNativeTrackIndex = nil

    guard currentTrackIndex != cachedNativeTrackIndex else {
      return []
    }

    return [.setTrack(cachedNativeTrackIndex)]
  }

  private mutating func suppressNativeTrackIfNeeded(currentTrackIndex: Int32) -> [VLCNativeSubtitleCommand] {
    if currentTrackIndex != -1, cachedNativeTrackIndex == nil {
      cachedNativeTrackIndex = currentTrackIndex
    }

    guard currentTrackIndex != -1 else {
      return []
    }

    return [.setTrack(-1)]
  }
}
