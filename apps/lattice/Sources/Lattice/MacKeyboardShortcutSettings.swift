import AppKit
import KeyboardShortcuts
import Observation
import SwiftUI

extension KeyboardShortcuts.Name {
  static let showJot = Self(
    "showJot",
    default: .init(.j, modifiers: [.command, .option, .control])
  )

  static let openTodayNote = Self(
    "openTodayNote",
    default: .init(.d, modifiers: [.command, .shift])
  )
}

@MainActor
@Observable
final class MacKeyboardShortcutSettings {
  enum Command: CaseIterable {
    case todayNote
    case jot
  }

  private let names: [Command: KeyboardShortcuts.Name]

  private(set) var todayNoteShortcut: KeyboardShortcuts.Shortcut?
  private(set) var jotShortcut: KeyboardShortcuts.Shortcut?

  init(
    todayNoteName: KeyboardShortcuts.Name = .openTodayNote,
    jotName: KeyboardShortcuts.Name = .showJot
  ) {
    names = [
      .todayNote: todayNoteName,
      .jot: jotName
    ]

    let todayShortcut = KeyboardShortcuts.getShortcut(for: todayNoteName)
    let jotShortcut = KeyboardShortcuts.getShortcut(for: jotName)
    if let todayShortcut, todayShortcut == jotShortcut {
      // Preserve an existing customized Jot shortcut when the newly introduced
      // Today’s Note default happens to collide with it.
      KeyboardShortcuts.setShortcut(nil, for: todayNoteName)
    }

    self.todayNoteShortcut = KeyboardShortcuts.getShortcut(for: todayNoteName)
    self.jotShortcut = KeyboardShortcuts.getShortcut(for: jotName)
  }

  func name(for command: Command) -> KeyboardShortcuts.Name {
    names[command]!
  }

  func shortcut(for command: Command) -> KeyboardShortcuts.Shortcut? {
    switch command {
    case .todayNote:
      todayNoteShortcut
    case .jot:
      jotShortcut
    }
  }

  func setShortcut(
    _ shortcut: KeyboardShortcuts.Shortcut?,
    for command: Command
  ) {
    KeyboardShortcuts.setShortcut(shortcut, for: name(for: command))

    if let shortcut {
      for otherCommand in Command.allCases where otherCommand != command {
        let otherName = name(for: otherCommand)
        if KeyboardShortcuts.getShortcut(for: otherName) == shortcut {
          KeyboardShortcuts.setShortcut(nil, for: otherName)
        }
      }
    }

    reload()
  }

  func resetShortcut(for command: Command) {
    setShortcut(name(for: command).defaultShortcut, for: command)
  }

  func matches(_ event: NSEvent, command: Command) -> Bool {
    guard !event.isARepeat,
          let eventShortcut = KeyboardShortcuts.Shortcut(event: event)
    else {
      return false
    }
    return eventShortcut == shortcut(for: command)
  }

  private func reload() {
    todayNoteShortcut = KeyboardShortcuts.getShortcut(for: name(for: .todayNote))
    jotShortcut = KeyboardShortcuts.getShortcut(for: name(for: .jot))
  }
}

@MainActor
struct MacLocalKeyboardShortcutMonitor {
  static func handle(
    _ event: NSEvent,
    settings: MacKeyboardShortcutSettings,
    canOpenTodayNote: Bool,
    openTodayNote: () -> Void
  ) -> Bool {
    guard canOpenTodayNote,
          settings.matches(event, command: .todayNote)
    else {
      return false
    }

    openTodayNote()
    return true
  }
}

struct MacLocalKeyboardShortcutMonitorView: NSViewRepresentable {
  let settings: MacKeyboardShortcutSettings
  let canOpenTodayNote: Bool
  let openTodayNote: @MainActor () -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator(parent: self)
  }

  func makeNSView(context: Context) -> NSView {
    let view = NSView(frame: .zero)
    context.coordinator.attach(to: view)
    return view
  }

  func updateNSView(_ nsView: NSView, context: Context) {
    context.coordinator.parent = self
  }

  static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
    coordinator.stop()
  }

  final class Coordinator {
    var parent: MacLocalKeyboardShortcutMonitorView
    private weak var view: NSView?
    private var monitor: Any?

    init(parent: MacLocalKeyboardShortcutMonitorView) {
      self.parent = parent
    }

    deinit {
      if let monitor {
        NSEvent.removeMonitor(monitor)
      }
    }

    @MainActor
    func attach(to view: NSView) {
      self.view = view
      monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
        var handled = false
        MainActor.assumeIsolated {
          guard let self,
                let mainWindow = self.view?.window,
                event.window === mainWindow || event.window?.sheetParent === mainWindow
          else {
            return
          }
          handled = MacLocalKeyboardShortcutMonitor.handle(
            event,
            settings: self.parent.settings,
            canOpenTodayNote: self.parent.canOpenTodayNote,
            openTodayNote: self.parent.openTodayNote
          )
        }
        return handled ? nil : event
      }
    }

    @MainActor
    func stop() {
      guard let monitor else { return }
      NSEvent.removeMonitor(monitor)
      self.monitor = nil
    }
  }
}
