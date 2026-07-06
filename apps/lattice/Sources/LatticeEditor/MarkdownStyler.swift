import Foundation

public enum MarkdownStyleKind: String, Equatable, Sendable {
  case heading
  case headingMarker
  case listMarker
  case taskCheckbox
  case completedTask
  case blockquote
  case thematicBreak
  case codeBlock
  case inlineCode
  case bold
  case italic
  case link
}

public struct MarkdownStyleSpan: Equatable, Sendable {
  public let kind: MarkdownStyleKind
  public let range: NSRange
  public let level: Int?
  public let linkDestination: String?

  public init(
    kind: MarkdownStyleKind,
    range: NSRange,
    level: Int? = nil,
    linkDestination: String? = nil
  ) {
    self.kind = kind
    self.range = range
    self.level = level
    self.linkDestination = linkDestination
  }
}

public enum MarkdownStyler {
  public static func spans(in text: String) -> [MarkdownStyleSpan] {
    let nsString = text as NSString
    let fullRange = NSRange(location: 0, length: nsString.length)
    guard fullRange.length > 0 else {
      return []
    }

    let codeBlocks = codeBlockRanges(in: nsString)
    var spans = codeBlocks.map {
      MarkdownStyleSpan(kind: .codeBlock, range: $0)
    }
    spans += blockSpans(in: nsString, codeBlocks: codeBlocks)
    spans += inlineSpans(in: text, fullRange: fullRange, skippedRanges: codeBlocks)
    return spans.sorted {
      if $0.range.location == $1.range.location {
        return $0.range.length > $1.range.length
      }
      return $0.range.location < $1.range.location
    }
  }

  private static func blockSpans(in nsString: NSString, codeBlocks: [NSRange]) -> [MarkdownStyleSpan] {
    var spans: [MarkdownStyleSpan] = []
    var location = 0
    while location < nsString.length {
      let lineRange = nsString.lineRange(for: NSRange(location: location, length: 0))
      if intersectsAny(lineRange, codeBlocks) {
        location = NSMaxRange(lineRange)
        continue
      }

      let line = nsString.substring(with: lineRange)
      if let match = MarkdownTextRange.firstRegexMatch("^\\s*(#{1,6})(\\s+)(.+)$", in: line) {
        let level = min(match.range(at: 1).length, 6)
        spans.append(MarkdownStyleSpan(
          kind: .headingMarker,
          range: shifted(match.range(at: 1), by: lineRange.location),
          level: level
        ))
        spans.append(MarkdownStyleSpan(
          kind: .heading,
          range: shifted(match.range(at: 3), by: lineRange.location),
          level: level
        ))
      } else if let match = MarkdownTextRange.firstRegexMatch("^\\s{0,3}>\\s?(.+)$", in: line) {
        spans.append(MarkdownStyleSpan(kind: .blockquote, range: lineRange))
        spans.append(MarkdownStyleSpan(
          kind: .italic,
          range: shifted(match.range(at: 1), by: lineRange.location)
        ))
      } else if let match = MarkdownTextRange.firstRegexMatch("^\\s*([-*+])\\s+(\\[[ xX]\\])\\s+(.+)$", in: line) {
        spans.append(MarkdownStyleSpan(
          kind: .listMarker,
          range: shifted(match.range(at: 1), by: lineRange.location)
        ))
        spans.append(MarkdownStyleSpan(
          kind: .taskCheckbox,
          range: shifted(match.range(at: 2), by: lineRange.location)
        ))
        let checkbox = (line as NSString).substring(with: match.range(at: 2))
        if checkbox.lowercased() == "[x]" {
          spans.append(MarkdownStyleSpan(
            kind: .completedTask,
            range: shifted(match.range(at: 3), by: lineRange.location)
          ))
        }
      } else if let match = MarkdownTextRange.firstRegexMatch("^\\s*([-*+])\\s+(.+)$", in: line) {
        spans.append(MarkdownStyleSpan(
          kind: .listMarker,
          range: shifted(match.range(at: 1), by: lineRange.location)
        ))
      } else if let match = MarkdownTextRange.firstRegexMatch("^\\s*(\\d+[.)])\\s+(.*)$", in: line) {
        spans.append(MarkdownStyleSpan(
          kind: .listMarker,
          range: shifted(match.range(at: 1), by: lineRange.location)
        ))
      } else if MarkdownTextRange.firstRegexMatch("^\\s{0,3}(([-*_])\\s*){3,}$", in: line) != nil {
        spans.append(MarkdownStyleSpan(kind: .thematicBreak, range: lineRange))
      }

      location = NSMaxRange(lineRange)
    }
    return spans
  }

