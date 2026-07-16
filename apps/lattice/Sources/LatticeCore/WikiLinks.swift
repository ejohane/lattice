import Foundation

public struct WikiLinkOccurrence: Equatable, Sendable {
  public let rawText: String
  public let displayText: String
  public let noteTitle: String?
  public let headingTitle: String?
  public let alias: String?
  public let targetNoteID: String?
  public let targetHeadingID: String?
  public let range: NSRange
  public let totalRange: NSRange

  public var visibleText: String {
    if let alias, !alias.isEmpty {
      return alias
    }
    return displayText
  }

  public var targetStem: String? {
    noteTitle?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
  }

  public var targetHeading: String? {
    headingTitle?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
  }

  public var isCurrentNoteHeadingLink: Bool {
    targetStem == nil && targetHeading != nil
  }

  public init(
    rawText: String,
    displayText: String,
    noteTitle: String?,
    headingTitle: String?,
    alias: String?,
    targetNoteID: String?,
    targetHeadingID: String?,
    range: NSRange,
    totalRange: NSRange
  ) {
    self.rawText = rawText
    self.displayText = displayText
    self.noteTitle = noteTitle
    self.headingTitle = headingTitle
    self.alias = alias
    self.targetNoteID = targetNoteID
    self.targetHeadingID = targetHeadingID
    self.range = range
    self.totalRange = totalRange
  }
}

public struct MarkdownHeading: Equatable, Sendable {
  public let title: String
  public let anchor: String
  public let level: Int
  public let range: NSRange
  public let headingID: String?

  public init(title: String, anchor: String, level: Int, range: NSRange, headingID: String?) {
    self.title = title
    self.anchor = anchor
    self.level = level
    self.range = range
    self.headingID = headingID
  }
}

public struct MarkdownLocalLink: Equatable, Sendable {
  public let label: String
  public let destination: String
  public let range: NSRange

  public init(label: String, destination: String, range: NSRange) {
    self.label = label
    self.destination = destination
    self.range = range
  }
}

public enum WikiLinkRenderStatus: String, Equatable, Sendable {
  case resolved
  case ambiguous
  case broken
}

public struct WikiLinkRenderState: Equatable, Sendable {
  public let range: NSRange
  public let status: WikiLinkRenderStatus

  public init(range: NSRange, status: WikiLinkRenderStatus) {
    self.range = range
    self.status = status
  }
}

public struct WikiNoteCandidate: Identifiable, Equatable, Sendable {
  public let id: String
  public let note: SavedNote
  public let noteID: String
  public let filenameStem: String
  public let title: String
  public let relativePath: String

  public init(note: SavedNote, noteID: String, filenameStem: String, title: String, relativePath: String) {
    self.id = noteID
    self.note = note
    self.noteID = noteID
    self.filenameStem = filenameStem
    self.title = title
    self.relativePath = relativePath
  }
}

public struct WikiHeadingCandidate: Identifiable, Equatable, Sendable {
  public let id: String
  public let noteID: String
  public let note: SavedNote
  public let title: String
  public let anchor: String
  public let headingID: String?
  public let level: Int

  public init(
    noteID: String,
    note: SavedNote,
    title: String,
    anchor: String,
    headingID: String?,
    level: Int
  ) {
    self.noteID = noteID
    self.note = note
    self.title = title
    self.anchor = anchor
    self.headingID = headingID
    self.level = level
    self.id = "\(noteID)#\(headingID ?? anchor)"
  }
}

public struct WikiBacklink: Equatable, Sendable {
  public let source: SavedNote
  public let sourceTitle: String
  public let targetNoteID: String
  public let rawText: String

  public init(source: SavedNote, sourceTitle: String, targetNoteID: String, rawText: String) {
    self.source = source
    self.sourceTitle = sourceTitle
    self.targetNoteID = targetNoteID
    self.rawText = rawText
  }
}

public enum MarkdownDocumentMetadata {
  public static let latticeIDKey = "id"
  public static let latticeCreatedAtKey = "created_at"
  public static let latticeKindKey = "kind"

