import Foundation

enum AppOpenBus {
  static let didRequestOpenURLs = Notification.Name("justplay.didRequestOpenURLs")

  private static let urlsUserInfoKey = "urls"

  static func post(urls: [URL]) {
    guard !urls.isEmpty else { return }
    NotificationCenter.default.post(
      name: didRequestOpenURLs,
      object: nil,
      userInfo: [urlsUserInfoKey: urls]
    )
  }

  static func urls(from notification: Notification) -> [URL] {
    notification.userInfo?[urlsUserInfoKey] as? [URL] ?? []
  }
}
