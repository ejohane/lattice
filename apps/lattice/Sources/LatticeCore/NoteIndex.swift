import Foundation
import SQLite3

public struct IndexedNote: Identifiable, Equatable, Sendable {
  public let url: URL
  public let relativePath: String
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
    SavedNote(url: url, dateString: dateString, modifiedAt: modifiedAt)
  }
}

public protocol NoteIndexing: AnyObject {
  func rebuild(notesFolderURL: URL) throws
  func refresh(note: SavedNote, notesFolderURL: URL) throws
  func recentNotes(notesFolderURL: URL, limit: Int) throws -> [SavedNote]
  func searchNotes(query: String, notesFolderURL: URL, limit: Int) throws -> [SavedNote]
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
    let relativePaths = Set(notes.map(\.note.relativePath))

    try connection.execute("BEGIN IMMEDIATE TRANSACTION")
    do {
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
      SELECT relative_path, date_string, modified_at
      FROM notes
      ORDER BY date_string DESC, length(filename) DESC, filename DESC, modified_at DESC
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
      SELECT notes.relative_path, notes.date_string, notes.modified_at
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

  public func indexedNotes(notesFolderURL: URL, limit: Int = 500) throws -> [IndexedNote] {
    let connection = try connection(for: notesFolderURL)
    let rows = try connection.query(
      """
      SELECT relative_path, date_string, filename, created_at, modified_at, size,
             fingerprint, title, excerpt, indexed_at
      FROM notes
      ORDER BY date_string DESC, length(filename) DESC, filename DESC, modified_at DESC
      LIMIT ?
      """,
      bindings: [.integer(Int64(limit))]
    )

    return rows.compactMap { row in
      indexedNote(from: row, notesFolderURL: notesFolderURL)
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
      let connection = try SQLiteConnection(url: databaseURL)
      try configure(connection)
      return connection
    } catch {
      try? fileManager.removeItem(at: databaseURL)
      let connection = try SQLiteConnection(url: databaseURL)
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
    try connection.execute("PRAGMA user_version = 1")
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

    let dateURLs = try fileManager.contentsOfDirectory(
      at: notesURL,
      includingPropertiesForKeys: [.isDirectoryKey],
      options: [.skipsHiddenFiles]
    )

    var documents: [IndexedDocument] = []
    for dateURL in dateURLs {
      let values = try dateURL.resourceValues(forKeys: [.isDirectoryKey])
      guard values.isDirectory == true else {
        continue
      }

      let noteURLs = try fileManager.contentsOfDirectory(
        at: dateURL,
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

    return documents
  }

  private func indexedDocument(for noteURL: URL, notesFolderURL: URL) throws -> IndexedDocument {
    guard let relativePath = Self.relativePath(for: noteURL, in: notesFolderURL) else {
      throw NoteIndexError.invalidNotesFolder(noteURL.path)
    }
    guard let body = try? String(contentsOf: noteURL, encoding: .utf8) else {
      throw NoteIndexError.unreadableNote(noteURL.path)
    }

    let resourceValues = try noteURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
    let filename = noteURL.lastPathComponent
    let dateString = noteURL.deletingLastPathComponent().lastPathComponent
    let modifiedAt = resourceValues.contentModificationDate
    let size = Int64(resourceValues.fileSize ?? 0)
    let title = NoteLibrary.firstHeading(in: body) ?? noteURL.deletingPathExtension().lastPathComponent
    let note = IndexedNote(
      url: noteURL.standardizedFileURL,
      relativePath: relativePath,
      dateString: dateString,
      filename: filename,
      createdAt: Self.createdDate(from: filename),
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
    try connection.execute(
      """
      INSERT INTO notes (
        relative_path, date_string, filename, created_at, modified_at, size,
        fingerprint, title, excerpt, indexed_at
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(relative_path) DO UPDATE SET
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
      try connection.execute("DELETE FROM notes WHERE id = ?", bindings: [.integer(rowID)])
    }
  }

  private func deleteRow(relativePath: String, connection: SQLiteConnection) throws {
    guard let rowID = try connection.scalarInt64(
      "SELECT id FROM notes WHERE relative_path = ?",
      bindings: [.text(relativePath)]
    ) else {
      return
    }
    try connection.execute("DELETE FROM notes_fts WHERE rowid = ?", bindings: [.integer(rowID)])
    try connection.execute("DELETE FROM notes WHERE id = ?", bindings: [.integer(rowID)])
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
      modifiedAt: Self.date(from: row["modified_at"]?.stringValue)
    )
  }

  private func indexedNote(from row: [String: SQLiteValue], notesFolderURL: URL) -> IndexedNote? {
    guard
      let relativePath = row["relative_path"]?.stringValue,
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

private enum SQLiteBinding {
  case integer(Int64)
  case text(String)
  case nullableText(String?)
}

private enum SQLiteValue {
  case integer(Int64)
  case text(String)
  case null

  var stringValue: String? {
    switch self {
    case .text(let value):
      return value
    case .integer(let value):
      return String(value)
    case .null:
      return nil
    }
  }

  var int64Value: Int64? {
    switch self {
    case .integer(let value):
      return value
    case .text(let value):
      return Int64(value)
    case .null:
      return nil
    }
  }
}

private final class SQLiteConnection {
  private let database: OpaquePointer?

  init(url: URL) throws {
    var database: OpaquePointer?
    guard sqlite3_open(url.path, &database) == SQLITE_OK else {
      let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "Could not open SQLite database."
      sqlite3_close(database)
      throw NoteIndexError.database(message)
    }
    self.database = database
  }

  deinit {
    sqlite3_close(database)
  }

  func execute(_ sql: String, bindings: [SQLiteBinding] = []) throws {
    let statement = try prepare(sql, bindings: bindings)
    defer { sqlite3_finalize(statement) }
    let result = sqlite3_step(statement)
    guard result == SQLITE_DONE || result == SQLITE_ROW else {
      throw error()
    }
  }

  func query(_ sql: String, bindings: [SQLiteBinding] = []) throws -> [[String: SQLiteValue]] {
    let statement = try prepare(sql, bindings: bindings)
    defer { sqlite3_finalize(statement) }

    var rows: [[String: SQLiteValue]] = []
    var result = sqlite3_step(statement)
    while result == SQLITE_ROW {
      let count = sqlite3_column_count(statement)
      var row: [String: SQLiteValue] = [:]
      for index in 0..<count {
        let name = String(cString: sqlite3_column_name(statement, index))
        row[name] = value(for: statement, index: index)
      }
      rows.append(row)
      result = sqlite3_step(statement)
    }

    guard result == SQLITE_DONE else {
      throw error()
    }

    return rows
  }

  func scalarInt64(_ sql: String, bindings: [SQLiteBinding] = []) throws -> Int64? {
    try query(sql, bindings: bindings).first?.values.first?.int64Value
  }

  private func prepare(_ sql: String, bindings: [SQLiteBinding]) throws -> OpaquePointer? {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
      throw error()
    }
    for (offset, binding) in bindings.enumerated() {
      try bind(binding, at: Int32(offset + 1), statement: statement)
    }
    return statement
  }

  private func bind(_ binding: SQLiteBinding, at index: Int32, statement: OpaquePointer?) throws {
    let result: Int32
    switch binding {
    case .integer(let value):
      result = sqlite3_bind_int64(statement, index, value)
    case .text(let value):
      result = sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT)
    case .nullableText(let value):
      if let value {
        result = sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT)
      } else {
        result = sqlite3_bind_null(statement, index)
      }
    }
    guard result == SQLITE_OK else {
      throw error()
    }
  }

  private func value(for statement: OpaquePointer?, index: Int32) -> SQLiteValue {
    switch sqlite3_column_type(statement, index) {
    case SQLITE_INTEGER:
      return .integer(sqlite3_column_int64(statement, index))
    case SQLITE_TEXT:
      return .text(String(cString: sqlite3_column_text(statement, index)))
    default:
      return .null
    }
  }

  private func error() -> NoteIndexError {
    NoteIndexError.database(String(cString: sqlite3_errmsg(database)))
  }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
