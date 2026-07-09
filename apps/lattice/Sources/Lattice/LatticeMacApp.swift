import AppKit
import LatticeShared
import Observation
import Sparkle
import SwiftUI

@main
struct LatticeMacApp: App {
  private static let minimumWindowWidth: CGFloat = 420
  private static let minimumWindowHeight: CGFloat = 280
  private static let settingsWindowWidth: CGFloat = 760
  private static let settingsWindowHeight: CGFloat = 660

  @NSApplicationDelegateAdaptor(MacAppDelegate.self) private var appDelegate
  @Environment(\.openWindow) private var openWindow
  @Environment(\.openSettings) private var openSettings
  @Environment(\.scenePhase) private var scenePhase
  @State private var model = LatticeAppModel()
  @State private var updateState = MacUpdateState()

  var body: some Scene {
    WindowGroup(id: "main") {
      LatticeRootView(
        model: model,
        commandPalettePlatformCommands: { commandPalettePlatformCommands }
      )
        .toolbar {
          if updateState.isUpdateAvailable {
            ToolbarItem(placement: .primaryAction) {
              Button {
                performUpdateAction()
              } label: {
                Label(updateState.indicatorTitle, systemImage: "arrow.down.circle.fill")
              }
              .help(updateState.indicatorHelp)
              .disabled(!canPerformUpdateAction)
            }
          }
        }
        .frame(minWidth: Self.minimumWindowWidth, minHeight: Self.minimumWindowHeight)
        .background(WindowConfiguration(
          width: Self.minimumWindowWidth,
          height: Self.minimumWindowHeight,
          identifier: Self.mainWindowIdentifier,
          theme: model.theme,
          isZenModeEnabled: model.isZenModeEnabled
        ))
        .task {
          appDelegate.attachUpdateState(updateState)
          model.start()
        }
        .onChange(of: scenePhase) { _, newPhase in
          if newPhase == .active {
            model.appBecameActive()
          }
        }
        .onChange(of: model.isShowingSettings) { _, isShowingSettings in
          if isShowingSettings {
            showSettingsWindow()
            model.isShowingSettings = false
          }
        }
    }
    .commands {
      CommandGroup(after: .appInfo) {
        Button("Settings...") {
          showSettingsWindow()
        }
        .keyboardShortcut(",", modifiers: [.command])
        Divider()
      }
      CommandGroup(replacing: .newItem) {
        Button("New Note") {
          showMainWindow()
          model.createNewNote()
        }
        .latticeKeyboardShortcut(model.keyboardShortcut(for: .newNote))
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
      CommandMenu("Actions") {
        Button("Settings...") {
          showSettingsWindow()
        }

        Divider()

        Button("Command Palette...") {
          showMainWindow()
          model.showCommandPalette()
        }
        .latticeKeyboardShortcut(model.keyboardShortcut(for: .commandPalette))

        Divider()

        Button(model.isZenModeEnabled ? "Exit Zen Mode" : "Enter Zen Mode") {
          showMainWindow()
          model.toggleZenMode()
        }
        .latticeKeyboardShortcut(model.keyboardShortcut(for: .zenMode))
        .disabled(!model.hasFolder)

        Divider()

        Button("Choose Notes Folder...") {
          showMainWindow()
          model.showFolderImporter()
        }
        Button(updateMenuTitle) {
          performUpdateAction()
        }
        .latticeKeyboardShortcut(model.keyboardShortcut(for: .checkForUpdates))
      }
      CommandMenu("Navigate") {
        Button("Back") {
          model.navigateBack()
        }
        .latticeKeyboardShortcut(model.keyboardShortcut(for: .navigateBack))
        .disabled(!model.canNavigateBack)

        Button("Forward") {
          model.navigateForward()
        }
        .latticeKeyboardShortcut(model.keyboardShortcut(for: .navigateForward))
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

    MenuBarExtra {
      Button("Show Lattice") {
        showMainWindow()
      }
      Button("New Note") {
        showMainWindow()
        model.createNewNote()
      }
      .latticeKeyboardShortcut(model.keyboardShortcut(for: .newNote))
      Divider()
      Button("Choose Notes Folder...") {
        showMainWindow()
        model.showFolderImporter()
      }
      Button("Settings...") {
        showSettingsWindow()
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
      if updateState.isUpdateAvailable {
        Divider()
        Button(updateState.menuItemTitle) {
          showMainWindow()
          performUpdateAction()
        }
        .disabled(!canPerformUpdateAction)
      }
      if updateState.isUpdaterConfigured {
        Divider()
        Button("Check for Updates...") {
          appDelegate.checkForUpdates()
        }
        .latticeKeyboardShortcut(model.keyboardShortcut(for: .checkForUpdates))
        .disabled(!appDelegate.canCheckForUpdates)
      }
      Divider()
      Button("Quit Lattice") {
        model.flushAutosave()
        NSApp.terminate(nil)
      }
      .keyboardShortcut("q", modifiers: [.command])
    } label: {
      Label("Lattice", systemImage: updateState.menuBarSystemImage)
    }

    Settings {
      TaskSyncSettingsView(
        model: model,
        releaseUpdateStatus: settingsReleaseUpdateStatus
      ) {
        checkForUpdatesFromSettings()
      }
        .frame(width: Self.settingsWindowWidth, height: Self.settingsWindowHeight)
        .background(SettingsWindowConfiguration(
          width: Self.settingsWindowWidth,
          height: Self.settingsWindowHeight,
          identifier: Self.settingsWindowIdentifier
        ))
        .task {
          model.start()
        }
    }
    .windowResizability(.contentSize)
  }

  private func showMainWindow() {
    if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == Self.mainWindowIdentifier }) {
      window.makeKeyAndOrderFront(nil)
    } else {
      openWindow(id: "main")
    }
    NSApp.activate(ignoringOtherApps: true)
  }

  private func showSettingsWindow() {
    if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == Self.settingsWindowIdentifier }) {
      window.makeKeyAndOrderFront(nil)
    } else {
      openSettings()
    }
    NSApp.activate(ignoringOtherApps: true)
  }

