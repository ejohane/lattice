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
}

private struct Fixture {
  let root: URL
  let library: NoteLibrary
  let folderAccessStore: FolderAccessStore
  let defaults: UserDefaults
  let suiteName: String
  let fileManager = FileManager.default

  init() throws {
    root = FileManager.default.temporaryDirectory
      .appendingPathComponent("lattice-app-model-\(UUID().uuidString)", isDirectory: true)
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
    defaults.removePersistentDomain(forName: suiteName)
  }
}

private enum FixtureError: Error {
  case defaultsUnavailable
}
