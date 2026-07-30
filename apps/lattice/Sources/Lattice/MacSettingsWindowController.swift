import AppKit
import SwiftUI

@MainActor
final class MacSettingsWindowController: NSWindowController {
  init() {
    let contentView = NSHostingView(rootView: MacSettingsView())
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 420, height: 150),
      styleMask: [.titled, .closable, .miniaturizable],
      backing: .buffered,
      defer: false
    )
    window.title = "Settings"
    window.contentView = contentView
    window.isReleasedWhenClosed = false
    super.init(window: window)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func present() {
    guard let window else { return }
    NSApp.activate(ignoringOtherApps: true)
    if window.isVisible {
      window.makeKeyAndOrderFront(nil)
    } else {
      window.center()
      showWindow(nil)
      window.makeKeyAndOrderFront(nil)
    }
    window.orderFrontRegardless()
  }
}
