import Foundation
import Testing
@testable import LatticeCore

@Suite("NoteStore")
struct NoteStoreTests {
  @Test("initializes a notes folder")
  func initializesNotesFolder() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }

    try fixture.store.initializeNotesFolder(at: fixture.root)

    #expect(fixture.fileManager.fileExists(atPath: fixture.root.path))
    #expect(fixture.fileManager.fileExists(atPath: fixture.root.appendingPathComponent("notes").path))
    #expect(!fixture.fileManager.fileExists(atPath: fixture.root.appendingPathComponent("config.json").path))
    #expect(!fixture.fileManager.fileExists(atPath: fixture.root.appendingPathComponent("raw").path))
  }

  @Test("creates a timestamped markdown note")
  func createsTimestampedMarkdownNote() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }

    try fixture.store.selectNotesFolder(fixture.root)
    let note = try fixture.store.createNote(body: "Hello\n\nWorld", now: fixture.date)

    #expect(note.url.path.hasSuffix("/notes/2026-06-17/2026-06-17T14-32-10.md"))
    #expect(try String(contentsOf: note.url, encoding: .utf8) == "Hello\n\nWorld\n")
    #expect(fixture.store.activeNoteURL()?.path == note.url.path)
  }

  @Test("updates the active markdown note in place")
  func updatesMarkdownNote() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }

    try fixture.store.selectNotesFolder(fixture.root)
    let note = try fixture.store.createNote(body: "First", now: fixture.date)
    let updated = try fixture.store.updateNote(note, body: "Second")

    #expect(updated.url == note.url)
    #expect(try String(contentsOf: note.url, encoding: .utf8) == "Second\n")
  }

  @Test("lists markdown notes grouped by date newest first")
  func listsNotesGroupedByDate() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }

    try fixture.store.selectNotesFolder(fixture.root)
    let notesURL = fixture.root.appendingPathComponent("notes", isDirectory: true)
    let olderDateURL = notesURL.appendingPathComponent("2026-06-16", isDirectory: true)
    let newerDateURL = notesURL.appendingPathComponent("2026-06-17", isDirectory: true)
    try fixture.fileManager.createDirectory(at: olderDateURL, withIntermediateDirectories: true)
    try fixture.fileManager.createDirectory(at: newerDateURL, withIntermediateDirectories: true)
    try "Older\n".write(
      to: olderDateURL.appendingPathComponent("2026-06-16T10-00-00.md"),
      atomically: true,
      encoding: .utf8
    )
    try "Newest\n".write(
      to: newerDateURL.appendingPathComponent("2026-06-17T15-00-00.md"),
      atomically: true,
      encoding: .utf8
    )
    try "Earlier\n".write(
      to: newerDateURL.appendingPathComponent("2026-06-17T09-00-00.md"),
      atomically: true,
      encoding: .utf8
    )
    try "Ignored\n".write(
      to: newerDateURL.appendingPathComponent("not-markdown.txt"),
      atomically: true,
      encoding: .utf8
    )

    let sections = try fixture.store.listNotes()

    #expect(sections.map(\.dateString) == ["2026-06-17", "2026-06-16"])
    #expect(sections[0].notes.map(\.title) == ["2026-06-17T15-00-00", "2026-06-17T09-00-00"])
    #expect(sections[1].notes.map(\.title) == ["2026-06-16T10-00-00"])
  }

  @Test("opens an existing note and marks it active")
  func opensExistingNote() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }

    try fixture.store.selectNotesFolder(fixture.root)
    let note = try fixture.store.createNote(body: "Open me", now: fixture.date)
    fixture.store.clearActiveNote()

    let opened = try fixture.store.openNote(note)

    #expect(opened == note)
    #expect(try fixture.store.body(for: opened) == "Open me\n")
    #expect(fixture.store.activeNoteURL()?.path == note.url.path)
  }

  @Test("allows clearing an existing markdown note")
  func allowsClearingExistingMarkdownNote() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }

    try fixture.store.selectNotesFolder(fixture.root)
    let note = try fixture.store.createNote(body: "First", now: fixture.date)
    let updated = try fixture.store.updateNote(note, body: "")

    #expect(updated.url == note.url)
    #expect(try String(contentsOf: note.url, encoding: .utf8) == "")
    #expect(fixture.store.activeNoteURL()?.path == note.url.path)
  }

  @Test("restores active note when the file exists")
  func restoresActiveNote() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }

    try fixture.store.selectNotesFolder(fixture.root)
    let note = try fixture.store.createNote(body: "Restored", now: fixture.date)

    let restored = fixture.store.restoreActiveNote()

    #expect(restored == note)
    #expect(try fixture.store.body(for: note) == "Restored\n")
  }

  @Test("editing session creates once and then updates in place")
  func editingSessionCreatesAndUpdatesNote() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }

    try fixture.store.selectNotesFolder(fixture.root)
    let session = NoteEditingSession(store: fixture.store)

    #expect(try session.save(body: "   \n") == .skippedEmptyDraft)
    guard case .saved(let note) = try session.save(body: "First") else {
      Issue.record("Expected first non-empty save to create a note")
      return
    }
    guard case .saved(let updated) = try session.save(body: "Second") else {
      Issue.record("Expected changed body to update the active note")
      return
    }

    #expect(updated == note)
    #expect(try String(contentsOf: note.url, encoding: .utf8) == "Second\n")
    #expect(try session.save(body: "Second") == .unchanged)
  }

  @Test("editing session allows clearing an active note")
  func editingSessionAllowsClearingActiveNote() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }

    try fixture.store.selectNotesFolder(fixture.root)
    let session = NoteEditingSession(store: fixture.store)
    guard case .saved(let note) = try session.save(body: "First") else {
      Issue.record("Expected first non-empty save to create a note")
      return
    }

    #expect(try session.save(body: "") == .saved(note))
    #expect(try String(contentsOf: note.url, encoding: .utf8) == "")
    #expect(session.savedBody == "")
  }

  @Test("editing session restores the active note body")
  func editingSessionRestoresActiveNote() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }

    try fixture.store.selectNotesFolder(fixture.root)
    let note = try fixture.store.createNote(body: "Restored session", now: fixture.date)
    let session = NoteEditingSession(store: fixture.store)

    let restored = try session.restoreActiveNote()

    #expect(restored?.note == note)
    #expect(restored?.body == "Restored session\n")
    #expect(session.currentNote == note)
    #expect(session.savedBody == "Restored session")
  }

  @Test("rejects empty notes")
  func rejectsEmptyNotes() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }

    try fixture.store.selectNotesFolder(fixture.root)

    #expect(throws: NoteStoreError.emptyNote) {
      _ = try fixture.store.createNote(body: "   \n\t", now: fixture.date)
    }
  }
}

