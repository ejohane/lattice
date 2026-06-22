import LatticeEditor
import SwiftUI

struct MacAppCommands: Commands {
  @ObservedObject var model: MacNoteWorkspaceModel
  let updater: SparkleUpdater

  var body: some Commands {
    CommandGroup(replacing: .newItem) {
      Button("New Note") {
        model.startNewNote()
      }
      .keyboardShortcut("n")
    }

    CommandGroup(after: .newItem) {
      Divider()

      Button("Open Notes Folder") {
        model.openNotesFolder()
      }
      .keyboardShortcut("o")

      Button("Reveal Current Note") {
        model.revealCurrentNote()
      }
      .keyboardShortcut("r")

      Button("Change Notes Folder...") {
        model.needsNotesFolder = true
      }
    }

    CommandMenu("Format") {
      Button("Heading") {
        MacMarkdownTextView.send(.heading)
      }
      Button("Bold") {
        MacMarkdownTextView.send(.bold)
      }
      .keyboardShortcut("b")
      Button("Italic") {
        MacMarkdownTextView.send(.italic)
      }
      .keyboardShortcut("i")
      Button("Bulleted List") {
        MacMarkdownTextView.send(.bulletList)
      }
      Button("Inline Code") {
        MacMarkdownTextView.send(.code)
      }
      Button("Link") {
        MacMarkdownTextView.send(.link)
      }
      .keyboardShortcut("k")
    }

    CommandGroup(after: .appSettings) {
      if updater.canCheckForUpdates {
        Button("Check for Updates...") {
          updater.checkForUpdates()
        }
      }
    }
  }
}
