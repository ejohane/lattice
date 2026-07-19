import Foundation

public struct ContextPackSource: Identifiable, Equatable, Sendable {
  public let noteID: String
  public let title: String
  public let body: String
  public let isExcerpt: Bool

  public init(
    noteID: String,
    title: String,
    body: String,
    isExcerpt: Bool = false
  ) {
    self.noteID = noteID
    self.title = title
    self.body = body
    self.isExcerpt = isExcerpt
  }

  public var id: String {
    noteID
  }

  public var displayTitle: String {
    isExcerpt ? "\(title) (selection)" : title
  }
}

public struct ContextPack: Equatable, Sendable {
  public let task: String
  public let sources: [ContextPackSource]
  public let generatedAt: Date

  public init(
    task: String,
    sources: [ContextPackSource],
    generatedAt: Date
  ) {
    self.task = task
    self.sources = sources
    self.generatedAt = generatedAt
  }
}

public enum ContextPackCompiler {
  public static func markdown(
    for pack: ContextPack,
    locale: Locale = .current,
    timeZone: TimeZone = .current
  ) -> String {
    var sections: [String] = []
    let task = pack.task.trimmingCharacters(in: .whitespacesAndNewlines)
    if !task.isEmpty {
      sections.append("# Task\n\n\(task)")
    }

    let renderedSources = pack.sources.map { source in
      let heading = sanitizedHeading(source.displayTitle)
      let body = cleanedBody(for: source)
      if body.isEmpty {
        return "## \(heading)"
      }
      return "## \(heading)\n\n\(body)"
    }
    let contextBody = renderedSources.joined(separator: "\n\n")
    sections.append(contextBody.isEmpty ? "# Context" : "# Context\n\n\(contextBody)")

    let dateFormatter = DateFormatter()
    dateFormatter.calendar = Calendar(identifier: .gregorian)
    dateFormatter.locale = locale
    dateFormatter.timeZone = timeZone
    dateFormatter.dateStyle = .long
    dateFormatter.timeStyle = .none

    var footer = "Generated from Lattice on \(dateFormatter.string(from: pack.generatedAt))."
    if !pack.sources.isEmpty {
      footer += "\nSources: \(pack.sources.map { sanitizedHeading($0.displayTitle) }.joined(separator: ", "))"
    }
    sections.append("---\n\(footer)")

    return sections.joined(separator: "\n\n") + "\n"
  }

  public static func approximateTokenCount(for markdown: String) -> Int {
    guard !markdown.isEmpty else {
      return 0
    }
    return Int(ceil(Double(markdown.count) / 4.0))
  }

  private static func cleanedBody(for source: ContextPackSource) -> String {
    var body = MarkdownDocumentMetadata.strippingFrontMatter(from: source.body)
    body = replacingHTMLComments(in: body)
    body = replacingImages(in: body)
    body = body.trimmingCharacters(in: .whitespacesAndNewlines)
    if !source.isExcerpt {
      body = removingLeadingTitle(from: body, matching: source.title)
    }
    return body.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func replacingHTMLComments(in body: String) -> String {
    guard let regex = try? NSRegularExpression(pattern: #"(?s)<!--\s*lattice:.*?-->"#) else {
      return body
    }
    let range = NSRange(location: 0, length: (body as NSString).length)
    return regex.stringByReplacingMatches(in: body, range: range, withTemplate: "")
  }

  private static func replacingImages(in body: String) -> String {
    let nsBody = NSMutableString(string: body)
    for image in MarkdownImageParser.links(in: body).reversed() {
      let altText = image.altText.trimmingCharacters(in: .whitespacesAndNewlines)
      let replacement = altText.isEmpty
        ? "[Image omitted]"
        : "[Image omitted: \(altText)]"
      nsBody.replaceCharacters(in: image.range, with: replacement)
    }
    return nsBody as String
  }

  private static func removingLeadingTitle(from body: String, matching title: String) -> String {
    let nsBody = body as NSString
    var location = 0
    while location < nsBody.length {
      let lineRange = nsBody.lineRange(for: NSRange(location: location, length: 0))
      let line = nsBody.substring(with: lineRange)
      let rendered = MarkdownPlainTextRenderer.lineText(from: line)
      if rendered.isEmpty {
        location = NSMaxRange(lineRange)
        continue
      }
      guard rendered.localizedCaseInsensitiveCompare(title) == .orderedSame else {
        return body
      }
      return nsBody.substring(from: NSMaxRange(lineRange))
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    return body
  }

  private static func sanitizedHeading(_ title: String) -> String {
    title
      .components(separatedBy: .newlines)
      .joined(separator: " ")
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
