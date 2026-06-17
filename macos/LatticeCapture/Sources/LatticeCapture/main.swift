import AppKit
import Carbon.HIToolbox
import Sparkle

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private let vaultService = VaultService()
  private let settings = AppSettings()
  private var windowController: MainWindowController?
  private var settingsWindowController: HotKeySettingsWindowController?
  private var vaultSetupWindowController: VaultSetupWindowController?
  private var statusItem: NSStatusItem?
  private var hotKey: GlobalHotKey?
  private var updaterController: SPUStandardUpdaterController?

  func applicationDidFinishLaunching(_ notification: Notification) {
    configureUpdater()
    applyAppearanceMode()
    buildStatusItem()
    registerConfiguredHotKey(showAlertOnFailure: false)
    if hasUsableActiveVault() {
      if ProcessInfo.processInfo.environment["LATTICE_HIDE_ON_LAUNCH"] != "1" {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
          self?.showMainWindow()
        }
      }
    } else {
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
        self?.showVaultSetup()
      }
    }
    if ProcessInfo.processInfo.environment["LATTICE_OPEN_HOTKEY_SETTINGS"] == "1" {
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
        self?.openHotKeySettings()
      }
    }
  }

  func applicationWillTerminate(_ notification: Notification) {
    windowController?.commitDraftBeforeExit()
    hotKey?.unregister()
  }

  func applicationShouldHandleReopen(
    _ sender: NSApplication,
    hasVisibleWindows flag: Bool
  ) -> Bool {
    if !flag {
      showMainWindow()
    }
    return true
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    false
  }

  private func buildStatusItem() {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    item.button?.title = "L"
    item.button?.font = .systemFont(ofSize: 13, weight: .semibold)
    item.menu = makeMenu()
    statusItem = item
  }

  private func makeMenu() -> NSMenu {
    let menu = NSMenu()

    let visibilityTitle = isMainWindowVisible ? "Hide Lattice" : "Show Lattice"
    menu.addItem(NSMenuItem(
      title: visibilityTitle,
      action: #selector(toggleMainWindowFromMenu),
      keyEquivalent: ""
    ))

    menu.addItem(NSMenuItem.separator())

    let vaultTitle: String
    if let vault = try? vaultService.currentVault() {
      vaultTitle = "Vault: \(vault.config.vault.name)"
    } else {
      vaultTitle = "Vault: Not Selected"
    }
    let vaultItem = NSMenuItem(
      title: vaultTitle,
      action: nil,
      keyEquivalent: ""
    )
    vaultItem.isEnabled = false
    menu.addItem(vaultItem)

    menu.addItem(NSMenuItem(
      title: "Open Vault",
      action: #selector(openVault),
      keyEquivalent: "o"
    ))
    menu.addItem(NSMenuItem(
      title: "Reveal Wiki",
      action: #selector(revealWiki),
      keyEquivalent: ""
    ))
    menu.addItem(NSMenuItem(
      title: "Change Vault...",
      action: #selector(changeVault),
      keyEquivalent: ""
    ))

    menu.addItem(NSMenuItem(
      title: "Settings...",
      action: #selector(openHotKeySettings),
      keyEquivalent: ","
    ))

    if updaterController != nil {
      menu.addItem(NSMenuItem(
        title: "Check for Updates...",
        action: #selector(checkForUpdates(_:)),
        keyEquivalent: ""
      ))
    }

    let appearanceItem = NSMenuItem(
      title: "Appearance",
      action: nil,
      keyEquivalent: ""
    )
    let appearanceMenu = NSMenu()
    for mode in AppAppearanceMode.allCases {
      let item = NSMenuItem(
        title: mode.title,
        action: #selector(setAppearanceModeFromMenu(_:)),
        keyEquivalent: ""
      )
      item.target = self
      item.representedObject = mode.rawValue
      item.state = settings.appearanceMode == mode ? .on : .off
      appearanceMenu.addItem(item)
    }
    menu.setSubmenu(appearanceMenu, for: appearanceItem)
    menu.addItem(appearanceItem)

    let hotKeyItem = NSMenuItem(
      title: "Hotkey: \(settings.hotKey.displayString)",
      action: nil,
      keyEquivalent: ""
    )
    hotKeyItem.isEnabled = false
    menu.addItem(hotKeyItem)

    menu.addItem(NSMenuItem.separator())
    menu.addItem(NSMenuItem(
      title: "Quit Lattice",
      action: #selector(NSApplication.terminate(_:)),
      keyEquivalent: "q"
    ))

    return menu
  }

  private var isMainWindowVisible: Bool {
    windowController?.window?.isVisible == true
  }

  private func refreshMenu() {
    statusItem?.menu = makeMenu()
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

  @objc private func toggleMainWindowFromMenu() {
    toggleMainWindow()
  }

  @objc private func openVault() {
    guard let vault = try? vaultService.currentVault() else {
      showVaultSetup()
      return
    }

    NSWorkspace.shared.open(vault.rootURL)
  }

  @objc private func revealWiki() {
    guard let vault = try? vaultService.currentVault() else {
      showVaultSetup()
      return
    }

    NSWorkspace.shared.open(vault.rootURL.appendingPathComponent("wiki", isDirectory: true))
  }

  @objc private func changeVault() {
    showVaultSetup()
  }

  @objc private func openHotKeySettings() {
    if settingsWindowController == nil {
      settingsWindowController = HotKeySettingsWindowController(
        settings: settings,
        onChange: { [weak self] in
          self?.registerConfiguredHotKey(showAlertOnFailure: true)
          self?.refreshMenu()
        },
        onAppearanceChange: { [weak self] in
          self?.applyAppearanceMode()
          self?.refreshMenu()
        }
      )
    }

    showMainWindow()
    settingsWindowController?.showWindow(nil)
    settingsWindowController?.window?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  @objc private func checkForUpdates(_ sender: Any?) {
    updaterController?.checkForUpdates(sender)
  }

  @objc private func setAppearanceModeFromMenu(_ sender: NSMenuItem) {
    guard
      let rawValue = sender.representedObject as? String,
      let mode = AppAppearanceMode(rawValue: rawValue)
    else {
      return
    }

    settings.appearanceMode = mode
    settingsWindowController?.reloadSettings()
    applyAppearanceMode()
    refreshMenu()
  }

  private func toggleMainWindow() {
    if let window = windowController?.window, window.isVisible, window.isKeyWindow {
      hideMainWindow()
    } else {
      showMainWindow()
    }
  }

  private func showMainWindow() {
    guard hasUsableActiveVault() else {
      showVaultSetup()
      return
    }

    if windowController == nil {
      windowController = MainWindowController(
        vaultService: vaultService,
        onVisibilityChange: { [weak self] in
          self?.refreshMenu()
        }
      )
    }

    windowController?.showWindow(nil)
    windowController?.window?.orderFrontRegardless()
    windowController?.window?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    refreshMenu()
  }

  private func showVaultSetup() {
    if vaultSetupWindowController == nil {
      vaultSetupWindowController = VaultSetupWindowController(
        vaultService: vaultService,
        onVaultSelected: { [weak self] in
          self?.vaultSetupWindowController?.close()
          self?.vaultSetupWindowController = nil
          self?.refreshMenu()
          self?.showMainWindow()
        }
      )
    }

    vaultSetupWindowController?.showWindow(nil)
    vaultSetupWindowController?.window?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    refreshMenu()
  }

  private func hasUsableActiveVault() -> Bool {
    guard let url = vaultService.activeVaultURL() else {
      return false
    }

    return vaultService.validateVault(at: url).isUsableVault
  }

  private func hideMainWindow() {
    windowController?.commitDraft()
    windowController?.window?.orderOut(nil)
    refreshMenu()
  }

  private func registerConfiguredHotKey(showAlertOnFailure: Bool) {
    hotKey?.unregister()
    hotKey = nil

    guard settings.hotKey.isEnabled else {
      return
    }

    let configuredHotKey = GlobalHotKey(shortcut: settings.hotKey) { [weak self] in
      self?.toggleMainWindow()
    }

    do {
      try configuredHotKey.register()
      hotKey = configuredHotKey
    } catch {
      if showAlertOnFailure {
        presentHotKeyRegistrationFailure(error)
      }
    }
  }

  private func presentHotKeyRegistrationFailure(_ error: Error) {
    let alert = NSAlert()
    alert.messageText = "Hotkey unavailable"
    alert.informativeText = "Lattice could not register \(settings.hotKey.displayString). Another app may already be using it."
    alert.alertStyle = .warning
    alert.runModal()
  }

  private func applyAppearanceMode() {
    NSApp.appearance = settings.appearanceMode.nsAppearance
    for window in NSApp.windows {
      window.contentView?.needsDisplay = true
    }
  }
}

@MainActor
final class MainWindowController: NSWindowController, NSWindowDelegate {
  private let vaultService: VaultService
  private let editorView: MarkdownEditorView
  private let onVisibilityChange: () -> Void

  init(
    vaultService: VaultService,
    onVisibilityChange: @escaping () -> Void
  ) {
    self.vaultService = vaultService
    self.editorView = MarkdownEditorView(vaultService: vaultService)
    self.onVisibilityChange = onVisibilityChange
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 420, height: 780),
      styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
      backing: .buffered,
      defer: false
    )

    window.title = "Lattice"
    window.titleVisibility = .hidden
    window.titlebarAppearsTransparent = true
    window.isReleasedWhenClosed = false
    window.minSize = NSSize(width: 380, height: 420)
    window.center()
    window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    window.contentView = editorView

    super.init(window: window)
    window.delegate = self
    window.toolbar = makeToolbar()
  }

  override func windowDidLoad() {
    super.windowDidLoad()
    editorView.focus()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  private func makeToolbar() -> NSToolbar {
    let toolbar = NSToolbar(identifier: "MarkdownToolbar")
    toolbar.delegate = self
    toolbar.displayMode = .iconOnly
    toolbar.allowsUserCustomization = false
    toolbar.showsBaselineSeparator = false
    return toolbar
  }

  override func showWindow(_ sender: Any?) {
    super.showWindow(sender)
    DispatchQueue.main.async { [weak self] in
      self?.editorView.focus()
    }
  }

  func commitDraft() {
    editorView.commitDraft()
  }

  func commitDraftBeforeExit() {
    editorView.commitDraftBeforeExit()
  }

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    commitDraft()
    sender.orderOut(nil)
    onVisibilityChange()
    return false
  }

  func windowDidMiniaturize(_ notification: Notification) {
    onVisibilityChange()
  }

  func windowDidDeminiaturize(_ notification: Notification) {
    onVisibilityChange()
  }

  func windowDidBecomeKey(_ notification: Notification) {
    onVisibilityChange()
  }

  func windowDidResignKey(_ notification: Notification) {
    commitDraft()
    onVisibilityChange()
  }
}

