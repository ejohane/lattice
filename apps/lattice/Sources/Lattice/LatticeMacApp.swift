import AppKit
import Sparkle
import SwiftUI

@main
struct LatticeMacApp: App {
  @NSApplicationDelegateAdaptor(MacAppDelegate.self) private var appDelegate

  var body: some Scene {
    WindowGroup("Lattice", id: "main") {
      MacMarkdownRootView()
        .frame(minWidth: 640, minHeight: 420)
    }
    .defaultSize(width: 960, height: 680)
  }
}

@MainActor
private final class MacAppDelegate: NSObject, NSApplicationDelegate {
  private var updaterController: SPUStandardUpdaterController?

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.regular)

    guard
      let feedURL = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
      !feedURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
      return
    }

    updaterController = SPUStandardUpdaterController(
      startingUpdater: true,
      updaterDelegate: nil,
      userDriverDelegate: nil
    )
  }
}
