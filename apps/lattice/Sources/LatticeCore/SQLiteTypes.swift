import Foundation
import SQLite3

enum SQLiteBinding {
  case integer(Int64)
  case text(String)
  case nullableText(String?)
}

enum SQLiteValue {
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

final class SQLiteConnection {
  private let database: OpaquePointer?
  private let makeError: (String) -> Error

  init(url: URL, makeError: @escaping (String) -> Error) throws {
    var database: OpaquePointer?
    guard sqlite3_open(url.path, &database) == SQLITE_OK else {
      let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "Could not open SQLite database."
      sqlite3_close(database)
      throw makeError(message)
    }
    self.database = database
    self.makeError = makeError
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
      result = sqlite3_bind_text(statement, index, value, -1, sqliteTransient)
    case .nullableText(let value):
      if let value {
        result = sqlite3_bind_text(statement, index, value, -1, sqliteTransient)
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

  private func error() -> Error {
    makeError(String(cString: sqlite3_errmsg(database)))
  }
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
