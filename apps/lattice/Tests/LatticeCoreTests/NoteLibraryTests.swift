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

  @Test("creates flat title-named markdown notes with durable creation metadata")
  func createsFlatTitleNamedMarkdownNote() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }

    try fixture.library.selectNotesFolder(fixture.root)
    let note = try fixture.library.createNote(body: "Hello\n\nWorld", now: fixture.date)

    #expect(note.url.path.hasSuffix("/notes/Hello.md"))
    #expect(try fixture.library.body(for: note) == "Hello\n\nWorld\n")
    let rawBody = try String(contentsOf: note.url, encoding: .utf8)
    #expect(MarkdownDocumentMetadata.noteID(in: rawBody) != nil)
    #expect(MarkdownDocumentMetadata.createdAt(in: rawBody) == fixture.date)
    #expect(fixture.library.activeNoteURL()?.path == note.url.path)

    _ = try fixture.library.updateNote(note, body: "Hello\n\nUpdated")
    let updatedRawBody = try String(contentsOf: note.url, encoding: .utf8)
    #expect(MarkdownDocumentMetadata.createdAt(in: updatedRawBody) == fixture.date)

    let noteID = try #require(MarkdownDocumentMetadata.noteID(in: updatedRawBody))
    _ = try fixture.library.updateNote(note, body: "")
    let clearedRawBody = try String(contentsOf: note.url, encoding: .utf8)
    #expect(MarkdownDocumentMetadata.noteID(in: clearedRawBody) == noteID)
    #expect(MarkdownDocumentMetadata.createdAt(in: clearedRawBody) == fixture.date)
    #expect(try fixture.library.body(for: note).isEmpty)
  }

  @Test("uses stable identity suffixes for duplicate note titles")
  func duplicateTitlesUseStableIdentitySuffixes() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }

    try fixture.library.selectNotesFolder(fixture.root)
    let first = try fixture.library.createNote(body: "# Project Plan", now: fixture.date)
    let second = try fixture.library.createNote(
      body: "# Project Plan\n\nDifferent project",
      now: fixture.date.addingTimeInterval(1)
    )

    #expect(first.filenameTitle == "Project Plan")
    #expect(second.filenameTitle.hasPrefix("Project Plan--"))
    #expect(fixture.library.displayTitle(for: first) == "Project Plan")
    #expect(fixture.library.displayTitle(for: second) == "Project Plan")
    #expect(first.url.deletingLastPathComponent() == second.url.deletingLastPathComponent())
  }

  @Test("renames and deletes inline tags across notes while preserving metadata")
  func rewritesTagsAcrossNotes() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }

    try fixture.library.selectNotesFolder(fixture.root)
    let first = try fixture.library.createNote(body: "# First\n\n#Work and `#work`", now: fixture.date)
    let second = try fixture.library.createNote(
      body: "# Second\n\n#work #project/lattice",
      now: fixture.date.addingTimeInterval(1)
    )
    let firstID = try #require(MarkdownDocumentMetadata.noteID(in: fixture.library.rawBody(for: first)))

    #expect(try fixture.library.rewriteTag(normalizedName: "work", to: "career") == 2)
    #expect(try fixture.library.body(for: first).contains("#career and `#work`"))
    #expect(try fixture.library.body(for: second).contains("#career #project/lattice"))
    #expect(MarkdownDocumentMetadata.noteID(in: try fixture.library.rawBody(for: first)) == firstID)

    #expect(try fixture.library.rewriteTag(normalizedName: "career", to: nil) == 2)
    #expect(try !fixture.library.body(for: second).contains("#career"))
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

  @Test("selecting the same notes folder can preserve active note state")
  func selectingSameNotesFolderCanPreserveActiveNote() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }

    try fixture.library.selectNotesFolder(fixture.root)
    let note = try fixture.library.createNote(body: "Keep open", now: fixture.date)

    try fixture.library.selectNotesFolder(fixture.root, preserveActiveNoteForSameFolder: true)

    #expect(fixture.library.restoreActiveNote() == note)
  }

  @Test("selecting a different notes folder clears active note state even when preserving same-folder state")
  func selectingDifferentNotesFolderClearsActiveNote() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }

    try fixture.library.selectNotesFolder(fixture.root)
    _ = try fixture.library.createNote(body: "Old folder", now: fixture.date)

    let otherRoot = fixture.root.appendingPathComponent("other", isDirectory: true)
    try fixture.library.selectNotesFolder(otherRoot, preserveActiveNoteForSameFolder: true)

    #expect(fixture.library.activeNoteURL() == nil)
    #expect(fixture.library.restoreActiveNote() == nil)
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

    #expect(note.url.path.hasSuffix("/notes/Project Brief draft.md"))
    #expect(fixture.library.displayTitle(for: note) == "Project Brief draft")
  }

  @Test("migrates legacy notes flat while preserving identities and relative references")
  func migratesLegacyNotesFlat() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }
    let backupRoot = fixture.root.appendingPathComponent("migration-backups", isDirectory: true)
    let library = NoteLibrary(
      defaults: fixture.defaults,
      fileManager: fixture.fileManager,
      migrationBackupRootURLProvider: { backupRoot }
    )
    try library.selectNotesFolder(fixture.root)

    let notesURL = fixture.root.appendingPathComponent("notes", isDirectory: true)
    let firstDateURL = notesURL.appendingPathComponent("2026-06-16", isDirectory: true)
    let secondDateURL = notesURL.appendingPathComponent("2026-06-17", isDirectory: true)
    let sourceDateURL = notesURL.appendingPathComponent("2026-06-18", isDirectory: true)
    let attachmentURL = fixture.root
      .appendingPathComponent("attachments/2026-06-18/image.png")
    try fixture.fileManager.createDirectory(at: firstDateURL, withIntermediateDirectories: true)
    try fixture.fileManager.createDirectory(at: secondDateURL, withIntermediateDirectories: true)
    try fixture.fileManager.createDirectory(at: sourceDateURL, withIntermediateDirectories: true)
    try fixture.fileManager.createDirectory(
      at: attachmentURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try Data("image".utf8).write(to: attachmentURL)

    let firstURL = firstDateURL.appendingPathComponent("2026-06-16T10-00-00.md")
    let secondURL = secondDateURL.appendingPathComponent("2026-06-17T10-00-00.md")
    let sourceURL = sourceDateURL.appendingPathComponent("2026-06-18T10-00-00.md")
    try "---\nlattice:\n  id: aaaa1111\n---\n\n# Project Plan\n".write(
      to: firstURL,
      atomically: true,
      encoding: .utf8
    )
    try "---\nlattice:\n  id: bbbb2222\n---\n\n# Project Plan\n\nSecond\n".write(
      to: secondURL,
      atomically: true,
      encoding: .utf8
    )
    try """
      ---
      lattice:
        id: source333
      ---

      # Source

      [[Project Plan]]
      [[Project Plan]]<!-- lattice:target=bbbb2222 -->
      [First](../2026-06-16/2026-06-16T10-00-00.md)
      ![Image](../../attachments/2026-06-18/image.png)
      """.write(to: sourceURL, atomically: true, encoding: .utf8)
    _ = try library.openNote(SavedNote(url: secondURL, dateString: "2026-06-17"))

    let preview = try #require(try library.flatNoteMigrationPreview())
    #expect(preview.noteCount == 3)

    let result = try library.migrateNotesToFlatLayout(now: fixture.date)
    let firstDestination = notesURL.appendingPathComponent("Project Plan.md")
    let secondDestination = notesURL.appendingPathComponent("Project Plan--bbbb2222.md")
    let sourceDestination = notesURL.appendingPathComponent("Source.md")

    #expect(result.migratedNoteCount == 3)
    #expect(result.collisionCount == 1)
    #expect(result.ambiguousLinkCount == 1)
    #expect(fixture.fileManager.fileExists(atPath: firstDestination.path))
    #expect(fixture.fileManager.fileExists(atPath: secondDestination.path))
    #expect(fixture.fileManager.fileExists(atPath: sourceDestination.path))
    #expect(library.activeNoteURL() == secondDestination)
    #expect(try library.flatNoteMigrationPreview() == nil)
    #expect(fixture.fileManager.fileExists(atPath: result.backupURL.path))

    let migratedSource = try String(contentsOf: sourceDestination, encoding: .utf8)
    #expect(migratedSource.contains("[[Project Plan]]\n"))
    #expect(migratedSource.contains(
      "[[Project Plan--bbbb2222|Project Plan]]<!-- lattice:target=bbbb2222 -->"
    ))
    #expect(migratedSource.contains("[First](Project Plan.md)"))
    #expect(migratedSource.contains("![Image](../attachments/2026-06-18/image.png)"))
    #expect(!fixture.fileManager.fileExists(atPath: firstDateURL.path))
    #expect(!fixture.fileManager.fileExists(atPath: secondDateURL.path))
    #expect(!fixture.fileManager.fileExists(atPath: sourceDateURL.path))
  }

  @Test("refuses migration when different notes share a durable identity")
  func refusesMigrationForConflictingNoteIDs() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }
    let backupRoot = fixture.root.appendingPathComponent("migration-backups", isDirectory: true)
    let library = NoteLibrary(
      defaults: fixture.defaults,
      fileManager: fixture.fileManager,
      migrationBackupRootURLProvider: { backupRoot }
    )
    try library.selectNotesFolder(fixture.root)

    let firstDirectory = fixture.root.appendingPathComponent("notes/2026-06-16", isDirectory: true)
    let secondDirectory = fixture.root.appendingPathComponent("notes/2026-06-17", isDirectory: true)
    try fixture.fileManager.createDirectory(at: firstDirectory, withIntermediateDirectories: true)
    try fixture.fileManager.createDirectory(at: secondDirectory, withIntermediateDirectories: true)
    let firstURL = firstDirectory.appendingPathComponent("first.md")
    let secondURL = secondDirectory.appendingPathComponent("second.md")
    try "---\nlattice:\n  id: duplicate123\n---\n\nFirst\n".write(
      to: firstURL,
      atomically: true,
      encoding: .utf8
    )
    try "---\nlattice:\n  id: duplicate123\n---\n\nSecond\n".write(
      to: secondURL,
      atomically: true,
      encoding: .utf8
    )

    #expect(throws: NoteLibraryError.self) {
      _ = try library.migrateNotesToFlatLayout(now: fixture.date)
    }
    #expect(fixture.fileManager.fileExists(atPath: firstURL.path))
    #expect(fixture.fileManager.fileExists(atPath: secondURL.path))
  }

  @Test("creates and reuses one canonical daily note")
  func createsAndReusesDailyNote() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }

    try fixture.library.selectNotesFolder(fixture.root)
    let first = try fixture.library.ensureDailyNote(now: fixture.date)
    try fixture.library.updateNote(first, body: "# Wednesday, June 17, 2026\n\nJournal entry")
    let second = try fixture.library.ensureDailyNote(now: fixture.date.addingTimeInterval(60))

    #expect(first.url == second.url)
    #expect(first.filenameTitle == "2026-06-17")
    #expect(try fixture.library.body(for: second).contains("Journal entry"))
  }

  @Test("strips block markdown from rendered display titles")
  func displayTitleStripsBlockMarkdown() throws {
    #expect(NoteLibrary.firstRenderedLine(in: "# Heading <!-- lattice:heading=abc -->") == "Heading")
    #expect(NoteLibrary.firstRenderedLine(in: "- [ ] Buy **milk**") == "Buy milk")
    #expect(NoteLibrary.firstRenderedLine(in: "> [[Daily Note#Tasks|Tasks]]") == "Tasks")
    #expect(NoteLibrary.firstRenderedLine(in: "\n---\n\n2026-06-17T14-32-10") == "2026-06-17T14-32-10")
  }

  @Test("saves image attachments outside notes with relative markdown paths")
  func savesImageAttachments() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }

    try fixture.library.selectNotesFolder(fixture.root)
    let noteDirectory = fixture.library.noteDateDirectory(in: fixture.root, now: fixture.date)
    let data = Data("image-bytes".utf8)
    let first = try fixture.library.saveImageAttachment(
      data: data,
      suggestedFilename: "Screen Shot: A.png",
      preferredExtension: "png",
      now: fixture.date,
      relativeTo: noteDirectory
    )
    let second = try fixture.library.saveImageAttachment(
      data: Data("other".utf8),
      suggestedFilename: "Screen Shot: A.png",
      preferredExtension: "png",
      now: fixture.date,
      relativeTo: noteDirectory
    )

    #expect(first.url.path.hasSuffix("/attachments/2026-06-17/Screen Shot- A-2026-06-17T14-32-10.png"))
    #expect(first.markdownPath == "../../attachments/2026-06-17/Screen Shot- A-2026-06-17T14-32-10.png")
    #expect(first.altText == "Screen Shot A")
    #expect(try Data(contentsOf: first.url) == data)
    #expect(second.url.path.hasSuffix("/attachments/2026-06-17/Screen Shot- A-2026-06-17T14-32-10-2.png"))
    #expect(try fixture.library.listNotes().isEmpty)
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
