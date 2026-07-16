import Foundation

public struct IndexedNote: Identifiable, Equatable, Sendable {
  public let url: URL
  public let relativePath: String
  public let noteID: String
  public let dateString: String
  public let filename: String
  public let createdAt: Date?
  public let modifiedAt: Date?
  public let size: Int64
  public let fingerprint: String
  public let title: String
  public let excerpt: String
  public let indexedAt: Date

  public var id: String {
    url.standardizedFileURL.path
  }

  public var savedNote: SavedNote {
    SavedNote(url: url, dateString: dateString, createdAt: createdAt, modifiedAt: modifiedAt)
  }
}

public protocol NoteIndexing: AnyObject {
  func rebuild(notesFolderURL: URL) throws
  func refresh(note: SavedNote, notesFolderURL: URL) throws
  func recentNotes(notesFolderURL: URL, limit: Int) throws -> [SavedNote]
  func searchNotes(query: String, notesFolderURL: URL, limit: Int) throws -> [SavedNote]
  func tagSummaries(notesFolderURL: URL) throws -> [NoteTagSummary]
  func notes(tagged normalizedName: String, notesFolderURL: URL, limit: Int) throws -> [SavedNote]
  func indexedNotes(notesFolderURL: URL, limit: Int) throws -> [IndexedNote]
  func wikiNoteCandidates(stem: String, notesFolderURL: URL, limit: Int) throws -> [WikiNoteCandidate]
  func wikiHeadingCandidates(
    noteID: String?,
    stem: String?,
    prefix: String,
    currentNote: SavedNote?,
    notesFolderURL: URL,
    limit: Int
  ) throws -> [WikiHeadingCandidate]
  func wikiBacklinks(to noteID: String, notesFolderURL: URL, limit: Int) throws -> [WikiBacklink]
  func wikiLinkRenderStates(
    body: String,
    currentNote: SavedNote?,
    notesFolderURL: URL
  ) throws -> [WikiLinkRenderState]
}

public extension NoteIndexing {
  func tagSummaries(notesFolderURL: URL) throws -> [NoteTagSummary] {
    []
  }

  func notes(tagged normalizedName: String, notesFolderURL: URL, limit: Int) throws -> [SavedNote] {
    []
  }
}

public enum NoteIndexError: LocalizedError, Equatable, Sendable {
  case invalidNotesFolder(String)
  case unreadableNote(String)
  case database(String)

  public var errorDescription: String? {
    switch self {
    case .invalidNotesFolder(let path):
      return "Invalid notes folder for indexing: \(path)"
    case .unreadableNote(let path):
      return "Could not read note for indexing: \(path)"
    case .database(let message):
      return message
    }
  }
}

public final class NoteIndex: NoteIndexing {
  private let fileManager: FileManager
  private let appSupportURL: URL

  public init(
    appSupportURL: URL? = nil,
    fileManager: FileManager = .default
  ) {
    self.fileManager = fileManager
    self.appSupportURL = appSupportURL ?? Self.defaultAppSupportURL(fileManager: fileManager)
  }

  public func databaseURL(for notesFolderURL: URL) -> URL {
    appSupportURL
      .appendingPathComponent("Indexes", isDirectory: true)
      .appendingPathComponent("\(Self.stableHash(notesFolderURL.standardizedFileURL.path)).sqlite")
  }

  public func rebuild(notesFolderURL: URL) throws {
    let connection = try connection(for: notesFolderURL)
    let notes = try indexedDocuments(in: notesFolderURL)
      .sorted { $0.note.relativePath < $1.note.relativePath }
    let relativePaths = Set(notes.map(\.note.relativePath))

    try connection.execute("BEGIN IMMEDIATE TRANSACTION")
    do {
      try connection.execute("DELETE FROM note_tags")
      try connection.execute("DELETE FROM tags")
      for document in notes {
        try upsert(document, connection: connection)
      }
      try deleteRowsNotIn(relativePaths, connection: connection)
      try connection.execute("COMMIT")
    } catch {
      try? connection.execute("ROLLBACK")
      throw error
    }
  }

  public func refresh(note: SavedNote, notesFolderURL: URL) throws {
    let connection = try connection(for: notesFolderURL)
    try connection.execute("BEGIN IMMEDIATE TRANSACTION")
    do {
      try refresh(note: note, notesFolderURL: notesFolderURL, connection: connection)
      try connection.execute("COMMIT")
    } catch {
      try? connection.execute("ROLLBACK")
      throw error
    }
  }

  private func refresh(note: SavedNote, notesFolderURL: URL, connection: SQLiteConnection) throws {
    if !fileManager.fileExists(atPath: note.url.path) {
      guard let relativePath = Self.relativePath(for: note.url, in: notesFolderURL) else {
        return
      }
      try deleteRow(relativePath: relativePath, connection: connection)
      return
    }

    let document = try indexedDocument(for: note.url, notesFolderURL: notesFolderURL)
    try upsert(document, connection: connection)
  }