  public enum NoteKind: String, Equatable, Sendable {
    case person
  }

  public static func noteID(in rawBody: String) -> String? {
    guard let frontMatter = frontMatter(in: rawBody) else {
      return nil
    }
    let pattern = #"(?m)^\s*id:\s*([A-Za-z0-9._:-]+)\s*$"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else {
      return nil
    }
    let range = NSRange(location: 0, length: (frontMatter as NSString).length)
    guard let match = regex.firstMatch(in: frontMatter, range: range) else {
      return nil
    }
    return (frontMatter as NSString).substring(with: match.range(at: 1)).nilIfEmpty
  }

  public static func createdAt(in rawBody: String) -> Date? {
    guard let frontMatter = frontMatter(in: rawBody) else {
      return nil
    }
    let pattern = #"(?m)^\s*created_at:\s*([^\s]+)\s*$"#
    guard
      let regex = try? NSRegularExpression(pattern: pattern),
      let match = regex.firstMatch(
        in: frontMatter,
        range: NSRange(location: 0, length: (frontMatter as NSString).length)
      )
    else {
      return nil
    }
    let value = (frontMatter as NSString).substring(with: match.range(at: 1))
    return ISO8601DateFormatter().date(from: value)
  }

  public static func kind(in rawBody: String) -> NoteKind? {
    guard let frontMatter = frontMatter(in: rawBody) else {
      return nil
    }
    let pattern = #"(?m)^\s*kind:\s*([A-Za-z0-9_-]+)\s*$"#
    guard
      let regex = try? NSRegularExpression(pattern: pattern),
      let match = regex.firstMatch(
        in: frontMatter,
        range: NSRange(location: 0, length: (frontMatter as NSString).length)
      )
    else {
      return nil
    }
    return NoteKind(rawValue: (frontMatter as NSString).substring(with: match.range(at: 1)))
  }

  public static func ensureNoteID(in rawBody: String, id: String = UUID().uuidString) -> String {
    ensureNoteMetadata(in: rawBody, id: id, createdAt: nil)
  }

  public static func ensureNoteMetadata(
    in rawBody: String,
    id: String = UUID().uuidString,
    createdAt: Date?
  ) -> String {
    let existingID = noteID(in: rawBody)
    let existingCreatedAt = self.createdAt(in: rawBody)
    guard existingID == nil || (createdAt != nil && existingCreatedAt == nil) else {
      return rawBody
    }

    guard let frontMatterRange = frontMatterRange(in: rawBody) else {
      var metadataLines = ["  id: \(existingID ?? id)"]
      if let createdAt {
        metadataLines.append("  created_at: \(ISO8601DateFormatter().string(from: createdAt))")
      }
      let prefix = """
        ---
        lattice:
        \(metadataLines.joined(separator: "\n"))
        ---

        """
      return prefix + rawBody.trimmingLeadingNewlines()
    }

    let nsString = rawBody as NSString
    let frontMatter = nsString.substring(with: frontMatterRange)
    let frontMatterNSString = frontMatter as NSString
    let latticePattern = #"(?m)^\s*lattice:\s*$"#
    let latticeMatch = (try? NSRegularExpression(pattern: latticePattern))?.firstMatch(
      in: frontMatter,
      range: NSRange(location: 0, length: frontMatterNSString.length)
    )

    var additions: [String] = []
    if existingID == nil {
      additions.append("  id: \(id)")
    }
    if let createdAt, existingCreatedAt == nil {
      additions.append("  created_at: \(ISO8601DateFormatter().string(from: createdAt))")
    }
    guard !additions.isEmpty else {
      return rawBody
    }

    let insertionLocation: Int
    let insertionText: String
    if let latticeMatch {
      let latticeLineRange = frontMatterNSString.lineRange(for: latticeMatch.range)
      insertionLocation = latticeLineRange.location + latticeLineRange.length
      insertionText = additions.joined(separator: "\n") + "\n"
    } else {
      let closingLineStart = frontMatterNSString.lineRange(
        for: NSRange(location: max(0, frontMatterNSString.length - 1), length: 0)
      ).location
      insertionLocation = closingLineStart
      insertionText = "lattice:\n" + additions.joined(separator: "\n") + "\n"
    }

    return nsString.replacingCharacters(
      in: NSRange(location: insertionLocation, length: 0),
      with: insertionText
    )
  }

  public static func ensurePersonMetadata(
    in rawBody: String,
    id: String = UUID().uuidString,
    createdAt: Date?
  ) -> String {
    let body = ensureNoteMetadata(in: rawBody, id: id, createdAt: createdAt)
    guard kind(in: body) != .person, let frontMatterRange = frontMatterRange(in: body) else {
      return body
    }

    let nsString = body as NSString
    let frontMatter = nsString.substring(with: frontMatterRange)
    let frontMatterNSString = frontMatter as NSString
    let latticePattern = #"(?m)^\s*lattice:\s*$"#
    guard let latticeMatch = (try? NSRegularExpression(pattern: latticePattern))?.firstMatch(
      in: frontMatter,
      range: NSRange(location: 0, length: frontMatterNSString.length)
    ) else {
      return body
    }
    let latticeLineRange = frontMatterNSString.lineRange(for: latticeMatch.range)
    let insertionLocation = latticeLineRange.location + latticeLineRange.length
    return nsString.replacingCharacters(
      in: NSRange(location: insertionLocation, length: 0),
      with: "  kind: person\n"
    )
  }

  public static func strippingFrontMatter(from rawBody: String) -> String {
    guard let range = frontMatterRange(in: rawBody) else {
      return rawBody
    }
    let nsString = rawBody as NSString
    return nsString.substring(from: NSMaxRange(range)).trimmingLeadingNewlines()
  }

  public static func frontMatterRange(in rawBody: String) -> NSRange? {
    let nsString = rawBody as NSString
    guard nsString.length >= 3, nsString.substring(with: NSRange(location: 0, length: 3)) == "---" else {
      return nil
    }

    var location = 0
    var isFirstLine = true
    while location < nsString.length {
      let lineRange = nsString.lineRange(for: NSRange(location: location, length: 0))
      let line = nsString.substring(with: lineRange).trimmingCharacters(in: .whitespacesAndNewlines)
      if !isFirstLine && line == "---" {
        return NSRange(location: 0, length: NSMaxRange(lineRange))
      }
      isFirstLine = false
      location = NSMaxRange(lineRange)
    }

    return nil
  }

  private static func frontMatter(in rawBody: String) -> String? {
    guard let range = frontMatterRange(in: rawBody) else {
      return nil
    }
    let nsString = rawBody as NSString
    return nsString.substring(with: range)
  }
}

