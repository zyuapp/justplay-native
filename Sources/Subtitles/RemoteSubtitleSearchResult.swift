import Foundation

struct RemoteSubtitleSearchResult: Identifiable, Hashable {
  let id: Int
  let fileID: Int
  let fileName: String
  let languageCode: String
  let languageName: String?
  let release: String?
  let title: String?
}