final class AppSettings {
  private enum DefaultsKey {
    static let appearanceMode = "appearanceMode"
    static let globalHotKey = "globalHotKey"
  }

  private let defaults = UserDefaults.standard

  var appearanceMode: AppAppearanceMode {
    get {
      guard
        let rawValue = defaults.string(forKey: DefaultsKey.appearanceMode),
        let mode = AppAppearanceMode(rawValue: rawValue)
      else {
        return .system
      }

      return mode
    }
    set {
      defaults.set(newValue.rawValue, forKey: DefaultsKey.appearanceMode)
    }
  }

  var hotKey: HotKeyShortcut {
    get {
      guard
        let stored = defaults.dictionary(forKey: DefaultsKey.globalHotKey),
        let keyCode = stored["keyCode"] as? Int
      else {
        return .defaultShortcut
      }

      let modifierRawValue: UInt
      if let modifiers = stored["modifiers"] as? UInt {
        modifierRawValue = modifiers
      } else if let modifiers = stored["modifiers"] as? Int {
        modifierRawValue = UInt(modifiers)
      } else {
        modifierRawValue = 0
      }

      return HotKeyShortcut(
        keyCode: UInt32(keyCode),
        modifiers: NSEvent.ModifierFlags(rawValue: modifierRawValue)
      )
    }
    set {
      defaults.set([
        "keyCode": Int(newValue.keyCode),
        "modifiers": newValue.modifiers.rawValue
      ], forKey: DefaultsKey.globalHotKey)
    }
  }
}

final class WindowBackgroundView: NSView {
  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    updateBackgroundColor()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    updateBackgroundColor()
  }

  private func updateBackgroundColor() {
    effectiveAppearance.performAsCurrentDrawingAppearance {
      layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    }
  }
}

enum AppAppearanceMode: String, CaseIterable {
  case system
  case light
  case dark

  var title: String {
    switch self {
    case .system:
      "System"
    case .light:
      "Light"
    case .dark:
      "Dark"
    }
  }

  var nsAppearance: NSAppearance? {
    switch self {
    case .system:
      nil
    case .light:
      NSAppearance(named: .aqua)
    case .dark:
      NSAppearance(named: .darkAqua)
    }
  }
}

struct HotKeyShortcut: Equatable {
  let keyCode: UInt32
  let modifiers: NSEvent.ModifierFlags

  static let disabled = HotKeyShortcut(keyCode: 0, modifiers: [])
  static let defaultShortcut = HotKeyShortcut(
    keyCode: UInt32(kVK_Space),
    modifiers: [.control, .option]
  )

  var isEnabled: Bool {
    keyCode != 0
  }

  var carbonModifiers: UInt32 {
    var carbonFlags: UInt32 = 0
    if modifiers.contains(.command) {
      carbonFlags |= UInt32(cmdKey)
    }
    if modifiers.contains(.option) {
      carbonFlags |= UInt32(optionKey)
    }
    if modifiers.contains(.control) {
      carbonFlags |= UInt32(controlKey)
    }
    if modifiers.contains(.shift) {
      carbonFlags |= UInt32(shiftKey)
    }
    return carbonFlags
  }

  var displayString: String {
    guard isEnabled else {
      return "None"
    }

    var parts: [String] = []
    if modifiers.contains(.control) {
      parts.append("Control")
    }
    if modifiers.contains(.option) {
      parts.append("Option")
    }
    if modifiers.contains(.shift) {
      parts.append("Shift")
    }
    if modifiers.contains(.command) {
      parts.append("Command")
    }
    parts.append(keyDisplayName(for: keyCode))
    return parts.joined(separator: "-")
  }

  var compactDisplayString: String {
    guard isEnabled else {
      return "None"
    }

    var result = ""
    if modifiers.contains(.control) {
      result += "⌃"
    }
    if modifiers.contains(.option) {
      result += "⌥"
    }
    if modifiers.contains(.shift) {
      result += "⇧"
    }
    if modifiers.contains(.command) {
      result += "⌘"
    }
    result += keyDisplayName(for: keyCode)
    return result
  }