  public func recentNotes(notesFolderURL: URL, limit: Int = 24) throws -> [SavedNote] {
    let connection = try connection(for: notesFolderURL)
    let rows = try connection.query(
      """
      SELECT relative_path, date_string, created_at, modified_at
      FROM notes
      ORDER BY created_at DESC, modified_at DESC, filename COLLATE NOCASE ASC
      LIMIT ?
      """,
      bindings: [.integer(Int64(limit))]
    )

    return rows.compactMap { row in
      savedNote(from: row, notesFolderURL: notesFolderURL)
    }
  }

  public func searchNotes(query: String, notesFolderURL: URL, limit: Int = 24) throws -> [SavedNote] {
    let matchQuery = Self.ftsQuery(from: query)
    guard !matchQuery.isEmpty else {
      return try recentNotes(notesFolderURL: notesFolderURL, limit: limit)
    }

    let connection = try connection(for: notesFolderURL)
    let rows = try connection.query(
      """
      SELECT notes.relative_path, notes.date_string, notes.created_at, notes.modified_at
      FROM notes_fts
      JOIN notes ON notes.id = notes_fts.rowid
      WHERE notes_fts MATCH ?
      ORDER BY rank
      LIMIT ?
      """,
      bindings: [.text(matchQuery), .integer(Int64(limit))]
    )

    return rows.compactMap { row in
      savedNote(from: row, notesFolderURL: notesFolderURL)
    }
  }

  public func tagSummaries(notesFolderURL: URL) throws -> [NoteTagSummary] {
    let connection = try connection(for: notesFolderURL)
    let rows = try connection.query(
      """
      SELECT tags.normalized_name, tags.display_name, COUNT(note_tags.note_relative_path) AS note_count
      FROM tags
      JOIN note_tags ON note_tags.normalized_name = tags.normalized_name
      GROUP BY tags.normalized_name, tags.display_name
      ORDER BY tags.display_name COLLATE NOCASE ASC
      """
    )
    return rows.compactMap { row in
      guard
        let normalizedName = row["normalized_name"]?.stringValue,
        let displayName = row["display_name"]?.stringValue,
        let noteCount = row["note_count"]?.int64Value
      else {
        return nil
      }
      return NoteTagSummary(
        name: displayName,
        normalizedName: normalizedName,
        noteCount: Int(noteCount)
      )
    }
  }

  public func notes(
    tagged normalizedName: String,
    notesFolderURL: URL,
    limit: Int = 2_000
  ) throws -> [SavedNote] {
    let connection = try connection(for: notesFolderURL)
    let rows = try connection.query(
      """
      SELECT notes.relative_path, notes.date_string, notes.created_at, notes.modified_at
      FROM note_tags
      JOIN notes ON notes.relative_path = note_tags.note_relative_path
      WHERE note_tags.normalized_name = ?
      ORDER BY notes.created_at DESC, notes.modified_at DESC, notes.filename COLLATE NOCASE ASC
      LIMIT ?
      """,
      bindings: [.text(NoteTagParser.normalizedName(normalizedName)), .integer(Int64(limit))]
    )
    return rows.compactMap { savedNote(from: $0, notesFolderURL: notesFolderURL) }
  }

  public func indexedNotes(notesFolderURL: URL, limit: Int = 500) throws -> [IndexedNote] {
    let connection = try connection(for: notesFolderURL)
    let rows = try connection.query(
      """
      SELECT relative_path, note_id, date_string, filename, created_at, modified_at, size,
             fingerprint, title, excerpt, indexed_at
      FROM notes
      ORDER BY created_at DESC, modified_at DESC, filename COLLATE NOCASE ASC
      LIMIT ?
      """,
      bindings: [.integer(Int64(limit))]
    )

    return rows.compactMap { row in
      indexedNote(from: row, notesFolderURL: notesFolderURL)
    }
  }

  public func wikiNoteCandidates(stem: String, notesFolderURL: URL, limit: Int = 20) throws -> [WikiNoteCandidate] {
    let connection = try connection(for: notesFolderURL)
    let normalizedStem = stem.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let rows = try connection.query(
      """
      SELECT relative_path, note_id, date_string, filename, modified_at, title
      FROM notes
      WHERE lower(replace(filename, '.md', '')) = ? OR lower(title) = ?
      ORDER BY date_string DESC, relative_path ASC
      LIMIT ?
      """,
      bindings: [.text(normalizedStem), .text(normalizedStem), .integer(Int64(limit))]
    )
    return rows.compactMap { row in
      guard
        let relativePath = row["relative_path"]?.stringValue,
        let noteID = row["note_id"]?.stringValue,
        let dateString = row["date_string"]?.stringValue,
        let filename = row["filename"]?.stringValue,
        let title = row["title"]?.stringValue
      else {
        return nil
      }
      let note = SavedNote(
        url: notesFolderURL.appendingPathComponent(relativePath),
        dateString: dateString,
        modifiedAt: Self.date(from: row["modified_at"]?.stringValue)
      )
      return WikiNoteCandidate(
        note: note,
        noteID: noteID,
        filenameStem: URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent,
        title: title,
        relativePath: relativePath
      )
    }
  }