public enum WikiLinkParser {
  public static func links(in text: String) -> [WikiLinkOccurrence] {
    let nsString = text as NSString
    let fullRange = NSRange(location: 0, length: nsString.length)
    guard fullRange.length > 0 else {
      return []
    }

    let skippedRanges = codeBlockRanges(in: nsString)
    guard let regex = try? NSRegularExpression(
      pattern: #"\[\[([^\]\n]+)\]\](?:<!--\s*lattice:([^>]*)-->)?"#
    ) else {
      return []
    }

    return regex.matches(in: text, range: fullRange).compactMap { match in
      guard !intersectsAny(match.range, skippedRanges) else {
        return nil
      }
      let rawTarget = nsString.substring(with: match.range(at: 1))
      let metadata = match.range(at: 2).location == NSNotFound
        ? [:]
        : parseMetadata(nsString.substring(with: match.range(at: 2)))
      let parsed = parseTarget(rawTarget)
      let range = match.range(at: 0)
      let linkOnlyRange = NSRange(location: range.location, length: match.range(at: 1).length + 4)
      return WikiLinkOccurrence(
        rawText: nsString.substring(with: linkOnlyRange),
        displayText: parsed.displayText,
        noteTitle: parsed.noteTitle,
        headingTitle: parsed.headingTitle,
        alias: parsed.alias,
        targetNoteID: metadata["target"],
        targetHeadingID: metadata["heading"],
        range: linkOnlyRange,
        totalRange: range
      )
    }
  }

