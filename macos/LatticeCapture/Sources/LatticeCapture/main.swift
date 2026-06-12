import AppKit
import Carbon.HIToolbox

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private let settings = AppSettings()
  private var statusItem: NSStatusItem?
  private var hotKey: GlobalHotKey?
  private var panelController: CapturePanelController?

  func applicationDidFinishLaunching(_ notification: Notification) {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    item.button?.title = "L"
    item.button?.font = .systemFont(ofSize: 13, weight: .semibold)
    item.menu = makeMenu()
    statusItem = item

    let captureService = LatticeCaptureService(settings: settings) { [weak self] state in
      self?.setStatus(state)
    }

    panelController = CapturePanelController(
      settings: settings,
      captureService: captureService
    )
    hotKey = GlobalHotKey { [weak self] in
      self?.panelController?.toggle()
    }
    hotKey?.register()

    if ProcessInfo.processInfo.environment["LATTICE_CAPTURE_SHOW_ON_LAUNCH"] == "1" {
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
        self?.panelController?.show()
      }
    }
  }

  func applicationWillTerminate(_ notification: Notification) {
    hotKey?.unregister()
  }

  private func makeMenu() -> NSMenu {
    let menu = NSMenu()
    menu.addItem(NSMenuItem(
      title: "Capture",
      action: #selector(showCapture),
      keyEquivalent: ""
    ))
    menu.addItem(NSMenuItem.separator())

    let screenshotItem = NSMenuItem(
      title: "Include Screenshot",
      action: #selector(toggleScreenshot),
      keyEquivalent: ""
    )
    screenshotItem.state = settings.includeScreenshot ? .on : .off
    menu.addItem(screenshotItem)

    menu.addItem(NSMenuItem(
      title: "Settings...",
      action: #selector(openSettings),
      keyEquivalent: ","
    ))
    menu.addItem(NSMenuItem.separator())
    menu.addItem(NSMenuItem(
      title: "Quit Lattice Capture",
      action: #selector(NSApplication.terminate(_:)),
      keyEquivalent: "q"
    ))
    return menu
  }

  @objc private func showCapture() {
    panelController?.show()
  }

  @objc private func toggleScreenshot(_ sender: NSMenuItem) {
    settings.includeScreenshot.toggle()
    sender.state = settings.includeScreenshot ? .on : .off
  }

  @objc private func openSettings() {
    SettingsDialog(settings: settings).show()
  }

  private func setStatus(_ state: CaptureStatus) {
    guard let button = statusItem?.button else {
      return
    }

    switch state {
    case .idle:
      button.title = "L"
    case .saving:
      button.title = "..."
    case .saved:
      button.title = "✓"
      DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
        self?.setStatus(.idle)
      }
    case .failed:
      button.title = "!"
      DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { [weak self] in
        self?.setStatus(.idle)
      }
    }
  }
}

final class GlobalHotKey {
  private var hotKeyRef: EventHotKeyRef?
  private var handlerRef: EventHandlerRef?
  private let action: @MainActor @Sendable () -> Void

  init(action: @escaping @MainActor @Sendable () -> Void) {
    self.action = action
  }

  func register() {
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

    InstallEventHandler(
      GetApplicationEventTarget(),
      callback,
      1,
      &eventType,
      selfPointer,
      &handlerRef
    )

    let hotKeyID = EventHotKeyID(
      signature: fourCharCode("LATT"),
      id: 1
    )
    RegisterEventHotKey(
      UInt32(kVK_Space),
      UInt32(controlKey | optionKey),
      hotKeyID,
      GetApplicationEventTarget(),
      0,
      &hotKeyRef
    )
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
}

private func fourCharCode(_ string: String) -> OSType {
  var result: UInt32 = 0
  for scalar in string.unicodeScalars.prefix(4) {
    result = (result << 8) + scalar.value
  }
  return result
}

final class AppSettings {
  private let defaults = UserDefaults.standard

  var latticePath: String {
    get {
      defaults.string(forKey: "latticePath") ?? "lattice"
    }
    set {
      defaults.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "latticePath")
    }
  }

