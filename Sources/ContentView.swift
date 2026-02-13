import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
  @StateObject private var viewModel = PlayerViewModel()

  @State private var isDropTargeted = false
  @State private var seekPosition: Double = 0
  @State private var isSeeking = false

  var body: some View {
    VStack(spacing: 0) {
      ZStack {
        PlaybackEngineView(engine: viewModel.engine)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .background(Color.black)

        if viewModel.currentURL == nil {
          emptyStateView
        }
      }
      .overlay(alignment: .topLeading) {
        if isDropTargeted {
          dropIndicator
        }
      }
      .onDrop(of: [.fileURL], isTargeted: $isDropTargeted, perform: handleDrop)

      controlsView
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
    .frame(minWidth: 960, minHeight: 600)
  }

  private var emptyStateView: some View {
    VStack(spacing: 14) {
      Image(systemName: "play.square.stack.fill")
        .resizable()
        .scaledToFit()
        .frame(width: 58, height: 58)
        .foregroundStyle(.white.opacity(0.8))

      Text("JustPlay")
        .font(.title2.weight(.semibold))
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
    .padding(28)
    .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
  }

  private var controlsView: some View {
    VStack(spacing: 10) {
      HStack(spacing: 10) {
        Button(action: viewModel.togglePlayPause) {
          Image(systemName: viewModel.playbackState.isPlaying ? "pause.fill" : "play.fill")
        }
        .keyboardShortcut(.space, modifiers: [])

        Button(action: viewModel.skipBackward) {
          Image(systemName: "gobackward.10")
        }

        Button(action: viewModel.skipForward) {
          Image(systemName: "goforward.10")
        }

        Text(formattedTime(viewModel.playbackState.currentTime))
          .font(.system(.footnote, design: .monospaced))
          .foregroundStyle(.secondary)
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
          .foregroundStyle(.secondary)
          .frame(width: 52, alignment: .trailing)

        Button("Open...") {
          viewModel.openPanel()
        }
      }

      HStack(spacing: 10) {
        Image(systemName: "speaker.wave.2")
          .foregroundStyle(.secondary)

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
        .frame(width: 250)

        Spacer()

        Button(action: toggleFullscreen) {
          Image(systemName: "arrow.up.left.and.arrow.down.right")
        }
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
    .background(.ultraThinMaterial)
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
}
