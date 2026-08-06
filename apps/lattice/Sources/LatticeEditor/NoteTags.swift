import Foundation

public struct NoteTagOccurrence: Equatable, Sendable {
  public let name: String
  public let normalizedName: String
  public let range: NSRange

  public init(name: String, normalizedName: String? = nil, range: NSRange) {
    self.name = name
    self.normalizedName = normalizedName ?? NoteTagParser.normalizedName(name)
    self.range = range
  }
}

public struct NoteTagSummary: Identifiable, Equatable, Hashable, Sendable {
  public let name: String
  public let normalizedName: String
  public let noteCount: Int

  public init(name: String, normalizedName: String? = nil, noteCount: Int) {
    self.name = name
    self.normalizedName = normalizedName ?? NoteTagParser.normalizedName(name)
    self.noteCount = noteCount
  }

  public var id: String { normalizedName }
}

public struct NoteTagAutocompleteContext: Equatable, Sendable {
  public let prefix: String
  public let replacementRange: NSRange

  public init(prefix: String, replacementRange: NSRange) {
    self.prefix = prefix
    self.replacementRange = replacementRange
  }
}

public enum NoteTagParser {
  private static let candidatePattern = ##"(?<![\p{L}\p{N}_/\\#-])#([\p{L}\p{N}_/-]+)"##
  private static let autocompletePattern = ##"(?<![\p{L}\p{N}_/\\#-])#([\p{L}\p{N}_/-]*)$"##

  public static func tags(in text: String) -> [NoteTagOccurrence] {
    guard let regex = try? NSRegularExpression(pattern: candidatePattern) else { return [] }

    let source = text as NSString
    let fullRange = NSRange(location: 0, length: source.length)
    let excluded = excludedRanges(in: source)
    return regex.matches(in: text, range: fullRange).compactMap { match in
      guard match.range(at: 1).location != NSNotFound,
            !intersects(match.range, ranges: excluded)
      else { return nil }

      let name = source.substring(with: match.range(at: 1))
      guard isValidName(name) else { return nil }
      return NoteTagOccurrence(name: name, range: match.range)
    }
  }

  public static func tag(at characterIndex: Int, in text: String) -> NoteTagOccurrence? {
    tags(in: text).first {
      characterIndex >= $0.range.location && characterIndex < NSMaxRange($0.range)
    }
  }

  public static func autocompleteContext(
    in text: String,
    selection: NSRange
  ) -> NoteTagAutocompleteContext? {
    let source = text as NSString
    guard selection.length == 0,
          selection.location >= 0,
          selection.location <= source.length,
          let regex = try? NSRegularExpression(pattern: autocompletePattern)
    else { return nil }

    let lineRange = source.lineRange(for: NSRange(location: selection.location, length: 0))
    let beforeCursor = NSRange(
      location: lineRange.location,
      length: max(0, selection.location - lineRange.location)
    )
    guard let match = regex.firstMatch(in: text, range: beforeCursor),
          NSMaxRange(match.range) == selection.location,
          !intersects(match.range, ranges: excludedRanges(in: source))
    else { return nil }

    let prefixRange = match.range(at: 1)
    let prefix = prefixRange.location == NSNotFound ? "" : source.substring(with: prefixRange)
    guard isValidAutocompletePrefix(prefix) else { return nil }
    return NoteTagAutocompleteContext(prefix: prefix, replacementRange: match.range)
  }

  public static func normalizedName(_ name: String) -> String {
    name.precomposedStringWithCanonicalMapping.lowercased()
  }

  public static func isValidName(_ name: String) -> Bool {
    guard !name.isEmpty else { return false }
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-/"))
    let scalars = name.unicodeScalars
    return scalars.allSatisfy { allowed.contains($0) }
      && scalars.contains { CharacterSet.letters.contains($0) }
      && name.first != "/"
      && name.last != "/"
      && !name.contains("//")
  }

  public static func replacingTag(
    normalizedName: String,
    with replacementName: String?,
    in text: String
  ) -> String {
    if let replacementName, !isValidName(replacementName) { return text }
    let identity = self.normalizedName(normalizedName)
    let matches = tags(in: text).filter { $0.normalizedName == identity }
    guard !matches.isEmpty else { return text }

    let mutable = NSMutableString(string: text)
    let replacement = replacementName.map { "#\($0)" }
    for match in matches.reversed() {
      if let replacement {
        mutable.replaceCharacters(in: match.range, with: replacement)
      } else {
        mutable.replaceCharacters(in: deletionRange(for: match.range, in: mutable), with: "")
      }
    }
    return mutable as String
  }