  public static func link(at characterIndex: Int, in text: String) -> WikiLinkOccurrence? {
    links(in: text).first { NSLocationInRange(characterIndex, $0.range) || NSLocationInRange(characterIndex, $0.totalRange) }
  }

  public static func targetComment(noteID: String, headingID: String? = nil) -> String {
    if let headingID, !headingID.isEmpty {
      return "<!-- lattice:target=\(noteID);heading=\(headingID) -->"
    }
    return "<!-- lattice:target=\(noteID) -->"
  }

  public static func replacingTargetComment(
    in text: String,
    for link: WikiLinkOccurrence,
    noteID: String,
    headingID: String? = nil
  ) -> String {
    let nsString = text as NSString
    let replacement = link.rawText + targetComment(noteID: noteID, headingID: headingID)
    return nsString.replacingCharacters(in: link.totalRange, with: replacement)
  }

  public static func autocompleteContext(in text: String, selection: NSRange) -> WikiAutocompleteContext? {
    guard selection.length == 0 else {
      return nil
    }
    let nsString = text as NSString
    let location = min(selection.location, nsString.length)
    let prefix = nsString.substring(to: location)
    guard let start = prefix.range(of: "[[", options: .backwards) else {
      return nil
    }
    let afterStart = String(prefix[start.upperBound...])
    guard !afterStart.contains("]]"), !afterStart.contains("\n") else {
      return nil
    }
    let replacementRange = NSRange(
      location: (prefix as NSString).range(of: "[[", options: .backwards).location,
      length: location - (prefix as NSString).range(of: "[[", options: .backwards).location
    )
    if afterStart.hasPrefix("#") {
      return .currentNoteHeading(prefix: String(afterStart.dropFirst()), replacementRange: replacementRange)
    }
    if let hashIndex = afterStart.firstIndex(of: "#") {
      let stem = String(afterStart[..<hashIndex])
      let headingPrefix = String(afterStart[afterStart.index(after: hashIndex)...])
      return .noteHeading(noteStem: stem, prefix: headingPrefix, replacementRange: replacementRange)
    }
    return .note(prefix: afterStart, replacementRange: replacementRange)
  }

  public static func obsidianAnchor(for heading: String) -> String {
    let allowedPunctuation = CharacterSet(charactersIn: "-_ ")
    let scalars = heading
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
      .unicodeScalars
      .filter { scalar in
        CharacterSet.alphanumerics.contains(scalar)
          || allowedPunctuation.contains(scalar)
      }
    return String(String.UnicodeScalarView(scalars)).replacingOccurrences(of: " ", with: "-")
  }

  private static func parseTarget(_ rawTarget: String) -> ParsedTarget {
    let parts = rawTarget.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
    let target = String(parts[0])
    let alias = parts.count > 1 ? String(parts[1]).nilIfEmpty : nil
    let targetParts = target.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
    let noteTitle = targetParts[0].isEmpty ? nil : String(targetParts[0])
    let headingTitle = targetParts.count > 1 ? String(targetParts[1]).nilIfEmpty : nil
    return ParsedTarget(
      displayText: target,
      noteTitle: noteTitle,
      headingTitle: headingTitle,
      alias: alias
    )
  }

