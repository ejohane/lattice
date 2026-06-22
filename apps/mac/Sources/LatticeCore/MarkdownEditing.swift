import Foundation

public struct MarkdownEditResult: Equatable {
  public let body: String
  public let selection: NSRange

  public init(body: String, selection: NSRange) {
    self.body = body
    self.selection = selection
  }
}

public enum MarkdownTextEditing {
  public static func apply(
    _ command: MarkdownCommand,
    to body: String,
    selection: NSRange
  ) -> MarkdownEditResult {
    switch command {
    case .heading:
      return insertLinePrefix("# ", in: body, selection: selection)
    case .bold:
      return wrapSelection(prefix: "**", suffix: "**", in: body, selection: selection)
    case .italic:
      return wrapSelection(prefix: "*", suffix: "*", in: body, selection: selection)
    case .bulletList:
      return insertLinePrefix("- ", in: body, selection: selection)
    case .code:
      return wrapSelection(prefix: "`", suffix: "`", in: body, selection: selection)
    case .link:
      return insertLink(in: body, selection: selection)
    }
  }

  private static func wrapSelection(
    prefix: String,
    suffix: String,
    in body: String,
    selection: NSRange
  ) -> MarkdownEditResult {
    let nsString = body as NSString
    let range = clamped(selection, length: nsString.length)
    let selectedText = nsString.substring(with: range)
    let replacement = prefix + selectedText + suffix
    let nextBody = nsString.replacingCharacters(in: range, with: replacement)

    let nextSelection: NSRange
    if selectedText.isEmpty {
      nextSelection = NSRange(location: range.location + prefix.count, length: 0)
    } else {
      nextSelection = NSRange(location: range.location, length: replacement.count)
    }

    return MarkdownEditResult(body: nextBody, selection: nextSelection)
  }

  private static func insertLinePrefix(
    _ prefix: String,
    in body: String,
    selection: NSRange
  ) -> MarkdownEditResult {
    let nsString = body as NSString
    let range = clamped(selection, length: nsString.length)
    let lineRange = nsString.lineRange(for: NSRange(location: range.location, length: 0))
    let nextBody = nsString.replacingCharacters(
      in: NSRange(location: lineRange.location, length: 0),
      with: prefix
    )
    return MarkdownEditResult(
      body: nextBody,
      selection: NSRange(location: range.location + prefix.count, length: range.length)
    )
  }

  private static func insertLink(
    in body: String,
    selection: NSRange
  ) -> MarkdownEditResult {
    let nsString = body as NSString
    let range = clamped(selection, length: nsString.length)
    let selectedText = nsString.substring(with: range)
    let label = selectedText.isEmpty ? "link" : selectedText
    let replacement = "[\(label)](url)"
    let nextBody = nsString.replacingCharacters(in: range, with: replacement)
    return MarkdownEditResult(
      body: nextBody,
      selection: NSRange(location: range.location + label.count + 3, length: 3)
    )
  }

  private static func clamped(_ range: NSRange, length: Int) -> NSRange {
    let location = max(0, min(range.location, length))
    let maxLength = length - location
    return NSRange(location: location, length: max(0, min(range.length, maxLength)))
  }
}
