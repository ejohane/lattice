import Foundation

public struct MarkdownImageLink: Equatable, Sendable {
  public let altText: String
  public let destination: String
  public let width: Double?
  public let range: NSRange
  public let lineRange: NSRange

  public init(altText: String, destination: String, width: Double? = nil, range: NSRange, lineRange: NSRange) {
    self.altText = altText
    self.destination = destination
    self.width = width
    self.range = range
    self.lineRange = lineRange
  }
}

public struct MarkdownImageRenderState: Equatable, Sendable {
  public let link: MarkdownImageLink
  public let url: URL

  public init(link: MarkdownImageLink, url: URL) {
    self.link = link
    self.url = url.standardizedFileURL
  }
}

public enum MarkdownImageParser {
  public static func links(in text: String) -> [MarkdownImageLink] {
    let nsString = text as NSString
    let fullRange = NSRange(location: 0, length: nsString.length)
    guard fullRange.length > 0,
          let regex = try? NSRegularExpression(pattern: #"!\[([^\]\n]*)\]\(([^)\n]+)\)"#) else {
      return []
    }
    let codeBlockRanges = codeBlockRanges(in: nsString)
    return regex.matches(in: text, range: fullRange)
      .filter { !range($0.range, intersectsAny: codeBlockRanges) }
      .map { match in
        let parsedAlt = parseAltText(nsString.substring(with: match.range(at: 1)))
        return MarkdownImageLink(
          altText: parsedAlt.text,
          destination: nsString.substring(with: match.range(at: 2)),
          width: parsedAlt.width,
          range: match.range(at: 0),
          lineRange: nsString.lineRange(for: match.range(at: 0))
        )
      }
  }

  public static func link(at characterIndex: Int, in text: String) -> MarkdownImageLink? {
    links(in: text).first { NSLocationInRange(characterIndex, $0.range) }
  }

  private static func codeBlockRanges(in nsString: NSString) -> [NSRange] {
    var ranges: [NSRange] = []
    var blockStart: Int?
    var location = 0

    while location < nsString.length {
      let lineRange = nsString.lineRange(for: NSRange(location: location, length: 0))
      let line = nsString.substring(with: lineRange)

      if firstMatch("^\\s*(```|~~~)", in: line) != nil {
        if let start = blockStart {
          ranges.append(NSRange(location: start, length: NSMaxRange(lineRange) - start))
          blockStart = nil
        } else {
          blockStart = lineRange.location
        }
      }

      let nextLocation = NSMaxRange(lineRange)
      if nextLocation <= location {
        break
      }
      location = nextLocation
    }

    if let start = blockStart {
      ranges.append(NSRange(location: start, length: nsString.length - start))
    }
    return ranges
  }

  private static func firstMatch(_ pattern: String, in string: String) -> NSTextCheckingResult? {
    guard let regex = try? NSRegularExpression(pattern: pattern) else {
      return nil
    }
    return regex.firstMatch(in: string, range: NSRange(location: 0, length: (string as NSString).length))
  }

  private static func range(_ range: NSRange, intersectsAny ranges: [NSRange]) -> Bool {
    ranges.contains { NSIntersectionRange(range, $0).length > 0 }
  }

  private static func parseAltText(_ rawAltText: String) -> (text: String, width: Double?) {
    guard let separatorIndex = rawAltText.lastIndex(of: "|") else {
      return (rawAltText, nil)
    }
    let widthText = rawAltText[rawAltText.index(after: separatorIndex)...]
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard let width = Double(widthText), width.isFinite, width > 0 else {
      return (rawAltText, nil)
    }
    let text = rawAltText[..<separatorIndex].trimmingCharacters(in: .whitespacesAndNewlines)
    return (String(text), width)
  }
}
