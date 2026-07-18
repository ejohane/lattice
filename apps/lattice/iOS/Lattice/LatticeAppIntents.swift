import AppIntents
import LatticeShared

struct CaptureNoteIntent: AppIntent {
  static let title: LocalizedStringResource = "Capture Note"
  static let description = IntentDescription("Save text as a new Markdown note in Lattice.")

  @available(iOS, introduced: 16.0, obsoleted: 26.0)
  static var openAppWhenRun: Bool { false }

  @available(iOS 26.0, *)
  static var supportedModes: IntentModes { .background }

  @Parameter(
    title: "Text",
    description: "The text to save as a new note."
  )
  var text: String

  static var parameterSummary: some ParameterSummary {
    Summary("Capture note")
  }

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog {
    let fileName = try LatticeQuickCapture.save(text: text)
    return .result(dialog: "Captured \(fileName) in Lattice.")
  }
}

struct LatticeAppShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(
      intent: CaptureNoteIntent(),
      phrases: [
        "Capture in \(.applicationName)",
        "Save a note in \(.applicationName)",
      ],
      shortTitle: "Capture Note",
      systemImageName: "square.and.pencil"
    )
  }

  static let shortcutTileColor: ShortcutTileColor = .navy
}
