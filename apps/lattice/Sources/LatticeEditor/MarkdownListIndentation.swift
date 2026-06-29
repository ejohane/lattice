import Foundation

public struct MarkdownListIndentationResult: Equatable, Sendable {
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

public enum MarkdownListIndentation {
  private static let indent = "    "

  private struct LineEdit {
    let location: Int
    let removedLength: Int
    let insertedLength: Int
  }

  public static func applyIndent(to body: String, selection: NSRange) -> MarkdownListIndentationResult? {
    apply(to: body, selection: selection) { line in
      guard isListItem(line) else {
        return nil
      }

      return (indent + line, RelativeLineEdit(locationOffset: 0, removedLength: 0, insertedLength: indent.utf16.count))
    }
  }

  public static func applyOutdent(to body: String, selection: NSRange) -> MarkdownListIndentationResult? {
    apply(to: body, selection: selection) { line in
      guard isListItem(line) else {
        return nil
      }

      let removalLength: Int
      if line.hasPrefix("\t") {
        removalLength = 1
      } else {
        removalLength = min(line.prefix(while: { $0 == " " }).count, indent.count)
      }

      guard removalLength > 0 else {
        return nil
      }

      let start = line.index(line.startIndex, offsetBy: removalLength)
      let nextLine = String(line[start...])
      return (nextLine, RelativeLineEdit(locationOffset: 0, removedLength: removalLength, insertedLength: 0))
    }
  }

  private static func apply(
    to body: String,
    selection: NSRange,
    transform: (String) -> (line: String, edit: RelativeLineEdit)?
  ) -> MarkdownListIndentationResult? {
    let nsString = body as NSString
    let range = MarkdownTextRange.clamped(selection, length: nsString.length)
    let selectedLines = lineRanges(intersecting: range, in: nsString)
    guard let firstLine = selectedLines.first, let lastLine = selectedLines.last else {
      return nil
    }

    var replacement = ""
    var edits: [LineEdit] = []
    var changed = false

    for lineRange in selectedLines {
      let contentRange = MarkdownTextRange.contentRangeWithoutLineEnding(lineRange, in: nsString)
      let lineEndingRange = NSRange(
        location: NSMaxRange(contentRange),
        length: NSMaxRange(lineRange) - NSMaxRange(contentRange)
      )
      let line = nsString.substring(with: contentRange)
      let lineEnding = nsString.substring(with: lineEndingRange)

      if let transformed = transform(line) {
        replacement += transformed.line + lineEnding
        edits.append(LineEdit(
          location: contentRange.location + transformed.edit.locationOffset,
          removedLength: transformed.edit.removedLength,
          insertedLength: transformed.edit.insertedLength
        ))
        changed = true
      } else {
        replacement += nsString.substring(with: lineRange)
      }
    }

    guard changed else {
      return nil
    }

    let replacementRange = NSRange(
      location: firstLine.location,
      length: NSMaxRange(lastLine) - firstLine.location
    )
    let nextBody = nsString.replacingCharacters(in: replacementRange, with: replacement)
    let selectionStart = transformedLocation(range.location, edits: edits)
    let selectionEnd = transformedLocation(NSMaxRange(range), edits: edits)
    let nextSelection = MarkdownTextRange.clamped(
      NSRange(location: selectionStart, length: max(0, selectionEnd - selectionStart)),
      length: (nextBody as NSString).length
    )

    return MarkdownListIndentationResult(
      body: nextBody,
      selection: nextSelection,
      replacementRange: replacementRange,
      replacement: replacement
    )
  }

  private struct RelativeLineEdit {
    let locationOffset: Int
    let removedLength: Int
    let insertedLength: Int
  }

  private static func isListItem(_ line: String) -> Bool {
    MarkdownTextRange.firstRegexMatch(
      "^([ \\t]*)(?:[-*+][ \\t]+(?:\\[[ xX]\\][ \\t]+)?|\\d+[.)][ \\t]+)",
      in: line
    ) != nil
  }

  private static func lineRanges(intersecting selection: NSRange, in nsString: NSString) -> [NSRange] {
    let safeLocation = min(selection.location, nsString.length)
    let selectedEnd = selection.length == 0
      ? safeLocation
      : max(safeLocation, min(NSMaxRange(selection) - 1, nsString.length))
    let firstRange = nsString.lineRange(for: NSRange(location: safeLocation, length: 0))
    let lastRange = nsString.lineRange(for: NSRange(location: selectedEnd, length: 0))
    let end = max(NSMaxRange(firstRange), NSMaxRange(lastRange))

    var ranges: [NSRange] = []
    var cursor = firstRange.location
    while cursor < end {
      let lineRange = nsString.lineRange(for: NSRange(location: cursor, length: 0))
      ranges.append(lineRange)
      let next = NSMaxRange(lineRange)
      guard next > cursor else {
        break
      }
      cursor = next
    }

    return ranges
  }

  private static func transformedLocation(_ location: Int, edits: [LineEdit]) -> Int {
    var offset = 0

    for edit in edits {
      if edit.removedLength == 0 {
        if location >= edit.location {
          offset += edit.insertedLength
        }
        continue
      }

      if location > edit.location + edit.removedLength {
        offset += edit.insertedLength - edit.removedLength
      } else if location >= edit.location {
        return max(0, edit.location + offset + edit.insertedLength)
      }
    }

    return max(0, location + offset)
  }

}