  private func keyDisplayName(for keyCode: UInt32) -> String {
    switch Int(keyCode) {
    case kVK_Space:
      return "Space"
    case kVK_Return:
      return "Return"
    case kVK_Tab:
      return "Tab"
    case kVK_Escape:
      return "Escape"
    case kVK_Delete:
      return "Delete"
    case kVK_ForwardDelete:
      return "Forward Delete"
    case kVK_LeftArrow:
      return "Left Arrow"
    case kVK_RightArrow:
      return "Right Arrow"
    case kVK_UpArrow:
      return "Up Arrow"
    case kVK_DownArrow:
      return "Down Arrow"
    case kVK_F1...kVK_F20:
      return "F\(Int(keyCode) - kVK_F1 + 1)"
    default:
      return KeyCodeDisplayNames.names[Int(keyCode)] ?? "Key \(keyCode)"
    }
  }
}

private enum KeyCodeDisplayNames {
  static let names: [Int: String] = [
    kVK_ANSI_A: "A",
    kVK_ANSI_B: "B",
    kVK_ANSI_C: "C",
    kVK_ANSI_D: "D",
    kVK_ANSI_E: "E",
    kVK_ANSI_F: "F",
    kVK_ANSI_G: "G",
    kVK_ANSI_H: "H",
    kVK_ANSI_I: "I",
    kVK_ANSI_J: "J",
    kVK_ANSI_K: "K",
    kVK_ANSI_L: "L",
    kVK_ANSI_M: "M",
    kVK_ANSI_N: "N",
    kVK_ANSI_O: "O",
    kVK_ANSI_P: "P",
    kVK_ANSI_Q: "Q",
    kVK_ANSI_R: "R",
    kVK_ANSI_S: "S",
    kVK_ANSI_T: "T",
    kVK_ANSI_U: "U",
    kVK_ANSI_V: "V",
    kVK_ANSI_W: "W",
    kVK_ANSI_X: "X",
    kVK_ANSI_Y: "Y",
    kVK_ANSI_Z: "Z",
    kVK_ANSI_0: "0",
    kVK_ANSI_1: "1",
    kVK_ANSI_2: "2",
    kVK_ANSI_3: "3",
    kVK_ANSI_4: "4",
    kVK_ANSI_5: "5",
    kVK_ANSI_6: "6",
    kVK_ANSI_7: "7",
    kVK_ANSI_8: "8",
    kVK_ANSI_9: "9",
    kVK_ANSI_Minus: "-",
    kVK_ANSI_Equal: "=",
    kVK_ANSI_LeftBracket: "[",
    kVK_ANSI_RightBracket: "]",
    kVK_ANSI_Backslash: "\\",
    kVK_ANSI_Semicolon: ";",
    kVK_ANSI_Quote: "'",
    kVK_ANSI_Grave: "`",
    kVK_ANSI_Comma: ",",
    kVK_ANSI_Period: ".",
    kVK_ANSI_Slash: "/"
  ]
}

enum HotKeyError: Error {
  case registrationFailed(OSStatus)
}

final class GlobalHotKey {
  private var hotKeyRef: EventHotKeyRef?
  private var handlerRef: EventHandlerRef?
  private let shortcut: HotKeyShortcut
  private let action: @MainActor @Sendable () -> Void

  init(shortcut: HotKeyShortcut, action: @escaping @MainActor @Sendable () -> Void) {
    self.shortcut = shortcut
    self.action = action
  }

  func register() throws {
    guard shortcut.isEnabled else {
      return
    }

    var eventType = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard),
      eventKind: UInt32(kEventHotKeyPressed)
    )

    let selfPointer = Unmanaged.passUnretained(self).toOpaque()
    let callback: EventHandlerUPP = { _, _, userData in
      guard let userData else {
        return noErr
      }

      let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
      let action = hotKey.action
      DispatchQueue.main.async {
        action()
      }
      return noErr
    }

    let handlerStatus = InstallEventHandler(
      GetApplicationEventTarget(),
      callback,
      1,
      &eventType,
      selfPointer,
      &handlerRef
    )
    guard handlerStatus == noErr else {
      throw HotKeyError.registrationFailed(handlerStatus)
    }

    let hotKeyID = EventHotKeyID(
      signature: fourCharCode("LATT"),
      id: 1
    )
    let hotKeyStatus = RegisterEventHotKey(
      shortcut.keyCode,
      shortcut.carbonModifiers,
      hotKeyID,
      GetApplicationEventTarget(),
      0,
      &hotKeyRef
    )

    guard hotKeyStatus == noErr else {
      unregister()
      throw HotKeyError.registrationFailed(hotKeyStatus)
    }
  }

  func unregister() {
    if let hotKeyRef {
      UnregisterEventHotKey(hotKeyRef)
    }
    if let handlerRef {
      RemoveEventHandler(handlerRef)
    }
    hotKeyRef = nil
    handlerRef = nil
  }

  deinit {
    unregister()
  }
}

private func fourCharCode(_ string: String) -> OSType {
  var result: UInt32 = 0
  for scalar in string.unicodeScalars.prefix(4) {
    result = (result << 8) + scalar.value
  }
  return result
}

@MainActor
final class HotKeySettingsWindowController: NSWindowController {
  private let settings: AppSettings
  private let onChange: () -> Void
  private let onAppearanceChange: () -> Void
  private let recorder = ShortcutRecorderField()
  private let appearanceControl = NSSegmentedControl(
    labels: AppAppearanceMode.allCases.map(\.title),
    trackingMode: .selectOne,
    target: nil,
    action: nil
  )
  private let statusLabel = NSTextField(labelWithString: "")