private struct Fixture {
  let root: URL
  let store: NoteStore
  let defaults: UserDefaults
  let suiteName: String
  let fileManager = FileManager.default
  let date: Date

  init() throws {
    root = FileManager.default.temporaryDirectory
      .appendingPathComponent("lattice-note-store-\(UUID().uuidString)", isDirectory: true)
    suiteName = "lattice-note-store-\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
      throw FixtureError.defaultsUnavailable
    }
    self.defaults = defaults
    store = NoteStore(defaults: defaults, fileManager: fileManager)

    var components = DateComponents()
    components.calendar = Calendar(identifier: .gregorian)
    components.timeZone = TimeZone.current
    components.year = 2026
    components.month = 6
    components.day = 17
    components.hour = 14
    components.minute = 32
    components.second = 10
    guard let date = components.date else {
      throw FixtureError.dateUnavailable
    }
    self.date = date
  }

  func cleanup() {
    try? fileManager.removeItem(at: root)
    defaults.removePersistentDomain(forName: suiteName)
  }
}

private enum FixtureError: Error {
  case defaultsUnavailable
  case dateUnavailable
}

@Suite("MarkdownTextEditing")
struct MarkdownTextEditingTests {
  @Test("wraps a selected range")
  func wrapsSelection() {
    let result = MarkdownTextEditing.apply(
      .bold,
      to: "Hello world",
      selection: NSRange(location: 6, length: 5)
    )

    #expect(result.body == "Hello **world**")
    #expect(result.selection == NSRange(location: 6, length: 9))
  }

  @Test("inserts line prefixes at the active line")
  func insertsLinePrefix() {
    let result = MarkdownTextEditing.apply(
      .bulletList,
      to: "One\nTwo",
      selection: NSRange(location: 5, length: 0)
    )

    #expect(result.body == "One\n- Two")
    #expect(result.selection == NSRange(location: 7, length: 0))
  }
}
