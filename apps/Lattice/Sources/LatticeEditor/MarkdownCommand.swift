import Foundation

public enum MarkdownCommand: Equatable {
  case heading
  case bold
  case italic
  case bulletList
  case code
  case link
}

public struct MarkdownEdit: Equatable {
  public let replacementRange: NSRange
  public let replacement: String
  public let selectedRange: NSRange

  public init(
    replacementRange: NSRange,
    replacement: String,
    selectedRange: NSRange
  ) {
    self.replacementRange = replacementRange
    self.replacement = replacement
    self.selectedRange = selectedRange
  }

  public func applied(to text: String) -> String {
    let nsString = text as NSString
    return nsString.replacingCharacters(in: replacementRange, with: replacement)
  }
}

public enum MarkdownCommandProcessor {
  public static func edit(
    for command: MarkdownCommand,
    in text: String,
    selectedRange range: NSRange
  ) -> MarkdownEdit {
    switch command {
    case .heading:
      linePrefixEdit("# ", in: text, selectedRange: range)
    case .bold:
      wrapSelection(prefix: "**", suffix: "**", in: text, selectedRange: range)
    case .italic:
      wrapSelection(prefix: "*", suffix: "*", in: text, selectedRange: range)
    case .bulletList:
      linePrefixEdit("- ", in: text, selectedRange: range)
    case .code:
      wrapSelection(prefix: "`", suffix: "`", in: text, selectedRange: range)
    case .link:
      linkEdit(in: text, selectedRange: range)
    }
  }

  private static func wrapSelection(
    prefix: String,
    suffix: String,
    in text: String,
    selectedRange range: NSRange
  ) -> MarkdownEdit {
    let selectedText = (text as NSString).substring(with: range)
    let replacement = prefix + selectedText + suffix
    let selectedRange: NSRange
    if selectedText.isEmpty {
      selectedRange = NSRange(location: range.location + prefix.utf16.count, length: 0)
    } else {
      selectedRange = NSRange(location: range.location, length: replacement.utf16.count)
    }
    return MarkdownEdit(
      replacementRange: range,
      replacement: replacement,
      selectedRange: selectedRange
    )
  }

  private static func linePrefixEdit(
    _ prefix: String,
    in text: String,
    selectedRange range: NSRange
  ) -> MarkdownEdit {
    let nsString = text as NSString
    let lineRange = nsString.lineRange(for: NSRange(location: range.location, length: 0))
    return MarkdownEdit(
      replacementRange: NSRange(location: lineRange.location, length: 0),
      replacement: prefix,
      selectedRange: NSRange(location: range.location + prefix.utf16.count, length: range.length)
    )
  }

  private static func linkEdit(
    in text: String,
    selectedRange range: NSRange
  ) -> MarkdownEdit {
    let selectedText = (text as NSString).substring(with: range)
    let label = selectedText.isEmpty ? "link" : selectedText
    let replacement = "[\(label)](url)"
    let urlLocation = range.location + label.utf16.count + 3
    return MarkdownEdit(
      replacementRange: range,
      replacement: replacement,
      selectedRange: NSRange(location: urlLocation, length: 3)
    )
  }
}
