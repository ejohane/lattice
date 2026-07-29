import AppKit
import SwiftUI

@MainActor
final class MacJotWindowController: NSObject, NSWindowDelegate {
  private let model: MacMarkdownAppModel
  private var window: NSWindow?
  private var previousApplication: NSRunningApplication?

  init(model: MacMarkdownAppModel) {
    self.model = model
  }

  func present(restoringPreviousApplicationOnDismiss: Bool) {
    if restoringPreviousApplicationOnDismiss {
      rememberFrontmostApplication()
    }

    let window = window ?? makeWindow()
    positionOnActiveScreenIfNeeded(window)
    NSApp.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)

    DispatchQueue.main.async { [weak window] in
      guard let window else { return }
      window.makeKey()
      if let editor = window.contentView?.firstDescendant(of: LiveMarkdownTextView.self) {
        window.makeFirstResponder(editor)
      }
    }
  }

  func dismiss() {
    guard let window else { return }

    // Hand activation back before removing the key window. Closing Jot while
    // Lattice is still active briefly promotes the main window, which reads as
    // a flash before the previous application becomes active again.
    restorePreviousApplication()
    window.orderOut(nil)
    window.close()
  }

  func windowWillClose(_ notification: Notification) {
    if let closingWindow = notification.object as? NSWindow, closingWindow === window {
      window = nil
    }

    // Keep this as a fallback for system-driven closes such as Command-W.
    restorePreviousApplication()
  }

  private func makeWindow() -> NSWindow {
    let content = MacJotView(model: model) { [weak self] in
      self?.dismiss()
    }
    let hostingView = NSHostingView(rootView: content)
    let window = NSWindow(
      contentRect: NSRect(
        origin: .zero,
        size: NSSize(width: MacJotMetrics.width, height: MacJotMetrics.height)
      ),
      styleMask: [.titled, .closable, .fullSizeContentView],
      backing: .buffered,
      defer: false
    )

    window.title = "Jot"
    window.titleVisibility = .hidden
    window.titlebarAppearsTransparent = true
    window.isMovableByWindowBackground = true
    window.isReleasedWhenClosed = false
    window.isRestorable = false
    window.hidesOnDeactivate = true
    window.level = .normal
    window.tabbingMode = .disallowed
    window.collectionBehavior.insert(.moveToActiveSpace)
    window.contentMinSize = NSSize(width: MacJotMetrics.width, height: MacJotMetrics.height)
    window.contentMaxSize = NSSize(width: MacJotMetrics.width, height: MacJotMetrics.height)
    window.contentView = hostingView
    window.delegate = self
    window.standardWindowButton(.closeButton)?.isHidden = true
    window.standardWindowButton(.miniaturizeButton)?.isHidden = true
    window.standardWindowButton(.zoomButton)?.isHidden = true

    self.window = window
    return window
  }

  private func rememberFrontmostApplication() {
    guard
      let application = NSWorkspace.shared.frontmostApplication,
      application.processIdentifier != ProcessInfo.processInfo.processIdentifier
    else {
      return
    }

    previousApplication = application
  }

  private func restorePreviousApplication() {
    guard let application = previousApplication else { return }
    previousApplication = nil

    guard !application.isTerminated else { return }
    NSApp.yieldActivation(to: application)
    _ = application.activate(from: .current, options: [])
  }

  private func positionOnActiveScreenIfNeeded(_ window: NSWindow) {
    guard !window.isVisible else { return }

    let mouseLocation = NSEvent.mouseLocation
    let screen = NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) }
      ?? NSScreen.main
    guard let visibleFrame = screen?.visibleFrame else { return }

    let frame = window.frame
    let origin = NSPoint(
      x: visibleFrame.midX - frame.width / 2,
      y: visibleFrame.midY - frame.height / 2
    )
    window.setFrameOrigin(origin)
  }
}

private extension NSView {
  func firstDescendant<ViewType: NSView>(of type: ViewType.Type) -> ViewType? {
    if let match = self as? ViewType {
      return match
    }

    for subview in subviews {
      if let match = subview.firstDescendant(of: type) {
        return match
      }
    }

    return nil
  }
}
