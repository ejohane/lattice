import Combine
import Foundation
import LatticeCore
import LatticeEditor

@MainActor
final class IOSNoteWorkspaceModel: ObservableObject {
  @Published var text = ""
  @Published var footerText = "Choose a notes folder"
  @Published var needsNotesFolder = true
  @Published var notesFolderPath = ""
  @Published var errorMessage: String?
  @Published var pendingCommand: MarkdownCommand?

  private let locationStore = IOSNotesLocationStore()
  private var activeNote: SavedNote?
  private var lastSavedBody = ""

  init() {
    prepare()
  }

  func prepare() {
    guard let rootURL = locationStore.activeNotesFolderURL(),
          NoteStore.validateNotesFolder(at: rootURL).isUsable else {
      needsNotesFolder = true
      footerText = "Choose a notes folder"
      return
    }

    needsNotesFolder = false
    notesFolderPath = rootURL.path
    restoreActiveNote()
    updateFooter()
  }

  func selectNotesFolder(_ url: URL) {
    do {
      try locationStore.selectNotesFolder(url)
      activeNote = nil
      lastSavedBody = ""
      text = ""
      prepare()
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func startNewNote() {
    save(showStatus: false)
    activeNote = nil
    lastSavedBody = ""
    text = ""
    locationStore.clearActiveNote()
    footerText = "New note"
  }

  func save(showStatus: Bool = true) {
    let body = normalized(text)
    guard activeNote != nil || !body.isEmpty else {
      updateFooter()
      return
    }
    guard body != lastSavedBody else {
      updateFooter()
      return
    }

    do {
      guard let note = try locationStore.withActiveNotesFolder({ rootURL -> SavedNote in
        let store = NoteStore(rootURL: rootURL)
        if let activeNote {
          return try store.updateNote(activeNote, body: body)
        }
        return try store.createNote(body: body)
      }) else {
        needsNotesFolder = true
        return
      }

      activeNote = note
      lastSavedBody = body
      locationStore.setActiveNoteURL(note.url)
      footerText = showStatus ? "Saved \(note.title)" : footerText
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func apply(_ command: MarkdownCommand) {
    pendingCommand = command
  }

  private func restoreActiveNote() {
    guard
      let noteURL = locationStore.activeNoteURL(),
      FileManager.default.fileExists(atPath: noteURL.path)
    else {
      locationStore.clearActiveNote()
      return
    }

    do {
      let note = SavedNote(url: noteURL)
      let body = try String(contentsOf: noteURL, encoding: .utf8)
      activeNote = note
      text = body
      lastSavedBody = normalized(body)
      footerText = note.title
    } catch {
      locationStore.clearActiveNote()
    }
  }

  private func normalized(_ body: String) -> String {
    body.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func updateFooter() {
    let count = text.count
    let unit = count == 1 ? "character" : "characters"
    footerText = "\(count) \(unit)"
  }
}
