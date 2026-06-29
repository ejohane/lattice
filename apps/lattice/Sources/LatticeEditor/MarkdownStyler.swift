import Foundation

public enum MarkdownStyleKind: String, Equatable, Sendable {
  case heading
  case headingMarker
  case listMarker
  case blockquote
  case thematicBreak
  case codeBlock
  case inlineCode
  case bold
  case italic
  case link
  case noteLink
  case noteLinkDelimiter
}

public struct MarkdownStyleSpan: Equatable, Sendable {
  public let kind: MarkdownStyleKind
  public let range: NSRange
  public let level: Int?
  public let containerRange: NSRange?

  public init(
    kind: MarkdownStyleKind,
    range: NSRange,
    level: Int? = nil,
    containerRange: NSRange? = nil
  ) {
    self.kind = kind
    self.range = range
    self.level = level
    self.containerRange = containerRange
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

  public static func noteLinkContainerRange(in text: String, containing selection: NSRange) -> NSRange? {
    spans(in: text).first { span in
      guard let containerRange = span.containerRange, span.kind == .noteLink else {
        return false
      }
      if selection.length == 0 {
        return NSLocationInRange(selection.location, containerRange)
      }
      return NSIntersectionRange(selection, containerRange).length > 0
    }?.containerRange
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
      if let match = firstMatch("^\\s*(#{1,6})(\\s+)(.+)$", in: line) {
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
      } else if let match = firstMatch("^\\s{0,3}>\\s?(.+)$", in: line) {
        spans.append(MarkdownStyleSpan(kind: .blockquote, range: lineRange))
        spans.append(MarkdownStyleSpan(
          kind: .italic,
          range: shifted(match.range(at: 1), by: lineRange.location)
        ))
      } else if let match = firstMatch("^\\s*([-*+])\\s+(\\[[ xX]\\]\\s+)?(.+)$", in: line) {
        spans.append(MarkdownStyleSpan(
          kind: .listMarker,
          range: shifted(match.range(at: 1), by: lineRange.location)
        ))
      } else if let match = firstMatch("^\\s*(\\d+[.)])\\s+(.+)$", in: line) {
        spans.append(MarkdownStyleSpan(
          kind: .listMarker,
          range: shifted(match.range(at: 1), by: lineRange.location)
        ))
      } else if firstMatch("^\\s{0,3}(([-*_])\\s*){3,}$", in: line) != nil {
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
    spans += matches(pattern: "`([^`\\n]+)`", in: text, fullRange: fullRange, skippedRanges: skippedRanges) {
      [MarkdownStyleSpan(kind: .inlineCode, range: $0.range(at: 0))]
    }
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
    spans += matches(pattern: "\\[([^\\]\\n]+)\\]\\(([^)\\n]+)\\)", in: text, fullRange: fullRange, skippedRanges: skippedRanges) {
      [MarkdownStyleSpan(kind: .link, range: $0.range(at: 1))]
    }
    spans += matches(pattern: "\\[\\[([^\\]\\n]+)\\]\\]", in: text, fullRange: fullRange, skippedRanges: skippedRanges) {
      let fullRange = $0.range(at: 0)
      return [
        MarkdownStyleSpan(
          kind: .noteLinkDelimiter,
          range: NSRange(location: fullRange.location, length: 2),
          containerRange: fullRange
        ),
        MarkdownStyleSpan(
          kind: .noteLink,
          range: $0.range(at: 1),
          containerRange: fullRange
        ),
        MarkdownStyleSpan(
          kind: .noteLinkDelimiter,
          range: NSRange(location: NSMaxRange(fullRange) - 2, length: 2),
          containerRange: fullRange
        )
      ]
    }
    return spans
  }

  private static func codeBlockRanges(in nsString: NSString) -> [NSRange] {
    var ranges: [NSRange] = []
    var start: Int?
    var location = 0
    while location < nsString.length {
      let lineRange = nsString.lineRange(for: NSRange(location: location, length: 0))
      let line = nsString.substring(with: lineRange)
      if firstMatch("^\\s*```", in: line) != nil {
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

  private static func intersectsAny(_ range: NSRange, _ ranges: [NSRange]) -> Bool {
    ranges.contains { NSIntersectionRange(range, $0).length > 0 }
  }
}
