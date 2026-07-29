import Foundation

public struct MarkdownSidebarPreview: Equatable, Sendable {
  public let title: String
  public let excerpt: String
  public let modifiedAt: Date?

  public init(
    file: MarkdownFile,
    body: String,
    modifiedAt: Date? = nil
  ) {
    let lines = body
      .components(separatedBy: .newlines)
      .map(Self.renderedLine)
      .filter { !$0.isEmpty }

    title = lines.first ?? file.url.deletingPathExtension().lastPathComponent
    excerpt = lines.dropFirst().prefix(2).joined(separator: " ")
    self.modifiedAt = modifiedAt
  }

  public func updating(body: String, file: MarkdownFile) -> Self {
    Self(
      file: file,
      body: body,
      modifiedAt: modifiedAt
    )
  }

  private static func renderedLine(_ source: String) -> String {
    var line = source.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !line.hasPrefix("<!--") else { return "" }
    line = line.replacingOccurrences(
      of: #"^#{1,6}\s+"#,
      with: "",
      options: .regularExpression
    )
    line = line.replacingOccurrences(
      of: #"^(?:[-+*]|\d+\.)\s+(?:\[[ xX]\]\s+)?"#,
      with: "",
      options: .regularExpression
    )
    line = line.replacingOccurrences(
      of: #"!\[([^\]]*)\]\([^)]*\)"#,
      with: "$1",
      options: .regularExpression
    )
    line = line.replacingOccurrences(
      of: #"\[([^\]]+)\]\([^)]*\)"#,
      with: "$1",
      options: .regularExpression
    )
    line = line.replacingOccurrences(
      of: #"\[\[([^\]]+)\]\]"#,
      with: "$1",
      options: .regularExpression
    )
    line = line.replacingOccurrences(
      of: #"[*_`~]+"#,
      with: "",
      options: .regularExpression
    )
    if line.range(
      of: #"^\|?(?:\s*:?-{3,}:?\s*\|)+$"#,
      options: .regularExpression
    ) != nil {
      return ""
    }
    line = line.replacingOccurrences(
      of: #"\s+"#,
      with: " ",
      options: .regularExpression
    )
    return line.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
