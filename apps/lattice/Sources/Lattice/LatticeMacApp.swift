import AppKit
import KeyboardShortcuts
import Sparkle
import SwiftUI

@main
@MainActor
struct LatticeMacApp: App {
  @NSApplicationDelegateAdaptor(MacAppDelegate.self) private var appDelegate

  var body: some Scene {
    WindowGroup("Lattice", id: "main") {
      MacMarkdownRootView(model: appDelegate.model)
        .frame(minWidth: 640, minHeight: 420)
    }
    .defaultSize(width: 960, height: 680)
    .commands {
      MacMarkdownCommands(
        checkForUpdates: appDelegate.checkForUpdates,
        showJot: appDelegate.showJot
      )
    }

    Settings {
      MacSettingsView()
    }
  }
}

private struct MacMarkdownCommands: Commands {
  let checkForUpdates: @MainActor () -> Void
  let showJot: @MainActor () -> Void
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
      Button("Jot…") {
        showJot()
      }

      Divider()

      Button("Command Palette…") {
        showCommandPaletteAction?.perform()
      }
      .keyboardShortcut("p", modifiers: [.command, .shift])
      .disabled(showCommandPaletteAction?.isEnabled != true)
    }
  }
}

@MainActor
final class MacAppDelegate: NSObject, NSApplicationDelegate {
  let model = MacMarkdownAppModel()
  private var updaterController: SPUStandardUpdaterController?
  private lazy var jotWindowController = MacJotWindowController(model: model)
  private var globalJotShortcutTask: Task<Void, Never>?

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.regular)
    globalJotShortcutTask = Task { @MainActor [weak self] in
      for await _ in KeyboardShortcuts.events(.keyDown, for: .showJot) {
        self?.showJotFromGlobalShortcut()
      }
    }

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

  func applicationWillTerminate(_ notification: Notification) {
    globalJotShortcutTask?.cancel()
  }

  func showJot() {
    jotWindowController.present(restoringPreviousApplicationOnDismiss: false)
  }

  private func showJotFromGlobalShortcut() {
    jotWindowController.present(restoringPreviousApplicationOnDismiss: true)
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
