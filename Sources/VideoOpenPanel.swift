import AppKit
import UniformTypeIdentifiers

enum VideoOpenPanel {
  static func present() {
    if Thread.isMainThread {
      presentOnMainThread()
      return
    }

    DispatchQueue.main.async {
      presentOnMainThread()
    }
  }

  private static func presentOnMainThread() {
    let panel = NSOpenPanel()
    panel.title = "Open Video"
    panel.prompt = "Open"
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false
    panel.canChooseFiles = true
    panel.allowedContentTypes = allowedContentTypes()

    guard panel.runModal() == .OK, let url = panel.url else { return }
    AppOpenBus.post(urls: [url])
  }

  private static func allowedContentTypes() -> [UTType] {
    var contentTypes: [UTType] = [.mpeg4Movie]
    if let matroskaType = UTType(filenameExtension: "mkv") {
      contentTypes.append(matroskaType)
    }
    return contentTypes
  }
}
