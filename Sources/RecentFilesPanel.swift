import SwiftUI

struct RecentFilesPanel: View {
  private enum PanelTab: Hashable {
    case recent
    case archive
  }

  let entries: [RecentPlaybackEntry]
  let archivedEntries: [RecentPlaybackEntry]
  let currentFilePath: String?
  let onSelect: (RecentPlaybackEntry) -> Void
  let onRemove: (RecentPlaybackEntry) -> Void
  let onRestoreArchived: (RecentPlaybackEntry) -> Void
  let onDeleteArchivedPermanently: (RecentPlaybackEntry) -> Void

  @State private var selectedTab: PanelTab = .recent

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Picker("Section", selection: $selectedTab) {
        Text("Recent").tag(PanelTab.recent)
        Text("Archive").tag(PanelTab.archive)
      }
      .pickerStyle(.segmented)
      .labelsHidden()

      Group {
        switch selectedTab {
        case .recent:
          recentTab
        case .archive:
          archiveTab
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    .frame(maxHeight: .infinity, alignment: .topLeading)
  }

  private var recentTab: some View {
    VStack(alignment: .leading, spacing: 14) {
      sectionHeader(title: "Recent", count: entries.count)

      if entries.isEmpty {
        Text("No recent videos yet.")
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .padding(.top, 4)
      } else {
        ScrollView {
          LazyVStack(spacing: 10) {
            ForEach(entries) { entry in
              recentRow(for: entry)
            }
          }
          .padding(.vertical, 4)
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private var archiveTab: some View {
    VStack(alignment: .leading, spacing: 14) {
      sectionHeader(title: "Archive", count: archivedEntries.count)

      if archivedEntries.isEmpty {
        Text("No archived videos yet.")
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .padding(.top, 4)
      } else {
        ScrollView {
          LazyVStack(spacing: 10) {
            ForEach(archivedEntries) { entry in
              archiveRow(for: entry)
            }
          }
          .padding(.vertical, 4)
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private func sectionHeader(title: String, count: Int) -> some View {
    HStack {
      Text(title)
        .font(.title3.weight(.semibold))

      Spacer()

      Text("\(count)")
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(.white.opacity(0.08), in: Capsule())
    }
  }

  private func recentRow(for entry: RecentPlaybackEntry) -> some View {
    let isCurrent = entry.filePath == currentFilePath
    let iconColor: Color = isCurrent ? .accentColor : .secondary
    let cardFill: Color = isCurrent ? Color.accentColor.opacity(0.2) : Color.white.opacity(0.06)
    let cardStroke: Color = isCurrent ? Color.accentColor.opacity(0.45) : Color.white.opacity(0.07)

    return HStack(spacing: 10) {
      Button {
        onSelect(entry)
      } label: {
        HStack(spacing: 10) {
          Image(systemName: "film")
            .font(.headline)
            .frame(width: 28, height: 28)
            .foregroundStyle(iconColor)

          VStack(alignment: .leading, spacing: 4) {
            Text(entry.displayName)
              .font(.subheadline.weight(.medium))
              .lineLimit(1)

            if isCurrent {
              Text("Now Playing")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color.accentColor)
            }

            Text(relativeDateText(for: entry.lastOpenedAt))
              .font(.caption)
              .foregroundStyle(.secondary)

            ProgressView(value: entry.progress)
              .progressViewStyle(.linear)

            Text(progressDetail(for: entry))
              .font(.caption2)
              .foregroundStyle(.secondary)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .buttonStyle(.plain)

      actionIconButton(
        systemName: "archivebox.fill",
        helpText: isCurrent ? "Cannot archive the currently playing video" : "Move to archive"
      ) {
        onRemove(entry)
      }
      .disabled(isCurrent)
    }
    .padding(10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .fill(cardFill)
    )
    .overlay {
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .stroke(cardStroke, lineWidth: 1)
    }
  }

  private func archiveRow(for entry: RecentPlaybackEntry) -> some View {
    HStack(spacing: 10) {
      VStack(alignment: .leading, spacing: 4) {
        Text(entry.displayName)
          .font(.subheadline.weight(.medium))
          .lineLimit(1)

        Text(relativeDateText(for: entry.lastOpenedAt))
          .font(.caption)
          .foregroundStyle(.secondary)

        Text(progressDetail(for: entry))
          .font(.caption2)
          .foregroundStyle(.secondary)
      }

      Spacer(minLength: 6)

      actionIconButton(systemName: "arrow.uturn.backward.circle.fill", helpText: "Undo archive") {
        onRestoreArchived(entry)
      }

      actionIconButton(systemName: "trash.circle.fill", helpText: "Delete permanently") {
        onDeleteArchivedPermanently(entry)
      }
    }
    .padding(10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .fill(Color.white.opacity(0.06))
    )
    .overlay {
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .stroke(Color.white.opacity(0.07), lineWidth: 1)
    }
  }

  private func progressDetail(for entry: RecentPlaybackEntry) -> String {
    if entry.lastPlaybackPosition <= 0 {
      return "Start from beginning"
    }

    let resumeText = formattedTime(entry.lastPlaybackPosition)
    if entry.duration > 0 {
      let durationText = formattedTime(entry.duration)
      return "Resume at \(resumeText) of \(durationText)"
    }

    return "Resume at \(resumeText)"
  }

  private func actionIconButton(systemName: String, helpText: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: systemName)
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(.secondary)
        .frame(width: 36, height: 36)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .help(helpText)
  }

  private func relativeDateText(for date: Date) -> String {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .full
    return "Opened \(formatter.localizedString(for: date, relativeTo: Date()))"
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
