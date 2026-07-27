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
    .commands {
      MacMarkdownCommands {
        appDelegate.checkForUpdates()
      }
    }
  }
}

private struct MacMarkdownCommands: Commands {
  let checkForUpdates: @MainActor () -> Void
  @FocusedValue(\.macMarkdownNewNoteAction) private var newNoteAction
  @FocusedValue(\.macMarkdownShowCommandPaletteAction)
  private var showCommandPaletteAction

  var body: some Commands {
    CommandGroup(after: .appInfo) {
      Button("Check for Updates…") {
        checkForUpdates()
      }
    }

    CommandGroup(replacing: .newItem) {
      Button("New Note") {
        newNoteAction?.perform()
      }
      .keyboardShortcut("n", modifiers: .command)
      .disabled(newNoteAction?.isEnabled != true)
    }

    CommandMenu("Commands") {
      Button("Command Palette…") {
        showCommandPaletteAction?.perform()
      }
      .keyboardShortcut("p", modifiers: [.command, .shift])
      .disabled(showCommandPaletteAction?.isEnabled != true)
    }
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

  func checkForUpdates() {
    guard let updaterController else {
      let alert = NSAlert()
      alert.messageText = "Updates are unavailable in this build"
      alert.informativeText = "Install a released build of Lattice to check for updates."
      alert.alertStyle = .informational
      alert.runModal()
      return
    }

    updaterController.checkForUpdates(nil)
  }
}
