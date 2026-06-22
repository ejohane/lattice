import Foundation

public enum MarkdownSemanticStyle: Equatable {
  case visibleToken
  case hiddenToken
  case heading(level: Int)
  case list
  case bullet
  case renderedBullet
  case blockQuote
  case rule
  case inlineCode
  case codeBlock
  case link
  case bold
  case italic
  case strikethrough
  case completedTask
}

public struct MarkdownRenderSpan: Equatable {
  public let range: NSRange
  public let style: MarkdownSemanticStyle

  public init(range: NSRange, style: MarkdownSemanticStyle) {
    self.range = range
    self.style = style
  }
}

public struct MarkdownRenderPlan: Equatable {
  public let spans: [MarkdownRenderSpan]

  public init(spans: [MarkdownRenderSpan]) {
    self.spans = spans
  }
}

public enum MarkdownRenderEngine {
  public static func renderPlan(
    for source: String,
    selectionRanges activeRanges: [NSRange]
  ) -> MarkdownRenderPlan {
    let nsString = source as NSString
    let codeBlockRanges = markdownCodeBlockRanges(in: nsString)
    var spans: [MarkdownRenderSpan] = []

    spans.append(contentsOf: renderMarkdownBlocks(
      in: nsString,
      codeBlockRanges: codeBlockRanges,
      activeRanges: activeRanges
    ))
    spans.append(contentsOf: renderMarkdownInline(
      in: source,
      skipping: codeBlockRanges,
      activeRanges: activeRanges
    ))

    return MarkdownRenderPlan(spans: spans)
  }

  private static func renderMarkdownBlocks(
    in nsString: NSString,
    codeBlockRanges: [NSRange],
    activeRanges: [NSRange]
  ) -> [MarkdownRenderSpan] {
    var spans: [MarkdownRenderSpan] = []
    var location = 0

    while location < nsString.length {
      let lineRange = nsString.lineRange(for: NSRange(location: location, length: 0))
      let line = nsString.substring(with: lineRange)
      let tokenStyle: MarkdownSemanticStyle = range(lineRange, containsAnyActive: activeRanges)
        ? .visibleToken
        : .hiddenToken

      if range(lineRange, intersectsAny: codeBlockRanges) {
        spans.append(MarkdownRenderSpan(range: lineRange, style: .codeBlock))
      } else if let match = firstMatch("^\\s*(#{1,6})(\\s+)(.+)$", in: line) {
        let level = min(match.range(at: 1).length, 6)
        spans.append(MarkdownRenderSpan(range: shifted(match.range(at: 1), by: lineRange.location), style: tokenStyle))
        spans.append(MarkdownRenderSpan(range: shifted(match.range(at: 2), by: lineRange.location), style: tokenStyle))
        spans.append(MarkdownRenderSpan(range: shifted(match.range(at: 3), by: lineRange.location), style: .heading(level: level)))
      } else if let match = firstMatch("^\\s{0,3}>\\s?(.+)$", in: line) {
        spans.append(MarkdownRenderSpan(range: lineRange, style: .blockQuote))
        spans.append(MarkdownRenderSpan(range: shifted(NSRange(location: 0, length: 1), by: lineRange.location), style: tokenStyle))
        spans.append(MarkdownRenderSpan(range: shifted(match.range(at: 1), by: lineRange.location), style: .italic))
      } else if let match = firstMatch("^\\s*([-*+])\\s+(\\[[ xX]\\])\\s+(.*)$", in: line) {
        let isActive = range(lineRange, containsAnyActive: activeRanges)
        let markerRange = shifted(match.range(at: 1), by: lineRange.location)
        let checkboxRange = shifted(match.range(at: 2), by: lineRange.location)
        let contentRange = shifted(match.range(at: 3), by: lineRange.location)
        let shouldRenderMarker = !isActive || contentRange.length == 0
        spans.append(MarkdownRenderSpan(range: lineRange, style: .list))
        spans.append(MarkdownRenderSpan(range: markerRange, style: shouldRenderMarker ? .renderedBullet : .bullet))
        spans.append(MarkdownRenderSpan(range: checkboxRange, style: isActive ? .bullet : .hiddenToken))
        if line.contains("[x]") || line.contains("[X]") {
          spans.append(MarkdownRenderSpan(range: contentRange, style: .completedTask))
        }
      } else if let match = firstMatch("^\\s*([-*+])\\s+(.*)$", in: line) {
        let isActive = range(lineRange, containsAnyActive: activeRanges)
        let contentRange = match.range(at: 2)
        let shouldRenderMarker = !isActive || contentRange.length == 0
        spans.append(MarkdownRenderSpan(range: lineRange, style: .list))
        spans.append(MarkdownRenderSpan(
          range: shifted(match.range(at: 1), by: lineRange.location),
          style: shouldRenderMarker ? .renderedBullet : .bullet
        ))
      } else if let match = firstMatch("^\\s*(\\d+[.)])\\s+(.*)$", in: line) {
        spans.append(MarkdownRenderSpan(range: lineRange, style: .list))
        spans.append(MarkdownRenderSpan(
          range: shifted(match.range(at: 1), by: lineRange.location),
          style: range(lineRange, containsAnyActive: activeRanges) ? .bullet : .hiddenToken
        ))
      } else if firstMatch("^\\s{0,3}(([-*_])\\s*){3,}$", in: line) != nil {
        spans.append(MarkdownRenderSpan(
          range: lineRange,
          style: range(lineRange, containsAnyActive: activeRanges) ? .rule : .hiddenToken
        ))
      }

      location = NSMaxRange(lineRange)
    }

    return spans
  }

