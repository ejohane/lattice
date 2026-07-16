import Foundation

public struct PersonCandidate: Identifiable, Equatable, Sendable {
  public let note: SavedNote
  public let noteID: String
  public let name: String
  public let relativePath: String

  public init(note: SavedNote, noteID: String, name: String, relativePath: String) {
    self.note = note
    self.noteID = noteID
    self.name = name
    self.relativePath = relativePath
  }

  public var id: String {
    noteID
  }
}

public struct PersonMentionOccurrence: Equatable, Sendable {
  public let name: String
  public let targetNoteID: String
  public let range: NSRange
  public let totalRange: NSRange

  public init(name: String, targetNoteID: String, range: NSRange, totalRange: NSRange) {
    self.name = name
    self.targetNoteID = targetNoteID
    self.range = range
    self.totalRange = totalRange
  }
}

public struct PersonMentionConnection: Equatable, Sendable {
  public let sourceNoteID: String
  public let targetNoteID: String
  public let name: String

  public init(sourceNoteID: String, targetNoteID: String, name: String) {
    self.sourceNoteID = sourceNoteID
    self.targetNoteID = targetNoteID
    self.name = name
  }
}

public struct PersonAutocompleteContext: Equatable, Sendable {
  public let name: String
  public let replacementRange: NSRange

  public init(name: String, replacementRange: NSRange) {
    self.name = name
    self.replacementRange = replacementRange
  }
}

public enum PersonMentionParser {
  private static let targetPattern = #"@([^<\n]+?)<!--\s*lattice:mention=([A-Za-z0-9._:-]+)\s*-->"#
  private static let autocompletePattern = #"(?<![\p{L}\p{N}_@])@([\p{L}\p{M}\p{N}.'’-]*(?: [\p{L}\p{M}\p{N}.'’-]*)*)$"#

  public static func mentions(in text: String) -> [PersonMentionOccurrence] {
    guard let regex = try? NSRegularExpression(pattern: targetPattern) else {
      return []
    }
    let nsString = text as NSString
    let fullRange = NSRange(location: 0, length: nsString.length)
    let excludedRanges = codeRanges(in: nsString)
    return regex.matches(in: text, range: fullRange).compactMap { match in
      guard
        match.range(at: 1).location != NSNotFound,
        match.range(at: 2).location != NSNotFound,
        !intersects(match.range, ranges: excludedRanges)
      else {
        return nil
      }
      let rawName = nsString.substring(with: match.range(at: 1))
      let name = rawName.trimmingCharacters(in: .whitespaces)
      guard isValidName(name) else {
        return nil
      }
      let leadingWhitespaceCount = rawName.utf16.count - rawName.drop(while: { $0.isWhitespace }).utf16.count
      let mentionRange = NSRange(
        location: match.range.location + leadingWhitespaceCount,
        length: 1 + (name as NSString).length
      )
      return PersonMentionOccurrence(
        name: name,
        targetNoteID: nsString.substring(with: match.range(at: 2)),
        range: mentionRange,
        totalRange: match.range
      )
    }
  }

  public static func mention(at characterIndex: Int, in text: String) -> PersonMentionOccurrence? {
    mentions(in: text).first {
      NSLocationInRange(characterIndex, $0.range) || NSLocationInRange(characterIndex, $0.totalRange)
    }
  }

  public static func autocompleteContext(in text: String, selection: NSRange) -> PersonAutocompleteContext? {
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

    let name = nsString.substring(with: match.range(at: 1))
    return PersonAutocompleteContext(name: name, replacementRange: match.range)
  }

  public static func targetComment(noteID: String) -> String {
    "<!-- lattice:mention=\(noteID) -->"
  }

  public static func replacement(name: String, noteID: String) -> String {
    "@\(name)\(targetComment(noteID: noteID))"
  }

  public static func isValidName(_ name: String) -> Bool {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    return !trimmed.isEmpty
      && trimmed.rangeOfCharacter(from: .letters) != nil
      && !trimmed.contains("@")
      && !trimmed.contains("<")
      && !trimmed.contains(">")
      && !trimmed.contains("\n")
  }

  private static func codeRanges(in nsString: NSString) -> [NSRange] {
    let fencedRanges = fencedCodeRanges(in: nsString)
    guard let inlineRegex = try? NSRegularExpression(pattern: #"`+[^`\n]+`+"#) else {
      return fencedRanges
    }
    let fullRange = NSRange(location: 0, length: nsString.length)
    return fencedRanges + inlineRegex.matches(in: nsString as String, range: fullRange).map(\.range)
  }

  private static func fencedCodeRanges(in nsString: NSString) -> [NSRange] {
    var ranges: [NSRange] = []
    var start: Int?
    var location = 0
    while location < nsString.length {
      let lineRange = nsString.lineRange(for: NSRange(location: location, length: 0))
      let line = nsString.substring(with: lineRange).trimmingCharacters(in: .whitespaces)
      if line.hasPrefix("```") || line.hasPrefix("~~~") {
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

  private static func intersects(_ range: NSRange, ranges: [NSRange]) -> Bool {
    ranges.contains { NSIntersectionRange(range, $0).length > 0 }
  }
}
