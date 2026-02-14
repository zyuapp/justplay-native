import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
  func application(_ application: NSApplication, open urls: [URL]) {
    AppOpenBus.post(urls: urls)
  }
}

@main
struct JustPlayNativeApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

  var body: some Scene {
    WindowGroup {
      ContentView()
    }
    .windowStyle(.hiddenTitleBar)
    .commands {
      CommandGroup(after: .newItem) {
        Button("Open...") {
          VideoOpenPanel.present()
        }
        .keyboardShortcut("o", modifiers: [.command])
      }
    }
  }
}
