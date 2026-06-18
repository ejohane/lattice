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