  private var commandPalettePlatformCommands: [CommandPaletteCommand] {
    [
      CommandPaletteCommand(
        id: "mac.settings",
        title: "Settings",
        subtitle: "Open Lattice preferences",
        systemImage: "gearshape",
        isSetupSafe: true,
        keyboardShortcut: "⌘,"
      ) {
        showSettingsWindow()
      },
      CommandPaletteCommand(
        id: "mac.checkForUpdates",
        title: updateState.isUpdateAvailable ? "Update Available" : "Check for Updates",
        subtitle: updateCommandSubtitle,
        systemImage: updateState.isUpdateAvailable ? "arrow.down.circle.fill" : "arrow.triangle.2.circlepath",
        isSetupSafe: true,
        keyboardShortcut: model.keyboardShortcut(for: .checkForUpdates)?.displayText
      ) {
        performUpdateAction()
      }
    ]
  }

  private var updateCommandSubtitle: String {
    if updateState.isUpdateAvailable {
      return updateState.indicatorHelp
    }
    if updateState.isUpdaterConfigured {
      return "Look for a newer Lattice release"
    }
    return "Available in release builds"
  }

  private var updateMenuTitle: String {
    if updateState.canInstallUpdate {
      return "Update Now..."
    }
    return "Check for Updates..."
  }

  private var canPerformUpdateAction: Bool {
    updateState.canInstallUpdate || appDelegate.canCheckForUpdates
  }

  private var settingsReleaseUpdateStatus: ReleaseUpdateStatus {
    if updateState.isUpdateAvailable {
      return .updateAvailable(
        version: updateState.updateVersion,
        title: updateState.updateTitle,
        canCheckForUpdates: appDelegate.canCheckForUpdates,
        canInstallUpdate: updateState.canInstallUpdate
      )
    }

    if updateState.isUpdaterConfigured {
      return .idle(canCheckForUpdates: appDelegate.canCheckForUpdates)
    }

    return .unavailable
  }

