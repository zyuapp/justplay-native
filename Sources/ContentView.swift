import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
  @StateObject private var viewModel = PlayerViewModel()

  @State private var isDropTargeted = false
  @State private var seekPosition: Double = 0
  @State private var isSeeking = false
  @State private var isFullscreen = false

  var body: some View {
    ZStack {
      backgroundLayer

      HStack(spacing: 0) {
        VStack(spacing: 14) {
          headerView
          playerSurface
            .frame(maxHeight: .infinity)
          controlsView
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)

        if !isFullscreen {
          Divider()
            .overlay(.white.opacity(0.08))

          RecentFilesPanel(
            entries: viewModel.recentEntries,
            currentFilePath: viewModel.currentFilePath,
            onSelect: viewModel.openRecent
          )
          .transition(.move(edge: .trailing).combined(with: .opacity))
        }
      }
    }
    .animation(.easeInOut(duration: 0.22), value: isFullscreen)
    .onAppear {
      syncFullscreenState()
    }
    .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { _ in
      isFullscreen = true
    }
    .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { _ in
      isFullscreen = false
    }
    .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
      syncFullscreenState()
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
    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .stroke(.white.opacity(0.12), lineWidth: 1)
    }
    .shadow(color: .black.opacity(0.3), radius: 18, x: 0, y: 10)
    .overlay(alignment: .topLeading) {
      if isDropTargeted {
        dropIndicator
      }
    }
    .overlay(alignment: .bottom) {
      subtitleOverlay
    }
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
          Image(systemName: viewModel.playbackState.isPlaying ? "pause.fill" : "play.fill")
        }
        .buttonStyle(.borderedProminent)
        .keyboardShortcut(.space, modifiers: [])

        Button(action: viewModel.skipBackward) {
          Image(systemName: "gobackward.10")
        }

        Button(action: viewModel.skipForward) {
          Image(systemName: "goforward.10")
        }

        Text(formattedTime(viewModel.playbackState.currentTime))
          .font(.system(.footnote, design: .monospaced))
          .foregroundStyle(.primary)
          .frame(width: 52, alignment: .leading)

        Slider(
          value: Binding(
            get: { seekPosition },
            set: { seekPosition = $0 }
          ),
          in: seekRange,
          onEditingChanged: { editing in
            isSeeking = editing
            if !editing {
              viewModel.seek(to: seekPosition)
            }
          }
        )
        .disabled(viewModel.playbackState.duration <= 0)

        Text(formattedTime(viewModel.playbackState.duration))
          .font(.system(.footnote, design: .monospaced))
          .foregroundStyle(.primary)
          .frame(width: 52, alignment: .trailing)

        Button("Open...") {
          viewModel.openPanel()
        }

        Menu {
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
          } else {
            Button("No subtitle loaded") {
            }
            .disabled(true)
          }
        } label: {
          Label("Subtitles", systemImage: viewModel.hasSubtitleTrack ? "captions.bubble.fill" : "captions.bubble")
        }
        .labelStyle(.titleAndIcon)
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

        Spacer()

        Button(action: toggleFullscreen) {
          Image(systemName: "arrow.up.left.and.arrow.down.right")
        }
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

      Spacer(minLength: 12)

      Button("Open...") {
        viewModel.openPanel()
      }

      Menu {
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
        Image(systemName: "captions.bubble")
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

  private var backgroundLayer: some View {
    LinearGradient(
      colors: [
        Color(red: 0.07, green: 0.1, blue: 0.14),
        Color(red: 0.11, green: 0.15, blue: 0.2)
      ],
      startPoint: .topLeading,
      endPoint: .bottomTrailing
    )
    .ignoresSafeArea()
  }

  private var seekRange: ClosedRange<Double> {
    let duration = max(viewModel.playbackState.duration, 0.1)
    return 0...duration
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

  private func toggleFullscreen() {
    NSApplication.shared.keyWindow?.toggleFullScreen(nil)
  }

  private func syncFullscreenState() {
    isFullscreen = NSApplication.shared.keyWindow?.styleMask.contains(.fullScreen) ?? false
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
