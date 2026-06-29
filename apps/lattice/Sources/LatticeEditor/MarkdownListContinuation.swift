import Foundation

public struct MarkdownListContinuationResult: Equatable, Sendable {
  public let body: String
  public let selection: NSRange
  public let replacementRange: NSRange
  public let replacement: String

  public init(body: String, selection: NSRange, replacementRange: NSRange, replacement: String) {
    self.body = body
    self.selection = selection
    self.replacementRange = replacementRange
    self.replacement = replacement
  }
}

public enum MarkdownListContinuation {
  private struct ListMarker {
    let lineContentRange: NSRange
    let continuationPrefix: String
    let hasContent: Bool
  }

  public static func applyReturn(to body: String, selection: NSRange) -> MarkdownListContinuationResult? {
    let nsString = body as NSString
    let range = MarkdownTextRange.clamped(selection, length: nsString.length)
    guard let marker = listMarker(at: range.location, in: nsString) else {
      return nil
    }

    if range.length == 0 && !marker.hasContent {
      let nextBody = nsString.replacingCharacters(in: marker.lineContentRange, with: "")
      return MarkdownListContinuationResult(
        body: nextBody,
        selection: NSRange(location: marker.lineContentRange.location, length: 0),
        replacementRange: marker.lineContentRange,
        replacement: ""
      )
    }

    let replacement = "\n" + marker.continuationPrefix
    let nextBody = nsString.replacingCharacters(in: range, with: replacement)
    return MarkdownListContinuationResult(
      body: nextBody,
      selection: NSRange(location: range.location + replacement.utf16.count, length: 0),
      replacementRange: range,
      replacement: replacement
    )
  }

  private static func listMarker(at location: Int, in nsString: NSString) -> ListMarker? {
    let safeLocation = min(location, nsString.length)
    let lineRange = nsString.lineRange(for: NSRange(location: safeLocation, length: 0))
    let lineContentRange = MarkdownTextRange.contentRangeWithoutLineEnding(lineRange, in: nsString)
    let line = nsString.substring(with: lineContentRange)

    if let marker = unorderedListMarker(line: line, lineContentRange: lineContentRange) {
      return marker
    }

    return orderedListMarker(line: line, lineContentRange: lineContentRange)
  }

  private static func unorderedListMarker(line: String, lineContentRange: NSRange) -> ListMarker? {
    guard let match = MarkdownTextRange.firstRegexMatch(
      "^([ \\t]*)([-*+])([ \\t]+)(?:(\\[[ xX]\\])([ \\t]+))?(.*)$",
      in: line
    ) else {
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

    return ListMarker(
      lineContentRange: lineContentRange,
      continuationPrefix: continuationPrefix,
      hasContent: !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    )
  }

  private static func orderedListMarker(line: String, lineContentRange: NSRange) -> ListMarker? {
    guard let match = MarkdownTextRange.firstRegexMatch(
      "^([ \\t]*)(\\d+)([.)])([ \\t]+)(.*)$",
      in: line
    ) else {
      return nil
    }

    let nsLine = line as NSString
    let indent = nsLine.substring(with: match.range(at: 1))
    let numberText = nsLine.substring(with: match.range(at: 2))
    let delimiter = nsLine.substring(with: match.range(at: 3))
    let spacing = nsLine.substring(with: match.range(at: 4))
    let content = nsLine.substring(with: match.range(at: 5))
    let nextNumber = (Int(numberText) ?? 0) + 1

    return ListMarker(
      lineContentRange: lineContentRange,
      continuationPrefix: "\(indent)\(nextNumber)\(delimiter)\(spacing)",
      hasContent: !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    )
  }

}
