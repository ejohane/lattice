import Foundation
import SQLite3

public final class TaskSyncStore {
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
      .appendingPathComponent("TaskSync", isDirectory: true)
      .appendingPathComponent("\(Self.stableHash(notesFolderURL.standardizedFileURL.path)).sqlite")
  }

  public func settings(notesFolderURL: URL) throws -> TaskSyncSettings {
    let rows = try connection(for: notesFolderURL).query("SELECT key, value FROM settings")
    var values: [String: String] = [:]
    for row in rows {
      if let key = row["key"]?.stringValue,
         let value = row["value"]?.stringValue {
        values[key] = value
      }
    }

    return TaskSyncSettings(
      isEnabled: values["is_enabled"] == "1",
      providerID: values["provider_id"] ?? "apple-reminders",
      destinationID: values["destination_id"].flatMap { $0.isEmpty ? nil : $0 },
      initialSyncConfirmed: values["initial_sync_confirmed"] == "1"
    )
  }

  public func saveSettings(_ settings: TaskSyncSettings, notesFolderURL: URL) throws {
    let connection = try connection(for: notesFolderURL)
    try connection.execute("BEGIN IMMEDIATE TRANSACTION")
    do {
      try set("is_enabled", value: settings.isEnabled ? "1" : "0", connection: connection)
      try set("provider_id", value: settings.providerID, connection: connection)
      try set("destination_id", value: settings.destinationID ?? "", connection: connection)
      try set(
        "initial_sync_confirmed",
        value: settings.initialSyncConfirmed ? "1" : "0",
        connection: connection
      )
      try connection.execute("COMMIT")
    } catch {
      try? connection.execute("ROLLBACK")
      throw error
    }
  }

  public func records(notesFolderURL: URL, providerID: String) throws -> [StoredTaskRecord] {
    let connection = try connection(for: notesFolderURL)
    let rows = try connection.query(
      """
      SELECT
        task_records.id,
        task_records.relative_path,
        task_records.line_number,
        task_records.title,
        task_records.normalized_title,
        task_records.is_completed,
        task_records.fingerprint,
        task_records.last_seen_at,
        task_records.deleted_at,
        provider_links.external_id,
        provider_links.destination_id,
        provider_links.external_title,
        provider_links.external_completed,
        provider_links.synced_title,
        provider_links.synced_completed,
        provider_links.updated_at
      FROM task_records
      LEFT JOIN provider_links
        ON provider_links.task_id = task_records.id
       AND provider_links.provider_id = ?
      """,
      bindings: [.text(providerID)]
    )

    return rows.compactMap { row in
      record(from: row, providerID: providerID)
    }
  }

  public func upsert(_ record: StoredTaskRecord, notesFolderURL: URL) throws {
    let connection = try connection(for: notesFolderURL)
    try connection.execute("BEGIN IMMEDIATE TRANSACTION")
    do {
      try upsert(record, connection: connection)
      if let link = record.link {
        try upsert(link, connection: connection)
      }
      try connection.execute("COMMIT")
    } catch {
      try? connection.execute("ROLLBACK")
      throw error
    }
  }

  public func markDeleted(
    taskID: String,
    deletedAt: Date = Date(),
    notesFolderURL: URL
  ) throws {
    try connection(for: notesFolderURL).execute(
      """
      UPDATE task_records
      SET deleted_at = ?
      WHERE id = ?
      """,
      bindings: [
        .text(Self.isoString(from: deletedAt)),
        .text(taskID)
      ]
    )
  }

  private func connection(for notesFolderURL: URL) throws -> TaskSQLiteConnection {
    let databaseURL = databaseURL(for: notesFolderURL)
    try fileManager.createDirectory(
      at: databaseURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    let connection = try TaskSQLiteConnection(url: databaseURL)
    try configure(connection)
    return connection
  }

  private func configure(_ connection: TaskSQLiteConnection) throws {
    try connection.execute("PRAGMA journal_mode = WAL")
    try connection.execute("PRAGMA foreign_keys = ON")
    try connection.execute(
      """
      CREATE TABLE IF NOT EXISTS settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
      """
    )
    try connection.execute(
      """
      CREATE TABLE IF NOT EXISTS task_records (
        id TEXT PRIMARY KEY,
        relative_path TEXT NOT NULL,
        line_number INTEGER NOT NULL,
        title TEXT NOT NULL,
        normalized_title TEXT NOT NULL,
        is_completed INTEGER NOT NULL,
        fingerprint TEXT NOT NULL,
        last_seen_at TEXT NOT NULL,
        deleted_at TEXT
      )
      """
    )
    try connection.execute(
      """
      CREATE TABLE IF NOT EXISTS provider_links (
        task_id TEXT NOT NULL,
        provider_id TEXT NOT NULL,
        external_id TEXT NOT NULL,
        destination_id TEXT NOT NULL,
        external_title TEXT NOT NULL,
        external_completed INTEGER NOT NULL,
        synced_title TEXT NOT NULL,
        synced_completed INTEGER NOT NULL,
        updated_at TEXT NOT NULL,
        PRIMARY KEY (task_id, provider_id),
        FOREIGN KEY (task_id) REFERENCES task_records(id) ON DELETE CASCADE
      )
      """
    )
    try connection.execute(
      "CREATE INDEX IF NOT EXISTS task_records_source ON task_records(relative_path, line_number)"
    )
    try connection.execute(
      "CREATE INDEX IF NOT EXISTS task_records_title ON task_records(relative_path, normalized_title)"
    )
    try connection.execute("PRAGMA user_version = 1")
  }

  private func set(_ key: String, value: String, connection: TaskSQLiteConnection) throws {
    try connection.execute(
      """
      INSERT INTO settings (key, value)
      VALUES (?, ?)
      ON CONFLICT(key) DO UPDATE SET value = excluded.value
      """,
      bindings: [.text(key), .text(value)]
    )
  }

  private func upsert(_ record: StoredTaskRecord, connection: TaskSQLiteConnection) throws {
    try connection.execute(
      """
      INSERT INTO task_records (
        id, relative_path, line_number, title, normalized_title, is_completed,
        fingerprint, last_seen_at, deleted_at
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        relative_path = excluded.relative_path,
        line_number = excluded.line_number,
        title = excluded.title,
        normalized_title = excluded.normalized_title,
        is_completed = excluded.is_completed,
        fingerprint = excluded.fingerprint,
        last_seen_at = excluded.last_seen_at,
        deleted_at = excluded.deleted_at
      """,
      bindings: [
        .text(record.id),
        .text(record.relativePath),
        .integer(Int64(record.lineNumber)),
        .text(record.title),
        .text(record.normalizedTitle),
        .integer(record.isCompleted ? 1 : 0),
        .text(record.fingerprint),
        .text(Self.isoString(from: record.lastSeenAt)),
        .nullableText(record.deletedAt.map(Self.isoString(from:)))
      ]
    )
  }

  private func upsert(_ link: StoredProviderLink, connection: TaskSQLiteConnection) throws {
    try connection.execute(
      """
      INSERT INTO provider_links (
        task_id, provider_id, external_id, destination_id, external_title,
        external_completed, synced_title, synced_completed, updated_at
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(task_id, provider_id) DO UPDATE SET
        external_id = excluded.external_id,
        destination_id = excluded.destination_id,
        external_title = excluded.external_title,
        external_completed = excluded.external_completed,
        synced_title = excluded.synced_title,
        synced_completed = excluded.synced_completed,
        updated_at = excluded.updated_at
      """,
      bindings: [
        .text(link.taskID),
        .text(link.providerID),
        .text(link.externalID),
        .text(link.destinationID),
        .text(link.externalTitle),
        .integer(link.externalCompleted ? 1 : 0),
        .text(link.syncedTitle),
        .integer(link.syncedCompleted ? 1 : 0),
        .text(Self.isoString(from: link.updatedAt))
      ]
    )
  }

  private func record(from row: [String: SQLiteValue], providerID: String) -> StoredTaskRecord? {
    guard
      let id = row["id"]?.stringValue,
      let relativePath = row["relative_path"]?.stringValue,
      let lineNumber = row["line_number"]?.int64Value,
      let title = row["title"]?.stringValue,
      let normalizedTitle = row["normalized_title"]?.stringValue,
      let isCompleted = row["is_completed"]?.int64Value,
      let fingerprint = row["fingerprint"]?.stringValue,
      let lastSeenAtValue = row["last_seen_at"]?.stringValue,
      let lastSeenAt = Self.date(from: lastSeenAtValue)
    else {
      return nil
    }

    let link: StoredProviderLink?
    if let externalID = row["external_id"]?.stringValue,
       let destinationID = row["destination_id"]?.stringValue,
       let externalTitle = row["external_title"]?.stringValue,
       let externalCompleted = row["external_completed"]?.int64Value,
       let syncedTitle = row["synced_title"]?.stringValue,
       let syncedCompleted = row["synced_completed"]?.int64Value,
       let updatedAtValue = row["updated_at"]?.stringValue,
       let updatedAt = Self.date(from: updatedAtValue) {
      link = StoredProviderLink(
        taskID: id,
        providerID: providerID,
        externalID: externalID,
        destinationID: destinationID,
        externalTitle: externalTitle,
        externalCompleted: externalCompleted == 1,
        syncedTitle: syncedTitle,
        syncedCompleted: syncedCompleted == 1,
        updatedAt: updatedAt
      )
    } else {
      link = nil
    }

    return StoredTaskRecord(
      id: id,
      relativePath: relativePath,
      lineNumber: Int(lineNumber),
      title: title,
      normalizedTitle: normalizedTitle,
      isCompleted: isCompleted == 1,
      fingerprint: fingerprint,
      lastSeenAt: lastSeenAt,
      deletedAt: Self.date(from: row["deleted_at"]?.stringValue),
      link: link
    )
  }

  private static func defaultAppSupportURL(fileManager: FileManager) -> URL {
    let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? fileManager.temporaryDirectory
    return baseURL.appendingPathComponent("Lattice", isDirectory: true)
  }

  private static func stableHash(_ input: String) -> String {
    var hash: UInt64 = 14695981039346656037
    for byte in input.utf8 {
      hash ^= UInt64(byte)
      hash &*= 1099511628211
    }
    return String(hash, radix: 16)
  }

  private static func isoString(from date: Date) -> String {
    ISO8601DateFormatter().string(from: date)
  }

  private static func date(from value: String?) -> Date? {
    guard let value, !value.isEmpty else {
      return nil
    }
    return ISO8601DateFormatter().date(from: value)
  }
}

private final class TaskSQLiteConnection {
  private let database: OpaquePointer?

  init(url: URL) throws {
    var database: OpaquePointer?
    guard sqlite3_open(url.path, &database) == SQLITE_OK else {
      let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "Could not open SQLite database."
      sqlite3_close(database)
      throw TaskSyncError.database(message)
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
      result = sqlite3_bind_text(statement, index, value, -1, TASK_SQLITE_TRANSIENT)
    case .nullableText(let value):
      if let value {
        result = sqlite3_bind_text(statement, index, value, -1, TASK_SQLITE_TRANSIENT)
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

  private func error() -> TaskSyncError {
    TaskSyncError.database(String(cString: sqlite3_errmsg(database)))
  }
}

private let TASK_SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
