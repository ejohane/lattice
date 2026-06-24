import Foundation
import LatticeCore
import LatticeShared
import Testing

@MainActor
@Suite("LatticeAppModel")
struct LatticeAppModelTests {
  @Test("drives choose folder, autosave, list, and reopen flow")
  func drivesFirstMilestoneNoteFlow() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }
    let model = LatticeAppModel(
      noteLibrary: fixture.library,
      folderAccessStore: fixture.folderAccessStore
    )

    try fixture.fileManager.createDirectory(at: fixture.root, withIntermediateDirectories: true)
    model.chooseFolder(fixture.root)
    #expect(model.hasFolder)
    #expect(model.sections.isEmpty)

    model.text = "# Universal Note\n\nBody"
    model.flushAutosave()

    let sections = model.sections
    #expect(sections.count == 1)
    let section = try #require(sections.first)
    #expect(section.notes.count == 1)
    let note = try #require(section.notes.first)
    #expect(note.url.path.contains("/notes/"))
    #expect(note.url.lastPathComponent.hasSuffix(".md"))
    #expect(try String(contentsOf: note.url, encoding: .utf8) == "# Universal Note\n\nBody\n")
    #expect(model.displayTitle(for: note) == "Universal Note")

    model.createNewNote()
    #expect(model.text == "")
    model.open(note)
    #expect(model.text == "# Universal Note\n\nBody\n")
  }

  @Test("adjusts editor font size with app-style bounds")
  func adjustsEditorFontSize() throws {
    let defaultsSuiteName = "font-size-\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: defaultsSuiteName) else {
      throw FixtureError.defaultsUnavailable
    }
    defer {
      defaults.removePersistentDomain(forName: defaultsSuiteName)
    }

    let model = LatticeAppModel(
      noteLibrary: NoteLibrary(defaults: defaults),
      folderAccessStore: FolderAccessStore(defaults: defaults)
    )

    #expect(model.editorFontSize == 14)

    model.increaseEditorFontSize()
    #expect(model.editorFontSize == 15)

    model.decreaseEditorFontSize()
    #expect(model.editorFontSize == 14)

    model.resetEditorFontSize()
    #expect(model.editorFontSize == 14)

    for _ in 0..<30 {
      model.decreaseEditorFontSize()
    }
    #expect(model.editorFontSize == 10)
    #expect(!model.canDecreaseEditorFontSize)

    for _ in 0..<30 {
      model.increaseEditorFontSize()
    }
    #expect(model.editorFontSize == 28)
    #expect(!model.canIncreaseEditorFontSize)
  }

  @Test("command palette only exposes update checking without a folder")
  func commandPaletteCommandsWithoutFolder() throws {
    let defaultsSuiteName = "command-palette-setup-\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: defaultsSuiteName) else {
      throw FixtureError.defaultsUnavailable
    }
    defer {
      defaults.removePersistentDomain(forName: defaultsSuiteName)
    }

    let model = LatticeAppModel(
      noteLibrary: NoteLibrary(defaults: defaults),
      folderAccessStore: FolderAccessStore(defaults: defaults)
    )
    let platformCommands = [
      CommandPaletteCommand(
        id: "test.checkForUpdates",
        title: "Check for Updates",
        systemImage: "arrow.triangle.2.circlepath"
      ) {}
    ]

    let titles = model.commandPaletteCommands(platformCommands: platformCommands).map(\.title)
    #expect(titles == ["Check for Updates"])
    #expect(titles.contains("Check for Updates"))
    #expect(!titles.contains("New Note"))
  }

  @Test("command palette shows recent notes and filters note switcher results by title")
  func commandPaletteShowsAndFiltersNotesByTitle() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }
    let model = LatticeAppModel(
      noteLibrary: fixture.library,
      folderAccessStore: fixture.folderAccessStore,
      noteIndex: NoteIndex(appSupportURL: fixture.appSupportURL)
    )

    try fixture.fileManager.createDirectory(at: fixture.root, withIntermediateDirectories: true)
    model.chooseFolder(fixture.root)
    model.text = "# Palette Target\n\nBody"
    model.flushAutosave()
    model.createNewNote()
    model.text = "# Another Note\n\nBody"
    model.flushAutosave()

    let recentNotes = model.commandPaletteNotes()
    #expect(recentNotes.count == 2)
    #expect(model.displayTitle(for: try #require(recentNotes.first)) == "Another Note")

    model.commandPaletteQuery = "palette"
    let notes = model.commandPaletteNotes()

    #expect(notes.count == 1)
    let note = try #require(notes.first)
    #expect(model.displayTitle(for: note) == "Palette Target")

    model.commandPaletteQuery = ""
    let commandTitles = model.commandPaletteCommands().map(\.title)
    #expect(commandTitles == ["New Note"])
    #expect(!commandTitles.contains("Heading"))
    #expect(!commandTitles.contains("Bold"))
    #expect(!commandTitles.contains("Italic"))
    #expect(!commandTitles.contains("List"))
    #expect(!commandTitles.contains("Code"))
    #expect(!commandTitles.contains("Link"))
    #expect(!commandTitles.contains("Increase Font Size"))
  }

  @Test("command palette searches indexed note bodies")
  func commandPaletteSearchesIndexedBodies() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }
    let model = LatticeAppModel(
      noteLibrary: fixture.library,
      folderAccessStore: fixture.folderAccessStore,
      noteIndex: NoteIndex(appSupportURL: fixture.appSupportURL)
    )

    try fixture.fileManager.createDirectory(at: fixture.root, withIntermediateDirectories: true)
    model.chooseFolder(fixture.root)
    model.text = "# Indexed Title\n\nBody has nebula phrase"
    model.flushAutosave()

    model.commandPaletteQuery = "nebula"
    let notes = model.commandPaletteNotes()

    #expect(notes.count == 1)
    #expect(model.displayTitle(for: try #require(notes.first)) == "Indexed Title")
  }

  @Test("index failure does not block markdown autosave")
  func indexFailureDoesNotBlockAutosave() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }
    let model = LatticeAppModel(
      noteLibrary: fixture.library,
      folderAccessStore: fixture.folderAccessStore,
      noteIndex: FailingNoteIndex()
    )

    try fixture.fileManager.createDirectory(at: fixture.root, withIntermediateDirectories: true)
    model.chooseFolder(fixture.root)
    model.text = "# Still Saves\n\nBody"
    model.flushAutosave()

    let section = try #require(model.sections.first)
    let note = try #require(section.notes.first)
    #expect(try String(contentsOf: note.url, encoding: .utf8) == "# Still Saves\n\nBody\n")

    model.commandPaletteQuery = "still"
    let fallbackNotes = model.commandPaletteNotes()
    #expect(fallbackNotes.count == 1)
  }
}

