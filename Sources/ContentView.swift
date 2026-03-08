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
  @State private var isHoveringFullscreenSubtitleHotspot = false
  @State private var isHoveringFullscreenSubtitlePanel = false
  @State private var isFullscreenSubtitlePanelVisible = false
  @State private var isVolumePopoverPresented = false
  @State private var keyboardMonitor: Any? = nil
  @State private var isSidebarVisible = true
  @State private var fullscreenSubtitleHideWorkItem: DispatchWorkItem?
  @State private var isSeekBarHovered = false

  private let liveSeekDispatchInterval: TimeInterval = 0.08
  private let fullscreenSubtitleHideDelay: TimeInterval = 0.35
  private let playbackRateOptions: [Double] = [0.5, 1.0, 1.25, 1.5, 2.0]

  var body: some View {
    ZStack {
      backgroundLayer

      HStack(spacing: 0) {
        VStack(spacing: isFullscreen ? 0 : DS.Spacing.lg) {
          if !isFullscreen {
            headerView
          }

          playerSurface
            .frame(maxHeight: .infinity)

          if !isFullscreen {
            controlsView
          }
        }
        .padding(.horizontal, isFullscreen ? 0 : DS.Spacing.xl)
        .padding(.vertical, isFullscreen ? 0 : DS.Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)

        if !isFullscreen && isSidebarVisible {
          RecentFilesPanel(
            entries: viewModel.recentEntries,
            archivedEntries: viewModel.archivedEntries,
            currentFilePath: viewModel.currentFilePath,
            onSelect: viewModel.openRecent,
            onRemove: viewModel.removeRecent,
            onRestoreArchived: viewModel.restoreArchivedRecent,
            onDeleteArchivedPermanently: viewModel.deleteArchivedRecentPermanently,
            subtitleCues: viewModel.subtitleTimelineCues,
            activeSubtitleCueIndex: viewModel.activeSubtitleCueIndex,
            activeSubtitleFileName: viewModel.activeSubtitleFileName,
            onAddSubtitle: viewModel.openSubtitlePanel,
            onSelectSubtitleCue: viewModel.seekToSubtitleCue
          )
          .padding(DS.Spacing.xl)
          .frame(width: 320)
          .frame(maxHeight: .infinity, alignment: .topLeading)
          .background(.ultraThinMaterial)
          .overlay(alignment: .leading) {
            Rectangle()
              .fill(DS.Colors.borderSubtle)
              .frame(width: DS.hairline)
          }
          .transition(.move(edge: .trailing).combined(with: .opacity))
        }
      }
    }
    .animation(DS.Anim.gentle, value: isFullscreen)
    .animation(DS.Anim.gentle, value: isSidebarVisible)
    .onAppear {
      syncFullscreenState()
      setupKeyboardMonitoring()
      DispatchQueue.main.async {
        syncFullscreenState()
      }
    }
    .onDisappear {
      teardownKeyboardMonitoring()
      resetFullscreenSubtitlePanelState()
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
      resetFullscreenSubtitlePanelState()
    }
    .onChange(of: viewModel.subtitleTimelineCues.isEmpty) { isEmpty in
      if isEmpty {
        resetFullscreenSubtitlePanelState()
      }
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
    .clipShape(RoundedRectangle(cornerRadius: isFullscreen ? 0 : DS.Radii.player, style: .continuous))
    .overlay {
      if !isFullscreen {
        RoundedRectangle(cornerRadius: DS.Radii.player, style: .continuous)
          .stroke(DS.Colors.borderSubtle, lineWidth: DS.hairline)
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
    .overlay(alignment: .trailing) {
      fullscreenSubtitleOverlay
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
  private var fullscreenSubtitleOverlay: some View {
    if isFullscreen, !viewModel.subtitleTimelineCues.isEmpty {
      ZStack(alignment: .trailing) {
        Color.clear
          .frame(width: 26)
          .frame(maxHeight: .infinity)
          .contentShape(Rectangle())
          .onHover(perform: updateFullscreenSubtitleHotspotHover)

        if isFullscreenSubtitlePanelVisible {
          SubtitleTimelinePanel(
            cues: viewModel.subtitleTimelineCues,
            activeCueIndex: viewModel.activeSubtitleCueIndex,
            activeSubtitleFileName: viewModel.activeSubtitleFileName,
            onAddSubtitle: viewModel.openSubtitlePanel,
            onSelectCue: viewModel.seekToSubtitleCue
          )
          .padding(DS.Spacing.lg)
          .frame(width: 360)
          .frame(maxHeight: .infinity, alignment: .topLeading)
          .background(.ultraThinMaterial)
          .overlay(alignment: .leading) {
            Rectangle()
              .fill(DS.Colors.borderSubtle)
              .frame(width: DS.hairline)
          }
          .transition(.move(edge: .trailing).combined(with: .opacity))
          .onHover(perform: updateFullscreenSubtitlePanelHover)
        }
      }
      .animation(DS.Anim.controlReveal, value: isFullscreenSubtitlePanelVisible)
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
          LinearGradient(
            colors: [.clear, .black.opacity(0.6)],
            startPoint: .top,
            endPoint: .bottom
          )
          .allowsHitTesting(false)

          controlsView
            .padding(.horizontal, DS.Spacing.xl)
            .padding(.bottom, DS.Spacing.lg)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
      }
      .contentShape(Rectangle())
      .onHover { hovering in
        isHoveringFullscreenControlsRegion = hovering
      }
      .animation(DS.Anim.controlReveal, value: isHoveringFullscreenControlsRegion)
    }
  }

  @ViewBuilder
  private var subtitleOverlay: some View {
    if
      let subtitleText = viewModel.subtitleText,
      !subtitleText.isEmpty,
      viewModel.currentURL != nil
    {
      SubtitleTextRenderer.render(subtitleText)
        .font(.system(size: 24, weight: .semibold, design: .rounded))
        .foregroundStyle(.white)
        .multilineTextAlignment(.center)
        .padding(.horizontal, DS.Spacing.xl)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DS.Radii.card, style: .continuous))
        .overlay {
          RoundedRectangle(cornerRadius: DS.Radii.card, style: .continuous)
            .stroke(DS.Colors.borderSubtle, lineWidth: DS.hairline)
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 26)
        .shadow(color: .black.opacity(0.35), radius: 6, x: 0, y: 2)
    }
  }

  private var emptyStateView: some View {
    VStack(spacing: DS.Spacing.lg) {
      ZStack {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
          .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
          .foregroundStyle(.white.opacity(0.2))
          .frame(width: 80, height: 80)

        Image(systemName: "play.square.stack.fill")
          .resizable()
          .scaledToFit()
          .frame(width: 40, height: 40)
          .foregroundStyle(
            LinearGradient(
              colors: [.white.opacity(0.9), .white.opacity(0.5)],
              startPoint: .top,
              endPoint: .bottom
            )
          )
      }

      Text("JustPlay")
        .font(.system(size: 22, weight: .semibold, design: .rounded))
        .foregroundStyle(.white)

      Text(viewModel.statusMessage)
        .font(.subheadline)
        .foregroundStyle(DS.Colors.textSecondary)
        .multilineTextAlignment(.center)

      Button {
        viewModel.openPanel()
      } label: {
        Text("Open Video...")
          .font(.subheadline.weight(.medium))
          .foregroundStyle(.white)
          .padding(.horizontal, 20)
          .padding(.vertical, DS.Spacing.md)
          .background(.white.opacity(0.12), in: Capsule())
          .overlay {
            Capsule()
              .stroke(.white.opacity(0.15), lineWidth: DS.hairline)
          }
      }
      .buttonStyle(.plain)
    }
    .padding(.horizontal, 28)
    .padding(.vertical, 24)
    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DS.Radii.player, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: DS.Radii.player, style: .continuous)
        .stroke(DS.Colors.borderSubtle, lineWidth: DS.hairline)
    }
  }

  private var controlsView: some View {
    let hasActiveMedia = viewModel.currentURL != nil

    return HStack(spacing: DS.Spacing.lg) {
      // Transport cluster (skip back, play/pause, skip forward)
      HStack(spacing: DS.Spacing.sm) {
        Button(action: viewModel.skipBackward) {
          Image(systemName: "gobackward.10")
            .font(.system(size: 13, weight: .semibold))
            .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .disabled(!hasActiveMedia)

        Button(action: viewModel.togglePlayPause) {
          Image(systemName: displayedIsPlaying ? "pause.fill" : "play.fill")
            .font(.system(size: 15, weight: .semibold))
            .frame(width: 36, height: 36)
            .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: DS.Radii.button, style: .continuous))
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.space, modifiers: [])
        .disabled(!hasActiveMedia)

        Button(action: viewModel.skipForward) {
          Image(systemName: "goforward.10")
            .font(.system(size: 13, weight: .semibold))
            .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .disabled(!hasActiveMedia)
      }

      HStack(spacing: DS.Spacing.md) {
        Text(displayedCurrentTime.playbackText)
          .font(.system(size: 11, weight: .medium, design: .monospaced))
          .foregroundStyle(.white.opacity(0.85))
          .frame(width: 52, alignment: .leading)

        seekBar

        Text(viewModel.playbackState.duration.playbackText)
          .font(.system(size: 11, weight: .medium, design: .monospaced))
          .foregroundStyle(DS.Colors.textSecondary)
          .frame(width: 52, alignment: .trailing)
      }
      .frame(maxWidth: .infinity)

      HStack(spacing: DS.Spacing.sm) {
        Button {
          isVolumePopoverPresented.toggle()
        } label: {
          Image(systemName: "speaker.wave.2.fill")
            .font(.system(size: 12))
        }
        .buttonStyle(.borderless)
        .help("Volume")
        .popover(isPresented: $isVolumePopoverPresented, arrowEdge: .top) {
          volumePopoverContent
        }

        Menu {
          ForEach(playbackRateOptions, id: \.self) { rate in
            Button {
              viewModel.playbackRate = rate
            } label: {
              HStack(spacing: 8) {
                Text(playbackRateLabel(for: rate))

                Spacer(minLength: 8)

                if isSelectedPlaybackRate(rate) {
                  Image(systemName: "checkmark")
                }
              }
              .frame(maxWidth: .infinity, alignment: .leading)
            }
          }
        } label: {
          Text(playbackRateLabel(for: viewModel.playbackRate))
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .frame(minWidth: 38)
        }
        .buttonStyle(.borderless)
        .menuIndicator(.hidden)
        .help("Playback Speed")
        .disabled(!hasActiveMedia)

        Menu {
          Button("Open...") {
            viewModel.openPanel()
          }

          Divider()

          Button(isSidebarVisible ? "Hide Sidebar" : "Show Sidebar") {
            isSidebarVisible.toggle()
          }
          .keyboardShortcut("b", modifiers: .command)

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
        } label: {
          Image(systemName: "ellipsis.circle")
            .font(.system(size: 12))
        }
        .buttonStyle(.borderless)
        .menuIndicator(.hidden)
        .help("More Actions")

        Button(action: toggleFullscreen) {
          Image(systemName: isFullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
            .font(.system(size: 12))
        }
        .buttonStyle(.borderless)
        .help(isFullscreen ? "Exit Full Screen" : "Enter Full Screen")
      }
    }
    .padding(.horizontal, DS.Spacing.lg)
    .padding(.vertical, DS.Spacing.md)
    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DS.Radii.controlBar, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: DS.Radii.controlBar, style: .continuous)
        .stroke(DS.Colors.borderSubtle, lineWidth: DS.hairline)
    }
    .dsModifier(DS.Shadows.controlBar())
  }

  private var volumePopoverContent: some View {
    let trailingControlWidth: CGFloat = 44

    return VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("Volume")
          .font(.subheadline.weight(.semibold))

        Spacer(minLength: 8)

        Button {
          viewModel.isMuted.toggle()
        } label: {
          Image(systemName: viewModel.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
        }
        .buttonStyle(.bordered)
        .frame(width: trailingControlWidth, alignment: .trailing)
        .help(viewModel.isMuted ? "Unmute" : "Mute")
      }

      HStack(spacing: 10) {
        Image(systemName: "speaker.wave.1.fill")
          .foregroundStyle(.secondary)

        Slider(value: $viewModel.volume, in: 0...1)
          .frame(maxWidth: .infinity)
          .disabled(viewModel.isMuted)
          .onChange(of: viewModel.volume) { newValue in
            if newValue > 0, viewModel.isMuted {
              viewModel.isMuted = false
            }
          }
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 14)
    .frame(width: 272)
  }

  private var headerView: some View {
    HStack(spacing: DS.Spacing.md) {
      Image(systemName: "film")
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(DS.Colors.textSecondary)

      Text(viewModel.currentURL?.lastPathComponent ?? "No video loaded")
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
    .padding(.horizontal, DS.Spacing.lg)
    .padding(.vertical, DS.Spacing.md)
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var backgroundLayer: some View {
    Group {
      if isFullscreen {
        Color.black
      } else {
        LinearGradient(
          colors: [
            Color(red: 0.06, green: 0.08, blue: 0.12),
            Color(red: 0.10, green: 0.13, blue: 0.18)
          ],
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        )
      }
    }
    .ignoresSafeArea()
  }

  private var seekBar: some View {
    let seekBarExpanded = isSeekBarHovered || isSeeking
    let trackHeight: CGFloat = seekBarExpanded ? 6 : 3
    let thumbVisible = seekBarExpanded

    return GeometryReader { geometry in
      let width = max(geometry.size.width, 1)
      let duration = max(viewModel.playbackState.duration, 0)
      let currentTime = displayedCurrentTime
      let playedRatio = normalizedSeekRatio(for: currentTime, duration: duration)
      let markerX = min(max(width * playedRatio, 0), width)
      let previewTime = isSeeking ? seekPosition : nil
      let previewPadding = min(CGFloat(28), width / 2)
      let previewCenterX = min(max(markerX, previewPadding), width - previewPadding)

      ZStack(alignment: .leading) {
        RoundedRectangle(cornerRadius: trackHeight / 2, style: .continuous)
          .fill(DS.Colors.seekTrack)
          .frame(height: trackHeight)

        RoundedRectangle(cornerRadius: trackHeight / 2, style: .continuous)
          .fill(DS.Colors.seekFill)
          .frame(width: max(width * playedRatio, trackHeight), height: trackHeight)

        Circle()
          .fill(DS.Colors.seekThumb)
          .frame(width: 12, height: 12)
          .shadow(color: .black.opacity(0.3), radius: 3, x: 0, y: 1)
          .offset(x: max(markerX - 6, 0))
          .scaleEffect(thumbVisible ? 1 : 0.01)
          .opacity(thumbVisible ? 1 : 0)

        if let previewTime {
          Text(previewTime.playbackText)
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundStyle(.white)
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, DS.Spacing.xs)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DS.Radii.seekPreview, style: .continuous))
            .overlay {
              RoundedRectangle(cornerRadius: DS.Radii.seekPreview, style: .continuous)
                .stroke(DS.Colors.borderSubtle, lineWidth: DS.hairline)
            }
            .position(x: previewCenterX, y: -8)
        }
      }
      .frame(height: 22)
      .contentShape(Rectangle())
      .onHover { hovering in
        isSeekBarHovered = hovering
      }
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
      .animation(DS.Anim.seekExpand, value: seekBarExpanded)
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
      .font(.subheadline.weight(.semibold))
      .padding(.horizontal, DS.Spacing.lg)
      .padding(.vertical, DS.Spacing.md)
      .foregroundStyle(.white)
      .background(.ultraThinMaterial, in: Capsule())
      .overlay {
        Capsule()
          .stroke(Color.accentColor.opacity(0.6), lineWidth: 1)
      }
      .shadow(color: Color.accentColor.opacity(0.3), radius: 8, x: 0, y: 2)
      .padding(DS.Spacing.lg)
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
        // Handle Cmd+B for sidebar toggle
        if event.keyCode == 11 {
          self.isSidebarVisible.toggle()
          return nil
        }
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

  private func updateFullscreenSubtitleHotspotHover(_ hovering: Bool) {
    isHoveringFullscreenSubtitleHotspot = hovering

    if hovering {
      showFullscreenSubtitlePanel()
    } else {
      scheduleFullscreenSubtitlePanelHideIfNeeded()
    }
  }

  private func updateFullscreenSubtitlePanelHover(_ hovering: Bool) {
    isHoveringFullscreenSubtitlePanel = hovering

    if hovering {
      showFullscreenSubtitlePanel()
    } else {
      scheduleFullscreenSubtitlePanelHideIfNeeded()
    }
  }

  private func showFullscreenSubtitlePanel() {
    fullscreenSubtitleHideWorkItem?.cancel()
    fullscreenSubtitleHideWorkItem = nil
    isFullscreenSubtitlePanelVisible = true
  }

  private func scheduleFullscreenSubtitlePanelHideIfNeeded() {
    fullscreenSubtitleHideWorkItem?.cancel()

    let workItem = DispatchWorkItem {
      if !isHoveringFullscreenSubtitleHotspot && !isHoveringFullscreenSubtitlePanel {
        isFullscreenSubtitlePanelVisible = false
      }
    }

    fullscreenSubtitleHideWorkItem = workItem
    DispatchQueue.main.asyncAfter(deadline: .now() + fullscreenSubtitleHideDelay, execute: workItem)
  }

  private func resetFullscreenSubtitlePanelState() {
    fullscreenSubtitleHideWorkItem?.cancel()
    fullscreenSubtitleHideWorkItem = nil
    isHoveringFullscreenSubtitleHotspot = false
    isHoveringFullscreenSubtitlePanel = false
    isFullscreenSubtitlePanelVisible = false
  }

  private func playbackRateLabel(for rate: Double) -> String {
    switch rate {
    case 0.5:
      return "0.5x"
    case 1.0:
      return "1.0x"
    case 1.25:
      return "1.25x"
    case 1.5:
      return "1.5x"
    case 2.0:
      return "2.0x"
    default:
      return String(format: "%.2fx", rate)
    }
  }

  private func isSelectedPlaybackRate(_ rate: Double) -> Bool {
    abs(rate - viewModel.playbackRate) < 0.001
  }
}
