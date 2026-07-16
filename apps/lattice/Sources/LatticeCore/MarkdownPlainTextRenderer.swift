import Foundation

public enum MarkdownPlainTextRenderer {
  public static func firstLine(in body: String) -> String? {
    var isInsideCodeFence = false

    for line in body.components(separatedBy: .newlines) {
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      if isCodeFence(trimmed) {
        isInsideCodeFence.toggle()
        continue
      }

      let rendered = isInsideCodeFence
        ? trimmed
        : lineText(from: trimmed)
      if !rendered.isEmpty {
        return rendered
      }
    }

    return nil
  }

  public static func lineText(from line: String) -> String {
    var text = line.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else {
      return ""
    }

    if text.matches(#"^([-*_]\s*){3,}$"#) {
      return ""
    }

    text = text.replacingRegex(#"^\s{0,3}(>\s*)+"#, with: "")
    text = text.replacingRegex(#"^\s{0,3}#{1,6}\s+"#, with: "")
    text = text.replacingRegex(#"\s+#{1,}\s*$"#, with: "")
    text = text.replacingRegex(#"^\s{0,3}(?:[-+*]|\d+[.)])\s+"#, with: "")
    text = text.replacingRegex(#"^\[[ xX]\]\s+"#, with: "")
    text = strippingHTMLComments(from: text)
    text = text.replacingRegex(#"!\[([^\]]*)\]\([^)]+\)"#, with: "$1")
    text = text.replacingRegex(#"\[([^\]]+)\]\([^)]+\)"#, with: "$1")
    text = text.replacingRegex(#"\[\[[^\]|]+(?:#[^\]|]+)?\|([^\]]+)\]\]"#, with: "$1")
    text = text.replacingRegex(#"\[\[([^\]#|]+)(?:#[^\]]+)?\]\]"#, with: "$1")
    text = text.replacingRegex(#"`+([^`]+)`+"#, with: "$1")
    text = text.replacingRegex(#"~~([^~]+)~~"#, with: "$1")
    text = text.replacingRegex(#"\*\*\*([^*]+)\*\*\*"#, with: "$1")
    text = text.replacingRegex(#"\*\*([^*]+)\*\*"#, with: "$1")
    text = text.replacingRegex(#"\*([^*]+)\*"#, with: "$1")
    text = text.replacingRegex(#"___([^_]+)___"#, with: "$1")
    text = text.replacingRegex(#"__([^_]+)__"#, with: "$1")
    text = text.replacingRegex(#"_([^_]+)_"#, with: "$1")
    text = text.replacingRegex(#"\s+"#, with: " ")

    return text.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  public static func strippingHTMLComments(from text: String) -> String {
    text.replacingRegex(#"\s*<!--.*?-->\s*"#, with: " ")
  }

  private static func isCodeFence(_ line: String) -> Bool {
    line.hasPrefix("```") || line.hasPrefix("~~~")
  }
}

private extension String {
  func replacingRegex(_ pattern: String, with replacement: String) -> String {
    replacingOccurrences(
      of: pattern,
      with: replacement,
      options: .regularExpression
    )
  }

  func matches(_ pattern: String) -> Bool {
    range(of: pattern, options: .regularExpression) != nil
  }
}