private struct Fixture {
  let root: URL
  let appSupportURL: URL
  let library: NoteLibrary
  let folderAccessStore: FolderAccessStore
  let defaults: UserDefaults
  let suiteName: String
  let fileManager = FileManager.default

  init() throws {
    root = FileManager.default.temporaryDirectory
      .appendingPathComponent("lattice-app-model-\(UUID().uuidString)", isDirectory: true)
    appSupportURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("lattice-app-model-index-\(UUID().uuidString)", isDirectory: true)
    suiteName = "lattice-app-model-\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
      throw FixtureError.defaultsUnavailable
    }
    self.defaults = defaults
    library = NoteLibrary(defaults: defaults, fileManager: fileManager)
    folderAccessStore = FolderAccessStore(defaults: defaults)
  }

  func cleanup() {
    try? fileManager.removeItem(at: root)
    try? fileManager.removeItem(at: appSupportURL)
    defaults.removePersistentDomain(forName: suiteName)
  }
}

private enum FixtureError: Error {
  case defaultsUnavailable
}

private final class FailingNoteIndex: NoteIndexing {
  func rebuild(notesFolderURL: URL) throws {
    throw FixtureError.defaultsUnavailable
  }

  func refresh(note: SavedNote, notesFolderURL: URL) throws {
    throw FixtureError.defaultsUnavailable
  }

  func recentNotes(notesFolderURL: URL, limit: Int) throws -> [SavedNote] {
    throw FixtureError.defaultsUnavailable
  }

  func searchNotes(query: String, notesFolderURL: URL, limit: Int) throws -> [SavedNote] {
    throw FixtureError.defaultsUnavailable
  }
}
