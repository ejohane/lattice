import Foundation
import LatticeCore
import Testing

@Suite("NoteLibrary")
struct NoteLibraryTests {
  @Test("initializes a notes folder without metadata sidecars")
  func initializesNotesFolder() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }

    try fixture.library.initializeNotesFolder(at: fixture.root)

    #expect(fixture.fileManager.fileExists(atPath: fixture.root.path))
    #expect(fixture.fileManager.fileExists(atPath: fixture.root.appendingPathComponent("notes").path))
    #expect(!fixture.fileManager.fileExists(atPath: fixture.root.appendingPathComponent("config.json").path))
    #expect(!fixture.fileManager.fileExists(atPath: fixture.root.appendingPathComponent(".lattice").path))
  }

  @Test("recommends app-owned iCloud Drive folder when available")
  func recommendsICloudFolderWhenAvailable() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }
    let iCloudRoot = fixture.root.appendingPathComponent("ubiquity", isDirectory: true)
    let library = NoteLibrary(
      defaults: fixture.defaults,
      fileManager: fixture.fileManager,
      iCloudContainerURLProvider: { iCloudRoot }
    )

    #expect(library.recommendedNotesFolder == .iCloud(
      iCloudRoot
        .appendingPathComponent("Documents", isDirectory: true)
        .appendingPathComponent("Lattice", isDirectory: true)
    ))
  }

  @Test("falls back to local documents folder when iCloud Drive is unavailable")
  func fallsBackWhenICloudUnavailable() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }
    let library = NoteLibrary(
      defaults: fixture.defaults,
      fileManager: fixture.fileManager,
      iCloudContainerURLProvider: { nil }
    )

    #expect(library.recommendedNotesFolder == .localFallback(library.fallbackNotesFolderURL))
  }

  @Test("migrates local fallback notes into iCloud without overwriting cloud notes")
  func migratesFallbackNotesToICloud() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }
    let fallbackRoot = fixture.root.appendingPathComponent("local", isDirectory: true)
    let iCloudRoot = fixture.root.appendingPathComponent("ubiquity", isDirectory: true)
    let library = NoteLibrary(
      defaults: fixture.defaults,
      fileManager: fixture.fileManager,
      fallbackNotesFolderURLProvider: { fallbackRoot },
      iCloudContainerURLProvider: { iCloudRoot }
    )
    let fallbackDateURL = fallbackRoot
      .appendingPathComponent("notes", isDirectory: true)
      .appendingPathComponent("2026-06-17", isDirectory: true)
    let iCloudDateURL = iCloudRoot
      .appendingPathComponent("notes", isDirectory: true)
      .appendingPathComponent("2026-06-17", isDirectory: true)
    try fixture.fileManager.createDirectory(at: fallbackDateURL, withIntermediateDirectories: true)
    try fixture.fileManager.createDirectory(at: iCloudDateURL, withIntermediateDirectories: true)
    try "Local\n".write(
      to: fallbackDateURL.appendingPathComponent("local.md"),
      atomically: true,
      encoding: .utf8
    )
    try "Existing cloud\n".write(
      to: iCloudDateURL.appendingPathComponent("conflict.md"),
      atomically: true,
      encoding: .utf8
    )
    try "Local conflict\n".write(
      to: fallbackDateURL.appendingPathComponent("conflict.md"),
      atomically: true,
      encoding: .utf8
    )

    try library.migrateFallbackNotesToICloudIfNeeded(iCloudFolderURL: iCloudRoot)

    #expect(try String(
      contentsOf: iCloudDateURL.appendingPathComponent("local.md"),
      encoding: .utf8
    ) == "Local\n")
    #expect(try String(
      contentsOf: iCloudDateURL.appendingPathComponent("conflict.md"),
      encoding: .utf8
    ) == "Existing cloud\n")
  }

  @Test("creates timestamped markdown notes under date folders")
  func createsTimestampedMarkdownNote() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }

    try fixture.library.selectNotesFolder(fixture.root)
    let note = try fixture.library.createNote(body: "Hello\n\nWorld", now: fixture.date)

    #expect(note.url.path.hasSuffix("/notes/2026-06-17/2026-06-17T14-32-10.md"))
    #expect(try fixture.library.body(for: note) == "Hello\n\nWorld\n")
    #expect(MarkdownDocumentMetadata.noteID(in: try String(contentsOf: note.url, encoding: .utf8)) != nil)
    #expect(fixture.library.activeNoteURL()?.path == note.url.path)
  }

  @Test("editing session creates once then autosaves in place")
  func editingSessionAutosavesInPlace() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }

    try fixture.library.selectNotesFolder(fixture.root)
    let session = NoteEditingSession(library: fixture.library)

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
    #expect(try fixture.library.body(for: note) == "Second\n")
    #expect(try session.save(body: "Second") == .unchanged)
  }

  @Test("editing session preserves in-progress list marker spacing")
  func editingSessionPreservesInProgressListMarkerSpacing() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }

    try fixture.library.selectNotesFolder(fixture.root)
    let session = NoteEditingSession(library: fixture.library)

    guard case .saved(let note) = try session.save(body: "- item") else {
      Issue.record("Expected first list item to create a note")
      return
    }

    #expect(try session.save(body: "- item\n- ") == .saved(note))
    #expect(try fixture.library.body(for: note) == "- item\n- \n")
    #expect(try session.save(body: "- item\n- ") == .unchanged)

    #expect(NoteEditingSession.normalizedBody("- [x] item\n- [ ] ") == "- [x] item\n- [ ] ")
    #expect(NoteEditingSession.normalizedBody("   \n") == "")
  }

  @Test("active note state is per defaults store")
  func activeNoteStateIsPerDevice() throws {
    let firstDevice = try Fixture()
    let secondDevice = try Fixture(root: firstDevice.root)
    defer {
      firstDevice.cleanup()
      secondDevice.cleanupDefaultsOnly()
    }

    try firstDevice.library.selectNotesFolder(firstDevice.root)
    let note = try firstDevice.library.createNote(body: "Device one", now: firstDevice.date)
    try secondDevice.library.selectNotesFolder(firstDevice.root)

    #expect(firstDevice.library.restoreActiveNote() == note)
    #expect(secondDevice.library.restoreActiveNote() == nil)
  }

  @Test("lists markdown notes grouped by date newest first")
  func listsNotesGroupedByDate() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }

    try fixture.library.selectNotesFolder(fixture.root)
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
    try "Ignored\n".write(
      to: newerDateURL.appendingPathComponent("not-markdown.txt"),
      atomically: true,
      encoding: .utf8
    )

    let sections = try fixture.library.listNotes()

    #expect(sections.map(\.dateString) == ["2026-06-17", "2026-06-16"])
    #expect(sections[0].notes.map(\.filenameTitle) == ["2026-06-17T15-00-00"])
    #expect(sections[1].notes.map(\.filenameTitle) == ["2026-06-16T10-00-00"])
  }

  @Test("uses first rendered line as display title")
  func displayTitleUsesFirstRenderedLine() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }

    try fixture.library.selectNotesFolder(fixture.root)
    let note = try fixture.library.createNote(
      body: "\n**Project Brief** [draft](https://example.com)\n\n## Ignored Heading",
      now: fixture.date
    )

    #expect(note.url.path.hasSuffix("/notes/2026-06-17/2026-06-17T14-32-10.md"))
    #expect(fixture.library.displayTitle(for: note) == "Project Brief draft")
  }

  @Test("strips block markdown from rendered display titles")
  func displayTitleStripsBlockMarkdown() throws {
    #expect(NoteLibrary.firstRenderedLine(in: "# Heading <!-- lattice:heading=abc -->") == "Heading")
    #expect(NoteLibrary.firstRenderedLine(in: "- [ ] Buy **milk**") == "Buy milk")
    #expect(NoteLibrary.firstRenderedLine(in: "> [[Daily Note#Tasks|Tasks]]") == "Tasks")
    #expect(NoteLibrary.firstRenderedLine(in: "\n---\n\n2026-06-17T14-32-10") == "2026-06-17T14-32-10")
  }

  @Test("rejects empty first notes")
  func rejectsEmptyNotes() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }

    try fixture.library.selectNotesFolder(fixture.root)

    #expect(throws: NoteLibraryError.emptyNote) {
      _ = try fixture.library.createNote(body: "   \n\t", now: fixture.date)
    }
  }

  @Test("deletes markdown notes and clears active note state")
  func deletesMarkdownNote() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }

    try fixture.library.selectNotesFolder(fixture.root)
    let note = try fixture.library.createNote(body: "Delete me", now: fixture.date)

    try fixture.library.deleteNote(note)

    #expect(!fixture.fileManager.fileExists(atPath: note.url.path))
    #expect(fixture.library.activeNoteURL() == nil)
    #expect(try fixture.library.listNotes().isEmpty)
  }
}

private struct Fixture {
  let root: URL
  let library: NoteLibrary
  let defaults: UserDefaults
  let suiteName: String
  let fileManager = FileManager.default
  let date: Date
  private let ownsRoot: Bool

  init(root: URL? = nil) throws {
    if let root {
      self.root = root
      self.ownsRoot = false
    } else {
      self.root = FileManager.default.temporaryDirectory
        .appendingPathComponent("lattice-note-library-\(UUID().uuidString)", isDirectory: true)
      self.ownsRoot = true
    }
    suiteName = "lattice-note-library-\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
      throw FixtureError.defaultsUnavailable
    }
    self.defaults = defaults
    library = NoteLibrary(defaults: defaults, fileManager: fileManager)

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
    if ownsRoot {
      try? fileManager.removeItem(at: root)
    }
    cleanupDefaultsOnly()
  }

  func cleanupDefaultsOnly() {
    defaults.removePersistentDomain(forName: suiteName)
  }
}

private enum FixtureError: Error {
  case defaultsUnavailable
  case dateUnavailable
}
