import Foundation
import SwiftUI

struct SubtitleTimelinePanel: View {
  private struct DisplayedCue: Identifiable {
    let id: Int
    let cue: SubtitleCue
  }

  let cues: [SubtitleCue]
  let activeCueIndex: Int?
  let activeSubtitleFileName: String?
  let onSelectCue: (Int) -> Void

  @State private var searchQuery = ""

  var body: some View {
    ScrollViewReader { proxy in
      VStack(alignment: .leading, spacing: 14) {
        header(using: proxy)

        if cues.isEmpty {
          Text("No subtitle lines available.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.top, 4)
        } else if displayedCues.isEmpty {
          Text("No matching subtitle lines.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.top, 4)
        } else {
          ScrollView {
            LazyVStack(spacing: 10) {
              ForEach(displayedCues) { displayedCue in
                cueRow(cue: displayedCue.cue, index: displayedCue.id)
                  .id(displayedCue.id)
              }
            }
            .padding(.vertical, 4)
          }
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
  }

  private func header(using proxy: ScrollViewProxy) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 8) {
        Text("Subtitles")
          .font(.title3.weight(.semibold))

        Spacer(minLength: 8)

        Button {
          jumpToCurrentCue(using: proxy)
        } label: {
          Image(systemName: "scope")
            .font(.system(size: 13, weight: .semibold))
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .help("Jump to current subtitle")
        .disabled(activeCueIndex == nil)
      }

      if let activeSubtitleFileName {
        Text(activeSubtitleFileName)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }

      TextField("Search subtitle lines", text: $searchQuery)
        .textFieldStyle(.roundedBorder)
        .font(.subheadline)
    }
  }

  private func cueRow(cue: SubtitleCue, index: Int) -> some View {
    let isActive = index == activeCueIndex
    let cardFill: Color = isActive ? Color.accentColor.opacity(0.2) : Color.white.opacity(0.06)
    let cardStroke: Color = isActive ? Color.accentColor.opacity(0.45) : Color.white.opacity(0.07)

    return Button {
      onSelectCue(index)
    } label: {
      VStack(alignment: .leading, spacing: 6) {
        Text(cue.start.playbackText)
          .font(.system(.caption, design: .monospaced).weight(.semibold))
          .foregroundStyle(isActive ? Color.accentColor : .secondary)

        SubtitleTextRenderer.render(cue.text)
          .font(.subheadline.weight(isActive ? .semibold : .regular))
          .multilineTextAlignment(.leading)
          .lineLimit(nil)
          .foregroundStyle(.primary)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(10)
      .background(
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .fill(cardFill)
      )
      .overlay {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .stroke(cardStroke, lineWidth: 1)
      }
    }
    .buttonStyle(.plain)
  }

  private var displayedCues: [DisplayedCue] {
    let indexedCues = cues.enumerated().map { index, cue in
      DisplayedCue(id: index, cue: cue)
    }

    let normalizedQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedQuery.isEmpty else {
      return indexedCues
    }

    return indexedCues.filter { displayedCue in
      let plainText = SubtitleTextRenderer.plainText(displayedCue.cue.text)
        .trimmingCharacters(in: .whitespacesAndNewlines)
      return plainText.localizedCaseInsensitiveContains(normalizedQuery)
    }
  }

  private func jumpToCurrentCue(using proxy: ScrollViewProxy) {
    guard let activeCueIndex else {
      return
    }

    if !displayedCues.contains(where: { $0.id == activeCueIndex }) {
      searchQuery = ""
      DispatchQueue.main.async {
        withAnimation(.easeInOut(duration: 0.22)) {
          proxy.scrollTo(activeCueIndex, anchor: .center)
        }
      }
      return
    }

    withAnimation(.easeInOut(duration: 0.22)) {
      proxy.scrollTo(activeCueIndex, anchor: .center)
    }
  }
}
