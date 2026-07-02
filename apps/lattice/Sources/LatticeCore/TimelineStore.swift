import Foundation

public struct TimelineEntry: Equatable, Identifiable, Sendable {
  public let id: String
  public let createdAt: Date
  public var body: String

  public init(id: String = UUID().uuidString, createdAt: Date = Date(), body: String) {
    self.id = id
    self.createdAt = createdAt
    self.body = body
  }
}

public struct TimelineDocument: Equatable, Sendable {
  public var entries: [TimelineEntry]

  public init(entries: [TimelineEntry] = []) {
    self.entries = entries
  }
}

public enum TimelineStoreError: LocalizedError, Equatable, Sendable {
  case invalidTimelineFile(String)

  public var errorDescription: String? {
    switch self {
    case .invalidTimelineFile(let path):
      return "Could not read timeline file: \(path)"
    }
  }
}

public final class TimelineStore {
  public static let filename = "Timeline.md"

  private let fileManager: FileManager
  private let now: () -> Date
  private let idProvider: () -> String
  private let encoder: JSONEncoder
  private let decoder: JSONDecoder

  public init(
    fileManager: FileManager = .default,
    now: @escaping () -> Date = Date.init,
    idProvider: @escaping () -> String = { UUID().uuidString }
  ) {
    self.fileManager = fileManager
    self.now = now
    self.idProvider = idProvider
    encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
  }

  public func timelineURL(notesFolderURL: URL) -> URL {
    notesFolderURL.standardizedFileURL.appendingPathComponent(Self.filename)
  }

  public func load(notesFolderURL: URL) throws -> TimelineDocument {
    let fileURL = timelineURL(notesFolderURL: notesFolderURL)
    guard fileManager.fileExists(atPath: fileURL.path) else {
      return TimelineDocument()
    }
    guard let raw = String(data: try Data(contentsOf: fileURL), encoding: .utf8) else {
      throw TimelineStoreError.invalidTimelineFile(fileURL.path)
    }
    return parse(raw)
  }

  public func save(_ document: TimelineDocument, notesFolderURL: URL) throws {
    let fileURL = timelineURL(notesFolderURL: notesFolderURL)
    try fileManager.createDirectory(
      at: fileURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try render(document).write(to: fileURL, atomically: true, encoding: .utf8)
  }

  public func parse(_ raw: String) -> TimelineDocument {
    let normalized = raw.replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
    let blocks = normalized.components(separatedBy: TimelineMarkdown.blockSeparator)
    var pendingMetadata: TimelineEntryMetadata?
    var entries: [TimelineEntry] = []

    for block in blocks {
      let trimmed = block.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty else {
        continue
      }

      if let metadata = metadata(from: trimmed) {
        pendingMetadata = metadata
        continue
      }

      if let firstLineEnd = trimmed.firstIndex(of: "\n") {
        let firstLine = String(trimmed[..<firstLineEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
        let rest = String(trimmed[trimmed.index(after: firstLineEnd)...]).trimmingCharacters(in: .whitespacesAndNewlines)
        if let metadata = metadata(from: firstLine), !rest.isEmpty {
          entries.append(TimelineEntry(id: metadata.id, createdAt: metadata.createdAt, body: rest))
          pendingMetadata = nil
          continue
        }
      }

      let entry = TimelineEntry(
        id: pendingMetadata?.id ?? idProvider(),
        createdAt: pendingMetadata?.createdAt ?? now(),
        body: trimmed
      )
      entries.append(entry)
      pendingMetadata = nil
    }

    return TimelineDocument(entries: entries)
  }

  public func render(_ document: TimelineDocument) -> String {
    let blocks = document.entries
      .filter { !$0.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
      .map { entry in
        "\(metadataComment(for: entry))\n\(entry.body.trimmingCharacters(in: .whitespacesAndNewlines))"
      }
    guard !blocks.isEmpty else {
      return ""
    }
    return blocks.joined(separator: "\n\n") + "\n"
  }

  private func metadata(from block: String) -> TimelineEntryMetadata? {
    guard block.hasPrefix("<!--"), block.hasSuffix("-->") else {
      return nil
    }
    let comment = block
      .dropFirst(4)
      .dropLast(3)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard comment.hasPrefix(TimelineMarkdown.metadataPrefix) else {
      return nil
    }
    let attributes = TimelineMarkdown.attributes(in: String(comment.dropFirst(TimelineMarkdown.metadataPrefix.count)))
    guard
      let id = attributes["id"],
      let createdAtString = attributes["createdAt"],
      let createdAt = TimelineMarkdown.iso8601Date(from: createdAtString)
    else {
      return nil
    }
    return TimelineEntryMetadata(id: id, createdAt: createdAt)
  }

  private func metadataComment(for entry: TimelineEntry) -> String {
    let id = TimelineMarkdown.escapedAttribute(entry.id)
    let createdAt = TimelineMarkdown.iso8601String(from: entry.createdAt)
    return "<!-- \(TimelineMarkdown.metadataPrefix) id=\"\(id)\" createdAt=\"\(createdAt)\" -->"
  }
}

private struct TimelineEntryMetadata {
  let id: String
  let createdAt: Date
}

private enum TimelineMarkdown {
  static let metadataPrefix = "lattice-timeline-entry"
  static let blockSeparator = "\n\n"

  static func attributes(in text: String) -> [String: String] {
    let pattern = #"([A-Za-z0-9_-]+)="([^"]*)""#
    guard let regex = try? NSRegularExpression(pattern: pattern) else {
      return [:]
    }
    let nsText = text as NSString
    let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
    return Dictionary(uniqueKeysWithValues: matches.compactMap { match in
      guard match.numberOfRanges == 3 else {
        return nil
      }
      let key = nsText.substring(with: match.range(at: 1))
      let value = nsText.substring(with: match.range(at: 2))
      return (key, value)
    })
  }

  static func escapedAttribute(_ value: String) -> String {
    value
      .replacingOccurrences(of: "&", with: "&amp;")
      .replacingOccurrences(of: "\"", with: "&quot;")
  }

  static func iso8601String(from date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    return formatter.string(from: date)
  }

  static func iso8601Date(from string: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    return formatter.date(from: string)
  }
}
