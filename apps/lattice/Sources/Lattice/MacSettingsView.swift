import KeyboardShortcuts
import SwiftUI

extension KeyboardShortcuts.Name {
  static let showJot = Self(
    "showJot",
    default: .init(.j, modifiers: [.command, .option, .control])
  )
}

struct MacSettingsView: View {
  var body: some View {
    Form {
      Section("Jot") {
        LabeledContent("Global shortcut") {
          Text("⌘⌥⌃J")
            .monospaced()
        }

        Text("Use this shortcut from any app while Lattice is running.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
    .frame(width: 420, height: 150)
  }
}
