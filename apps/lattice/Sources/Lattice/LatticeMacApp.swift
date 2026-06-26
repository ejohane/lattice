import AppKit
import LatticeShared
import Sparkle
import SwiftUI

@main
struct LatticeMacApp: App {
  private static let minimumWindowWidth: CGFloat = 420
  private static let minimumWindowHeight: CGFloat = 280

  @NSApplicationDelegateAdaptor(MacAppDelegate.self) private var appDelegate
  @Environment(\.openWindow) private var openWindow
  @State private var model = LatticeAppModel()

  var body: some Scene {
    WindowGroup(id: "main") {
      LatticeRootView(
        model: model,
        commandPalettePlatformCommands: { commandPalettePlatformCommands }
      )
        .frame(minWidth: Self.minimumWindowWidth, minHeight: Self.minimumWindowHeight)
        .background(WindowConfiguration(
          width: Self.minimumWindowWidth,
          height: Self.minimumWindowHeight,
          identifier: Self.mainWindowIdentifier
        ))
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
      CommandGroup(replacing: .pasteboard) {
        Button("Cut") {
          NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil)
        }
        .keyboardShortcut("x", modifiers: [.command])

        Button("Copy") {
          NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil)
        }
        .keyboardShortcut("c", modifiers: [.command])

        Button("Paste") {
          NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)
        }
        .keyboardShortcut("v", modifiers: [.command])

        Button("Select All") {
          NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
        }
        .keyboardShortcut("a", modifiers: [.command])
      }
      CommandMenu("Lattice") {
        Button("Settings...") {
          showMainWindow()
          model.showSettings()
        }
        .keyboardShortcut(",", modifiers: [.command])

        Divider()

        Button("Command Palette...") {
          showMainWindow()
          model.showCommandPalette()
        }
        .keyboardShortcut("p", modifiers: [.command, .shift])

        Divider()

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
      CommandMenu("Navigate") {
        Button("Back") {
          model.navigateBack()
        }
        .keyboardShortcut("[", modifiers: [.command])
        .disabled(!model.canNavigateBack)

        Button("Forward") {
          model.navigateForward()
        }
        .keyboardShortcut("]", modifiers: [.command])
        .disabled(!model.canNavigateForward)
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
      Button("Settings...") {
        showMainWindow()
        model.showSettings()
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
    if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == Self.mainWindowIdentifier }) {
      window.makeKeyAndOrderFront(nil)
    } else {
      openWindow(id: "main")
    }
    NSApp.activate(ignoringOtherApps: true)
  }

  private var commandPalettePlatformCommands: [CommandPaletteCommand] {
    [
      CommandPaletteCommand(
        id: "mac.checkForUpdates",
        title: "Check for Updates",
        subtitle: appDelegate.canCheckForUpdates
          ? "Look for a newer Lattice release"
          : "Available in release builds",
        systemImage: "arrow.triangle.2.circlepath",
        isSetupSafe: true
      ) {
        if appDelegate.canCheckForUpdates {
          appDelegate.checkForUpdates()
        } else {
          model.errorMessage = "Update checking is available in release builds."
        }
      }
    ]
  }
}

private extension LatticeMacApp {
  static let mainWindowIdentifier = "main"
}

private struct WindowConfiguration: NSViewRepresentable {
  let width: CGFloat
  let height: CGFloat
  let identifier: String

  func makeNSView(context: Context) -> NSView {
    let view = NSView()
    updateWindow(for: view)
    return view
  }

  func updateNSView(_ nsView: NSView, context: Context) {
    updateWindow(for: nsView)
  }

  private func updateWindow(for view: NSView) {
    DispatchQueue.main.async {
      let size = NSSize(width: width, height: height)
      view.window?.identifier = NSUserInterfaceItemIdentifier(identifier)
      view.window?.minSize = size
      view.window?.contentMinSize = size
    }
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
