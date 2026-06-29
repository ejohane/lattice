import Foundation

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

  private func connection(for notesFolderURL: URL) throws -> SQLiteConnection {
    let databaseURL = databaseURL(for: notesFolderURL)
    try fileManager.createDirectory(
      at: databaseURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    let connection = try SQLiteConnection(url: databaseURL, makeError: TaskSyncError.database)
    try configure(connection)
    return connection
  }

  private func configure(_ connection: SQLiteConnection) throws {
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

  private func set(_ key: String, value: String, connection: SQLiteConnection) throws {
    try connection.execute(
      """
      INSERT INTO settings (key, value)
      VALUES (?, ?)
      ON CONFLICT(key) DO UPDATE SET value = excluded.value
      """,
      bindings: [.text(key), .text(value)]
    )
  }

  private func upsert(_ record: StoredTaskRecord, connection: SQLiteConnection) throws {
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

  private func upsert(_ link: StoredProviderLink, connection: SQLiteConnection) throws {
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