  private func checkForUpdatesFromSettings() {
    performUpdateAction()
  }

  private func performUpdateAction() {
    if appDelegate.canInstallAvailableUpdate {
      appDelegate.installAvailableUpdate()
      return
    }

    if appDelegate.canCheckForUpdates {
      appDelegate.checkForUpdates()
    } else {
      model.errorMessage = "Update checking is available in release builds."
    }
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

@MainActor
@Observable
private final class MacUpdateState {
  var isUpdaterConfigured = false
  var isUpdateAvailable = false
  var canInstallUpdate = false
  var updateVersion: String?
  var updateTitle: String?

  var indicatorTitle: String {
    if canInstallUpdate, let updateVersion {
      return "Update \(updateVersion) Ready"
    }
    if let updateVersion {
      return "Update \(updateVersion) Available"
    }
    return "Update Available"
  }

  var indicatorHelp: String {
    if canInstallUpdate, let updateTitle, let updateVersion, updateTitle != updateVersion {
      return "\(updateTitle) \(updateVersion) is ready to install"
    }
    if canInstallUpdate, let updateVersion {
      return "Lattice \(updateVersion) is ready to install"
    }
    if let updateTitle, let updateVersion, updateTitle != updateVersion {
      return "\(updateTitle) \(updateVersion) is available"
    }
    if let updateVersion {
      return "Lattice \(updateVersion) is available"
    }
    return "A new Lattice update is available"
  }

  var menuItemTitle: String {
    "\(indicatorTitle)..."
  }

  var menuBarSystemImage: String {
    isUpdateAvailable ? "arrow.down.circle.fill" : "square.and.pencil"
  }

  func markUpdaterConfigured(_ isConfigured: Bool) {
    isUpdaterConfigured = isConfigured
  }

  func markUpdateAvailable(_ item: SUAppcastItem, canInstallUpdate: Bool = false) {
    isUpdateAvailable = true
    updateVersion = item.displayVersionString
    updateTitle = item.title
    self.canInstallUpdate = self.canInstallUpdate || canInstallUpdate
  }

  func markUpdateInstallReady(_ item: SUAppcastItem) {
    markUpdateAvailable(item, canInstallUpdate: true)
  }

  func clearUpdateAvailable() {
    isUpdateAvailable = false
    canInstallUpdate = false
    updateVersion = nil
    updateTitle = nil
  }
}

private extension LatticeMacApp {
  static let mainWindowIdentifier = "main"
  static let settingsWindowIdentifier = "settings"
}

private extension View {
  @ViewBuilder
  func latticeKeyboardShortcut(_ shortcut: LatticeKeyboardShortcut?) -> some View {
    if let shortcut,
       let key = shortcut.key.first {
      keyboardShortcut(KeyEquivalent(key), modifiers: shortcut.eventModifiers)
    } else {
      self
    }
  }
}

private extension LatticeKeyboardShortcut {
  var eventModifiers: EventModifiers {
    var modifiers = EventModifiers()
    if self.modifiers.contains(.command) {
      modifiers.insert(.command)
    }
    if self.modifiers.contains(.shift) {
      modifiers.insert(.shift)
    }
    if self.modifiers.contains(.option) {
      modifiers.insert(.option)
    }
    if self.modifiers.contains(.control) {
      modifiers.insert(.control)
    }
    return modifiers
  }
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
  let theme: LatticeTheme
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
      let backgroundColor = theme.nsColor(.appBackground)
      window.identifier = NSUserInterfaceItemIdentifier(identifier)
      window.minSize = size
      window.contentMinSize = size
      window.backgroundColor = backgroundColor
      window.titleVisibility = isZenModeEnabled ? .hidden : .visible
      window.titlebarAppearsTransparent = true
      window.toolbar?.showsBaselineSeparator = false
      window.standardWindowButton(.closeButton)?.isHidden = isZenModeEnabled
      window.standardWindowButton(.miniaturizeButton)?.isHidden = isZenModeEnabled
      window.standardWindowButton(.zoomButton)?.isHidden = isZenModeEnabled
      window.styleMask.insert(.fullSizeContentView)
      if isZenModeEnabled {
        window.toolbar?.isVisible = false
      } else {
        window.toolbar?.isVisible = true
      }
      applyBackground(backgroundColor, to: window)
    }
  }

