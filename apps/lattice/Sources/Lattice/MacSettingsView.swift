import KeyboardShortcuts
import SwiftUI

struct MacSettingsView: View {
  let shortcutSettings: MacKeyboardShortcutSettings

  var body: some View {
    Form {
      Section("Keyboard Shortcuts") {
        shortcutRow("Today’s Note", command: .todayNote)

        Text("Create or open today’s daily note while Lattice is active.")
          .font(.caption)
          .foregroundStyle(.secondary)

        Divider()

        shortcutRow("Jot", command: .jot)

        Text("Use Jot from any app while Lattice is running.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
    .frame(width: 460, height: 260)
  }

  private func shortcutRow(
    _ title: String,
    command: MacKeyboardShortcutSettings.Command
  ) -> some View {
    LabeledContent(title) {
      HStack(spacing: 8) {
        KeyboardShortcuts.Recorder(
          for: shortcutSettings.name(for: command)
        ) { shortcut in
          shortcutSettings.setShortcut(shortcut, for: command)
        }

        Button("Reset") {
          shortcutSettings.resetShortcut(for: command)
        }
      }
    }
  }
}
