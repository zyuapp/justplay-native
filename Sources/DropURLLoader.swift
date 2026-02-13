import Foundation
import UniformTypeIdentifiers

enum DropURLLoader {
  static func loadFirstURL(from providers: [NSItemProvider], completion: @escaping (URL?) -> Void) -> Bool {
    guard let provider = providers.first(where: {
      $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
    }) else {
      completion(nil)
      return false
    }

    provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
      let url = resolveURL(from: item)
      DispatchQueue.main.async {
        completion(url)
      }
    }

    return true
  }

  private static func resolveURL(from item: NSSecureCoding?) -> URL? {
    if let url = item as? URL {
      return url
    }

    if let nsURL = item as? NSURL {
      return nsURL as URL
    }

    if let data = item as? Data,
      let rawValue = String(data: data, encoding: .utf8)
    {
      let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
      return URL(string: trimmed)
    }

    return nil
  }
}