  init(
    settings: AppSettings,
    onChange: @escaping () -> Void,
    onAppearanceChange: @escaping () -> Void
  ) {
    self.settings = settings
    self.onChange = onChange
    self.onAppearanceChange = onAppearanceChange

    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 440, height: 300),
      styleMask: [.titled, .closable],
      backing: .buffered,
      defer: false
    )
    window.title = "Lattice Settings"
    window.isReleasedWhenClosed = false
    window.center()

    super.init(window: window)
    buildContent()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func showWindow(_ sender: Any?) {
    reloadSettings()
    super.showWindow(sender)
  }

  func reloadSettings() {
    recorder.shortcut = settings.hotKey
    updateAppearanceControl()
    updateStatus()
  }

  private func buildContent() {
    guard let window else {
      return
    }

    let titleLabel = NSTextField(labelWithString: "Global Hotkey")
    titleLabel.font = .systemFont(ofSize: 18, weight: .semibold)

    let descriptionLabel = NSTextField(wrappingLabelWithString: "Use this shortcut to show or hide the Lattice editor from anywhere.")
    descriptionLabel.font = .systemFont(ofSize: 13, weight: .regular)
    descriptionLabel.textColor = .secondaryLabelColor

    recorder.shortcut = settings.hotKey
    recorder.onChange = { [weak self] shortcut in
      guard let self else {
        return
      }
      self.settings.hotKey = shortcut
      self.updateStatus()
      self.onChange()
    }
    recorder.onInvalidShortcut = { [weak self] in
      self?.statusLabel.stringValue = "Use Command, Option, Control, or a function key."
    }
    recorder.translatesAutoresizingMaskIntoConstraints = false

    let resetButton = NSButton(
      title: "Reset",
      target: self,
      action: #selector(resetShortcut)
    )
    resetButton.bezelStyle = .rounded

    let clearButton = NSButton(
      title: "Clear",
      target: self,
      action: #selector(clearShortcut)
    )
    clearButton.bezelStyle = .rounded

    let buttonStack = NSStackView(views: [resetButton, clearButton])
    buttonStack.orientation = .horizontal
    buttonStack.spacing = 8
    buttonStack.alignment = .centerY

    statusLabel.font = .systemFont(ofSize: 12, weight: .regular)
    statusLabel.textColor = .secondaryLabelColor

    let appearanceTitleLabel = NSTextField(labelWithString: "Appearance")
    appearanceTitleLabel.font = .systemFont(ofSize: 18, weight: .semibold)

    let appearanceDescriptionLabel = NSTextField(wrappingLabelWithString: "Choose whether Lattice follows macOS or always uses a fixed appearance.")
    appearanceDescriptionLabel.font = .systemFont(ofSize: 13, weight: .regular)
    appearanceDescriptionLabel.textColor = .secondaryLabelColor

    appearanceControl.target = self
    appearanceControl.action = #selector(appearanceControlChanged)
    appearanceControl.translatesAutoresizingMaskIntoConstraints = false
    updateAppearanceControl()

    let stack = NSStackView(views: [
      titleLabel,
      descriptionLabel,
      recorder,
      buttonStack,
      statusLabel,
      appearanceTitleLabel,
      appearanceDescriptionLabel,
      appearanceControl
    ])
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 12
    stack.edgeInsets = NSEdgeInsets(top: 22, left: 24, bottom: 18, right: 24)
    stack.translatesAutoresizingMaskIntoConstraints = false

    let contentView = WindowBackgroundView()
    contentView.addSubview(stack)
    window.contentView = contentView

    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
      stack.topAnchor.constraint(equalTo: contentView.topAnchor),
      stack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor),
      recorder.widthAnchor.constraint(equalToConstant: 220),
      recorder.heightAnchor.constraint(equalToConstant: 36),
      appearanceControl.widthAnchor.constraint(equalToConstant: 260)
    ])

    updateStatus()
  }

  @objc private func resetShortcut() {
    settings.hotKey = .defaultShortcut
    recorder.shortcut = settings.hotKey
    updateStatus()
    onChange()
  }

  @objc private func clearShortcut() {
    settings.hotKey = .disabled
    recorder.shortcut = settings.hotKey
    updateStatus()
    onChange()
  }

  private func updateStatus() {
    statusLabel.stringValue = settings.hotKey.isEnabled
      ? "Current: \(settings.hotKey.displayString)"
      : "No global hotkey is set."
  }

  @objc private func appearanceControlChanged() {
    guard AppAppearanceMode.allCases.indices.contains(appearanceControl.selectedSegment) else {
      return
    }

    settings.appearanceMode = AppAppearanceMode.allCases[appearanceControl.selectedSegment]
    onAppearanceChange()
  }

  private func updateAppearanceControl() {
    guard let index = AppAppearanceMode.allCases.firstIndex(of: settings.appearanceMode) else {
      appearanceControl.selectedSegment = 0
      return
    }
    appearanceControl.selectedSegment = index
  }
}

final class ShortcutRecorderField: NSTextField {
  var onChange: ((HotKeyShortcut) -> Void)?
  var onInvalidShortcut: (() -> Void)?
  var shortcut: HotKeyShortcut = .defaultShortcut {
    didSet {
      updateDisplay()
    }
  }

  private var isRecording = false

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    isEditable = false
    isSelectable = false
    isBordered = true
    isBezeled = true
    bezelStyle = .roundedBezel
    drawsBackground = true
    alignment = .center
    font = .systemFont(ofSize: 15, weight: .medium)
    focusRingType = .default
    updateDisplay()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override var acceptsFirstResponder: Bool {
    true
  }

  override func mouseDown(with event: NSEvent) {
    window?.makeFirstResponder(self)
    beginRecording()
  }

  override func becomeFirstResponder() -> Bool {
    let became = super.becomeFirstResponder()
    if became {
      beginRecording()
    }
    return became
  }

  override func resignFirstResponder() -> Bool {
    isRecording = false
    updateDisplay()
    return super.resignFirstResponder()
  }

  override func keyDown(with event: NSEvent) {
    if event.keyCode == UInt16(kVK_Escape) {
      isRecording = false
      updateDisplay()
      return
    }

    if event.keyCode == UInt16(kVK_Delete) || event.keyCode == UInt16(kVK_ForwardDelete) {
      shortcut = .disabled
      isRecording = false
      onChange?(shortcut)
      return
    }

    let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    let keyCode = UInt32(event.keyCode)
    let hasUsefulModifier = modifiers.contains(.command)
      || modifiers.contains(.option)
      || modifiers.contains(.control)
    let isFunctionKey = Int(keyCode) >= kVK_F1 && Int(keyCode) <= kVK_F20

    guard hasUsefulModifier || isFunctionKey else {
      onInvalidShortcut?()
      NSSound.beep()
      beginRecording()
      return
    }

    shortcut = HotKeyShortcut(keyCode: keyCode, modifiers: modifiers)
    isRecording = false
    onChange?(shortcut)
  }

  private func beginRecording() {
    isRecording = true
    stringValue = "Type shortcut..."
    textColor = .secondaryLabelColor
  }

  private func updateDisplay() {
    stringValue = isRecording ? "Type shortcut..." : shortcut.compactDisplayString
    textColor = shortcut.isEnabled ? .labelColor : .secondaryLabelColor
  }
}

extension MainWindowController: NSToolbarDelegate {
  func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
    EditorToolbarItem.allCases.map { NSToolbarItem.Identifier($0.rawValue) }
  }

  func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
    toolbarAllowedItemIdentifiers(toolbar)
  }

  func toolbar(
    _ toolbar: NSToolbar,
    itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
    willBeInsertedIntoToolbar flag: Bool
  ) -> NSToolbarItem? {
    guard let itemKind = EditorToolbarItem(rawValue: itemIdentifier.rawValue) else {
      return nil
    }

    let item = NSToolbarItem(itemIdentifier: itemIdentifier)
    item.label = itemKind.label
    item.paletteLabel = itemKind.label
    item.toolTip = itemKind.tooltip
    item.image = NSImage(systemSymbolName: itemKind.symbolName, accessibilityDescription: itemKind.label)
    item.target = self
    item.action = itemKind.action
    return item
  }

  @objc func insertHeading() {
    editorView.applyMarkdown(.heading)
  }

  @objc func insertBold() {
    editorView.applyMarkdown(.bold)
  }

  @objc func insertItalic() {
    editorView.applyMarkdown(.italic)
  }

  @objc func insertBulletList() {
    editorView.applyMarkdown(.bulletList)
  }

  @objc func insertCode() {
    editorView.applyMarkdown(.code)
  }

  @objc func insertLink() {
    editorView.applyMarkdown(.link)
  }

  @objc func saveCapture() {
    do {
      let capture = try vaultService.saveCapture(body: editorView.text, source: "macos-app")
      editorView.clear()
      editorView.showStatus("Saved \(capture.id)")
    } catch {
      presentSaveError(error)
    }
  }

  private func presentSaveError(_ error: Error) {
    let alert = NSAlert()
    alert.messageText = "Capture not saved"
    alert.informativeText = error.localizedDescription
    alert.alertStyle = .warning
    if let window {
      alert.beginSheetModal(for: window)
    } else {
      alert.runModal()
    }
  }
}

@MainActor
final class VaultSetupWindowController: NSWindowController {
  private let vaultService: VaultService
  private let onVaultSelected: () -> Void
  private let defaultPathLabel = NSTextField(labelWithString: "")