  var vaultPath: String {
    get {
      defaults.string(forKey: "vaultPath") ?? ""
    }
    set {
      defaults.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "vaultPath")
    }
  }

  var includeScreenshot: Bool {
    get {
      if defaults.object(forKey: "includeScreenshot") == nil {
        return true
      }
      return defaults.bool(forKey: "includeScreenshot")
    }
    set {
      defaults.set(newValue, forKey: "includeScreenshot")
    }
  }
}

enum CaptureStatus {
  case idle
  case saving
  case saved
  case failed
}

enum CaptureRunResult {
  case success
  case failure(String)
}

struct CaptureConfiguration: Sendable {
  let latticePath: String
  let vaultPath: String
  let includeScreenshot: Bool
}

@MainActor
final class CapturePanelController: NSWindowController {
  private let settings: AppSettings
  private let captureService: LatticeCaptureService
  private let inputField = CaptureTextField()
  private weak var previousApp: NSRunningApplication?
  private var keyMonitor: Any?

  init(settings: AppSettings, captureService: LatticeCaptureService) {
    self.settings = settings
    self.captureService = captureService

    let window = CaptureWindow(
      contentRect: NSRect(x: 0, y: 0, width: 760, height: 82),
      styleMask: [.titled, .fullSizeContentView],
      backing: .buffered,
      defer: false
    )
    window.level = .floating
    window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
    window.isMovableByWindowBackground = false
    window.backgroundColor = .clear
    window.isOpaque = false
    window.hasShadow = true
    window.titleVisibility = .hidden
    window.titlebarAppearsTransparent = true
    window.isReleasedWhenClosed = false
    window.standardWindowButton(.closeButton)?.isHidden = true
    window.standardWindowButton(.miniaturizeButton)?.isHidden = true
    window.standardWindowButton(.zoomButton)?.isHidden = true

    super.init(window: window)
    window.onSubmit = { [weak self] in
      self?.submit()
    }
    window.onCancel = { [weak self] in
      self?.hide()
    }
    buildContent()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func toggle() {
    if window?.isVisible == true {
      hide()
    } else {
      show()
    }
  }

  func show() {
    previousApp = NSWorkspace.shared.frontmostApplication
    guard let window else {
      return
    }

    inputField.stringValue = ""
    centerWindow(window)
    installKeyMonitor()
    window.alphaValue = 0
    NSApp.setActivationPolicy(.regular)
    window.orderFrontRegardless()

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self, weak window] in
      guard let self, let window else {
        return
      }
      NSApp.activate(ignoringOtherApps: true)
      window.makeKeyAndOrderFront(nil)
      window.makeFirstResponder(self.inputField)
      self.inputField.selectText(nil)
      self.inputField.currentEditor()?.selectedRange = NSRange(
        location: self.inputField.stringValue.count,
        length: 0
      )
    }

    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.08
      window.animator().alphaValue = 1
    }
  }

  func hide() {
    guard let window else {
      return
    }
    removeKeyMonitor()
    window.orderOut(nil)
    NSApp.setActivationPolicy(.accessory)
  }

  private func buildContent() {
    guard let window else {
      return
    }

    let root = NSVisualEffectView()
    root.material = .popover
    root.blendingMode = .behindWindow
    root.state = .active
    root.wantsLayer = true
    root.layer?.cornerRadius = 32
    root.layer?.cornerCurve = .continuous
    root.layer?.borderWidth = 0
    root.layer?.borderColor = nil
    root.translatesAutoresizingMaskIntoConstraints = false

    inputField.onSubmit = { [weak self] in
      self?.submit()
    }
    inputField.onCancel = { [weak self] in
      self?.hide()
    }
    inputField.placeholderString = "Capture..."
    inputField.font = .systemFont(ofSize: 28, weight: .regular)
    inputField.textColor = .labelColor
    inputField.isEditable = true
    inputField.isSelectable = true
    inputField.isEnabled = true
    inputField.isBordered = false
    inputField.isBezeled = false
    inputField.drawsBackground = false
    inputField.focusRingType = .none
    inputField.lineBreakMode = .byTruncatingTail
    inputField.usesSingleLineMode = true
    inputField.cell?.wraps = false
    inputField.cell?.isScrollable = true
    inputField.translatesAutoresizingMaskIntoConstraints = false

    window.contentView = root
    root.addSubview(inputField)

    NSLayoutConstraint.activate([
      root.widthAnchor.constraint(equalToConstant: 760),
      root.heightAnchor.constraint(equalToConstant: 82),
      inputField.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 34),
      inputField.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -34),
      inputField.centerYAnchor.constraint(equalTo: root.centerYAnchor),
      inputField.heightAnchor.constraint(equalToConstant: 36),
    ])
  }

  private func submit() {
    let note = inputField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !note.isEmpty else {
      NSSound.beep()
      return
    }

    hide()
    previousApp?.activate()

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { [captureService, settings] in
      captureService.capture(note: note, includeScreenshot: settings.includeScreenshot)
    }
  }

  private func installKeyMonitor() {
    removeKeyMonitor()
    keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard let self, self.window?.isVisible == true else {
        return event
      }

      if event.keyCode == 53 {
        self.hide()
        return nil
      }

      let isReturn = event.keyCode == 36 || event.keyCode == 76
      let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
      if isReturn && modifiers.contains(.command) {
        self.submit()
        return nil
      }

      return event
    }
  }

  private func removeKeyMonitor() {
    if let keyMonitor {
      NSEvent.removeMonitor(keyMonitor)
      self.keyMonitor = nil
    }
  }

  private func centerWindow(_ window: NSWindow) {
    let screen = NSScreen.main ?? NSScreen.screens.first
    guard let frame = screen?.visibleFrame else {
      window.center()
      return
    }

    let origin = NSPoint(
      x: frame.midX - window.frame.width / 2,
      y: frame.midY - window.frame.height / 2
    )
    window.setFrameOrigin(origin)
  }
}