  private static func parseMetadata(_ metadata: String) -> [String: String] {
    metadata.split(separator: ";").reduce(into: [:]) { result, part in
      let pair = part.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
      guard pair.count == 2 else {
        return
      }
      result[String(pair[0]).trimmingCharacters(in: .whitespacesAndNewlines)] =
        String(pair[1]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
  }

  private static func codeBlockRanges(in nsString: NSString) -> [NSRange] {
    var ranges: [NSRange] = []
    var start: Int?
    var location = 0
    while location < nsString.length {
      let lineRange = nsString.lineRange(for: NSRange(location: location, length: 0))
      let line = nsString.substring(with: lineRange)
      if line.trimmingCharacters(in: .whitespaces).hasPrefix("```")
        || line.trimmingCharacters(in: .whitespaces).hasPrefix("~~~") {
        if let existingStart = start {
          ranges.append(NSRange(location: existingStart, length: NSMaxRange(lineRange) - existingStart))
          start = nil
        } else {
          start = lineRange.location
        }
      }
      location = NSMaxRange(lineRange)
    }
    if let start {
      ranges.append(NSRange(location: start, length: nsString.length - start))
    }
    return ranges
  }

  private static func intersectsAny(_ range: NSRange, _ ranges: [NSRange]) -> Bool {
    ranges.contains { NSIntersectionRange(range, $0).length > 0 }
  }
}

public enum WikiAutocompleteContext: Equatable, Sendable {
  case note(prefix: String, replacementRange: NSRange)
  case noteHeading(noteStem: String, prefix: String, replacementRange: NSRange)
  case currentNoteHeading(prefix: String, replacementRange: NSRange)

  public var replacementRange: NSRange {
    switch self {
    case .note(_, let range), .noteHeading(_, _, let range), .currentNoteHeading(_, let range):
      return range
    }
  }
}

public enum MarkdownHeadingScanner {
  public static func headings(in text: String) -> [MarkdownHeading] {
    let nsString = text as NSString
    var headings: [MarkdownHeading] = []
    var location = 0
    while location < nsString.length {
      let lineRange = nsString.lineRange(for: NSRange(location: location, length: 0))
      let line = nsString.substring(with: lineRange)
      if let match = firstMatch(#"^\s*(#{1,6})\s+(.+?)(?:\s*<!--\s*lattice:heading=([A-Za-z0-9._:-]+)\s*-->)?\s*$"#, in: line) {
        let level = match.range(at: 1).length
        let title = (line as NSString).substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespaces)
        let headingID = match.range(at: 3).location == NSNotFound ? nil : (line as NSString).substring(with: match.range(at: 3))
        if !title.isEmpty {
          headings.append(MarkdownHeading(
            title: title,
            anchor: WikiLinkParser.obsidianAnchor(for: title),
            level: level,
            range: shifted(match.range(at: 2), by: lineRange.location),
            headingID: headingID
          ))
        }
      }
      location = NSMaxRange(lineRange)
    }
    return headings
  }

  private static func firstMatch(_ pattern: String, in string: String) -> NSTextCheckingResult? {
    guard let regex = try? NSRegularExpression(pattern: pattern) else {
      return nil
    }
    return regex.firstMatch(in: string, range: NSRange(location: 0, length: (string as NSString).length))
  }

  private static func shifted(_ range: NSRange, by offset: Int) -> NSRange {
    NSRange(location: range.location + offset, length: range.length)
  }
}

public enum MarkdownLocalLinkParser {
  public static func links(in text: String) -> [MarkdownLocalLink] {
    let nsString = text as NSString
    let fullRange = NSRange(location: 0, length: nsString.length)
    guard
      fullRange.length > 0,
      let regex = try? NSRegularExpression(pattern: #"(?<!!)\[([^\]\n]+)\]\(([^)\n]+\.md(?:#[^)\n]+)?)\)"#)
    else {
      return []
    }
    return regex.matches(in: text, range: fullRange).map { match in
      MarkdownLocalLink(
        label: nsString.substring(with: match.range(at: 1)),
        destination: nsString.substring(with: match.range(at: 2)),
        range: match.range(at: 0)
      )
    }
  }

  public static func link(at characterIndex: Int, in text: String) -> MarkdownLocalLink? {
    links(in: text).first { NSLocationInRange(characterIndex, $0.range) }
  }
}

private struct ParsedTarget {
  let displayText: String
  let noteTitle: String?
  let headingTitle: String?
  let alias: String?
}

private extension String {
  var nilIfEmpty: String? {
    isEmpty ? nil : self
  }

  func trimmingLeadingNewlines() -> String {
    var result = self
    while result.first == "\n" || result.first == "\r" {
      result.removeFirst()
    }
    return result
  }
}