  init(
    vaultService: VaultService,
    onVaultSelected: @escaping () -> Void
  ) {
    self.vaultService = vaultService
    self.onVaultSelected = onVaultSelected

    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 520, height: 300),
      styleMask: [.titled, .closable],
      backing: .buffered,
      defer: false
    )
    window.title = "Choose Lattice Vault"
    window.isReleasedWhenClosed = false
    window.center()

    super.init(window: window)
    buildContent()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func showWindow(_ sender: Any?) {
    defaultPathLabel.stringValue = vaultService.defaultVaultURL.path
    super.showWindow(sender)
  }

  private func buildContent() {
    guard let window else {
      return
    }

    let titleLabel = NSTextField(labelWithString: "Choose a vault")
    titleLabel.font = .systemFont(ofSize: 22, weight: .semibold)

    let descriptionLabel = NSTextField(wrappingLabelWithString: "Lattice stores captures, queues, wiki files, and app state in a local folder. Choose an existing folder or initialize the default location.")
    descriptionLabel.font = .systemFont(ofSize: 13, weight: .regular)
    descriptionLabel.textColor = .secondaryLabelColor

    defaultPathLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
    defaultPathLabel.textColor = .tertiaryLabelColor
    defaultPathLabel.lineBreakMode = .byTruncatingMiddle

    let useDefaultButton = NSButton(
      title: "Use ~/Documents/lattice",
      target: self,
      action: #selector(useDefaultVault)
    )
    useDefaultButton.bezelStyle = .rounded
    useDefaultButton.keyEquivalent = "\r"

    let chooseButton = NSButton(
      title: "Choose Folder...",
      target: self,
      action: #selector(chooseFolder)
    )
    chooseButton.bezelStyle = .rounded

    let buttonStack = NSStackView(views: [useDefaultButton, chooseButton])
    buttonStack.orientation = .horizontal
    buttonStack.spacing = 10
    buttonStack.alignment = .centerY

    let stack = NSStackView(views: [
      titleLabel,
      descriptionLabel,
      defaultPathLabel,
      buttonStack
    ])
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 14
    stack.edgeInsets = NSEdgeInsets(top: 28, left: 30, bottom: 24, right: 30)
    stack.translatesAutoresizingMaskIntoConstraints = false

    let contentView = WindowBackgroundView()
    contentView.addSubview(stack)
    window.contentView = contentView

    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
      stack.topAnchor.constraint(equalTo: contentView.topAnchor),
      stack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor),
      defaultPathLabel.widthAnchor.constraint(equalToConstant: 460)
    ])
  }

  @objc private func useDefaultVault() {
    handleSelectedVault(vaultService.defaultVaultURL)
  }

  @objc private func chooseFolder() {
    let panel = NSOpenPanel()
    panel.title = "Choose Lattice Vault Folder"
    panel.prompt = "Choose"
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.canCreateDirectories = true
    panel.allowsMultipleSelection = false

    guard panel.runModal() == .OK, let url = panel.url else {
      return
    }

    handleSelectedVault(url)
  }

  private func handleSelectedVault(_ url: URL) {
    switch vaultService.validateVault(at: url) {
    case .valid:
      select(url)
    case .uninitialized:
      guard confirmInitialization(at: url) else {
        return
      }
      select(url)
    case .invalid(let message):
      presentError(message)
    }
  }

  private func select(_ url: URL) {
    do {
      _ = try vaultService.selectVault(url)
      onVaultSelected()
    } catch {
      presentError(error.localizedDescription)
    }
  }

  private func confirmInitialization(at url: URL) -> Bool {
    let alert = NSAlert()
    alert.messageText = "Initialize this folder as a Lattice vault?"
    alert.informativeText = "Lattice will create config, raw capture, queue, wiki, and skills files in:\n\n\(url.path)"
    alert.alertStyle = .informational
    alert.addButton(withTitle: "Initialize Vault")
    alert.addButton(withTitle: "Cancel")
    return alert.runModal() == .alertFirstButtonReturn
  }

  private func presentError(_ message: String) {
    let alert = NSAlert()
    alert.messageText = "Vault unavailable"
    alert.informativeText = message
    alert.alertStyle = .warning
    alert.runModal()
  }
}

private enum EditorToolbarItem: String, CaseIterable {
  case save
  case heading
  case bold
  case italic
  case bulletList
  case code
  case link
}

private extension EditorToolbarItem {
  var label: String {
    switch self {
    case .save:
      "Save Capture"
    case .heading:
      "Heading"
    case .bold:
      "Bold"
    case .italic:
      "Italic"
    case .bulletList:
      "Bulleted List"
    case .code:
      "Inline Code"
    case .link:
      "Link"
    }
  }

  var tooltip: String {
    switch self {
    case .save:
      "Save note to the active vault"
    case .heading:
      "Insert Markdown heading"
    case .bold:
      "Wrap selection in bold Markdown"
    case .italic:
      "Wrap selection in italic Markdown"
    case .bulletList:
      "Start a Markdown bulleted list"
    case .code:
      "Wrap selection in inline code Markdown"
    case .link:
      "Insert a Markdown link"
    }
  }

  var symbolName: String {
    switch self {
    case .save:
      "tray.and.arrow.down"
    case .heading:
      "textformat.size"
    case .bold:
      "bold"
    case .italic:
      "italic"
    case .bulletList:
      "list.bullet"
    case .code:
      "chevron.left.forwardslash.chevron.right"
    case .link:
      "link"
    }
  }

  var action: Selector {
    switch self {
    case .save:
      #selector(MainWindowController.saveCapture)
    case .heading:
      #selector(MainWindowController.insertHeading)
    case .bold:
      #selector(MainWindowController.insertBold)
    case .italic:
      #selector(MainWindowController.insertItalic)
    case .bulletList:
      #selector(MainWindowController.insertBulletList)
    case .code:
      #selector(MainWindowController.insertCode)
    case .link:
      #selector(MainWindowController.insertLink)
    }
  }
}

enum MarkdownCommand {
  case heading
  case bold
  case italic
  case bulletList
  case code
  case link
}

final class DraftStore {
  private let draftURL: URL

  init(fileManager: FileManager = .default) {
    let baseURL = fileManager.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    ).first ?? fileManager.homeDirectoryForCurrentUser

    let directoryURL = baseURL.appendingPathComponent(
      "LatticeCapture",
      isDirectory: true
    )
    try? fileManager.createDirectory(
      at: directoryURL,
      withIntermediateDirectories: true
    )
    draftURL = directoryURL.appendingPathComponent("draft.md")
  }

  func load() -> String {
    (try? String(contentsOf: draftURL, encoding: .utf8)) ?? ""
  }

  func save(_ body: String) throws {
    try body.write(to: draftURL, atomically: true, encoding: .utf8)
  }

  func clear() throws {
    if FileManager.default.fileExists(atPath: draftURL.path) {
      try FileManager.default.removeItem(at: draftURL)
    }
  }
}

final class MarkdownEditorView: NSView, NSTextViewDelegate {
  private let vaultService: VaultService
  private let scrollView = NSScrollView()
  private let textView = MarkdownTextView()
  private let characterCountLabel = NSTextField(labelWithString: "0 characters")
  private let draftStore = DraftStore()
  private var isRenderingMarkdown = false
  private var statusResetWorkItem: DispatchWorkItem?
  private var isCommittingDraft = false

