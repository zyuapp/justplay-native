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
  let onAddSubtitle: () -> Void
  let onSelectCue: (Int) -> Void

  @State private var searchQuery = ""

  var body: some View {
    ScrollViewReader { proxy in
      VStack(alignment: .leading, spacing: DS.Spacing.lg) {
        header(using: proxy)

        if cues.isEmpty {
          Text("No subtitle lines available.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.top, DS.Spacing.xs)
        } else if displayedCues.isEmpty {
          Text("No matching subtitle lines.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.top, DS.Spacing.xs)
        } else {
          ScrollView {
            LazyVStack(spacing: DS.Spacing.sm) {
              ForEach(displayedCues) { displayedCue in
                SubtitleCueRow(
                  cue: displayedCue.cue,
                  index: displayedCue.id,
                  isActive: displayedCue.id == activeCueIndex,
                  onSelect: onSelectCue
                )
                .id(displayedCue.id)
              }
            }
            .padding(.vertical, DS.Spacing.xs)
          }
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
  }

  private func header(using proxy: ScrollViewProxy) -> some View {
    VStack(alignment: .leading, spacing: DS.Spacing.sm) {
      HStack(spacing: DS.Spacing.md) {
        Text("SUBTITLES")
          .font(.system(size: 13, weight: .semibold))
          .tracking(0.5)
          .foregroundStyle(.secondary)

        Spacer(minLength: DS.Spacing.md)

        Button {
          onAddSubtitle()
        } label: {
          Image(systemName: "plus")
            .font(.system(size: 12, weight: .semibold))
        }
        .buttonStyle(.borderless)
        .controlSize(.small)

        Button {
          jumpToCurrentCue(using: proxy)
        } label: {
          Image(systemName: "scope")
            .font(.system(size: 12, weight: .semibold))
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .disabled(activeCueIndex == nil)
      }

      if let activeSubtitleFileName {
        Text(activeSubtitleFileName)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }

      TextField("Search subtitle lines", text: $searchQuery)
        .textFieldStyle(.plain)
        .font(.subheadline)
        .padding(.horizontal, DS.Spacing.md)
        .padding(.vertical, DS.Spacing.sm)
        .background(DS.Colors.surfacePrimary, in: RoundedRectangle(cornerRadius: DS.Radii.button, style: .continuous))
        .overlay {
          RoundedRectangle(cornerRadius: DS.Radii.button, style: .continuous)
            .stroke(DS.Colors.borderSubtle, lineWidth: DS.hairline)
        }
    }
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
      Task { @MainActor in
        withAnimation(DS.Anim.gentle) {
          proxy.scrollTo(activeCueIndex, anchor: .center)
        }
      }
      return
    }

    withAnimation(DS.Anim.gentle) {
      proxy.scrollTo(activeCueIndex, anchor: .center)
    }
  }

}

private struct SubtitleCueRow: View {
  let cue: SubtitleCue
  let index: Int
  let isActive: Bool
  let onSelect: (Int) -> Void

  @State private var isHovered = false

  var body: some View {
    let fill: Color = isActive
      ? DS.Colors.surfaceSelected
      : (isHovered ? DS.Colors.surfaceHovered : .clear)

    Button {
      onSelect(index)
    } label: {
      HStack(alignment: .top, spacing: DS.Spacing.md) {
        Text(cue.start.playbackText)
          .font(.system(size: 11, weight: .medium, design: .monospaced))
          .foregroundStyle(isActive ? Color.accentColor : DS.Colors.textSecondary)
          .frame(width: 44, alignment: .leading)

        Text("\u{00B7}")
          .foregroundStyle(DS.Colors.textTertiary)

        SubtitleTextRenderer.render(cue.text)
          .font(.subheadline.weight(isActive ? .semibold : .regular))
          .multilineTextAlignment(.leading)
          .lineLimit(nil)
          .foregroundStyle(.primary)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .padding(.horizontal, DS.Spacing.md)
      .padding(.vertical, DS.Spacing.sm)
      .background(
        RoundedRectangle(cornerRadius: DS.Radii.button, style: .continuous)
          .fill(fill)
      )
    }
    .buttonStyle(.plain)
    .onHover { hovering in
      isHovered = hovering
    }
  }
}
