import SwiftUI

struct SubtitleSearchPanel: View {
  @Binding var apiKey: String
  @Binding var query: String
  let isConfigured: Bool
  let hasSubtitleTrack: Bool
  let subtitlesEnabled: Bool
  let isLoading: Bool
  let statusMessage: String?
  let results: [RemoteSubtitleSearchResult]
  let activeDownloadID: Int?
  let onSaveAPIKey: () -> Void
  let onAddSubtitle: () -> Void
  let onToggleSubtitles: () -> Void
  let onRemoveSubtitle: () -> Void
  let onUseCurrentFileName: () -> Void
  let onSearch: () -> Void
  let onDownload: (RemoteSubtitleSearchResult) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        Text("Subtitle Search")
          .font(.title3.weight(.semibold))

        Spacer()

        if isLoading {
          ProgressView()
            .controlSize(.small)
        }
      }

      VStack(alignment: .leading, spacing: 8) {
        Text("OpenSubtitles API Key")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)

        HStack(spacing: 8) {
          TextField("Enter API key", text: $apiKey)
            .textFieldStyle(.roundedBorder)

          Button("Save") {
            onSaveAPIKey()
          }
          .buttonStyle(.borderedProminent)
        }
      }

      HStack(spacing: 8) {
        Button("Add Subtitle...") {
          onAddSubtitle()
        }

        if hasSubtitleTrack {
          Button(subtitlesEnabled ? "Hide Subtitles" : "Show Subtitles") {
            onToggleSubtitles()
          }

          Button("Remove Subtitle") {
            onRemoveSubtitle()
          }
        }
      }

      TextField("Search by video title", text: $query)
        .textFieldStyle(.roundedBorder)
        .disabled(!isConfigured || isLoading)

      HStack(spacing: 8) {
        Button("Use File Name") {
          onUseCurrentFileName()
        }
        .disabled(!isConfigured || isLoading)

        Button("Search") {
          onSearch()
        }
        .buttonStyle(.borderedProminent)
        .disabled(!isConfigured || isLoading)
      }

      if let statusMessage, !statusMessage.isEmpty {
        Text(statusMessage)
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      if results.isEmpty {
        Text("No subtitle results")
          .font(.caption)
          .foregroundStyle(.secondary)
          .padding(.top, 2)
      } else {
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 8) {
            ForEach(results) { result in
              subtitleRow(for: result)
            }
          }
          .padding(.vertical, 2)
        }
        .frame(maxHeight: 240)
      }
    }
    .padding(16)
    .frame(minWidth: 700, minHeight: 420)
  }

  private func subtitleRow(for result: RemoteSubtitleSearchResult) -> some View {
    HStack(alignment: .top, spacing: 10) {
      VStack(alignment: .leading, spacing: 2) {
        Text(result.title ?? result.fileName)
          .font(.subheadline.weight(.medium))
          .lineLimit(1)

        Text(result.fileName)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)

        Text(result.languageName ?? result.languageCode.uppercased())
          .font(.caption2)
          .foregroundStyle(.secondary)
          .lineLimit(1)

        if let release = result.release, !release.isEmpty {
          Text(release)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
      }

      Spacer(minLength: 8)

      Button(activeDownloadID == result.id ? "Downloading..." : "Download") {
        onDownload(result)
      }
      .buttonStyle(.bordered)
      .disabled(activeDownloadID != nil)
    }
    .padding(8)
    .background(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .fill(Color.white.opacity(0.06))
    )
    .overlay {
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .stroke(Color.white.opacity(0.08), lineWidth: 1)
    }
  }
}
