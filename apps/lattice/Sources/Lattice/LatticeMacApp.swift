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
  @Environment(\.scenePhase) private var scenePhase
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
          identifier: Self.mainWindowIdentifier,
          isZenModeEnabled: model.isZenModeEnabled
        ))
        .task {
          model.start()
        }
        .onChange(of: scenePhase) { _, newPhase in
          if newPhase == .active {
            model.appBecameActive()
          }
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
      CommandGroup(replacing: .sidebar) {
        Button("Toggle Sidebar") {
          appDelegate.toggleSidebar()
        }
        .keyboardShortcut("s", modifiers: [.command, .option])
      }
      CommandMenu("Editor") {
        Button("Add Attachment...") {
          showMainWindow()
          chooseImageAttachments()
        }
        .disabled(!model.hasFolder)

        Divider()

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
        id: "mac.addAttachment",
        title: "Add Attachment",
        subtitle: "Choose an image to attach to the current note",
        systemImage: "plus",
        isEnabled: model.hasFolder
      ) {
        showMainWindow()
        chooseImageAttachments()
      },
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

  private func chooseImageAttachments() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.png, .jpeg, .gif, .heic, .tiff, .webP]
    panel.allowsMultipleSelection = true
    panel.canChooseDirectories = false
    panel.canChooseFiles = true
    panel.title = "Add Attachment"
    panel.prompt = "Attach"

    if panel.runModal() == .OK {
      model.insertImageAttachmentFiles(panel.urls)
    }
  }
}

private extension LatticeMacApp {
  static let mainWindowIdentifier = "main"
}

private extension NSWindow {
  var splitViewController: NSSplitViewController? {
    contentViewController?.firstDescendant(of: NSSplitViewController.self)
      ?? contentView?.firstDescendant(of: NSSplitView.self)?.owningSplitViewController
  }

  var sidebarToggleButton: NSButton? {
    contentView?.superview?.firstDescendant(of: NSButton.self) { button in
      let label = button.accessibilityLabel() ?? button.toolTip ?? button.title
      return label == "Show Sidebar" || label == "Hide Sidebar"
    }
  }
}

private extension NSApplication {
  var activeWindow: NSWindow? {
    keyWindow ?? mainWindow ?? windows.first(where: { $0.isVisible })
  }
}

private extension NSViewController {
  func firstDescendant<T: NSViewController>(of type: T.Type) -> T? {
    if let match = self as? T {
      return match
    }
    for child in children {
      if let match = child.firstDescendant(of: type) {
        return match
      }
    }
    return nil
  }
}

private extension NSView {
  func firstDescendant<T: NSView>(of type: T.Type) -> T? {
    if let match = self as? T {
      return match
    }
    for subview in subviews {
      if let match = subview.firstDescendant(of: type) {
        return match
      }
    }
    return nil
  }

  func firstDescendant<T: NSView>(of type: T.Type, where predicate: (T) -> Bool) -> T? {
    if let match = self as? T, predicate(match) {
      return match
    }
    for subview in subviews {
      if let match = subview.firstDescendant(of: type, where: predicate) {
        return match
      }
    }
    return nil
  }
}

private extension NSSplitView {
  var owningSplitViewController: NSSplitViewController? {
    var responder: NSResponder? = nextResponder
    while let currentResponder = responder {
      if let splitViewController = currentResponder as? NSSplitViewController {
        return splitViewController
      }
      responder = currentResponder.nextResponder
    }
    return nil
  }
}

private struct WindowConfiguration: NSViewRepresentable {
  let width: CGFloat
  let height: CGFloat
  let identifier: String
  let isZenModeEnabled: Bool

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
      guard let window = view.window else {
        return
      }
      window.identifier = NSUserInterfaceItemIdentifier(identifier)
      window.minSize = size
      window.contentMinSize = size
      window.titleVisibility = isZenModeEnabled ? .hidden : .visible
      window.titlebarAppearsTransparent = isZenModeEnabled
      window.standardWindowButton(.closeButton)?.isHidden = isZenModeEnabled
      window.standardWindowButton(.miniaturizeButton)?.isHidden = isZenModeEnabled
      window.standardWindowButton(.zoomButton)?.isHidden = isZenModeEnabled
      if isZenModeEnabled {
        window.styleMask.insert(.fullSizeContentView)
        window.toolbar?.isVisible = false
      } else {
        window.styleMask.remove(.fullSizeContentView)
        window.toolbar?.isVisible = true
      }
    }
  }
}

@MainActor
final class MacAppDelegate: NSObject, NSApplicationDelegate {
  private var updaterController: SPUStandardUpdaterController?
  private var sidebarShortcutMonitor: Any?

  var canCheckForUpdates: Bool {
    updaterController != nil
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    resetStaleSidebarPersistenceIfNeeded()

    sidebarShortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard Self.isToggleSidebarShortcut(event) else {
        return event
      }
      self?.toggleSidebar()
      return nil
    }

    configureUpdater()
    NSApp.setActivationPolicy(.regular)
  }

  func applicationWillTerminate(_ notification: Notification) {
    if let sidebarShortcutMonitor {
      NSEvent.removeMonitor(sidebarShortcutMonitor)
    }
    NSApp.sendAction(#selector(NSResponder.cancelOperation(_:)), to: nil, from: nil)
  }

  func checkForUpdates() {
    updaterController?.checkForUpdates(nil)
  }

  func toggleSidebar() {
    if let toggleSidebarItem = NSApp.activeWindow?.toolbar?.items.first(where: { $0.itemIdentifier == .toggleSidebar }),
       let button = toggleSidebarItem.view as? NSButton {
      button.performClick(nil)
      return
    }
    if let button = NSApp.activeWindow?.sidebarToggleButton {
      button.performClick(nil)
      return
    }
    if let splitViewController = NSApp.activeWindow?.splitViewController {
      splitViewController.toggleSidebar(nil)
      return
    }
    NSApp.sendAction(#selector(NSSplitViewController.toggleSidebar(_:)), to: nil, from: nil)
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

  private func resetStaleSidebarPersistenceIfNeeded() {
    let key = "didResetSidebarPersistenceForNativeToggle"
    let defaults = UserDefaults.standard
    guard !defaults.bool(forKey: key) else {
      return
    }

    for defaultsKey in defaults.dictionaryRepresentation().keys
      where defaultsKey.hasPrefix("NSSplitView Subview Frames")
        && defaultsKey.contains("SidebarNavigationSplitView") {
      defaults.removeObject(forKey: defaultsKey)
    }
    defaults.set(true, forKey: key)
  }

  private static func isToggleSidebarShortcut(_ event: NSEvent) -> Bool {
    guard event.charactersIgnoringModifiers?.lowercased() == "s" else {
      return false
    }
    let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    return modifiers.contains(.command)
      && modifiers.contains(.option)
      && !modifiers.contains(.shift)
      && !modifiers.contains(.control)
  }
}