  private static func inlineSpans(
    in text: String,
    fullRange: NSRange,
    skippedRanges: [NSRange]
  ) -> [MarkdownStyleSpan] {
    var spans: [MarkdownStyleSpan] = []
    let inlineCodeSpans = matches(pattern: "`([^`\\n]+)`", in: text, fullRange: fullRange, skippedRanges: skippedRanges) {
      [MarkdownStyleSpan(kind: .inlineCode, range: $0.range(at: 0))]
    }
    let inlineCodeRanges = inlineCodeSpans.map(\.range)
    spans += inlineCodeSpans
    spans += matches(pattern: "(\\*\\*|__)(.+?)\\1", in: text, fullRange: fullRange, skippedRanges: skippedRanges) {
      [MarkdownStyleSpan(kind: .bold, range: $0.range(at: 2))]
    }
    spans += matches(
      pattern: "(?<!\\*)\\*(?!\\*)([^*\\n]+)(?<!\\*)\\*(?!\\*)",
      in: text,
      fullRange: fullRange,
      skippedRanges: skippedRanges
    ) {
      [MarkdownStyleSpan(kind: .italic, range: $0.range(at: 1))]
    }
    spans += matches(
      pattern: "(?<!_)_(?!_)([^_\\n]+)(?<!_)_(?!_)",
      in: text,
      fullRange: fullRange,
      skippedRanges: skippedRanges
    ) {
      [MarkdownStyleSpan(kind: .italic, range: $0.range(at: 1))]
    }
    spans += matches(pattern: "\\[([^\\]\\n]+)\\]\\(([^)\\n]+)\\)", in: text, fullRange: fullRange, skippedRanges: skippedRanges) {
      let nsString = text as NSString
      return [MarkdownStyleSpan(
        kind: .link,
        range: $0.range(at: 1),
        linkDestination: nsString.substring(with: $0.range(at: 2))
      )]
    }
    let markdownLinkRanges = checkingMatches(
      pattern: "!?\\[[^\\]\\n]+\\]\\([^)\\n]+\\)",
      in: text,
      fullRange: fullRange,
      skippedRanges: skippedRanges
    ).map(\.range)
    spans += autolinkSpans(
      in: text,
      fullRange: fullRange,
      skippedRanges: skippedRanges + inlineCodeRanges + markdownLinkRanges
    )
    return spans
  }

  private static func autolinkSpans(
    in text: String,
    fullRange: NSRange,
    skippedRanges: [NSRange]
  ) -> [MarkdownStyleSpan] {
    guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
      return []
    }

    return detector.matches(in: text, range: fullRange)
      .filter { $0.resultType == .link && !intersectsAny($0.range, skippedRanges) }
      .map {
        MarkdownStyleSpan(
          kind: .link,
          range: $0.range,
          linkDestination: $0.url?.absoluteString ?? (text as NSString).substring(with: $0.range)
        )
      }
  }

  private static func codeBlockRanges(in nsString: NSString) -> [NSRange] {
    var ranges: [NSRange] = []
    var start: Int?
    var location = 0
    while location < nsString.length {
      let lineRange = nsString.lineRange(for: NSRange(location: location, length: 0))
      let line = nsString.substring(with: lineRange)
      if MarkdownTextRange.firstRegexMatch("^\\s*```", in: line) != nil {
        if let existingStart = start {
          ranges.append(NSRange(
            location: existingStart,
            length: NSMaxRange(lineRange) - existingStart
          ))
          start = nil
        } else {
          start = lineRange.location
        }
      }
      location = NSMaxRange(lineRange)
    }
    if let existingStart = start {
      ranges.append(NSRange(location: existingStart, length: nsString.length - existingStart))
    }
    return ranges
  }

  private static func matches(
    pattern: String,
    in text: String,
    fullRange: NSRange,
    skippedRanges: [NSRange],
    makeSpans: (NSTextCheckingResult) -> [MarkdownStyleSpan]
  ) -> [MarkdownStyleSpan] {
    guard let regex = try? NSRegularExpression(pattern: pattern) else {
      return []
    }
    return regex.matches(in: text, range: fullRange)
      .filter { !intersectsAny($0.range, skippedRanges) }
      .flatMap(makeSpans)
  }

  private static func checkingMatches(
    pattern: String,
    in text: String,
    fullRange: NSRange,
    skippedRanges: [NSRange]
  ) -> [NSTextCheckingResult] {
    guard let regex = try? NSRegularExpression(pattern: pattern) else {
      return []
    }
    return regex.matches(in: text, range: fullRange)
      .filter { !intersectsAny($0.range, skippedRanges) }
  }

  private static func shifted(_ range: NSRange, by offset: Int) -> NSRange {
    NSRange(location: range.location + offset, length: range.length)
  }

  private static func intersectsAny(_ range: NSRange, _ ranges: [NSRange]) -> Bool {
    ranges.contains { NSIntersectionRange(range, $0).length > 0 }
  }
}
