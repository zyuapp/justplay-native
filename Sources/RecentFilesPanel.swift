import SwiftUI

struct RecentFilesPanel: View {
  let entries: [RecentPlaybackEntry]
  let currentFilePath: String?
  let onSelect: (RecentPlaybackEntry) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Recent")
        .font(.title3.weight(.semibold))

      if entries.isEmpty {
        Text("No recent videos yet.")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      } else {
        ScrollView {
          LazyVStack(spacing: 8) {
            ForEach(entries) { entry in
              Button {
                onSelect(entry)
              } label: {
                recentRow(for: entry)
              }
              .buttonStyle(.plain)
            }
          }
          .padding(.vertical, 2)
        }
      }
    }
    .padding(14)
    .frame(width: 290)
    .frame(maxHeight: .infinity, alignment: .topLeading)
    .background(.regularMaterial)
  }

  @ViewBuilder
  private func recentRow(for entry: RecentPlaybackEntry) -> some View {
    let isCurrent = entry.filePath == currentFilePath

    HStack(spacing: 10) {
      Image(systemName: "film")
        .font(.headline)
        .frame(width: 28, height: 28)
        .foregroundStyle(isCurrent ? Color.accentColor : Color.secondary)

      VStack(alignment: .leading, spacing: 4) {
        Text(entry.displayName)
          .font(.subheadline.weight(.medium))
          .lineLimit(1)

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
    .padding(10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .fill(isCurrent ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.08))
    )
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