  private static func renderMarkdownInline(
    in source: String,
    skipping skippedRanges: [NSRange],
    activeRanges: [NSRange]
  ) -> [MarkdownRenderSpan] {
    var spans: [MarkdownRenderSpan] = []

    spans.append(contentsOf: inlineStyle(
      pattern: "`([^`\\n]+)`",
      in: source,
      skipping: skippedRanges,
      activeRanges: activeRanges,
      contentStyle: .inlineCode,
      tokenGroups: [0],
      contentGroups: [1]
    ))
    spans.append(contentsOf: inlineStyle(
      pattern: "!\\[([^\\]\\n]*)\\]\\(([^)\\n]+)\\)",
      in: source,
      skipping: skippedRanges,
      activeRanges: activeRanges,
      contentStyle: .link,
      tokenGroups: [0],
      contentGroups: [1]
    ))
    spans.append(contentsOf: inlineStyle(
      pattern: "\\[([^\\]\\n]+)\\]\\(([^)\\n]+)\\)",
      in: source,
      skipping: skippedRanges,
      activeRanges: activeRanges,
      contentStyle: .link,
      tokenGroups: [0],
      contentGroups: [1]
    ))
    spans.append(contentsOf: inlineStyle(
      pattern: "(\\*\\*|__)(.+?)\\1",
      in: source,
      skipping: skippedRanges,
      activeRanges: activeRanges,
      contentStyle: .bold,
      tokenGroups: [0],
      contentGroups: [2]
    ))
    spans.append(contentsOf: inlineStyle(
      pattern: "(~~)(.+?)\\1",
      in: source,
      skipping: skippedRanges,
      activeRanges: activeRanges,
      contentStyle: .strikethrough,
      tokenGroups: [0],
      contentGroups: [2]
    ))
    spans.append(contentsOf: inlineStyle(
      pattern: "(?<!\\*)\\*(?!\\*)([^*\\n]+)(?<!\\*)\\*(?!\\*)",
      in: source,
      skipping: skippedRanges,
      activeRanges: activeRanges,
      contentStyle: .italic,
      tokenGroups: [0],
      contentGroups: [1]
    ))
    spans.append(contentsOf: inlineStyle(
      pattern: "(?<!_)_(?!_)([^_\\n]+)(?<!_)_(?!_)",
      in: source,
      skipping: skippedRanges,
      activeRanges: activeRanges,
      contentStyle: .italic,
      tokenGroups: [0],
      contentGroups: [1]
    ))

    return spans
  }

  private static func inlineStyle(
    pattern: String,
    in source: String,
    skipping skippedRanges: [NSRange],
    activeRanges: [NSRange],
    contentStyle: MarkdownSemanticStyle,
    tokenGroups: [Int],
    contentGroups: [Int]
  ) -> [MarkdownRenderSpan] {
    guard let regex = try? NSRegularExpression(pattern: pattern) else {
      return []
    }

    let nsString = source as NSString
    let fullRange = NSRange(location: 0, length: nsString.length)
    let matches = regex.matches(in: source, range: fullRange)
    var spans: [MarkdownRenderSpan] = []

    for match in matches where !range(match.range, intersectsAny: skippedRanges) {
      let tokenStyle: MarkdownSemanticStyle = range(match.range, containsAnyActive: activeRanges)
        ? .visibleToken
        : .hiddenToken

      for group in tokenGroups {
        let tokenRange = match.range(at: group)
        if tokenRange.location != NSNotFound {
          spans.append(MarkdownRenderSpan(range: tokenRange, style: tokenStyle))
        }
      }

      for group in contentGroups {
        let contentRange = match.range(at: group)
        if contentRange.location != NSNotFound {
          spans.append(MarkdownRenderSpan(range: contentRange, style: contentStyle))
        }
      }
    }

    return spans
  }

  private static func markdownCodeBlockRanges(in nsString: NSString) -> [NSRange] {
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

      location = NSMaxRange(lineRange)
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

    return regex.firstMatch(
      in: string,
      range: NSRange(location: 0, length: (string as NSString).length)
    )
  }

  private static func shifted(_ range: NSRange, by offset: Int) -> NSRange {
    NSRange(location: range.location + offset, length: range.length)
  }

  private static func range(_ range: NSRange, intersectsAny ranges: [NSRange]) -> Bool {
    ranges.contains { NSIntersectionRange(range, $0).length > 0 }
  }

  private static func range(_ range: NSRange, containsAnyActive activeRanges: [NSRange]) -> Bool {
    activeRanges.contains { activeRange in
      if activeRange.length > 0 {
        return NSIntersectionRange(range, activeRange).length > 0
      }

      return activeRange.location > range.location && activeRange.location < NSMaxRange(range)
    }
  }
}