  public func wikiHeadingCandidates(
    noteID: String?,
    stem: String?,
    prefix: String,
    currentNote: SavedNote?,
    notesFolderURL: URL,
    limit: Int = 20
  ) throws -> [WikiHeadingCandidate] {
    let connection = try connection(for: notesFolderURL)
    let normalizedPrefix = prefix.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let rows: [[String: SQLiteValue]]

    if let noteID {
      rows = try headingRows(
        connection: connection,
        whereClause: "notes.note_id = ?",
        bindings: [.text(noteID), .text("\(normalizedPrefix)%"), .integer(Int64(limit))]
      )
    } else if let stem, !stem.isEmpty {
      rows = try headingRows(
        connection: connection,
        whereClause: "(lower(replace(notes.filename, '.md', '')) = ? OR lower(notes.title) = ?)",
        bindings: [
          .text(stem.lowercased()),
          .text(stem.lowercased()),
          .text("\(normalizedPrefix)%"),
          .integer(Int64(limit))
        ]
      )
    } else if let currentNote, let relativePath = Self.relativePath(for: currentNote.url, in: notesFolderURL) {
      rows = try headingRows(
        connection: connection,
        whereClause: "notes.relative_path = ?",
        bindings: [.text(relativePath), .text("\(normalizedPrefix)%"), .integer(Int64(limit))]
      )
    } else {
      return []
    }

    return rows.compactMap { headingCandidate(from: $0, notesFolderURL: notesFolderURL) }
  }

  public func wikiBacklinks(to noteID: String, notesFolderURL: URL, limit: Int = 100) throws -> [WikiBacklink] {
    let connection = try connection(for: notesFolderURL)
    let rows = try connection.query(
      """
      SELECT notes.relative_path, notes.date_string, notes.modified_at, notes.title, wiki_links.target_note_id, wiki_links.raw_text
      FROM wiki_links
      JOIN notes ON notes.relative_path = wiki_links.source_relative_path
      WHERE wiki_links.target_note_id = ?
      ORDER BY notes.date_string DESC, notes.relative_path ASC
      LIMIT ?
      """,
      bindings: [.text(noteID), .integer(Int64(limit))]
    )
    return rows.compactMap { row in
      guard
        let relativePath = row["relative_path"]?.stringValue,
        let dateString = row["date_string"]?.stringValue,
        let title = row["title"]?.stringValue,
        let targetNoteID = row["target_note_id"]?.stringValue,
        let rawText = row["raw_text"]?.stringValue
      else {
        return nil
      }
      return WikiBacklink(
        source: SavedNote(
          url: notesFolderURL.appendingPathComponent(relativePath),
          dateString: dateString,
          modifiedAt: Self.date(from: row["modified_at"]?.stringValue)
        ),
        sourceTitle: title,
        targetNoteID: targetNoteID,
        rawText: rawText
      )
    }
  }

  public func wikiLinkRenderStates(
    body: String,
    currentNote: SavedNote?,
    notesFolderURL: URL
  ) throws -> [WikiLinkRenderState] {
    try WikiLinkParser.links(in: body).map { link in
      let status = try resolveRenderStatus(for: link, currentNote: currentNote, notesFolderURL: notesFolderURL)
      return WikiLinkRenderState(range: link.range, status: status)
    }
  }

  public func schemaVersion(notesFolderURL: URL) throws -> Int {
    let connection = try connection(for: notesFolderURL)
    return Int(try connection.scalarInt64("PRAGMA user_version") ?? 0)
  }

  private func connection(for notesFolderURL: URL) throws -> SQLiteConnection {
    let databaseURL = databaseURL(for: notesFolderURL)
    try fileManager.createDirectory(
      at: databaseURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )

    do {
      let connection = try SQLiteConnection(url: databaseURL, makeError: NoteIndexError.database)
      try configure(connection)
      return connection
    } catch {
      try? fileManager.removeItem(at: databaseURL)
      let connection = try SQLiteConnection(url: databaseURL, makeError: NoteIndexError.database)
      try configure(connection)
      return connection
    }
  }

