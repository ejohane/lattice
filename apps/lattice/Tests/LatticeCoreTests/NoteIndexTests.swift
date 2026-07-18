import Foundation
import LatticeCore
import Testing

@Suite("NoteIndex")
struct NoteIndexTests {
  @Test("database URL is app-support scoped and folder specific")
  func databaseURLIsAppSupportScopedAndFolderSpecific() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }
    let otherFolder = fixture.root.deletingLastPathComponent()
      .appendingPathComponent("other-notes-\(UUID().uuidString)", isDirectory: true)

    let firstURL = fixture.index.databaseURL(for: fixture.root)
    let secondURL = fixture.index.databaseURL(for: otherFolder)

    #expect(firstURL.path.hasPrefix(fixture.appSupportURL.path))
    #expect(!firstURL.path.hasPrefix(fixture.root.path))
    #expect(firstURL != secondURL)
  }

  @Test("creates schema with version and indexes markdown files only")
  func rebuildIndexesMarkdownFilesOnly() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }

    try fixture.writeNote(
      relativePath: "notes/2026-06-17/2026-06-17T14-32-10.md",
      body: "**Project Brief**\n\n# Later Heading\n\nUseful body text"
    )
    try fixture.writeNote(
      relativePath: "notes/2026-06-17/not-markdown.txt",
      body: "# Ignored"
    )

    try fixture.index.rebuild(notesFolderURL: fixture.root)

    let notes = try fixture.index.indexedNotes(notesFolderURL: fixture.root)
    #expect(try fixture.index.schemaVersion(notesFolderURL: fixture.root) == 4)
    #expect(notes.count == 1)
    let note = try #require(notes.first)
    #expect(note.relativePath == "notes/2026-06-17/2026-06-17T14-32-10.md")
    #expect(!note.noteID.isEmpty)
    #expect(note.title == "Project Brief")
    #expect(note.excerpt == "Useful body text")
    #expect(note.createdAt != nil)
  }

  @Test("indexes person notes and durable mention connections")
  func indexesPeopleAndMentions() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }

    try fixture.writeNote(
      relativePath: "notes/Erik Johansson.md",
      body: "---\nlattice:\n  id: person-1\n  kind: person\n---\n\n# Erik Johansson\n\n#design"
    )
    try fixture.writeNote(
      relativePath: "notes/Meeting.md",
      body: "---\nlattice:\n  id: meeting-1\n---\n\n# Meeting\n\nTalked to @Erik Johansson<!-- lattice:mention=person-1 --> about #design."
    )

    try fixture.index.rebuild(notesFolderURL: fixture.root)

    let candidates = try fixture.index.personCandidates(prefix: "Erik J", notesFolderURL: fixture.root)
    #expect(candidates.map(\.name) == ["Erik Johansson"])
    #expect(candidates.first?.noteID == "person-1")
    let connections = try fixture.index.personMentions(from: "meeting-1", notesFolderURL: fixture.root)
    #expect(connections == [PersonMentionConnection(
      sourceNoteID: "meeting-1",
      targetNoteID: "person-1",
      name: "Erik Johansson"
    )])
    let meeting = try #require(try fixture.index.indexedNotes(notesFolderURL: fixture.root).first {
      $0.noteID == "meeting-1"
    })
    #expect(meeting.excerpt == "Talked to @Erik Johansson about #design.")

    let design = try #require(try fixture.index.tagSummaries(notesFolderURL: fixture.root).first)
    #expect(design.noteCount == 2)
  }

  @Test("indexes flat notes using durable creation metadata")
  func rebuildIndexesFlatNotes() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }
    let createdAt = try #require(ISO8601DateFormatter().date(from: "2026-06-17T14:32:10Z"))
    try fixture.writeNote(
      relativePath: "notes/Project Brief.md",
      body: "---\nlattice:\n  id: project123\n  created_at: 2026-06-17T14:32:10Z\n---\n\n# Project Brief\n"
    )

    try fixture.index.rebuild(notesFolderURL: fixture.root)

    let note = try #require(try fixture.index.indexedNotes(notesFolderURL: fixture.root).first)
    #expect(note.relativePath == "notes/Project Brief.md")
    #expect(note.noteID == "project123")
    #expect(note.createdAt == createdAt)
    #expect(note.savedNote.createdAt == createdAt)
    #expect(try fixture.index.recentNotes(notesFolderURL: fixture.root).first?.createdAt == createdAt)
  }

  @Test("indexes unique tag note counts and filters notes")
  func indexesTags() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }

    try fixture.writeNote(
      relativePath: "notes/2026-06-17/First.md",
      body: "# First\n\n#Work #work #project/lattice"
    )
    try fixture.writeNote(
      relativePath: "notes/2026-06-18/Second.md",
      body: "# Second\n\n#WORK `#project/lattice`"
    )

    try fixture.index.rebuild(notesFolderURL: fixture.root)

    let summaries = try fixture.index.tagSummaries(notesFolderURL: fixture.root)
    #expect(summaries.map(\.normalizedName) == ["project/lattice", "work"])
    #expect(summaries.first { $0.normalizedName == "work" }?.noteCount == 2)
    #expect(summaries.first { $0.normalizedName == "project/lattice" }?.noteCount == 1)
    #expect(try fixture.index.notes(
      tagged: "WORK",
      notesFolderURL: fixture.root,
      limit: 10
    ).count == 2)
  }

  @Test("uses plain first line as title and extracts the first useful excerpt")
  func plainFirstLineTitleAndExcerpt() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }

    try fixture.writeNote(
      relativePath: "notes/2026-06-17/2026-06-17T14-32-10.md",
      body: "\n\nPlain first line\n\nSecond line"
    )

    try fixture.index.rebuild(notesFolderURL: fixture.root)

    let note = try #require(try fixture.index.indexedNotes(notesFolderURL: fixture.root).first)
    #expect(note.title == "Plain first line")
    #expect(note.excerpt == "Second line")
  }

  @Test("refresh updates an existing row without duplicates")
  func refreshUpdatesExistingRow() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }
    let noteURL = try fixture.writeNote(
      relativePath: "notes/2026-06-17/2026-06-17T14-32-10.md",
      body: "# First\n\nOld body"
    )

    try fixture.index.rebuild(notesFolderURL: fixture.root)
    try "# Updated\n\nNew searchable body".write(to: noteURL, atomically: true, encoding: .utf8)
    try fixture.index.refresh(
      note: SavedNote(url: noteURL, dateString: "2026-06-17"),
      notesFolderURL: fixture.root
    )

    let notes = try fixture.index.indexedNotes(notesFolderURL: fixture.root)
    #expect(notes.count == 1)
    #expect(try #require(notes.first).title == "Updated")
    #expect(try fixture.index.searchNotes(query: "searchable", notesFolderURL: fixture.root, limit: 10).count == 1)
  }

  @Test("rebuild removes rows for deleted files")
  func rebuildRemovesDeletedFiles() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }
    let firstURL = try fixture.writeNote(
      relativePath: "notes/2026-06-17/2026-06-17T14-32-10.md",
      body: "# First"
    )
    _ = try fixture.writeNote(
      relativePath: "notes/2026-06-18/2026-06-18T09-00-00.md",
      body: "# Second"
    )

    try fixture.index.rebuild(notesFolderURL: fixture.root)
    try fixture.fileManager.removeItem(at: firstURL)
    try fixture.index.rebuild(notesFolderURL: fixture.root)

    let notes = try fixture.index.indexedNotes(notesFolderURL: fixture.root)
    #expect(notes.count == 1)
    #expect(try #require(notes.first).title == "Second")
  }

  @Test("rebuild handles renamed files with the same durable note ID")
  func rebuildHandlesRenamedFiles() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }
    let firstURL = try fixture.writeNote(
      relativePath: "notes/2026-06-17/Old Name.md",
      body: "---\nlattice:\n  id: durable-note\n---\n\n# Old Name"
    )
    let renamedURL = firstURL.deletingLastPathComponent().appendingPathComponent("New Name.md")

    try fixture.index.rebuild(notesFolderURL: fixture.root)
    try fixture.fileManager.moveItem(at: firstURL, to: renamedURL)
    try fixture.index.rebuild(notesFolderURL: fixture.root)

    let notes = try fixture.index.indexedNotes(notesFolderURL: fixture.root)
    #expect(notes.count == 1)
    let note = try #require(notes.first)
    #expect(note.noteID == "durable-note")
    #expect(note.relativePath == "notes/2026-06-17/New Name.md")
  }

  @Test("FTS finds title and body matches")
  func ftsFindsTitleAndBodyMatches() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }

    try fixture.writeNote(
      relativePath: "notes/2026-06-17/2026-06-17T14-32-10.md",
      body: "# Alpha Title\n\nBody text"
    )
    try fixture.writeNote(
      relativePath: "notes/2026-06-18/2026-06-18T09-00-00.md",
      body: "# Second\n\nContains quasar marker"
    )

    try fixture.index.rebuild(notesFolderURL: fixture.root)

    let titleMatches = try fixture.index.searchNotes(query: "alpha", notesFolderURL: fixture.root, limit: 10)
    let bodyMatches = try fixture.index.searchNotes(query: "quasar", notesFolderURL: fixture.root, limit: 10)
    #expect(titleMatches.count == 1)
    #expect(try #require(titleMatches.first).filenameTitle == "2026-06-17T14-32-10")
    #expect(bodyMatches.count == 1)
    #expect(try #require(bodyMatches.first).filenameTitle == "2026-06-18T09-00-00")
  }

  @Test("corrupt database is recreated")
  func corruptDatabaseIsRecreated() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }
    try fixture.writeNote(
      relativePath: "notes/2026-06-17/2026-06-17T14-32-10.md",
      body: "# Recovered"
    )
    let databaseURL = fixture.index.databaseURL(for: fixture.root)
    try fixture.fileManager.createDirectory(
      at: databaseURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try "not a sqlite database".write(to: databaseURL, atomically: true, encoding: .utf8)

    try fixture.index.rebuild(notesFolderURL: fixture.root)

    let notes = try fixture.index.indexedNotes(notesFolderURL: fixture.root)
    #expect(notes.count == 1)
    #expect(try #require(notes.first).title == "Recovered")
  }
}

private struct Fixture {
  let root: URL
  let appSupportURL: URL
  let index: NoteIndex
  let fileManager = FileManager.default

  init() throws {
    root = FileManager.default.temporaryDirectory
      .appendingPathComponent("lattice-note-index-\(UUID().uuidString)", isDirectory: true)
    appSupportURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("lattice-note-index-db-\(UUID().uuidString)", isDirectory: true)
    index = NoteIndex(appSupportURL: appSupportURL, fileManager: fileManager)
    try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
  }

  @discardableResult
  func writeNote(relativePath: String, body: String) throws -> URL {
    let url = root.appendingPathComponent(relativePath)
    try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try body.write(to: url, atomically: true, encoding: .utf8)
    return url
  }

  func cleanup() {
    try? fileManager.removeItem(at: root)
    try? fileManager.removeItem(at: appSupportURL)
  }
}
