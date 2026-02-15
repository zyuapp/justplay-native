import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
  @StateObject private var viewModel = PlayerViewModel()

  @State private var isDropTargeted = false
  @State private var seekPosition: Double = 0
  @State private var isSeeking = false
  @State private var seekStartedWhilePlaying = false
  @State private var lastLiveSeekDispatchTimestamp: TimeInterval = 0
  @State private var isFullscreen = false
  @State private var isHoveringFullscreenControlsRegion = false
  @State private var keyboardMonitor: Any? = nil

  private let liveSeekDispatchInterval: TimeInterval = 0.08

  var body: some View {
    ZStack {
      backgroundLayer

      HStack(spacing: 0) {
        VStack(spacing: isFullscreen ? 0 : 14) {
          if !isFullscreen {
            headerView
          }

          playerSurface
            .frame(maxHeight: .infinity)

          if !isFullscreen {
            controlsView
          }
        }
        .padding(.horizontal, isFullscreen ? 0 : 16)
        .padding(.vertical, isFullscreen ? 0 : 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)

        if !isFullscreen {
          Divider()
            .overlay(.white.opacity(0.08))

          RecentFilesPanel(
            entries: viewModel.recentEntries,
            archivedEntries: viewModel.archivedEntries,
            currentFilePath: viewModel.currentFilePath,
            onSelect: viewModel.openRecent,
            onRemove: viewModel.removeRecent,
            onRestoreArchived: viewModel.restoreArchivedRecent,
            onDeleteArchivedPermanently: viewModel.deleteArchivedRecentPermanently
          )
          .padding(16)
          .frame(width: 320)
          .frame(maxHeight: .infinity, alignment: .topLeading)
          .background(.regularMaterial)
          .transition(.move(edge: .trailing).combined(with: .opacity))
        }
      }
    }
    .animation(.easeInOut(duration: 0.22), value: isFullscreen)
    .onAppear {
      syncFullscreenState()
      setupKeyboardMonitoring()
      DispatchQueue.main.async {
        syncFullscreenState()
      }
    }
    .onDisappear {
      teardownKeyboardMonitoring()
    }
    .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { _ in
      isFullscreen = true
    }
    .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { _ in
      isFullscreen = false
    }
    .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { notification in
      syncFullscreenState(from: notification.object as? NSWindow)
    }
    .onReceive(NotificationCenter.default.publisher(for: AppOpenBus.didRequestOpenURLs)) { notification in
      let urls = AppOpenBus.urls(from: notification)
      guard let firstURL = urls.first else { return }
      viewModel.open(url: firstURL)
    }
    .onChange(of: viewModel.playbackState.currentTime) { newValue in
      guard !isSeeking else { return }
      seekPosition = max(newValue, 0)
    }
    .onChange(of: isFullscreen) { newValue in
      guard !newValue else { return }
      isHoveringFullscreenControlsRegion = false
    }
    .onChange(of: viewModel.playbackState.duration) { newValue in
      guard !isSeeking else { return }
      seekPosition = min(seekPosition, max(newValue, 0))
    }
    .frame(minWidth: 1080, minHeight: 640)
  }

  private var playerSurface: some View {
    ZStack {
      PlaybackEngineView(engine: viewModel.engine)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)

      if viewModel.currentURL == nil {
        emptyStateView
      }
    }
    .clipShape(RoundedRectangle(cornerRadius: isFullscreen ? 0 : 18, style: .continuous))
    .overlay {
      if !isFullscreen {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
          .stroke(.white.opacity(0.12), lineWidth: 1)
      }
    }
    .shadow(color: .black.opacity(isFullscreen ? 0 : 0.3), radius: isFullscreen ? 0 : 18, x: 0, y: isFullscreen ? 0 : 10)
    .overlay(alignment: .topLeading) {
      if isDropTargeted {
        dropIndicator
      }
    }
    .overlay(alignment: .bottom) {
      subtitleOverlay
    }
    .overlay(alignment: .bottom) {
      fullscreenControlsOverlay
    }
    .simultaneousGesture(
      TapGesture(count: 2)
        .onEnded {
          toggleFullscreen()
        }
    )
    .onDrop(of: [.fileURL], isTargeted: $isDropTargeted, perform: handleDrop)
    .contextMenu {
      Button("Open...") {
        viewModel.openPanel()
      }

      Divider()

      Button("Add Subtitle...") {
        viewModel.openSubtitlePanel()
      }

      if viewModel.hasSubtitleTrack {
        Button(viewModel.subtitlesEnabled ? "Hide Subtitles" : "Show Subtitles") {
          viewModel.subtitlesEnabled.toggle()
        }

        Button("Remove Subtitle") {
          viewModel.removeSubtitleTrack()
        }
      }
    }
  }

  @ViewBuilder
  private var fullscreenControlsOverlay: some View {
    if isFullscreen {
      ZStack(alignment: .bottom) {
        Color.clear
          .frame(maxWidth: .infinity)
          .frame(height: 172)

        if isHoveringFullscreenControlsRegion {
          controlsView
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
      }
      .contentShape(Rectangle())
      .onHover { hovering in
        isHoveringFullscreenControlsRegion = hovering
      }
      .animation(.easeInOut(duration: 0.16), value: isHoveringFullscreenControlsRegion)
    }
  }

  @ViewBuilder
  private var subtitleOverlay: some View {
    if
      let subtitleText = viewModel.subtitleText,
      !subtitleText.isEmpty,
      viewModel.currentURL != nil
    {
      Text(subtitleText)
        .font(.system(size: 24, weight: .semibold, design: .rounded))
        .foregroundStyle(.white)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.black.opacity(0.68), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(.horizontal, 28)
        .padding(.bottom, 26)
        .shadow(color: .black.opacity(0.35), radius: 6, x: 0, y: 2)
    }
  }

  private var emptyStateView: some View {
    VStack(spacing: 12) {
      Image(systemName: "play.square.stack.fill")
        .resizable()
        .scaledToFit()
        .frame(width: 54, height: 54)
        .foregroundStyle(.white.opacity(0.8))

      Text("JustPlay")
        .font(.title3.weight(.semibold))
        .foregroundStyle(.white)

      Text(viewModel.statusMessage)
        .font(.subheadline)
        .foregroundStyle(.white.opacity(0.7))
        .multilineTextAlignment(.center)

      Button("Open Video...") {
        viewModel.openPanel()
      }
      .buttonStyle(.borderedProminent)
    }
    .padding(.horizontal, 28)
    .padding(.vertical, 24)
    .background(.black.opacity(0.52), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
  }

  private var controlsView: some View {
    VStack(spacing: 12) {
      HStack(spacing: 10) {
        Button(action: viewModel.togglePlayPause) {
          Image(systemName: displayedIsPlaying ? "pause.fill" : "play.fill")
        }
        .buttonStyle(.borderedProminent)
        .keyboardShortcut(.space, modifiers: [])

        Button(action: viewModel.skipBackward) {
          Image(systemName: "gobackward.10")
        }

        Button(action: viewModel.skipForward) {
          Image(systemName: "goforward.10")
        }

        Text(formattedTime(displayedCurrentTime))
          .font(.system(.footnote, design: .monospaced))
          .foregroundStyle(.primary)
          .frame(width: 52, alignment: .leading)

        seekBar

        Text(formattedTime(viewModel.playbackState.duration))
          .font(.system(.footnote, design: .monospaced))
          .foregroundStyle(.primary)
          .frame(width: 52, alignment: .trailing)

        Button("Open...") {
          viewModel.openPanel()
        }

        Button {
          viewModel.openSubtitlePanel()
        } label: {
          Label("Subtitles", systemImage: viewModel.hasSubtitleTrack ? "captions.bubble.fill" : "captions.bubble")
        }
        .buttonStyle(.bordered)

        Button(action: toggleFullscreen) {
          Image(systemName: "arrow.up.left.and.arrow.down.right")
        }
        .buttonStyle(.bordered)
      }

      HStack(spacing: 10) {
        Image(systemName: "speaker.wave.2")
          .foregroundStyle(.primary)

        Slider(value: $viewModel.volume, in: 0...1)
          .frame(maxWidth: 180)

        Button(action: { viewModel.isMuted.toggle() }) {
          Image(systemName: viewModel.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
        }

        Picker("Speed", selection: $viewModel.playbackRate) {
          Text("0.5x").tag(0.5)
          Text("1.0x").tag(1.0)
          Text("1.25x").tag(1.25)
          Text("1.5x").tag(1.5)
          Text("2.0x").tag(2.0)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 250)
      }

      HStack(spacing: 8) {
        Label(statusLineText, systemImage: "info.circle")
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)

        Spacer(minLength: 8)
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .stroke(.white.opacity(0.12), lineWidth: 1)
    }
  }

  private var headerView: some View {
    HStack(spacing: 12) {
      Text(viewModel.currentURL?.lastPathComponent ?? "Open a local video to start playback")
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .stroke(.white.opacity(0.12), lineWidth: 1)
    }
  }

  private var backgroundLayer: some View {
    Group {
      if isFullscreen {
        Color.black
      } else {
        LinearGradient(
          colors: [
            Color(red: 0.07, green: 0.1, blue: 0.14),
            Color(red: 0.11, green: 0.15, blue: 0.2)
          ],
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        )
      }
    }
    .ignoresSafeArea()
  }

  private var seekBar: some View {
    GeometryReader { geometry in
      let width = max(geometry.size.width, 1)
      let duration = max(viewModel.playbackState.duration, 0)
      let currentTime = displayedCurrentTime
      let playedRatio = normalizedSeekRatio(for: currentTime, duration: duration)
      let markerX = min(max(width * playedRatio, 0), width)
      let previewTime = isSeeking ? seekPosition : nil
      let previewPadding = min(CGFloat(28), width / 2)
      let previewCenterX = min(max(markerX, previewPadding), width - previewPadding)

      ZStack(alignment: .leading) {
        Capsule(style: .continuous)
          .fill(.white.opacity(0.2))
          .frame(height: 4)

        Capsule(style: .continuous)
          .fill(.white.opacity(0.88))
          .frame(width: max(width * playedRatio, 4), height: 4)

        Circle()
          .fill(.white)
          .frame(width: 10, height: 10)
          .offset(x: max(markerX - 5, 0))

        if let previewTime {
          Text(formattedTime(previewTime))
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .position(x: previewCenterX, y: -8)
        }
      }
      .frame(height: 22)
      .contentShape(Rectangle())
      .gesture(
        DragGesture(minimumDistance: 0)
          .onChanged { value in
            guard duration > 0 else { return }
            let clampedX = min(max(value.location.x, 0), width)

            let targetTime = seekTime(for: clampedX, totalWidth: width)
            if !isSeeking {
              beginSeekingSession()
            }

            seekPosition = targetTime
            dispatchLiveSeekIfNeeded(to: targetTime)
          }
          .onEnded { value in
            guard duration > 0 else {
              endSeekingSession()
              return
            }

            let clampedX = min(max(value.location.x, 0), width)
            let targetTime = seekTime(for: clampedX, totalWidth: width)
            seekPosition = targetTime
            viewModel.seek(to: targetTime, persistImmediately: true)
            endSeekingSession()
          }
      )
      .opacity(duration > 0 ? 1 : 0.5)
    }
    .frame(maxWidth: .infinity)
    .frame(height: 22)
  }

  private func normalizedSeekRatio(for time: Double, duration: Double) -> Double {
    guard duration > 0 else {
      return 0
    }

    return min(max(time / duration, 0), 1)
  }

  private func seekTime(for positionX: CGFloat, totalWidth: CGFloat) -> Double {
    let clampedWidth = max(totalWidth, 1)
    let ratio = min(max(Double(positionX / clampedWidth), 0), 1)
    return ratio * max(viewModel.playbackState.duration, 0)
  }

  private var displayedCurrentTime: TimeInterval {
    isSeeking ? seekPosition : viewModel.playbackState.currentTime
  }

  private var displayedIsPlaying: Bool {
    isSeeking ? seekStartedWhilePlaying : viewModel.playbackState.isPlaying
  }

  private func beginSeekingSession() {
    isSeeking = true
    seekStartedWhilePlaying = viewModel.playbackState.isPlaying
    lastLiveSeekDispatchTimestamp = 0
  }

  private func endSeekingSession() {
    isSeeking = false
    lastLiveSeekDispatchTimestamp = 0
  }

  private func dispatchLiveSeekIfNeeded(to time: TimeInterval) {
    let now = Date.timeIntervalSinceReferenceDate
    guard now - lastLiveSeekDispatchTimestamp >= liveSeekDispatchInterval else {
      return
    }

    lastLiveSeekDispatchTimestamp = now
    viewModel.seek(to: time)
  }

  private var dropIndicator: some View {
    Label("Drop to Open", systemImage: "arrow.down.doc")
      .font(.headline)
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
      .foregroundStyle(.white)
      .background(.blue.opacity(0.8), in: Capsule())
      .padding(14)
  }

  private func handleDrop(providers: [NSItemProvider]) -> Bool {
    DropURLLoader.loadFirstURL(from: providers) { url in
      guard let url else { return }
      viewModel.open(url: url)
    }
  }

  private func setupKeyboardMonitoring() {
    guard keyboardMonitor == nil else {
      return
    }

    keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
      guard self.currentWindow() != nil else {
        return event
      }

      guard !event.modifierFlags.contains(.command) else {
        return event
      }

      if event.keyCode == 53 {
        self.exitFullScreenIfNeeded()
        return nil
      }

      guard self.viewModel.currentURL != nil else {
        return event
      }

      switch event.keyCode {
      case 49:
        self.viewModel.togglePlayPause()
        return nil
      case 123:
        self.viewModel.skipBackward()
        return nil
      case 124:
        self.viewModel.skipForward()
        return nil
      default:
        return event
      }
    }
  }

  private func teardownKeyboardMonitoring() {
    if let monitor = keyboardMonitor {
      NSEvent.removeMonitor(monitor)
      keyboardMonitor = nil
    }
  }

  private func exitFullScreenIfNeeded() {
    guard
      let window = currentWindow(),
      window.styleMask.contains(.fullScreen)
    else {
      return
    }

    window.toggleFullScreen(nil)
  }

  private func toggleFullscreen() {
    currentWindow()?.toggleFullScreen(nil)
  }

  private func syncFullscreenState(from window: NSWindow? = nil) {
    if let window {
      isFullscreen = window.styleMask.contains(.fullScreen)
      return
    }

    isFullscreen = currentWindow()?.styleMask.contains(.fullScreen) ?? false
  }

  private func currentWindow() -> NSWindow? {
    NSApplication.shared.mainWindow ?? NSApplication.shared.keyWindow
  }

  private func formattedTime(_ seconds: TimeInterval) -> String {
    guard seconds.isFinite else { return "00:00" }

    let totalSeconds = max(Int(seconds.rounded(.down)), 0)
    let hours = totalSeconds / 3600
    let minutes = (totalSeconds % 3600) / 60
    let remainderSeconds = totalSeconds % 60

    if hours > 0 {
      return String(format: "%d:%02d:%02d", hours, minutes, remainderSeconds)
    }

    return String(format: "%02d:%02d", minutes, remainderSeconds)
  }

  private var statusLineText: String {
    if let subtitleName = viewModel.activeSubtitleFileName {
      return "Subtitles: \(subtitleName)"
    }

    return viewModel.statusMessage
  }
}