  private func configure(_ connection: SQLiteConnection) throws {
    try connection.execute("PRAGMA journal_mode = WAL")
    try connection.execute("PRAGMA foreign_keys = ON")
    try connection.execute(
      """
      CREATE TABLE IF NOT EXISTS notes (
        id INTEGER PRIMARY KEY,
        relative_path TEXT NOT NULL UNIQUE,
        note_id TEXT NOT NULL UNIQUE,
        date_string TEXT NOT NULL,
        filename TEXT NOT NULL,
        created_at TEXT,
        modified_at TEXT,
        size INTEGER NOT NULL,
        fingerprint TEXT NOT NULL,
        title TEXT NOT NULL,
        excerpt TEXT NOT NULL,
        indexed_at TEXT NOT NULL
      )
      """
    )
    try ensureColumn("notes", column: "note_id", definition: "TEXT NOT NULL DEFAULT ''", connection: connection)
    let ftsTables = try connection.query(
      "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'notes_fts'"
    )
    if let ftsSQL = ftsTables.first?["sql"]?.stringValue,
       ftsSQL.contains("content='notes'") || ftsSQL.contains("content=\"notes\"") {
      try connection.execute("DROP TABLE IF EXISTS notes_fts")
    }
    try connection.execute(
      """
      CREATE VIRTUAL TABLE IF NOT EXISTS notes_fts USING fts5(
        title,
        excerpt,
        body
      )
      """
    )
    try connection.execute(
      """
      CREATE TABLE IF NOT EXISTS note_headings (
        id INTEGER PRIMARY KEY,
        note_id TEXT NOT NULL,
        note_relative_path TEXT NOT NULL,
        heading_id TEXT,
        title TEXT NOT NULL,
        anchor TEXT NOT NULL,
        level INTEGER NOT NULL,
        range_location INTEGER NOT NULL,
        range_length INTEGER NOT NULL
      )
      """
    )
    try connection.execute(
      """
      CREATE TABLE IF NOT EXISTS wiki_links (
        id INTEGER PRIMARY KEY,
        source_relative_path TEXT NOT NULL,
        source_note_id TEXT NOT NULL,
        target_note_id TEXT,
        target_heading_id TEXT,
        target_stem TEXT,
        target_heading TEXT,
        raw_text TEXT NOT NULL,
        range_location INTEGER NOT NULL,
        range_length INTEGER NOT NULL
      )
      """
    )
    try connection.execute(
      """
      CREATE TABLE IF NOT EXISTS tags (
        normalized_name TEXT PRIMARY KEY,
        display_name TEXT NOT NULL
      )
      """
    )
    try connection.execute(
      """
      CREATE TABLE IF NOT EXISTS note_tags (
        note_relative_path TEXT NOT NULL,
        normalized_name TEXT NOT NULL,
        PRIMARY KEY (note_relative_path, normalized_name)
      )
      """
    )
    try connection.execute("CREATE INDEX IF NOT EXISTS idx_notes_filename_stem ON notes(filename)")
    try connection.execute("CREATE INDEX IF NOT EXISTS idx_headings_note ON note_headings(note_id)")
    try connection.execute("CREATE INDEX IF NOT EXISTS idx_wiki_links_target ON wiki_links(target_note_id)")
    try connection.execute("CREATE INDEX IF NOT EXISTS idx_note_tags_name ON note_tags(normalized_name)")
    try connection.execute("PRAGMA user_version = 3")
  }

  private func ensureColumn(
    _ table: String,
    column: String,
    definition: String,
    connection: SQLiteConnection
  ) throws {
    let rows = try connection.query("PRAGMA table_info(\(table))")
    if rows.contains(where: { $0["name"]?.stringValue == column }) {
      return
    }
    try connection.execute("ALTER TABLE \(table) ADD COLUMN \(column) \(definition)")
  }

  private func indexedDocuments(in notesFolderURL: URL) throws -> [IndexedDocument] {
    let notesURL = notesFolderURL.appendingPathComponent("notes", isDirectory: true)
    var isDirectory: ObjCBool = false
    guard fileManager.fileExists(atPath: notesURL.path, isDirectory: &isDirectory) else {
      return []
    }
    guard isDirectory.boolValue else {
      throw NoteIndexError.invalidNotesFolder(notesURL.path)
    }

    let childURLs = try fileManager.contentsOfDirectory(
      at: notesURL,
      includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
      options: [.skipsHiddenFiles]
    )

    var documents: [IndexedDocument] = []
    for childURL in childURLs {
      let values = try childURL.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
      if values.isRegularFile == true, childURL.pathExtension.lowercased() == "md" {
        documents.append(try indexedDocument(for: childURL, notesFolderURL: notesFolderURL))
      } else if values.isDirectory == true {
        let noteURLs = try fileManager.contentsOfDirectory(
          at: childURL,
          includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey],
          options: [.skipsHiddenFiles]
        )
        for noteURL in noteURLs where noteURL.pathExtension.lowercased() == "md" {
          guard (try? noteURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
            continue
          }
          documents.append(try indexedDocument(for: noteURL, notesFolderURL: notesFolderURL))
        }
      }
    }