  init(vaultService: VaultService, frame frameRect: NSRect = .zero) {
    self.vaultService = vaultService
    super.init(frame: frameRect)
    buildView()
    textView.string = draftStore.load()
    renderMarkdown()
    updateCharacterCount()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override var isFlipped: Bool {
    true
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    updateBackgroundColor()
    textView.insertionPointColor = .controlAccentColor
    renderMarkdown()
  }

  func focus() {
    window?.makeFirstResponder(textView)
  }

  var text: String {
    textView.string
  }

  func clear() {
    textView.string = ""
    try? draftStore.clear()
    renderMarkdown()
    updateCharacterCount()
  }

  func showStatus(_ status: String) {
    statusResetWorkItem?.cancel()
    characterCountLabel.stringValue = status
    characterCountLabel.textColor = .secondaryLabelColor

    let workItem = DispatchWorkItem { [weak self] in
      self?.updateCharacterCount()
    }
    statusResetWorkItem = workItem
    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: workItem)
  }

  func applyMarkdown(_ command: MarkdownCommand) {
    focus()

    switch command {
    case .heading:
      insertLinePrefix("# ")
    case .bold:
      wrapSelection(prefix: "**", suffix: "**")
    case .italic:
      wrapSelection(prefix: "*", suffix: "*")
    case .bulletList:
      insertLinePrefix("- ")
    case .code:
      wrapSelection(prefix: "`", suffix: "`")
    case .link:
      insertLink()
    }
  }

  func textDidChange(_ notification: Notification) {
    statusResetWorkItem?.cancel()
    persistCurrentDraft()
    renderMarkdown()
    updateCharacterCount()
  }

  func textViewDidChangeSelection(_ notification: Notification) {
    renderMarkdown()
  }

  func commitDraft() {
    guard !isCommittingDraft else {
      return
    }

    persistCurrentDraft()
    let body = textView.string
    guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      try? draftStore.clear()
      return
    }

    isCommittingDraft = true
    defer {
      isCommittingDraft = false
    }
    characterCountLabel.stringValue = "Saving..."

