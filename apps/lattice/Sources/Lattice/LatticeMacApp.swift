import AppKit
import LatticeShared
import Sparkle
import SwiftUI

@main
struct LatticeMacApp: App {
  @NSApplicationDelegateAdaptor(MacAppDelegate.self) private var appDelegate
  @Environment(\.openWindow) private var openWindow
  @State private var model = LatticeAppModel()

  var body: some Scene {
    WindowGroup(id: "main") {
      LatticeRootView(model: model)
        .frame(minWidth: 760, minHeight: 520)
        .task {
          model.start()
        }
    }
    .commands {
      CommandGroup(replacing: .newItem) {
        Button("New Note") {
          showMainWindow()
          model.createNewNote()
        }
        .keyboardShortcut("n", modifiers: [.command])
      }
      CommandMenu("Lattice") {
        Button("Choose Notes Folder...") {
          showMainWindow()
          model.showFolderImporter()
        }
        if appDelegate.canCheckForUpdates {
          Button("Check for Updates...") {
            appDelegate.checkForUpdates()
          }
        }
      }
      CommandMenu("Editor") {
        Button("Increase Font Size") {
          model.increaseEditorFontSize()
        }
        .keyboardShortcut("+", modifiers: [.command])
        .disabled(!model.canIncreaseEditorFontSize)

        Button("Decrease Font Size") {
          model.decreaseEditorFontSize()
        }
        .keyboardShortcut("-", modifiers: [.command])
        .disabled(!model.canDecreaseEditorFontSize)

        Button("Reset Font Size") {
          model.resetEditorFontSize()
        }
        .keyboardShortcut("0", modifiers: [.command])
      }
    }

    MenuBarExtra("Lattice", systemImage: "square.and.pencil") {
      Button("Show Lattice") {
        showMainWindow()
      }
      Button("New Note") {
        showMainWindow()
        model.createNewNote()
      }
      .keyboardShortcut("n", modifiers: [.command])
      Divider()
      Button("Choose Notes Folder...") {
        showMainWindow()
        model.showFolderImporter()
      }
      if let folderURL = model.folderURL {
        Button("Open Notes Folder") {
          NSWorkspace.shared.open(folderURL)
        }
      }
      if let noteURL = model.selectedNote?.url {
        Button("Reveal Current Note") {
          NSWorkspace.shared.activateFileViewerSelecting([noteURL])
        }
      }
      if appDelegate.canCheckForUpdates {
        Divider()
        Button("Check for Updates...") {
          appDelegate.checkForUpdates()
        }
      }
      Divider()
      Button("Quit Lattice") {
        model.flushAutosave()
        NSApp.terminate(nil)
      }
      .keyboardShortcut("q", modifiers: [.command])
    }
  }

  private func showMainWindow() {
    openWindow(id: "main")
    NSApp.activate(ignoringOtherApps: true)
  }
}

@MainActor
final class MacAppDelegate: NSObject, NSApplicationDelegate {
  private var updaterController: SPUStandardUpdaterController?

  var canCheckForUpdates: Bool {
    updaterController != nil
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    configureUpdater()
    NSApp.setActivationPolicy(.regular)
  }

  func applicationWillTerminate(_ notification: Notification) {
    NSApp.sendAction(#selector(NSResponder.cancelOperation(_:)), to: nil, from: nil)
  }

  func checkForUpdates() {
    updaterController?.checkForUpdates(nil)
  }

  private func configureUpdater() {
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