  private static func isValidAutocompletePrefix(_ prefix: String) -> Bool {
    guard !prefix.isEmpty else { return true }
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-/"))
    let scalars = prefix.unicodeScalars
    return scalars.allSatisfy { allowed.contains($0) }
      && scalars.contains { CharacterSet.letters.contains($0) }
      && prefix.first != "/"
      && !prefix.contains("//")
  }

  private static func deletionRange(for range: NSRange, in string: NSString) -> NSRange {
    let previousLocation = range.location - 1
    let nextLocation = NSMaxRange(range)
    let hasPreviousSpace = previousLocation >= 0
      && isHorizontalWhitespace(string.character(at: previousLocation))
    let hasNextSpace = nextLocation < string.length
      && isHorizontalWhitespace(string.character(at: nextLocation))

    if hasPreviousSpace && (!hasNextSpace || nextLocation == string.length) {
      return NSRange(location: previousLocation, length: range.length + 1)
    }
    if hasNextSpace {
      return NSRange(location: range.location, length: range.length + 1)
    }
    return range
  }

  private static func isHorizontalWhitespace(_ character: unichar) -> Bool {
    character == 9 || character == 32
  }

  private static func excludedRanges(in source: NSString) -> [NSRange] {
    let frontMatter = frontMatterRange(in: source).map { [$0] } ?? []
    let fenced = fencedCodeRanges(in: source)
    let fullRange = NSRange(location: 0, length: source.length)
    let patterns = [
      #"`+[^`\n]+`+"#,
      #"`+[^`\n]*$"#,
      #"\]\([^\n)]*\)"#,
      #"<[^>\n]+>"#,
      #"(?:https?://|www\.)\S+"#
    ]
    let inline = patterns.flatMap { pattern -> [NSRange] in
      guard let regex = try? NSRegularExpression(
        pattern: pattern,
        options: pattern.contains("$") ? [.anchorsMatchLines] : []
      ) else { return [] }
      return regex.matches(in: source as String, range: fullRange)
        .map(\.range)
        .filter { !intersects($0, ranges: frontMatter + fenced) }
    }
    return frontMatter + fenced + inline
  }

  private static func frontMatterRange(in source: NSString) -> NSRange? {
    guard source.length >= 4 else { return nil }
    let firstLine = source.lineRange(for: NSRange(location: 0, length: 0))
    guard source.substring(with: firstLine).trimmingCharacters(in: .newlines) == "---" else {
      return nil
    }

    var location = NSMaxRange(firstLine)
    while location < source.length {
      let lineRange = source.lineRange(for: NSRange(location: location, length: 0))
      let line = source.substring(with: lineRange).trimmingCharacters(in: .newlines)
      if line == "---" || line == "..." {
        return NSRange(location: 0, length: NSMaxRange(lineRange))
      }
      location = NSMaxRange(lineRange)
    }
    return nil
  }

  private static func fencedCodeRanges(in source: NSString) -> [NSRange] {
    var ranges: [NSRange] = []
    var blockStart: Int?
    var fenceMarker: String?
    var location = 0

    while location < source.length {
      let lineRange = source.lineRange(for: NSRange(location: location, length: 0))
      let line = source.substring(with: lineRange).trimmingCharacters(in: .whitespacesAndNewlines)
      let marker = line.hasPrefix("```") ? "```" : (line.hasPrefix("~~~") ? "~~~" : nil)
      if let marker {
        if let start = blockStart, fenceMarker == marker {
          ranges.append(NSRange(location: start, length: NSMaxRange(lineRange) - start))
          blockStart = nil
          fenceMarker = nil
        } else if blockStart == nil {
          blockStart = lineRange.location
          fenceMarker = marker
        }
      }
      location = NSMaxRange(lineRange)
    }

    if let start = blockStart {
      ranges.append(NSRange(location: start, length: source.length - start))
    }
    return ranges
  }

  private static func intersects(_ range: NSRange, ranges: [NSRange]) -> Bool {
    ranges.contains { NSIntersectionRange(range, $0).length > 0 }
  }
}