final class CaptureWindow: NSWindow {
  var onSubmit: (() -> Void)?
  var onCancel: (() -> Void)?

  override var canBecomeKey: Bool {
    true
  }

  override var canBecomeMain: Bool {
    true
  }

  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    if event.keyCode == 53 {
      onCancel?()
      return true
    }

    let isReturn = event.keyCode == 36 || event.keyCode == 76
    let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    if isReturn && modifiers.contains(.command) {
      onSubmit?()
      return true
    }

    return super.performKeyEquivalent(with: event)
  }
}

final class CaptureTextField: NSTextField {
  var onSubmit: (() -> Void)?
  var onCancel: (() -> Void)?

  override var acceptsFirstResponder: Bool {
    true
  }

  override func becomeFirstResponder() -> Bool {
    let became = super.becomeFirstResponder()
    currentEditor()?.selectedRange = NSRange(location: stringValue.count, length: 0)
    return became
  }

  override func keyDown(with event: NSEvent) {
    if event.keyCode == 53 {
      onCancel?()
      return
    }

    let isReturn = event.keyCode == 36 || event.keyCode == 76
    if isReturn && event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command) {
      onSubmit?()
      return
    }

    super.keyDown(with: event)
  }
}

final class LatticeCaptureService {
  private let settings: AppSettings
  private let status: @MainActor @Sendable (CaptureStatus) -> Void

  init(settings: AppSettings, status: @escaping @MainActor @Sendable (CaptureStatus) -> Void) {
    self.settings = settings
    self.status = status
  }

  @MainActor
  func capture(note: String, includeScreenshot: Bool) {
    status(.saving)
    let configuration = CaptureConfiguration(
      latticePath: settings.latticePath.isEmpty ? "lattice" : settings.latticePath,
      vaultPath: settings.vaultPath,
      includeScreenshot: includeScreenshot
    )
    let status = status
    DispatchQueue.global(qos: .userInitiated).async {
      let result = Self.runCapture(note: note, configuration: configuration)
      DispatchQueue.main.async {
        switch result {
        case .success:
          status(.saved)
        case .failure(let message):
          status(.failed)
          Self.presentFailure(message)
        }
      }
    }
  }

