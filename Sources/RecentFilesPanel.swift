import SwiftUI

private let recentRelativeDateFormatter: RelativeDateTimeFormatter = {
  let formatter = RelativeDateTimeFormatter()
  formatter.unitsStyle = .full
  return formatter
}()

private func recentRelativeDateText(for date: Date) -> String {
  "Opened \(recentRelativeDateFormatter.localizedString(for: date, relativeTo: Date()))"
}

struct RecentFilesPanel: View {
  private enum PanelTab: Hashable {
    case recent
    case archive
    case subtitles
  }

  let entries: [RecentPlaybackEntry]
  let archivedEntries: [RecentPlaybackEntry]
  let currentFilePath: String?
  let onSelect: (RecentPlaybackEntry) -> Void
  let onRemove: (RecentPlaybackEntry) -> Void
  let onRestoreArchived: (RecentPlaybackEntry) -> Void
  let onDeleteArchivedPermanently: (RecentPlaybackEntry) -> Void
  let subtitleCues: [SubtitleCue]
  let activeSubtitleCueIndex: Int?
  let activeSubtitleFileName: String?
  let onAddSubtitle: () -> Void
  let onSelectSubtitleCue: (Int) -> Void

  @State private var selectedTab: PanelTab = .recent

  var body: some View {
    VStack(alignment: .leading, spacing: DS.Spacing.lg) {
      Picker("Section", selection: $selectedTab) {
        Text("Recent").tag(PanelTab.recent)
        Text("Archive").tag(PanelTab.archive)
        Text("Subtitles").tag(PanelTab.subtitles)
      }
      .pickerStyle(.segmented)
      .labelsHidden()

      Group {
        switch selectedTab {
        case .recent:
          recentTab
        case .archive:
          archiveTab
        case .subtitles:
          subtitlesTab
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .animation(DS.Anim.snappy, value: selectedTab)
    }
    .frame(maxHeight: .infinity, alignment: .topLeading)
  }

  private var recentTab: some View {
    VStack(alignment: .leading, spacing: DS.Spacing.lg) {
      sectionHeader(title: "RECENT", count: entries.count)

      if entries.isEmpty {
        Text("No recent videos yet.")
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .padding(.top, DS.Spacing.xs)
      } else {
        ScrollView {
          LazyVStack(spacing: DS.Spacing.md) {
            ForEach(entries) { entry in
              RecentRowView(
                entry: entry,
                isCurrent: entry.filePath == currentFilePath,
                onSelect: onSelect,
                onRemove: onRemove
              )
            }
          }
          .padding(.vertical, DS.Spacing.xs)
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private var archiveTab: some View {
    VStack(alignment: .leading, spacing: DS.Spacing.lg) {
      sectionHeader(title: "ARCHIVE", count: archivedEntries.count)

      if archivedEntries.isEmpty {
        Text("No archived videos yet.")
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .padding(.top, DS.Spacing.xs)
      } else {
        ScrollView {
          LazyVStack(spacing: DS.Spacing.md) {
            ForEach(archivedEntries) { entry in
              archiveRow(for: entry)
            }
          }
          .padding(.vertical, DS.Spacing.xs)
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private var subtitlesTab: some View {
    SubtitleTimelinePanel(
      cues: subtitleCues,
      activeCueIndex: activeSubtitleCueIndex,
      activeSubtitleFileName: activeSubtitleFileName,
      onAddSubtitle: onAddSubtitle,
      onSelectCue: onSelectSubtitleCue
    )
  }

  private func sectionHeader(title: String, count: Int) -> some View {
    HStack {
      Text(title)
        .font(.system(size: 13, weight: .semibold))
        .tracking(0.5)
        .foregroundStyle(.secondary)

      Spacer()

      Text("\(count)")
        .font(.system(size: 11, weight: .medium, design: .monospaced))
        .foregroundStyle(DS.Colors.textSecondary)
        .padding(.horizontal, DS.Spacing.sm)
        .padding(.vertical, 2)
        .background(DS.Colors.surfacePrimary, in: Capsule())
    }
  }

  private func archiveRow(for entry: RecentPlaybackEntry) -> some View {
    HStack(spacing: DS.Spacing.md) {
      VStack(alignment: .leading, spacing: DS.Spacing.xs) {
        Text(entry.displayName)
          .font(.subheadline.weight(.medium))
          .lineLimit(1)

        Text(entry.progressDetailText)
          .font(.caption2)
          .foregroundStyle(.secondary)
      }

      Spacer(minLength: DS.Spacing.sm)

      actionIconButton(systemName: "arrow.uturn.backward.circle.fill", helpText: "Undo archive") {
        onRestoreArchived(entry)
      }

      actionIconButton(systemName: "trash.circle.fill", helpText: "Delete permanently") {
        onDeleteArchivedPermanently(entry)
      }
    }
    .padding(DS.Spacing.md)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: DS.Radii.card, style: .continuous)
        .fill(DS.Colors.surfacePrimary)
    )
    .help(recentRelativeDateText(for: entry.lastOpenedAt))
  }

  private func actionIconButton(systemName: String, helpText: String, action: @escaping () -> Void) -> some View {
    ActionIconButton(systemName: systemName, helpText: helpText, action: action)
  }

}

// MARK: - Recent Row

private struct RecentRowView: View {
  let entry: RecentPlaybackEntry
  let isCurrent: Bool
  let onSelect: (RecentPlaybackEntry) -> Void
  let onRemove: (RecentPlaybackEntry) -> Void

  @State private var isHovered = false

  var body: some View {
    let fill: Color = isCurrent
      ? DS.Colors.surfaceSelected
      : (isHovered ? DS.Colors.surfaceHovered : .clear)

    HStack(spacing: DS.Spacing.md) {
      Button {
        onSelect(entry)
      } label: {
        HStack(spacing: DS.Spacing.md) {
          Image(systemName: "film")
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(isCurrent ? Color.accentColor : .secondary)
            .frame(width: 32, height: 32)
            .background(
              (isCurrent ? Color.accentColor : Color.white).opacity(0.1),
              in: RoundedRectangle(cornerRadius: DS.Radii.button, style: .continuous)
            )

          VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            Text(entry.displayName)
              .font(.subheadline.weight(.medium))
              .lineLimit(1)

            if isCurrent {
              Text("NOW PLAYING")
                .font(.system(size: 10, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(Color.accentColor)
            }

            progressBar(for: entry)

            Text(entry.progressDetailText)
              .font(.caption2)
              .foregroundStyle(.secondary)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .buttonStyle(.plain)

      if isHovered && !isCurrent {
        ActionIconButton(
          systemName: "archivebox.fill",
          helpText: "Move to archive"
        ) {
          onRemove(entry)
        }
        .transition(.opacity)
      }
    }
    .padding(DS.Spacing.md)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: DS.Radii.card, style: .continuous)
        .fill(fill)
    )
    .overlay {
      if isCurrent {
        RoundedRectangle(cornerRadius: DS.Radii.card, style: .continuous)
          .stroke(Color.accentColor.opacity(0.3), lineWidth: DS.hairline)
      }
    }
    .onHover { hovering in
      withAnimation(DS.Anim.snappy) {
        isHovered = hovering
      }
    }
    .help(recentRelativeDateText(for: entry.lastOpenedAt))
  }

  private func progressBar(for entry: RecentPlaybackEntry) -> some View {
    GeometryReader { geometry in
      let width = max(geometry.size.width, 1)
      let filledWidth = max(width * entry.progress, 2)

      ZStack(alignment: .leading) {
        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
          .fill(DS.Colors.seekTrack)

        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
          .fill(isCurrent ? Color.accentColor : DS.Colors.seekFill)
          .frame(width: filledWidth)
      }
    }
    .frame(height: 3)
  }
}

// MARK: - Action Icon Button

private struct ActionIconButton: View {
  let systemName: String
  let helpText: String
  let action: () -> Void

  @State private var isHovered = false

  var body: some View {
    Button(action: action) {
      Image(systemName: systemName)
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(isHovered ? Color.primary : .secondary)
        .frame(width: 32, height: 32)
        .background(
          isHovered ? DS.Colors.surfaceHovered : .clear,
          in: RoundedRectangle(cornerRadius: DS.Radii.button, style: .continuous)
        )
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .help(helpText)
    .onHover { hovering in
      isHovered = hovering
    }
  }
}