    do {
      let result = try vaultService.saveCapture(body: body, source: "macos-app")
      clearDraftIfUnchanged(body)
      updateSaveStatus(result)
    } catch {
      updateSaveFailure(error)
    }
  }

  func commitDraftBeforeExit() {
    guard !isCommittingDraft else {
      return
    }

    persistCurrentDraft()
    let body = textView.string
    guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      try? draftStore.clear()
      return
    }

    do {
      let result = try vaultService.saveCapture(body: body, source: "macos-app")
      clearDraftIfUnchanged(body)
      updateSaveStatus(result)
    } catch {
      updateSaveFailure(error)
    }
  }

  private func buildView() {
    wantsLayer = true
    updateBackgroundColor()

    scrollView.drawsBackground = false
    scrollView.hasVerticalScroller = true
    scrollView.hasHorizontalScroller = false
    scrollView.autohidesScrollers = true
    scrollView.translatesAutoresizingMaskIntoConstraints = false

    textView.delegate = self
    textView.string = ""
    textView.font = .systemFont(ofSize: 21, weight: .regular)
    textView.textColor = .labelColor
    textView.backgroundColor = .clear
    textView.insertionPointColor = .controlAccentColor
    textView.isRichText = false
    textView.importsGraphics = false
    textView.allowsUndo = true
    textView.usesFindPanel = true
    textView.isAutomaticDashSubstitutionEnabled = false
    textView.isAutomaticQuoteSubstitutionEnabled = false
    textView.isAutomaticTextReplacementEnabled = false
    textView.isVerticallyResizable = true
    textView.isHorizontallyResizable = false
    textView.minSize = NSSize(width: 0, height: 0)
    textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    textView.textContainerInset = NSSize(width: 36, height: 72)
    textView.textContainer?.widthTracksTextView = true
    textView.textContainer?.containerSize = NSSize(
      width: CGFloat.greatestFiniteMagnitude,
      height: CGFloat.greatestFiniteMagnitude
    )
    textView.typingAttributes = editorTypingAttributes()

    scrollView.documentView = textView

    characterCountLabel.font = .systemFont(ofSize: 13, weight: .medium)
    characterCountLabel.textColor = .tertiaryLabelColor
    characterCountLabel.alignment = .center
    characterCountLabel.translatesAutoresizingMaskIntoConstraints = false

    addSubview(scrollView)
    addSubview(characterCountLabel)

    NSLayoutConstraint.activate([
      scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
      scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
      scrollView.topAnchor.constraint(equalTo: topAnchor),
      scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

      characterCountLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
      characterCountLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -18)
    ])
  }

  private func updateBackgroundColor() {
    effectiveAppearance.performAsCurrentDrawingAppearance {
      layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    }
  }

  private func editorTypingAttributes() -> [NSAttributedString.Key: Any] {
    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.lineSpacing = 5
    paragraphStyle.paragraphSpacing = 12

    return [
      .font: NSFont.systemFont(ofSize: 21, weight: .regular),
      .foregroundColor: NSColor.labelColor,
      .paragraphStyle: paragraphStyle
    ]
  }

  private func renderMarkdown() {
    guard !isRenderingMarkdown, let storage = textView.textStorage else {
      return
    }

    isRenderingMarkdown = true
    let selectedRanges = textView.selectedRanges
    let activeRanges = selectedRanges.map(\.rangeValue)
    let fullRange = NSRange(location: 0, length: storage.length)
    let codeBlockRanges = markdownCodeBlockRanges(in: storage.string as NSString)

    storage.beginEditing()
    if storage.length > 0 {
      storage.setAttributes(editorTypingAttributes(), range: fullRange)
      renderMarkdownBlocks(in: storage, codeBlockRanges: codeBlockRanges, activeRanges: activeRanges)
      renderMarkdownInline(in: storage, skipping: codeBlockRanges, activeRanges: activeRanges)
    }
    storage.endEditing()

    textView.typingAttributes = editorTypingAttributes()
    isRenderingMarkdown = false
  }

  private func renderMarkdownBlocks(
    in storage: NSTextStorage,
    codeBlockRanges: [NSRange],
    activeRanges: [NSRange]
  ) {
    let nsString = storage.string as NSString
    var location = 0

    while location < nsString.length {
      let lineRange = nsString.lineRange(for: NSRange(location: location, length: 0))
      let line = nsString.substring(with: lineRange)
      let tokenAttributes = range(lineRange, containsAnyActive: activeRanges)
        ? markdownTokenAttributes()
        : markdownHiddenTokenAttributes()

      if range(lineRange, intersectsAny: codeBlockRanges) {
        storage.addAttributes(markdownCodeBlockAttributes(), range: lineRange)
      } else if let match = firstMatch("^\\s*(#{1,6})\\s+(.+)$", in: line) {
        let level = min(match.range(at: 1).length, 6)
        let markerRange = shifted(match.range(at: 1), by: lineRange.location)
        let contentRange = shifted(match.range(at: 2), by: lineRange.location)
        storage.addAttributes(tokenAttributes, range: markerRange)
        storage.addAttributes(markdownHeadingAttributes(level: level), range: contentRange)
      } else if let match = firstMatch("^\\s{0,3}>\\s?(.+)$", in: line) {
        storage.addAttributes(markdownBlockQuoteAttributes(), range: lineRange)
        storage.addAttributes(tokenAttributes, range: shifted(NSRange(location: 0, length: 1), by: lineRange.location))
        storage.addAttributes([.font: markdownItalicFont()], range: shifted(match.range(at: 1), by: lineRange.location))
      } else if let match = firstMatch("^\\s*([-*+])\\s+(\\[[ xX]\\])\\s+(.+)$", in: line) {
        let isActive = range(lineRange, containsAnyActive: activeRanges)
        let markerRange = shifted(match.range(at: 1), by: lineRange.location)
        let checkboxRange = shifted(match.range(at: 2), by: lineRange.location)
        let contentRange = shifted(match.range(at: 3), by: lineRange.location)
        storage.addAttributes(markdownListAttributes(), range: lineRange)
        storage.addAttributes(isActive ? markdownBulletAttributes() : markdownRenderedBulletAttributes(), range: markerRange)
        storage.addAttributes(
          isActive ? markdownBulletAttributes() : markdownHiddenTokenAttributes(),
          range: checkboxRange
        )
        if line.contains("[x]") || line.contains("[X]") {
          storage.addAttributes(markdownCompletedTaskAttributes(), range: contentRange)
        }
      } else if let match = firstMatch("^\\s*([-*+])\\s+(.+)$", in: line) {
        storage.addAttributes(markdownListAttributes(), range: lineRange)
        let isActive = range(lineRange, containsAnyActive: activeRanges)
        storage.addAttributes(
          isActive ? markdownBulletAttributes() : markdownRenderedBulletAttributes(),
          range: shifted(match.range(at: 1), by: lineRange.location)
        )
      } else if let match = firstMatch("^\\s*(\\d+[.)])\\s+(.+)$", in: line) {
        storage.addAttributes(markdownListAttributes(), range: lineRange)
        storage.addAttributes(
          range(lineRange, containsAnyActive: activeRanges) ? markdownBulletAttributes() : markdownHiddenTokenAttributes(),
          range: shifted(match.range(at: 1), by: lineRange.location)
        )
      } else if firstMatch("^\\s{0,3}(([-*_])\\s*){3,}$", in: line) != nil {
        storage.addAttributes(
          range(lineRange, containsAnyActive: activeRanges) ? markdownRuleAttributes() : markdownHiddenTokenAttributes(),
          range: lineRange
        )
      }

      location = NSMaxRange(lineRange)
    }
  }

  private func renderMarkdownInline(
    in storage: NSTextStorage,
    skipping skippedRanges: [NSRange],
    activeRanges: [NSRange]
  ) {
    applyInlineStyle(
      pattern: "`([^`\\n]+)`",
      in: storage,
      skipping: skippedRanges,
      activeRanges: activeRanges,
      contentAttributes: markdownInlineCodeAttributes(),
      tokenGroups: [0],
      contentGroups: [1]
    )

    applyInlineStyle(
      pattern: "!\\[([^\\]\\n]*)\\]\\(([^)\\n]+)\\)",
      in: storage,
      skipping: skippedRanges,
      activeRanges: activeRanges,
      contentAttributes: markdownLinkAttributes(),
      tokenGroups: [0],
      contentGroups: [1]
    )

    applyInlineStyle(
      pattern: "\\[([^\\]\\n]+)\\]\\(([^)\\n]+)\\)",
      in: storage,
      skipping: skippedRanges,
      activeRanges: activeRanges,
      contentAttributes: markdownLinkAttributes(),
      tokenGroups: [0],
      contentGroups: [1]
    )

    applyInlineStyle(
      pattern: "(\\*\\*|__)(.+?)\\1",
      in: storage,
      skipping: skippedRanges,
      activeRanges: activeRanges,
      contentAttributes: [
        .font: markdownBoldFont(),
        .foregroundColor: NSColor.labelColor
      ],
      tokenGroups: [0],
      contentGroups: [2]
    )

    applyInlineStyle(
      pattern: "(~~)(.+?)\\1",
      in: storage,
      skipping: skippedRanges,
      activeRanges: activeRanges,
      contentAttributes: [
        .font: markdownBodyFont(),
        .foregroundColor: NSColor.labelColor,
        .strikethroughStyle: NSUnderlineStyle.single.rawValue
      ],
      tokenGroups: [0],
      contentGroups: [2]
    )

    applyInlineStyle(
      pattern: "(?<!\\*)\\*(?!\\*)([^*\\n]+)(?<!\\*)\\*(?!\\*)",
      in: storage,
      skipping: skippedRanges,
      activeRanges: activeRanges,
      contentAttributes: [
        .font: markdownItalicFont(),
        .foregroundColor: NSColor.labelColor
      ],
      tokenGroups: [0],
      contentGroups: [1]
    )

    applyInlineStyle(
      pattern: "(?<!_)_(?!_)([^_\\n]+)(?<!_)_(?!_)",
      in: storage,
      skipping: skippedRanges,
      activeRanges: activeRanges,
      contentAttributes: [
        .font: markdownItalicFont(),
        .foregroundColor: NSColor.labelColor
      ],
      tokenGroups: [0],
      contentGroups: [1]
    )
  }

  private func applyInlineStyle(
    pattern: String,
    in storage: NSTextStorage,
    skipping skippedRanges: [NSRange],
    activeRanges: [NSRange],
    contentAttributes: [NSAttributedString.Key: Any],
    tokenGroups: [Int],
    contentGroups: [Int]
  ) {
    guard let regex = try? NSRegularExpression(pattern: pattern) else {
      return
    }

    let nsString = storage.string as NSString
    let fullRange = NSRange(location: 0, length: nsString.length)
    let matches = regex.matches(in: storage.string, range: fullRange)

    for match in matches where !range(match.range, intersectsAny: skippedRanges) {
      let tokenAttributes = range(match.range, containsAnyActive: activeRanges)
        ? markdownTokenAttributes()
        : markdownHiddenTokenAttributes()

      for group in tokenGroups {
        let tokenRange = match.range(at: group)
        if tokenRange.location != NSNotFound {
          storage.addAttributes(tokenAttributes, range: tokenRange)
        }
      }

      for group in contentGroups {
        let contentRange = match.range(at: group)
        if contentRange.location != NSNotFound {
          storage.addAttributes(contentAttributes, range: contentRange)
        }
      }
    }
  }

  private func markdownCodeBlockRanges(in nsString: NSString) -> [NSRange] {
    var ranges: [NSRange] = []
    var blockStart: Int?
    var location = 0

    while location < nsString.length {
      let lineRange = nsString.lineRange(for: NSRange(location: location, length: 0))
      let line = nsString.substring(with: lineRange)

      if firstMatch("^\\s*(```|~~~)", in: line) != nil {
        if let start = blockStart {
          ranges.append(NSRange(location: start, length: NSMaxRange(lineRange) - start))
          blockStart = nil
        } else {
          blockStart = lineRange.location
        }
      }

      location = NSMaxRange(lineRange)
    }

    if let start = blockStart {
      ranges.append(NSRange(location: start, length: nsString.length - start))
    }

    return ranges
  }

  private func firstMatch(_ pattern: String, in string: String) -> NSTextCheckingResult? {
    guard let regex = try? NSRegularExpression(pattern: pattern) else {
      return nil
    }

    return regex.firstMatch(
      in: string,
      range: NSRange(location: 0, length: (string as NSString).length)
    )
  }

  private func shifted(_ range: NSRange, by offset: Int) -> NSRange {
    NSRange(location: range.location + offset, length: range.length)
  }

  private func range(_ range: NSRange, intersectsAny ranges: [NSRange]) -> Bool {
    ranges.contains { NSIntersectionRange(range, $0).length > 0 }
  }

  private func range(_ range: NSRange, containsAnyActive activeRanges: [NSRange]) -> Bool {
    activeRanges.contains { activeRange in
      if activeRange.length > 0 {
        return NSIntersectionRange(range, activeRange).length > 0
      }

      return activeRange.location > range.location && activeRange.location < NSMaxRange(range)
    }
  }

  private func markdownBodyFont() -> NSFont {
    NSFont.systemFont(ofSize: 21, weight: .regular)
  }

  private func markdownBoldFont() -> NSFont {
    NSFont.systemFont(ofSize: 21, weight: .semibold)
  }

  private func markdownItalicFont() -> NSFont {
    NSFontManager.shared.convert(markdownBodyFont(), toHaveTrait: .italicFontMask)
  }

  private func markdownMonospaceFont() -> NSFont {
    NSFont.monospacedSystemFont(ofSize: 19, weight: .regular)
  }

  private func markdownHeadingAttributes(level: Int) -> [NSAttributedString.Key: Any] {
    let sizes: [CGFloat] = [34, 30, 26, 23, 21, 20]
    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.paragraphSpacingBefore = level <= 2 ? 20 : 14
    paragraphStyle.paragraphSpacing = 14
    paragraphStyle.lineSpacing = 3

    return [
      .font: NSFont.systemFont(ofSize: sizes[level - 1], weight: .bold),
      .foregroundColor: NSColor.labelColor,
      .paragraphStyle: paragraphStyle
    ]
  }

  private func markdownTokenAttributes() -> [NSAttributedString.Key: Any] {
    [
      .foregroundColor: NSColor.tertiaryLabelColor,
      .font: NSFont.monospacedSystemFont(ofSize: 17, weight: .regular)
    ]
  }

  private func markdownHiddenTokenAttributes() -> [NSAttributedString.Key: Any] {
    [
      .foregroundColor: NSColor.clear,
      .font: NSFont.systemFont(ofSize: 1, weight: .regular)
    ]
  }

  private func markdownBulletAttributes() -> [NSAttributedString.Key: Any] {
    [
      .foregroundColor: NSColor.controlAccentColor,
      .font: NSFont.systemFont(ofSize: 22, weight: .bold)
    ]
  }

  private func markdownRenderedBulletAttributes() -> [NSAttributedString.Key: Any] {
    var attributes: [NSAttributedString.Key: Any] = [
      .foregroundColor: NSColor.controlAccentColor,
      .font: NSFont.systemFont(ofSize: 22, weight: .bold)
    ]

    if let glyphInfo = NSGlyphInfo(
      glyphName: "bullet",
      for: NSFont.systemFont(ofSize: 22, weight: .bold),
      baseString: "-"
    ) {
      attributes[.glyphInfo] = glyphInfo
    }

    return attributes
  }

  private func markdownListAttributes() -> [NSAttributedString.Key: Any] {
    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.lineSpacing = 5
    paragraphStyle.paragraphSpacing = 8
    paragraphStyle.headIndent = 28
    paragraphStyle.firstLineHeadIndent = 0

    return [.paragraphStyle: paragraphStyle]
  }

  private func markdownBlockQuoteAttributes() -> [NSAttributedString.Key: Any] {
    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.lineSpacing = 5
    paragraphStyle.paragraphSpacing = 10
    paragraphStyle.headIndent = 20
    paragraphStyle.firstLineHeadIndent = 20

    return [
      .foregroundColor: NSColor.secondaryLabelColor,
      .paragraphStyle: paragraphStyle
    ]
  }

  private func markdownRuleAttributes() -> [NSAttributedString.Key: Any] {
    [
      .foregroundColor: NSColor.tertiaryLabelColor,
      .font: NSFont.monospacedSystemFont(ofSize: 18, weight: .medium)
    ]
  }

  private func markdownInlineCodeAttributes() -> [NSAttributedString.Key: Any] {
    [
      .font: markdownMonospaceFont(),
      .foregroundColor: NSColor.systemPink,
      .backgroundColor: NSColor.controlBackgroundColor.withAlphaComponent(0.8)
    ]
  }

  private func markdownCodeBlockAttributes() -> [NSAttributedString.Key: Any] {
    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.lineSpacing = 3
    paragraphStyle.paragraphSpacing = 0

    return [
      .font: markdownMonospaceFont(),
      .foregroundColor: NSColor.labelColor,
      .backgroundColor: NSColor.controlBackgroundColor.withAlphaComponent(0.8),
      .paragraphStyle: paragraphStyle
    ]
  }

  private func markdownLinkAttributes() -> [NSAttributedString.Key: Any] {
    [
      .font: markdownBodyFont(),
      .foregroundColor: NSColor.systemBlue,
      .underlineStyle: NSUnderlineStyle.single.rawValue
    ]
  }

  private func markdownCompletedTaskAttributes() -> [NSAttributedString.Key: Any] {
    [
      .foregroundColor: NSColor.secondaryLabelColor,
      .strikethroughStyle: NSUnderlineStyle.single.rawValue
    ]
  }

  private func updateCharacterCount() {
    let count = textView.string.count
    let unit = count == 1 ? "character" : "characters"
    characterCountLabel.stringValue = "\(count) \(unit)"
    characterCountLabel.textColor = .tertiaryLabelColor
  }

  private func persistCurrentDraft() {
    do {
      if textView.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        try draftStore.clear()
      } else {
        try draftStore.save(textView.string)
      }
    } catch {
      characterCountLabel.stringValue = "Draft could not be saved"
    }
  }

  private func clearDraftIfUnchanged(_ committedBody: String) {
    guard textView.string == committedBody else {
      persistCurrentDraft()
      return
    }

    textView.string = ""
    try? draftStore.clear()
    renderMarkdown()
  }

  private func updateSaveStatus(_ result: CaptureRecord) {
    characterCountLabel.stringValue = "Saved \(result.id)"
  }

  private func updateSaveFailure(_ error: Error) {
    let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    characterCountLabel.stringValue = message.isEmpty
      ? "Could not save. Draft kept."
      : "Could not save. Draft kept."
  }

  private func wrapSelection(prefix: String, suffix: String) {
    let range = textView.selectedRange()
    let selectedText = (textView.string as NSString).substring(with: range)
    let replacement = prefix + selectedText + suffix
    replace(range, with: replacement)

    if selectedText.isEmpty {
      textView.setSelectedRange(NSRange(location: range.location + prefix.count, length: 0))
    } else {
      textView.setSelectedRange(NSRange(location: range.location, length: replacement.count))
    }
  }

  private func insertLinePrefix(_ prefix: String) {
    let nsString = textView.string as NSString
    let range = textView.selectedRange()
    let lineRange = nsString.lineRange(for: NSRange(location: range.location, length: 0))
    replace(NSRange(location: lineRange.location, length: 0), with: prefix)
    textView.setSelectedRange(NSRange(location: range.location + prefix.count, length: range.length))
  }

  private func insertLink() {
    let range = textView.selectedRange()
    let selectedText = (textView.string as NSString).substring(with: range)
    let label = selectedText.isEmpty ? "link" : selectedText
    let replacement = "[\(label)](url)"
    replace(range, with: replacement)

    let urlLocation = range.location + label.count + 3
    textView.setSelectedRange(NSRange(location: urlLocation, length: 3))
  }

  private func replace(_ range: NSRange, with string: String) {
    guard textView.shouldChangeText(in: range, replacementString: string) else {
      return
    }

    textView.textStorage?.replaceCharacters(in: range, with: string)
    textView.didChangeText()
    textView.typingAttributes = editorTypingAttributes()
  }
}

final class MarkdownTextView: NSTextView {
  override var acceptsFirstResponder: Bool {
    true
  }

  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    if modifiers == .command,
       event.charactersIgnoringModifiers?.lowercased() == "a" {
      selectAll(nil)
      return true
    }

    return super.performKeyEquivalent(with: event)
  }

  override func viewDidMoveToSuperview() {
    super.viewDidMoveToSuperview()
    if let bounds = superview?.bounds {
      frame = bounds
      minSize = bounds.size
    }
    autoresizingMask = [.width]
  }
}
