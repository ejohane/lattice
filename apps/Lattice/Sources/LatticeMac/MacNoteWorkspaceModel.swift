import AppKit
import Combine
import LatticeCore

@MainActor
final class MacNoteWorkspaceModel: ObservableObject {
  @Published var text = ""
  @Published var footerText = "0 characters"
  @Published var needsNotesFolder = false
  @Published var notesFolderPath = ""
  @Published var errorMessage: String?

  let settings = MacAppSettings()

  private let locationStore = MacNotesLocationStore()
  private var activeNote: SavedNote?
  private var lastSavedBody = ""
  private var autosaveTask: Task<Void, Never>?
  private var statusResetTask: Task<Void, Never>?

  init() {
    prepare()
  }

  var defaultNotesFolderURL: URL {
    locationStore.defaultNotesFolderURL
  }

  func prepare() {
    guard let rootURL = usableRootURL() else {
      needsNotesFolder = true
      notesFolderPath = defaultNotesFolderURL.path
      updateFooter()
      return
    }

    needsNotesFolder = false
    notesFolderPath = rootURL.path
    restoreActiveNote()
    updateFooter()
  }

  func useDefaultNotesFolder() {
    selectNotesFolder(defaultNotesFolderURL)
  }

  func chooseNotesFolder() {
    let panel = NSOpenPanel()
    panel.title = "Choose Lattice Notes Folder"
    panel.prompt = "Choose"
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.canCreateDirectories = true
    panel.allowsMultipleSelection = false

    guard panel.runModal() == .OK, let url = panel.url else {
      return
    }

    selectNotesFolder(url)
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
    flushAutosave()
    activeNote = nil
    lastSavedBody = ""
    text = ""
    locationStore.clearActiveNote()
    showStatus("New note")
  }

  func scheduleAutosave() {
    autosaveTask?.cancel()
    autosaveTask = Task { [weak self] in
      try? await Task.sleep(nanoseconds: 800_000_000)
      guard !Task.isCancelled else {
        return
      }
      self?.save(showSaveStatus: true)
    }
    updateFooter()
  }

  func flushAutosave() {
    autosaveTask?.cancel()
    autosaveTask = nil
    save(showSaveStatus: false)
  }

  func save(showSaveStatus: Bool) {
    autosaveTask?.cancel()
    autosaveTask = nil

    let body = normalized(text)
    guard activeNote != nil || !body.isEmpty else {
      updateFooter()
      return
    }
    guard body != lastSavedBody else {
      updateFooter()
      return
    }
    guard let store = noteStore() else {
      needsNotesFolder = true
      return
    }

    do {
      let note: SavedNote
      if let activeNote {
        note = try store.updateNote(activeNote, body: body)
      } else {
        note = try store.createNote(body: body)
      }
      activeNote = note
      lastSavedBody = body
      locationStore.setActiveNoteURL(note.url)
      if showSaveStatus {
        showStatus("Autosaved \(note.title)")
      } else {
        updateFooter()
      }
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func openNotesFolder() {
    guard let rootURL = usableRootURL() else {
      needsNotesFolder = true
      return
    }
    NSWorkspace.shared.open(rootURL)
  }

  func revealCurrentNote() {
    guard
      let noteURL = locationStore.activeNoteURL(),
      FileManager.default.fileExists(atPath: noteURL.path)
    else {
      NSSound.beep()
      return
    }

    NSWorkspace.shared.activateFileViewerSelecting([noteURL])
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
      let body = try noteStore()?.body(for: note) ?? ""
      activeNote = note
      lastSavedBody = normalized(body)
      text = body
      showStatus(note.title)
    } catch {
      locationStore.clearActiveNote()
    }
  }

  private func usableRootURL() -> URL? {
    guard let rootURL = locationStore.activeNotesFolderURL() else {
      return nil
    }
    return NoteStore.validateNotesFolder(at: rootURL).isUsable ? rootURL : nil
  }

  private func noteStore() -> NoteStore? {
    guard let rootURL = usableRootURL() else {
      return nil
    }
    return NoteStore(rootURL: rootURL)
  }

  private func normalized(_ body: String) -> String {
    body.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func showStatus(_ status: String) {
    statusResetTask?.cancel()
    footerText = status
    statusResetTask = Task { [weak self] in
      try? await Task.sleep(nanoseconds: 2_000_000_000)
      guard !Task.isCancelled else {
        return
      }
      self?.updateFooter()
    }
  }

  private func updateFooter() {
    let count = text.count
    let unit = count == 1 ? "character" : "characters"
    footerText = "\(count) \(unit)"
  }
}
