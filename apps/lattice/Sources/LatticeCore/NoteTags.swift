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

public struct NoteTagSummary: Identifiable, Equatable, Sendable {
  public let name: String
  public let normalizedName: String
  public let noteCount: Int

  public init(name: String, normalizedName: String? = nil, noteCount: Int) {
    self.name = name
    self.normalizedName = normalizedName ?? NoteTagParser.normalizedName(name)
    self.noteCount = noteCount
  }

  public var id: String {
    normalizedName
  }
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
    guard let regex = try? NSRegularExpression(pattern: candidatePattern) else {
      return []
    }

    let nsString = text as NSString
    let fullRange = NSRange(location: 0, length: nsString.length)
    let excludedRanges = codeRanges(in: nsString)
    return regex.matches(in: text, range: fullRange).compactMap { match in
      guard
        match.range(at: 1).location != NSNotFound,
        !intersects(match.range, ranges: excludedRanges)
      else {
        return nil
      }
      let name = nsString.substring(with: match.range(at: 1))
      guard isValidName(name) else {
        return nil
      }
      return NoteTagOccurrence(name: name, range: match.range)
    }
  }

  public static func tag(at characterIndex: Int, in text: String) -> NoteTagOccurrence? {
    tags(in: text).first { occurrence in
      characterIndex >= occurrence.range.location && characterIndex < NSMaxRange(occurrence.range)
    }
  }

  public static func autocompleteContext(
    in text: String,
    selection: NSRange
  ) -> NoteTagAutocompleteContext? {
    let nsString = text as NSString
    guard
      selection.length == 0,
      selection.location >= 0,
      selection.location <= nsString.length,
      let regex = try? NSRegularExpression(pattern: autocompletePattern)
    else {
      return nil
    }

    let lineRange = nsString.lineRange(for: NSRange(location: selection.location, length: 0))
    let rangeBeforeCursor = NSRange(
      location: lineRange.location,
      length: max(0, selection.location - lineRange.location)
    )
    guard
      let match = regex.firstMatch(in: text, range: rangeBeforeCursor),
      NSMaxRange(match.range) == selection.location,
      !intersects(match.range, ranges: codeRanges(in: nsString))
    else {
      return nil
    }

    let prefixRange = match.range(at: 1)
    let prefix = prefixRange.location == NSNotFound ? "" : nsString.substring(with: prefixRange)
    return NoteTagAutocompleteContext(prefix: prefix, replacementRange: match.range)
  }

  public static func normalizedName(_ name: String) -> String {
    name.lowercased()
  }

  public static func isValidName(_ name: String) -> Bool {
    guard !name.isEmpty else {
      return false
    }

    let allowedPunctuation = CharacterSet(charactersIn: "_-/")
    let allowed = CharacterSet.alphanumerics.union(allowedPunctuation)
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
    let matches = tags(in: text).filter { $0.normalizedName == normalizedName }
    guard !matches.isEmpty else {
      return text
    }

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

  private static func deletionRange(for range: NSRange, in string: NSString) -> NSRange {
    let previousLocation = range.location - 1
    let nextLocation = NSMaxRange(range)
    let hasPreviousSpace = previousLocation >= 0 && isHorizontalWhitespace(string.character(at: previousLocation))
    let hasNextSpace = nextLocation < string.length && isHorizontalWhitespace(string.character(at: nextLocation))

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

  private static func codeRanges(in nsString: NSString) -> [NSRange] {
    let fencedRanges = fencedCodeRanges(in: nsString)
    guard
      let inlineRegex = try? NSRegularExpression(pattern: #"`+[^`\n]+`+"#),
      let openInlineRegex = try? NSRegularExpression(pattern: #"`+[^`\n]*$"#, options: [.anchorsMatchLines])
    else {
      return fencedRanges
    }
    let fullRange = NSRange(location: 0, length: nsString.length)
    let inlineRanges = inlineRegex.matches(in: nsString as String, range: fullRange)
      .map(\.range)
      .filter { !intersects($0, ranges: fencedRanges) }
    let openInlineRanges = openInlineRegex.matches(in: nsString as String, range: fullRange)
      .map(\.range)
      .filter { !intersects($0, ranges: fencedRanges + inlineRanges) }
    return fencedRanges + inlineRanges + openInlineRanges
  }

  private static func fencedCodeRanges(in nsString: NSString) -> [NSRange] {
    var ranges: [NSRange] = []
    var blockStart: Int?
    var fenceMarker: String?
    var location = 0

    while location < nsString.length {
      let lineRange = nsString.lineRange(for: NSRange(location: location, length: 0))
      let line = nsString.substring(with: lineRange)
        .trimmingCharacters(in: .whitespacesAndNewlines)
      let marker: String?
      if line.hasPrefix("```") {
        marker = "```"
      } else if line.hasPrefix("~~~") {
        marker = "~~~"
      } else {
        marker = nil
      }

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
      ranges.append(NSRange(location: start, length: nsString.length - start))
    }
    return ranges
  }

  private static func intersects(_ range: NSRange, ranges: [NSRange]) -> Bool {
    ranges.contains { NSIntersectionRange(range, $0).length > 0 }
  }
}
