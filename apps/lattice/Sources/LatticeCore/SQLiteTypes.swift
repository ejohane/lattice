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