    return documents
  }

  private func indexedDocument(for noteURL: URL, notesFolderURL: URL) throws -> IndexedDocument {
    guard let relativePath = Self.relativePath(for: noteURL, in: notesFolderURL) else {
      throw NoteIndexError.invalidNotesFolder(noteURL.path)
    }
    guard var rawBody = try? String(contentsOf: noteURL, encoding: .utf8) else {
      throw NoteIndexError.unreadableNote(noteURL.path)
    }
    if MarkdownDocumentMetadata.noteID(in: rawBody) == nil, !rawBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      rawBody = MarkdownDocumentMetadata.ensureNoteID(in: rawBody)
      try rawBody.write(to: noteURL, atomically: true, encoding: .utf8)
    }
    let body = MarkdownDocumentMetadata.strippingFrontMatter(from: rawBody)
    let noteID = MarkdownDocumentMetadata.noteID(in: rawBody) ?? Self.stableHash(relativePath)

    let resourceValues = try noteURL.resourceValues(
      forKeys: [.contentModificationDateKey, .creationDateKey, .fileSizeKey]
    )
    let filename = noteURL.lastPathComponent
    let createdAt = MarkdownDocumentMetadata.createdAt(in: rawBody)
      ?? Self.createdDate(from: filename)
      ?? resourceValues.creationDate
      ?? resourceValues.contentModificationDate
    let parentName = noteURL.deletingLastPathComponent().lastPathComponent
    let dateString = parentName == "notes"
      ? createdAt.map(Self.localDateString(from:)) ?? "Unknown"
      : parentName
    let modifiedAt = resourceValues.contentModificationDate
    let size = Int64(resourceValues.fileSize ?? 0)
    let title = NoteLibrary.firstRenderedLine(in: body) ?? noteURL.deletingPathExtension().lastPathComponent
    let note = IndexedNote(
      url: noteURL.standardizedFileURL,
      relativePath: relativePath,
      noteID: noteID,
      dateString: dateString,
      filename: filename,
      createdAt: createdAt,
      modifiedAt: modifiedAt,
      size: size,
      fingerprint: Self.fingerprint(modifiedAt: modifiedAt, size: size),
      title: title,
      excerpt: Self.excerpt(from: body),
      indexedAt: Date()
    )

    return IndexedDocument(note: note, body: body)
  }

  private func upsert(_ document: IndexedDocument, connection: SQLiteConnection) throws {
    try deleteRowsWithNoteID(
      document.note.noteID,
      exceptRelativePath: document.note.relativePath,
      connection: connection
    )
    try connection.execute(
      """
      INSERT INTO notes (
        relative_path, note_id, date_string, filename, created_at, modified_at, size,
        fingerprint, title, excerpt, indexed_at
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(relative_path) DO UPDATE SET
        note_id = excluded.note_id,
        date_string = excluded.date_string,
        filename = excluded.filename,
        created_at = excluded.created_at,
        modified_at = excluded.modified_at,
        size = excluded.size,
        fingerprint = excluded.fingerprint,
        title = excluded.title,
        excerpt = excluded.excerpt,
        indexed_at = excluded.indexed_at
      """,
      bindings: [
        .text(document.note.relativePath),
        .text(document.note.noteID),
        .text(document.note.dateString),
        .text(document.note.filename),
        .nullableText(Self.isoString(from: document.note.createdAt)),
        .nullableText(Self.isoString(from: document.note.modifiedAt)),
        .integer(document.note.size),
        .text(document.note.fingerprint),
        .text(document.note.title),
        .text(document.note.excerpt),
        .text(Self.isoString(from: document.note.indexedAt) ?? "")
      ]
    )

    guard let rowID = try connection.scalarInt64(
      "SELECT id FROM notes WHERE relative_path = ?",
      bindings: [.text(document.note.relativePath)]
    ) else {
      throw NoteIndexError.database("Could not resolve indexed note row ID.")
    }
    try connection.execute("DELETE FROM notes_fts WHERE rowid = ?", bindings: [.integer(rowID)])
    try connection.execute(
      "INSERT INTO notes_fts(rowid, title, excerpt, body) VALUES (?, ?, ?, ?)",
      bindings: [
        .integer(rowID),
        .text(document.note.title),
        .text(document.note.excerpt),
        .text(document.body)
      ]
    )
    try upsertHeadings(document, connection: connection)
    try upsertWikiLinks(for: document, connection: connection)
    try upsertTags(for: document, connection: connection)
  }

  private func deleteRowsNotIn(_ relativePaths: Set<String>, connection: SQLiteConnection) throws {
    let rows = try connection.query("SELECT id, relative_path FROM notes")
    for row in rows {
      guard
        let rowID = row["id"]?.int64Value,
        let relativePath = row["relative_path"]?.stringValue,
        !relativePaths.contains(relativePath)
      else {
        continue
      }
      try connection.execute("DELETE FROM notes_fts WHERE rowid = ?", bindings: [.integer(rowID)])
      try connection.execute("DELETE FROM note_headings WHERE note_relative_path = ?", bindings: [.text(relativePath)])
      try connection.execute("DELETE FROM wiki_links WHERE source_relative_path = ?", bindings: [.text(relativePath)])
      try connection.execute("DELETE FROM note_tags WHERE note_relative_path = ?", bindings: [.text(relativePath)])
      try connection.execute("DELETE FROM notes WHERE id = ?", bindings: [.integer(rowID)])
    }
    try deleteUnusedTags(connection: connection)
  }

  private func deleteRow(relativePath: String, connection: SQLiteConnection) throws {
    guard let rowID = try connection.scalarInt64(
      "SELECT id FROM notes WHERE relative_path = ?",
      bindings: [.text(relativePath)]
    ) else {
      return
    }
    try connection.execute("DELETE FROM notes_fts WHERE rowid = ?", bindings: [.integer(rowID)])
    try connection.execute("DELETE FROM note_headings WHERE note_relative_path = ?", bindings: [.text(relativePath)])
    try connection.execute("DELETE FROM wiki_links WHERE source_relative_path = ?", bindings: [.text(relativePath)])
    try connection.execute("DELETE FROM note_tags WHERE note_relative_path = ?", bindings: [.text(relativePath)])
    try connection.execute("DELETE FROM notes WHERE id = ?", bindings: [.integer(rowID)])
    try deleteUnusedTags(connection: connection)
  }

  private func deleteRowsWithNoteID(
    _ noteID: String,
    exceptRelativePath relativePathToKeep: String,
    connection: SQLiteConnection
  ) throws {
    let rows = try connection.query(
      "SELECT id, relative_path FROM notes WHERE note_id = ? AND relative_path != ?",
      bindings: [.text(noteID), .text(relativePathToKeep)]
    )
    for row in rows {
      guard
        let rowID = row["id"]?.int64Value,
        let relativePath = row["relative_path"]?.stringValue
      else {
        continue
      }
      try connection.execute("DELETE FROM notes_fts WHERE rowid = ?", bindings: [.integer(rowID)])
      try connection.execute("DELETE FROM note_headings WHERE note_relative_path = ?", bindings: [.text(relativePath)])
      try connection.execute("DELETE FROM wiki_links WHERE source_relative_path = ?", bindings: [.text(relativePath)])
      try connection.execute("DELETE FROM note_tags WHERE note_relative_path = ?", bindings: [.text(relativePath)])
      try connection.execute("DELETE FROM notes WHERE id = ?", bindings: [.integer(rowID)])
    }
    try deleteUnusedTags(connection: connection)
  }

  private func upsertTags(for document: IndexedDocument, connection: SQLiteConnection) throws {
    try connection.execute(
      "DELETE FROM note_tags WHERE note_relative_path = ?",
      bindings: [.text(document.note.relativePath)]
    )

    var insertedNames: Set<String> = []
    for tag in NoteTagParser.tags(in: document.body) where insertedNames.insert(tag.normalizedName).inserted {
      try connection.execute(
        "INSERT OR IGNORE INTO tags(normalized_name, display_name) VALUES (?, ?)",
        bindings: [.text(tag.normalizedName), .text(tag.name)]
      )
      try connection.execute(
        "INSERT INTO note_tags(note_relative_path, normalized_name) VALUES (?, ?)",
        bindings: [.text(document.note.relativePath), .text(tag.normalizedName)]
      )
    }
    try deleteUnusedTags(connection: connection)
  }

  private func deleteUnusedTags(connection: SQLiteConnection) throws {
    try connection.execute(
      "DELETE FROM tags WHERE normalized_name NOT IN (SELECT DISTINCT normalized_name FROM note_tags)"
    )
  }

  private func upsertHeadings(_ document: IndexedDocument, connection: SQLiteConnection) throws {
    try connection.execute("DELETE FROM note_headings WHERE note_relative_path = ?", bindings: [.text(document.note.relativePath)])
    for heading in MarkdownHeadingScanner.headings(in: document.body) {
      try connection.execute(
        """
        INSERT INTO note_headings (
          note_id, note_relative_path, heading_id, title, anchor, level, range_location, range_length
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """,
        bindings: [
          .text(document.note.noteID),
          .text(document.note.relativePath),
          .nullableText(heading.headingID),
          .text(heading.title),
          .text(heading.anchor),
          .integer(Int64(heading.level)),
          .integer(Int64(heading.range.location)),
          .integer(Int64(heading.range.length))
        ]
      )
    }
  }

  private func upsertWikiLinks(for document: IndexedDocument, connection: SQLiteConnection) throws {
    try connection.execute("DELETE FROM wiki_links WHERE source_relative_path = ?", bindings: [.text(document.note.relativePath)])
    for link in WikiLinkParser.links(in: document.body) {
      try connection.execute(
        """
        INSERT INTO wiki_links (
          source_relative_path, source_note_id, target_note_id, target_heading_id,
          target_stem, target_heading, raw_text, range_location, range_length
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        bindings: [
          .text(document.note.relativePath),
          .text(document.note.noteID),
          .nullableText(link.targetNoteID),
          .nullableText(link.targetHeadingID),
          .nullableText(link.targetStem),
          .nullableText(link.targetHeading),
          .text(link.rawText),
          .integer(Int64(link.range.location)),
          .integer(Int64(link.range.length))
        ]
      )
    }
  }

  private func headingRows(
    connection: SQLiteConnection,
    whereClause: String,
    bindings: [SQLiteBinding]
  ) throws -> [[String: SQLiteValue]] {
    try connection.query(
      """
      SELECT notes.relative_path, notes.note_id, notes.date_string, notes.modified_at,
             note_headings.title, note_headings.anchor, note_headings.heading_id, note_headings.level
      FROM note_headings
      JOIN notes ON notes.note_id = note_headings.note_id
      WHERE \(whereClause) AND lower(note_headings.title) LIKE ?
      ORDER BY note_headings.level ASC, note_headings.title ASC
      LIMIT ?
      """,
      bindings: bindings
    )
  }

  private func headingCandidate(
    from row: [String: SQLiteValue],
    notesFolderURL: URL
  ) -> WikiHeadingCandidate? {
    guard
      let relativePath = row["relative_path"]?.stringValue,
      let noteID = row["note_id"]?.stringValue,
      let dateString = row["date_string"]?.stringValue,
      let title = row["title"]?.stringValue,
      let anchor = row["anchor"]?.stringValue,
      let level = row["level"]?.int64Value
    else {
      return nil
    }
    return WikiHeadingCandidate(
      noteID: noteID,
      note: SavedNote(
        url: notesFolderURL.appendingPathComponent(relativePath),
        dateString: dateString,
        modifiedAt: Self.date(from: row["modified_at"]?.stringValue)
      ),
      title: title,
      anchor: anchor,
      headingID: row["heading_id"]?.stringValue,
      level: Int(level)
    )
  }

  private func resolveRenderStatus(
    for link: WikiLinkOccurrence,
    currentNote: SavedNote?,
    notesFolderURL: URL
  ) throws -> WikiLinkRenderStatus {
    if let targetNoteID = link.targetNoteID {
      let connection = try connection(for: notesFolderURL)
      let count = try connection.scalarInt64(
        "SELECT COUNT(*) FROM notes WHERE note_id = ?",
        bindings: [.text(targetNoteID)]
      ) ?? 0
      guard count > 0 else {
        return .broken
      }
      if let heading = link.targetHeading, !heading.isEmpty {
        return try headingExists(
          connection: connection,
          noteID: targetNoteID,
          headingID: link.targetHeadingID,
          headingTitle: heading
        ) ? .resolved : .broken
      }
      return .resolved
    }

    if link.isCurrentNoteHeadingLink {
      guard let currentNote, let relativePath = Self.relativePath(for: currentNote.url, in: notesFolderURL) else {
        return .broken
      }
      let connection = try connection(for: notesFolderURL)
      let row = try connection.query("SELECT note_id FROM notes WHERE relative_path = ?", bindings: [.text(relativePath)]).first
      guard let noteID = row?["note_id"]?.stringValue else {
        return .broken
      }
      return try headingExists(
        connection: connection,
        noteID: noteID,
        headingID: nil,
        headingTitle: link.targetHeading ?? ""
      ) ? .resolved : .broken
    }

    guard let targetStem = link.targetStem else {
      return .broken
    }
    let candidates = try wikiNoteCandidates(stem: targetStem, notesFolderURL: notesFolderURL, limit: 3)
    guard !candidates.isEmpty else {
      return .broken
    }
    if let heading = link.targetHeading, !heading.isEmpty {
      let connection = try connection(for: notesFolderURL)
      let candidatesWithHeading = try candidates.filter {
        try headingExists(
          connection: connection,
          noteID: $0.noteID,
          headingID: nil,
          headingTitle: heading
        )
      }
      if candidatesWithHeading.isEmpty {
        return .broken
      }
      return candidatesWithHeading.count > 1 ? .ambiguous : .resolved
    }
    if candidates.count > 1 {
      return .ambiguous
    }
    return .resolved
  }

  private func headingExists(
    connection: SQLiteConnection,
    noteID: String,
    headingID: String?,
    headingTitle: String
  ) throws -> Bool {
    if let headingID, !headingID.isEmpty {
      return (try connection.scalarInt64(
        "SELECT COUNT(*) FROM note_headings WHERE note_id = ? AND heading_id = ?",
        bindings: [.text(noteID), .text(headingID)]
      ) ?? 0) > 0
    }
    let anchor = WikiLinkParser.obsidianAnchor(for: headingTitle)
    return (try connection.scalarInt64(
      "SELECT COUNT(*) FROM note_headings WHERE note_id = ? AND anchor = ?",
      bindings: [.text(noteID), .text(anchor)]
    ) ?? 0) > 0
  }

  private func savedNote(from row: [String: SQLiteValue], notesFolderURL: URL) -> SavedNote? {
    guard
      let relativePath = row["relative_path"]?.stringValue,
      let dateString = row["date_string"]?.stringValue
    else {
      return nil
    }
    return SavedNote(
      url: notesFolderURL.appendingPathComponent(relativePath),
      dateString: dateString,
      createdAt: Self.date(from: row["created_at"]?.stringValue),
      modifiedAt: Self.date(from: row["modified_at"]?.stringValue)
    )
  }

  private func indexedNote(from row: [String: SQLiteValue], notesFolderURL: URL) -> IndexedNote? {
    guard
      let relativePath = row["relative_path"]?.stringValue,
      let noteID = row["note_id"]?.stringValue,
      let dateString = row["date_string"]?.stringValue,
      let filename = row["filename"]?.stringValue,
      let size = row["size"]?.int64Value,
      let fingerprint = row["fingerprint"]?.stringValue,
      let title = row["title"]?.stringValue,
      let excerpt = row["excerpt"]?.stringValue,
      let indexedAtString = row["indexed_at"]?.stringValue,
      let indexedAt = Self.date(from: indexedAtString)
    else {
      return nil
    }

    return IndexedNote(
      url: notesFolderURL.appendingPathComponent(relativePath),
      relativePath: relativePath,
      noteID: noteID.isEmpty ? Self.stableHash(relativePath) : noteID,
      dateString: dateString,
      filename: filename,
      createdAt: Self.date(from: row["created_at"]?.stringValue),
      modifiedAt: Self.date(from: row["modified_at"]?.stringValue),
      size: size,
      fingerprint: fingerprint,
      title: title,
      excerpt: excerpt,
      indexedAt: indexedAt
    )
  }

  private static func defaultAppSupportURL(fileManager: FileManager) -> URL {
    let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? fileManager.temporaryDirectory
    return baseURL.appendingPathComponent("Lattice", isDirectory: true)
  }

  private static func relativePath(for noteURL: URL, in notesFolderURL: URL) -> String? {
    let basePath = notesFolderURL.standardizedFileURL.path
    let notePath = noteURL.standardizedFileURL.path
    guard notePath == basePath || notePath.hasPrefix("\(basePath)/") else {
      return nil
    }
    let startIndex = notePath.index(notePath.startIndex, offsetBy: basePath.count)
    let suffix = notePath[startIndex...].trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    return suffix.isEmpty ? nil : suffix
  }

  private static func fingerprint(modifiedAt: Date?, size: Int64) -> String {
    "\(Int64((modifiedAt ?? Date(timeIntervalSince1970: 0)).timeIntervalSince1970)):\(size)"
  }

  private static func createdDate(from filename: String) -> Date? {
    let stem = URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent
    let base = String(stem.prefix(19))
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss"
    return formatter.date(from: base)
  }

  private static func localDateString(from date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: date)
  }

  private static func excerpt(from body: String) -> String {
    for line in body.components(separatedBy: .newlines) {
      let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else {
        continue
      }
      return String(trimmed.prefix(240))
    }
    return ""
  }

  private static func ftsQuery(from query: String) -> String {
    let terms = query
      .lowercased()
      .split { !$0.isLetter && !$0.isNumber }
      .map(String.init)
      .filter { !$0.isEmpty }

    return terms.map { "\($0)*" }.joined(separator: " ")
  }

  private static func stableHash(_ input: String) -> String {
    var hash: UInt64 = 14695981039346656037
    for byte in input.utf8 {
      hash ^= UInt64(byte)
      hash &*= 1099511628211
    }
    return String(hash, radix: 16)
  }

  private static func isoString(from date: Date?) -> String? {
    guard let date else {
      return nil
    }
    return ISO8601DateFormatter().string(from: date)
  }

  private static func date(from value: String?) -> Date? {
    guard let value, !value.isEmpty else {
      return nil
    }
    return ISO8601DateFormatter().date(from: value)
  }
}

private struct IndexedDocument {
  let note: IndexedNote
  let body: String
}
