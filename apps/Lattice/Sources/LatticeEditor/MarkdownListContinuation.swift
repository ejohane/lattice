import Foundation

public enum MarkdownListContinuation {
  private struct MarkdownListMarker {
    let lineContentRange: NSRange
    let continuationPrefix: String
    let hasContent: Bool
  }

  public static func edit(
    in text: String,
    selectedRange range: NSRange
  ) -> MarkdownEdit? {
    guard let marker = markdownListMarker(in: text, at: range.location) else {
      return nil
    }

    if range.length == 0 && !marker.hasContent {
      return MarkdownEdit(
        replacementRange: marker.lineContentRange,
        replacement: "",
        selectedRange: NSRange(location: marker.lineContentRange.location, length: 0)
      )
    }

    let replacement = "\n" + marker.continuationPrefix
    return MarkdownEdit(
      replacementRange: range,
      replacement: replacement,
      selectedRange: NSRange(location: range.location + replacement.utf16.count, length: 0)
    )
  }

  private static func markdownListMarker(
    in text: String,
    at location: Int
  ) -> MarkdownListMarker? {
    let nsString = text as NSString
    let safeLocation = min(location, nsString.length)
    let lineRange = nsString.lineRange(for: NSRange(location: safeLocation, length: 0))
    let lineContentRange = contentRangeWithoutLineEnding(lineRange, in: nsString)
    let line = nsString.substring(with: lineContentRange)

    if let marker = unorderedListMarker(line: line, lineContentRange: lineContentRange) {
      return marker
    }

    return orderedListMarker(line: line, lineContentRange: lineContentRange)
  }

  private static func unorderedListMarker(
    line: String,
    lineContentRange: NSRange
  ) -> MarkdownListMarker? {
    guard let match = firstRegexMatch("^([ \\t]*)([-*+])([ \\t]+)(?:(\\[[ xX]\\])([ \\t]+))?(.*)$", in: line) else {
      return nil
    }

    let nsLine = line as NSString
    let indent = nsLine.substring(with: match.range(at: 1))
    let bullet = nsLine.substring(with: match.range(at: 2))
    let spacing = nsLine.substring(with: match.range(at: 3))
    let contentRange = match.range(at: 6)
    let content = contentRange.location == NSNotFound ? "" : nsLine.substring(with: contentRange)
    let taskSpacingRange = match.range(at: 5)
    let continuationPrefix: String

    if match.range(at: 4).location == NSNotFound {
      continuationPrefix = indent + bullet + spacing
    } else {
      let taskSpacing = taskSpacingRange.location == NSNotFound ? spacing : nsLine.substring(with: taskSpacingRange)
      continuationPrefix = indent + bullet + spacing + "[ ]" + taskSpacing
    }

    return MarkdownListMarker(
      lineContentRange: lineContentRange,
      continuationPrefix: continuationPrefix,
      hasContent: !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    )
  }

  private static func orderedListMarker(
    line: String,
    lineContentRange: NSRange
  ) -> MarkdownListMarker? {
    guard let match = firstRegexMatch("^([ \\t]*)(\\d+)([.)])([ \\t]+)(.*)$", in: line) else {
      return nil
    }

    let nsLine = line as NSString
    let indent = nsLine.substring(with: match.range(at: 1))
    let numberText = nsLine.substring(with: match.range(at: 2))
    let delimiter = nsLine.substring(with: match.range(at: 3))
    let spacing = nsLine.substring(with: match.range(at: 4))
    let content = nsLine.substring(with: match.range(at: 5))
    let nextNumber = (Int(numberText) ?? 0) + 1

    return MarkdownListMarker(
      lineContentRange: lineContentRange,
      continuationPrefix: "\(indent)\(nextNumber)\(delimiter)\(spacing)",
      hasContent: !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    )
  }

  private static func contentRangeWithoutLineEnding(
    _ lineRange: NSRange,
    in nsString: NSString
  ) -> NSRange {
    var end = NSMaxRange(lineRange)
    while end > lineRange.location {
      let character = nsString.character(at: end - 1)
      if character == 10 || character == 13 {
        end -= 1
      } else {
        break
      }
    }

    return NSRange(location: lineRange.location, length: end - lineRange.location)
  }

  private static func firstRegexMatch(
    _ pattern: String,
    in string: String
  ) -> NSTextCheckingResult? {
    guard let regex = try? NSRegularExpression(pattern: pattern) else {
      return nil
    }

    return regex.firstMatch(in: string, range: NSRange(location: 0, length: (string as NSString).length))
  }
}