  private static func runCapture(note: String, configuration: CaptureConfiguration) -> CaptureRunResult {
    let process = Process()
    let latticePath = configuration.latticePath

    if latticePath.contains("/") {
      process.executableURL = URL(fileURLWithPath: expandingTilde(in: latticePath))
      process.arguments = captureArguments(includeScreenshot: configuration.includeScreenshot)
    } else {
      process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
      process.arguments = [latticePath] + captureArguments(includeScreenshot: configuration.includeScreenshot)
    }

    var environment = ProcessInfo.processInfo.environment
    environment["PATH"] = defaultPath(environment["PATH"])
    let vaultPath = configuration.vaultPath
    if !vaultPath.isEmpty {
      environment["LATTICE_VAULT_PATH"] = expandingTilde(in: vaultPath)
    }
    process.environment = environment

    let input = Pipe()
    let output = Pipe()
    let error = Pipe()
    process.standardInput = input
    process.standardOutput = output
    process.standardError = error

    do {
      try process.run()
      input.fileHandleForWriting.write(Data(note.utf8))
      try input.fileHandleForWriting.close()
      process.waitUntilExit()
    } catch {
      return .failure("Could not run lattice: \(error.localizedDescription)")
    }

    if process.terminationStatus == 0 {
      return .success
    }

    let stderr = String(data: error.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let stdout = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return .failure(stderr ?? stdout ?? "lattice capture failed.")
  }

  private static func captureArguments(includeScreenshot: Bool) -> [String] {
    var arguments = ["capture", "--stdin", "--source", "mac-app", "--json"]
    if !includeScreenshot {
      arguments.append("--no-screenshot")
    }
    return arguments
  }

  @MainActor
  private static func presentFailure(_ message: String) {
    let alert = NSAlert()
    alert.messageText = "Capture failed"
    alert.informativeText = message
    alert.alertStyle = .warning
    alert.runModal()
  }
}

@MainActor
final class SettingsDialog {
  private let settings: AppSettings

  init(settings: AppSettings) {
    self.settings = settings
  }

  func show() {
    let cliField = NSTextField(string: settings.latticePath)
    cliField.placeholderString = "lattice"
    let vaultField = NSTextField(string: settings.vaultPath)
    vaultField.placeholderString = "Optional vault path"

    let stack = NSStackView(views: [
      labeledField(label: "Lattice CLI", field: cliField),
      labeledField(label: "Vault Path", field: vaultField)
    ])
    stack.orientation = .vertical
    stack.spacing = 10
    stack.edgeInsets = NSEdgeInsets(top: 4, left: 0, bottom: 0, right: 0)

    let alert = NSAlert()
    alert.messageText = "Lattice Capture Settings"
    alert.informativeText = "Global hotkey: Control-Option-Space. Save capture: Command-Return."
    alert.accessoryView = stack
    alert.addButton(withTitle: "Save")
    alert.addButton(withTitle: "Cancel")

    if alert.runModal() == .alertFirstButtonReturn {
      settings.latticePath = cliField.stringValue.isEmpty ? "lattice" : cliField.stringValue
      settings.vaultPath = vaultField.stringValue
    }
  }

  private func labeledField(label: String, field: NSTextField) -> NSView {
    let labelView = NSTextField(labelWithString: label)
    labelView.font = .systemFont(ofSize: 12, weight: .medium)
    labelView.textColor = .secondaryLabelColor
    field.frame.size.width = 360

    let stack = NSStackView(views: [labelView, field])
    stack.orientation = .vertical
    stack.spacing = 4
    return stack
  }
}

private func expandingTilde(in path: String) -> String {
  if path == "~" {
    return FileManager.default.homeDirectoryForCurrentUser.path
  }

  if path.hasPrefix("~/") {
    return FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(String(path.dropFirst(2)))
      .path
  }

  return path
}

private func defaultPath(_ existing: String?) -> String {
  let commonPaths = [
    FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin").path,
    "/opt/homebrew/bin",
    "/usr/local/bin",
    "/usr/bin",
    "/bin",
    "/usr/sbin",
    "/sbin"
  ]

  guard let existing, !existing.isEmpty else {
    return commonPaths.joined(separator: ":")
  }

  return ([existing] + commonPaths).joined(separator: ":")
}
