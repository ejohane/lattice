import Foundation

public struct ActivityEvent: Codable, Equatable, Identifiable, Sendable {
  public enum Kind: String, Codable, Sendable {
    case captureCreated
    case noteCreated
    case noteEdited
    case noteOpened
  }

  public let id: String
  public let timestamp: Date
  public let kind: Kind
  public let noteID: String?
  public let noteRelativePath: String?
  public let noteTitle: String?
  public let text: String?
  public let beforeExcerpt: String?
  public let afterExcerpt: String?

  public init(
    id: String = UUID().uuidString,
    timestamp: Date = Date(),
    kind: Kind,
    noteID: String? = nil,
    noteRelativePath: String? = nil,
    noteTitle: String? = nil,
    text: String? = nil,
    beforeExcerpt: String? = nil,
    afterExcerpt: String? = nil
  ) {
    self.id = id
    self.timestamp = timestamp
    self.kind = kind
    self.noteID = noteID
    self.noteRelativePath = noteRelativePath
    self.noteTitle = noteTitle
    self.text = text
    self.beforeExcerpt = beforeExcerpt
    self.afterExcerpt = afterExcerpt
  }
}

public protocol ActivityStoring: AnyObject {
  func append(_ event: ActivityEvent, notesFolderURL: URL) throws
  func events(on day: Date, notesFolderURL: URL) throws -> [ActivityEvent]
}

public enum ActivityStoreError: LocalizedError, Equatable, Sendable {
  case invalidEventData(String)

  public var errorDescription: String? {
    switch self {
    case .invalidEventData(let path):
      return "Could not read activity event in \(path)."
    }
  }
}

public final class ActivityStore: ActivityStoring {
  private let fileManager: FileManager
  private let calendar: Calendar
  private let encoder: JSONEncoder
  private let decoder: JSONDecoder

  public init(
    fileManager: FileManager = .default,
    calendar: Calendar = .current
  ) {
    self.fileManager = fileManager
    self.calendar = calendar
    encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
  }

  public func append(_ event: ActivityEvent, notesFolderURL: URL) throws {
    let fileURL = activityFileURL(for: event.timestamp, notesFolderURL: notesFolderURL)
    try fileManager.createDirectory(
      at: fileURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    let data = try encoder.encode(event)
    let line = data + Data([0x0a])
    if fileManager.fileExists(atPath: fileURL.path) {
      let handle = try FileHandle(forWritingTo: fileURL)
      defer { try? handle.close() }
      try handle.seekToEnd()
      try handle.write(contentsOf: line)
    } else {
      try line.write(to: fileURL, options: .atomic)
    }
  }

  public func events(on day: Date, notesFolderURL: URL) throws -> [ActivityEvent] {
    let fileURL = activityFileURL(for: day, notesFolderURL: notesFolderURL)
    guard fileManager.fileExists(atPath: fileURL.path) else {
      return []
    }
    let data = try Data(contentsOf: fileURL)
    guard let contents = String(data: data, encoding: .utf8) else {
      throw ActivityStoreError.invalidEventData(fileURL.path)
    }
    return try contents
      .split(separator: "\n", omittingEmptySubsequences: true)
      .map { line in
        guard let data = String(line).data(using: .utf8) else {
          throw ActivityStoreError.invalidEventData(fileURL.path)
        }
        return try decoder.decode(ActivityEvent.self, from: data)
      }
      .sorted { $0.timestamp < $1.timestamp }
  }

  public func activityFileURL(for day: Date, notesFolderURL: URL) -> URL {
    notesFolderURL
      .standardizedFileURL
      .appendingPathComponent(".lattice", isDirectory: true)
      .appendingPathComponent("activity", isDirectory: true)
      .appendingPathComponent("\(Self.localDateString(from: day, calendar: calendar)).jsonl")
  }

  private static func localDateString(from date: Date, calendar: Calendar) -> String {
    let formatter = DateFormatter()
    formatter.calendar = calendar
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = calendar.timeZone
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: date)
  }
}