  private func applyBackground(_ color: NSColor, to window: NSWindow) {
    window.backgroundColor = color
    let layerColor = resolvedLayerColor(color, for: window)
    window.contentView?.wantsLayer = true
    window.contentView?.layer?.backgroundColor = layerColor
    window.contentView?.superview?.wantsLayer = true
    window.contentView?.superview?.layer?.backgroundColor = layerColor
  }

  private func resolvedLayerColor(_ color: NSColor, for window: NSWindow) -> CGColor {
    var layerColor = color.cgColor
    window.effectiveAppearance.performAsCurrentDrawingAppearance {
      layerColor = color.cgColor
    }
    return layerColor
  }
}

private struct SettingsWindowConfiguration: NSViewRepresentable {
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
      guard let window = view.window else {
        return
      }
      let size = NSSize(width: width, height: height)
      window.identifier = NSUserInterfaceItemIdentifier(identifier)
      window.title = "Settings"
      window.titleVisibility = .hidden
      window.minSize = size
      window.maxSize = size
      window.contentMinSize = size
      window.contentMaxSize = size
      window.titlebarAppearsTransparent = true
      window.toolbarStyle = .unified
      window.toolbar?.showsBaselineSeparator = false
      window.styleMask.remove(.resizable)
    }
  }
}

@MainActor
final class MacAppDelegate: NSObject, NSApplicationDelegate, SPUUpdaterDelegate, @preconcurrency SPUStandardUserDriverDelegate {
  private var updaterController: SPUStandardUpdaterController?
  private var sidebarShortcutMonitor: Any?
  private weak var updateState: MacUpdateState?
  private var immediateInstallHandler: (() -> Void)?

  var canCheckForUpdates: Bool {
    updaterController?.updater.canCheckForUpdates ?? false
  }

  var canInstallAvailableUpdate: Bool {
    immediateInstallHandler != nil
  }

  var supportsGentleScheduledUpdateReminders: Bool {
    true
  }

  fileprivate func attachUpdateState(_ state: MacUpdateState) {
    updateState = state
    publishUpdaterConfiguration()
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
    updaterController?.updater.checkForUpdates()
  }

  func installAvailableUpdate() {
    immediateInstallHandler?()
  }

  func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
    updateState?.markUpdateAvailable(item)
  }

  func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: any Error) {
    immediateInstallHandler = nil
    updateState?.clearUpdateAvailable()
  }

  func updater(_ updater: SPUUpdater, didDownloadUpdate item: SUAppcastItem) {
    updateState?.markUpdateAvailable(item)
  }

  func updater(
    _ updater: SPUUpdater,
    willInstallUpdateOnQuit item: SUAppcastItem,
    immediateInstallationBlock immediateInstallHandler: @escaping () -> Void
  ) -> Bool {
    self.immediateInstallHandler = immediateInstallHandler
    updateState?.markUpdateInstallReady(item)
    return true
  }

  func standardUserDriverShouldHandleShowingScheduledUpdate(
    _ update: SUAppcastItem,
    andInImmediateFocus immediateFocus: Bool
  ) -> Bool {
    updateState?.markUpdateAvailable(update)
    return immediateFocus
  }

  func standardUserDriverWillHandleShowingUpdate(
    _ handleShowingUpdate: Bool,
    forUpdate update: SUAppcastItem,
    state: SPUUserUpdateState
  ) {
    updateState?.markUpdateAvailable(update)
  }

  func toggleSidebar() {
    if NSApp.activeWindow?.identifier?.rawValue == LatticeMacApp.settingsWindowIdentifier {
      return
    }
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
      updaterDelegate: self,
      userDriverDelegate: self
    )
    publishUpdaterConfiguration()
  }

  private func publishUpdaterConfiguration() {
    updateState?.markUpdaterConfigured(updaterController != nil)
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
