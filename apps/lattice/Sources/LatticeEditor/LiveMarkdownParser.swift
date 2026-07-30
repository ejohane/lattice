import Foundation

public enum LiveMarkdownTokenKind: Equatable, Sendable {
  case heading(level: Int)
  case thematicBreak
  case codeBlock(isFence: Bool)
  case blockquote(level: Int)
  case bold
  case boldItalic
  case italic
  case strikethrough
  case escapedCharacter
  case inlineCode
  case markdownLink(destination: String)
  case referenceLink(destination: String)
  case autolink(destination: String)
  case footnoteReference(label: String)
  case footnoteDefinition(label: String)
  case bareLink(destination: String)
  case wikiLink(target: String)
  case bullet
  case orderedList
  case task(isChecked: Bool)
}

public struct LiveMarkdownToken: Equatable, Sendable {
  public let kind: LiveMarkdownTokenKind
  public let fullRange: NSRange
  public let contentRange: NSRange
  public let syntaxRanges: [NSRange]
  public let decorationRange: NSRange?

  public init(
    kind: LiveMarkdownTokenKind,
    fullRange: NSRange,
    contentRange: NSRange,
    syntaxRanges: [NSRange],
    decorationRange: NSRange? = nil
  ) {
    self.kind = kind
    self.fullRange = fullRange
    self.contentRange = contentRange
    self.syntaxRanges = syntaxRanges
    self.decorationRange = decorationRange
  }

  public func isActive(selection: NSRange) -> Bool {
    guard selection.location != NSNotFound else { return false }
    if selection.length == 0 {
      return selection.location >= fullRange.location
        && selection.location <= NSMaxRange(fullRange)
    }
    return NSIntersectionRange(selection, fullRange).length > 0
  }

  public func shifted(by delta: Int) -> LiveMarkdownToken {
    LiveMarkdownToken(
      kind: kind,
      fullRange: Self.shift(fullRange, by: delta),
      contentRange: Self.shift(contentRange, by: delta),
      syntaxRanges: syntaxRanges.map { Self.shift($0, by: delta) },
      decorationRange: decorationRange.map { Self.shift($0, by: delta) }
    )
  }

  private static func shift(_ range: NSRange, by delta: Int) -> NSRange {
    NSRange(location: max(0, range.location + delta), length: range.length)
  }
}

public enum LiveMarkdownParser {
  public static func tokens(in text: String, range requestedRange: NSRange? = nil) -> [LiveMarkdownToken] {
    tokens(in: text as NSString, range: requestedRange)
  }

  public static func tokens(
    in source: NSString,
    range requestedRange: NSRange? = nil
  ) -> [LiveMarkdownToken] {
    guard source.length > 0 else { return [] }

    let parseRange: NSRange
    if let requestedRange {
      parseRange = lineRange(in: source, covering: requestedRange, adjacentLineCount: 0)
    } else {
      parseRange = NSRange(location: 0, length: source.length)
    }

    var result: [LiveMarkdownToken] = []
    let definitions = referenceDefinitions(in: source)
    let codeLines = codeBlockLines(in: source)
    var location = parseRange.location
    while location < NSMaxRange(parseRange) {
      let rawLineRange = source.lineRange(for: NSRange(location: location, length: 0))
      let lineRange = MarkdownTextRange.contentRangeWithoutLineEnding(rawLineRange, in: source)
      let line = source.substring(with: lineRange)

      if let codeLine = codeLines.first(where: { $0.range == rawLineRange }) {
        result.append(codeBlockToken(
          lineRange: lineRange,
          isFence: codeLine.isFence
        ))
        let nextLocation = NSMaxRange(rawLineRange)
        guard nextLocation > location else { break }
        location = nextLocation
        continue
      }

      let blockTokens = blockTokens(in: line, offset: lineRange.location, lineRange: lineRange)
      result += blockTokens
      let footnoteDefinition = footnoteDefinitionToken(
        in: line,
        offset: lineRange.location,
        lineRange: lineRange
      )
      if let footnoteDefinition {
        result.append(footnoteDefinition)
      } else if !blockTokens.contains(where: { $0.kind == .thematicBreak }) {
        result += inlineTokens(
          in: line,
          offset: lineRange.location,
          referenceDefinitions: definitions
        )
      }

      let nextLocation = NSMaxRange(rawLineRange)
      guard nextLocation > location else { break }
      location = nextLocation
    }

    return result.sorted {
      if $0.fullRange.location == $1.fullRange.location {
        return $0.fullRange.length > $1.fullRange.length
      }
      return $0.fullRange.location < $1.fullRange.location
    }
  }

  public static func affectedLineRange(
    in text: String,
    around range: NSRange,
    adjacentLineCount: Int = 1
  ) -> NSRange {
    affectedLineRange(
      in: text as NSString,
      around: range,
      adjacentLineCount: adjacentLineCount
    )
  }

  public static func affectedLineRange(
    in source: NSString,
    around range: NSRange,
    adjacentLineCount: Int = 1
  ) -> NSRange {
    lineRange(
      in: source,
      covering: range,
      adjacentLineCount: max(0, adjacentLineCount)
    )
  }

  private static func blockTokens(
    in line: String,
    offset: Int,
    lineRange: NSRange
  ) -> [LiveMarkdownToken] {
    let source = line as NSString
    if MarkdownTextRange.firstRegexMatch(
      "^([ \\t]{0,3})([-*_])(?:[ \\t]*\\2){2,}[ \\t]*$",
      in: line
    ) != nil {
      return [LiveMarkdownToken(
        kind: .thematicBreak,
        fullRange: lineRange,
        contentRange: lineRange,
        syntaxRanges: [lineRange],
        decorationRange: lineRange
      )]
    }

    if let match = MarkdownTextRange.firstRegexMatch("^([ \\t]{0,3})(#{1,6})([ \\t]+)(.*)$", in: line) {
      let level = min(6, match.range(at: 2).length)
      let syntax = combined(match.range(at: 2), match.range(at: 3), offset: offset)
      return [LiveMarkdownToken(
        kind: .heading(level: level),
        fullRange: lineRange,
        contentRange: shifted(match.range(at: 4), by: offset),
        syntaxRanges: [syntax]
      )]
    }

    if let match = MarkdownTextRange.firstRegexMatch("^([ \\t]{0,3}(?:>[ \\t]*)+)(.*)$", in: line) {
      let prefix = source.substring(with: match.range(at: 1))
      let content = match.range(at: 2)
      var tokens = [LiveMarkdownToken(
        kind: .blockquote(level: prefix.filter { $0 == ">" }.count),
        fullRange: lineRange,
        contentRange: shifted(content, by: offset),
        syntaxRanges: [shifted(match.range(at: 1), by: offset)],
        decorationRange: lineRange
      )]

      if content.length > 0 {
        tokens += blockTokens(
          in: source.substring(with: content),
          offset: offset + content.location,
          lineRange: lineRange
        )
      }
      return tokens
    }

    if let match = MarkdownTextRange.firstRegexMatch(
      "^([ \\t]*)(\\d+[.)])([ \\t]+)(.*)$",
      in: line
    ) {
      return [LiveMarkdownToken(
        kind: .orderedList,
        fullRange: lineRange,
        contentRange: shifted(match.range(at: 4), by: offset),
        syntaxRanges: [],
        decorationRange: shifted(match.range(at: 2), by: offset)
      )]
    }

    guard let match = MarkdownTextRange.firstRegexMatch(
      "^([ \\t]*)([-*+])([ \\t]+)(?:(\\[([ xX])\\])([ \\t]+))?(.*)$",
      in: line
    ) else {
      return []
    }

    let bulletRange = shifted(match.range(at: 2), by: offset)
    let contentRange = shifted(match.range(at: 7), by: offset)
    if match.range(at: 4).location != NSNotFound {
      let checkboxRange = shifted(match.range(at: 4), by: offset)
      let state = source.substring(with: match.range(at: 5))
      return [LiveMarkdownToken(
        kind: .task(isChecked: state.lowercased() == "x"),
        fullRange: lineRange,
        contentRange: contentRange,
        syntaxRanges: [bulletRange, checkboxRange],
        decorationRange: checkboxRange
      )]
    }

    return [LiveMarkdownToken(
      kind: .bullet,
      fullRange: lineRange,
      contentRange: contentRange,
      syntaxRanges: [bulletRange],
      decorationRange: bulletRange
    )]
  }

  private static func inlineTokens(
    in line: String,
    offset: Int,
    referenceDefinitions: [String: String]
  ) -> [LiveMarkdownToken] {
    let fullRange = NSRange(location: 0, length: (line as NSString).length)
    guard fullRange.length > 0 else { return [] }

    var allEscapedTokens = escapedCharacterTokens(in: line, offset: offset)
    if let hardBreak = hardBreakToken(in: line, offset: offset) {
      allEscapedTokens.append(hardBreak)
    }
    let allEscapedRanges = allEscapedTokens.map(\.fullRange).map { shifted($0, by: -offset) }
    let codeTokens = matches(pattern: "`([^`\\n]+)`", in: line, range: fullRange, skippedRanges: allEscapedRanges) {
      token(kind: .inlineCode, match: $0, contentGroup: 1, markerLength: 1, offset: offset)
    }
    let codeRanges = codeTokens.map(\.fullRange).map { shifted($0, by: -offset) }
    let escapedTokens = allEscapedTokens.filter { token in
      !codeRanges.contains { NSIntersectionRange(token.fullRange, $0).length > 0 }
    }
    let escapedRanges = escapedTokens.map(\.fullRange).map { shifted($0, by: -offset) }

    let wikiLinkTokens = line.contains("[[")
      ? matches(
        pattern: "\\[\\[([^\\[\\]\\n]+)\\]\\]",
        in: line,
        range: fullRange,
        skippedRanges: codeRanges
      ) { match in
        wikiLinkToken(match: match, in: line, offset: offset)
      }
      : []
    let wikiLinkRanges = wikiLinkTokens.map(\.fullRange).map { shifted($0, by: -offset) }
    let imageRanges = imageMarkdownRanges(in: line)

    let markdownLinkTokens = line.contains("](")
      ? matches(
        pattern: "(?<!!)\\[([^]\\n]+)\\]\\(([^)\\n]+)\\)",
        in: line,
        range: fullRange,
        skippedRanges: codeRanges + wikiLinkRanges + imageRanges
      ) { match in
        markdownLinkToken(match: match, in: line, offset: offset)
      }
      : []
    let markdownLinkRanges = markdownLinkTokens.map(\.fullRange).map { shifted($0, by: -offset) }
    let referenceLinkTokens = referenceLinkTokens(
      in: line,
      offset: offset,
      definitions: referenceDefinitions,
      skippedRanges: codeRanges + wikiLinkRanges + imageRanges + markdownLinkRanges
    )
    let referenceLinkRanges = referenceLinkTokens.map(\.fullRange).map { shifted($0, by: -offset) }
    let autolinkTokens = autolinkTokens(
      in: line,
      offset: offset,
      skippedRanges: codeRanges + wikiLinkRanges + imageRanges + markdownLinkRanges + referenceLinkRanges
    )
    let autolinkRanges = autolinkTokens.map(\.fullRange).map { shifted($0, by: -offset) }
    let linkOpaqueRanges = codeRanges + wikiLinkRanges + imageRanges + markdownLinkRanges + referenceLinkRanges + autolinkRanges
    let footnoteTokens = footnoteReferenceTokens(
      in: line,
      offset: offset,
      skippedRanges: linkOpaqueRanges
    )
    let footnoteRanges = footnoteTokens.map(\.fullRange).map { shifted($0, by: -offset) }
    let bareLinkTokens = bareLinkTokens(
      in: line,
      offset: offset,
      skippedRanges: codeRanges + wikiLinkRanges + imageRanges + markdownLinkRanges + referenceLinkRanges + autolinkRanges + footnoteRanges
    )
    let bareLinkRanges = bareLinkTokens.map(\.fullRange).map { shifted($0, by: -offset) }
    let opaqueRanges = escapedRanges + codeRanges + wikiLinkRanges + imageRanges + markdownLinkRanges
      + referenceLinkRanges + autolinkRanges + footnoteRanges + bareLinkRanges

    let quadBoldTokens = matches(
      pattern: "(\\*{4}|_{4})(.+?)\\1",
      in: line,
      range: fullRange,
      skippedRanges: opaqueRanges
    ) { match in
      token(
        kind: .bold,
        match: match,
        contentGroup: 2,
        markerLength: match.range(at: 1).length,
        offset: offset
      )
    }
    let quadBoldRanges = quadBoldTokens.map(\.fullRange).map { shifted($0, by: -offset) }

    let boldItalicTokens = matches(
      pattern: "(\\*{3}|_{3})(.+?)\\1",
      in: line,
      range: fullRange,
      skippedRanges: opaqueRanges + quadBoldRanges
    ) { match in
      token(
        kind: .boldItalic,
        match: match,
        contentGroup: 2,
        markerLength: match.range(at: 1).length,
        offset: offset
      )
    }
    let boldItalicRanges = boldItalicTokens.map(\.fullRange).map { shifted($0, by: -offset) }

    let strikethroughTokens = matches(
      pattern: "(~~)(.+?)\\1",
      in: line,
      range: fullRange,
      skippedRanges: opaqueRanges + quadBoldRanges + boldItalicRanges
    ) { match in
      token(
        kind: .strikethrough,
        match: match,
        contentGroup: 2,
        markerLength: match.range(at: 1).length,
        offset: offset
      )
    }
    let strikethroughRanges = strikethroughTokens.map(\.fullRange).map { shifted($0, by: -offset) }

    let boldTokens = matches(
      pattern: "(\\*{2}|_{2})(.+?)\\1",
      in: line,
      range: fullRange,
      skippedRanges: opaqueRanges + quadBoldRanges + boldItalicRanges + strikethroughRanges
    ) { match in
      let markerLength = match.range(at: 1).length
      return token(
        kind: .bold,
        match: match,
        contentGroup: 2,
        markerLength: markerLength,
        offset: offset
      )
    }
    let boldRanges = boldTokens.map(\.fullRange).map { shifted($0, by: -offset) }
    let nestedItalicTokens = nestedItalicTokens(
      in: line,
      offset: offset,
      outerTokens: quadBoldTokens + boldTokens + boldItalicTokens
    )
    let skipped = opaqueRanges + quadBoldRanges + boldItalicRanges + strikethroughRanges + boldRanges

    let starItalic = matches(
      pattern: "(?<!\\*)\\*(?!\\*)([^*\\n]+)(?<!\\*)\\*(?!\\*)",
      in: line,
      range: fullRange,
      skippedRanges: skipped
    ) {
      token(kind: .italic, match: $0, contentGroup: 1, markerLength: 1, offset: offset)
    }
    let underscoreItalic = matches(
      pattern: "(?<!_)_(?!_)([^_\\n]+)(?<!_)_(?!_)",
      in: line,
      range: fullRange,
      skippedRanges: skipped
    ) {
      token(kind: .italic, match: $0, contentGroup: 1, markerLength: 1, offset: offset)
    }

    return escapedTokens + codeTokens + wikiLinkTokens + markdownLinkTokens + referenceLinkTokens
      + autolinkTokens + footnoteTokens + bareLinkTokens + boldItalicTokens + strikethroughTokens
      + quadBoldTokens + boldTokens + nestedItalicTokens + starItalic + underscoreItalic
  }

  private static func nestedItalicTokens(
    in line: String,
    offset: Int,
    outerTokens: [LiveMarkdownToken]
  ) -> [LiveMarkdownToken] {
    var result: [LiveMarkdownToken] = []
    for outer in outerTokens {
      let localContentRange = shifted(outer.contentRange, by: -offset)
      result += matches(
        pattern: "(?<!\\*)\\*(?!\\*)([^*\\n]+)(?<!\\*)\\*(?!\\*)",
        in: line,
        range: localContentRange,
        skippedRanges: []
      ) {
        token(kind: .italic, match: $0, contentGroup: 1, markerLength: 1, offset: offset)
      }
      result += matches(
        pattern: "(?<!_)_(?!_)([^_\\n]+)(?<!_)_(?!_)",
        in: line,
        range: localContentRange,
        skippedRanges: []
      ) {
        token(kind: .italic, match: $0, contentGroup: 1, markerLength: 1, offset: offset)
      }
    }
    return result
  }

  private struct CodeBlockLine {
    let range: NSRange
    let isFence: Bool
  }

  private static func codeBlockLines(in source: NSString) -> [CodeBlockLine] {
    var lines: [CodeBlockLine] = []
    var insideFence = false
    var location = 0

    while location < source.length {
      let rawLineRange = source.lineRange(for: NSRange(location: location, length: 0))
      let lineRange = MarkdownTextRange.contentRangeWithoutLineEnding(rawLineRange, in: source)
      let line = source.substring(with: lineRange)
      let isFence = MarkdownTextRange.firstRegexMatch(
        "^([ \\t]{0,3})(`{3,}).*$",
        in: line
      ) != nil

      if isFence {
        lines.append(CodeBlockLine(range: rawLineRange, isFence: true))
        insideFence.toggle()
      } else if insideFence {
        lines.append(CodeBlockLine(range: rawLineRange, isFence: false))
      }

      let nextLocation = NSMaxRange(rawLineRange)
      guard nextLocation > location else { break }
      location = nextLocation
    }
    return lines
  }

  private static func codeBlockToken(
    lineRange: NSRange,
    isFence: Bool
  ) -> LiveMarkdownToken {
    LiveMarkdownToken(
      kind: .codeBlock(isFence: isFence),
      fullRange: lineRange,
      contentRange: lineRange,
      syntaxRanges: isFence ? [lineRange] : []
    )
  }

  private static func referenceDefinitions(in source: NSString) -> [String: String] {
    var definitions: [String: String] = [:]
    var location = 0
    while location < source.length {
      let rawLineRange = source.lineRange(for: NSRange(location: location, length: 0))
      let lineRange = MarkdownTextRange.contentRangeWithoutLineEnding(rawLineRange, in: source)
      let line = source.substring(with: lineRange)
      if let match = MarkdownTextRange.firstRegexMatch(
        "^\\[([^]\\n]+)\\]:[ \\t]*(?:<([^>\\n]+)>|(\\S+))",
        in: line
      ) {
        let label = (line as NSString).substring(with: match.range(at: 1)).lowercased()
        let destinationRange = match.range(at: 2).location != NSNotFound
          ? match.range(at: 2)
          : match.range(at: 3)
        definitions[label] = (line as NSString).substring(with: destinationRange)
      }
      let nextLocation = NSMaxRange(rawLineRange)
      guard nextLocation > location else { break }
      location = nextLocation
    }
    return definitions
  }

  private static func referenceLinkTokens(
    in line: String,
    offset: Int,
    definitions: [String: String],
    skippedRanges: [NSRange]
  ) -> [LiveMarkdownToken] {
    let source = line as NSString
    let fullRange = NSRange(location: 0, length: source.length)
    guard let regex = try? NSRegularExpression(pattern: "\\[([^]\\n]+)\\]\\[([^]\\n]*)\\]") else {
      return []
    }
    return regex.matches(in: line, range: fullRange).compactMap { match in
      guard !skippedRanges.contains(where: { NSIntersectionRange($0, match.range).length > 0 }) else {
        return nil
      }
      let label = source.substring(with: match.range(at: 1))
      let reference = source.substring(with: match.range(at: 2))
      guard let destination = definitions[(reference.isEmpty ? label : reference).lowercased()] else {
        return nil
      }
      let suffix = NSRange(
        location: NSMaxRange(match.range(at: 1)),
        length: NSMaxRange(match.range(at: 0)) - NSMaxRange(match.range(at: 1))
      )
      return LiveMarkdownToken(
        kind: .referenceLink(destination: destination),
        fullRange: shifted(match.range(at: 0), by: offset),
        contentRange: shifted(match.range(at: 1), by: offset),
        syntaxRanges: [
          shifted(NSRange(location: match.range(at: 0).location, length: 1), by: offset),
          shifted(suffix, by: offset)
        ]
      )
    }
  }

  private static func imageMarkdownRanges(in line: String) -> [NSRange] {
    let source = line as NSString
    let fullRange = NSRange(location: 0, length: source.length)
    guard let regex = try? NSRegularExpression(
      pattern: "!\\[[^]\\n]*\\]\\([^)\\n]+\\)"
    ) else { return [] }
    return regex.matches(in: line, range: fullRange).map(\.range)
  }

  private static func footnoteReferenceTokens(
    in line: String,
    offset: Int,
    skippedRanges: [NSRange]
  ) -> [LiveMarkdownToken] {
    let source = line as NSString
    let fullRange = NSRange(location: 0, length: source.length)
    guard let regex = try? NSRegularExpression(pattern: "\\[\\^([^]\\n]+)\\]") else { return [] }
    return regex.matches(in: line, range: fullRange).compactMap { match in
      guard !skippedRanges.contains(where: { NSIntersectionRange($0, match.range).length > 0 }) else {
        return nil
      }
      return LiveMarkdownToken(
        kind: .footnoteReference(label: source.substring(with: match.range(at: 1))),
        fullRange: shifted(match.range(at: 0), by: offset),
        contentRange: shifted(match.range(at: 1), by: offset),
        syntaxRanges: [
          shifted(NSRange(location: match.range(at: 0).location, length: 2), by: offset),
          shifted(NSRange(location: NSMaxRange(match.range(at: 0)) - 1, length: 1), by: offset)
        ]
      )
    }
  }

  private static func footnoteDefinitionToken(
    in line: String,
    offset: Int,
    lineRange: NSRange
  ) -> LiveMarkdownToken? {
    guard let match = MarkdownTextRange.firstRegexMatch("^\\[\\^([^]\\n]+)\\]:", in: line) else {
      return nil
    }
    return LiveMarkdownToken(
      kind: .footnoteDefinition(label: (line as NSString).substring(with: match.range(at: 1))),
      fullRange: lineRange,
      contentRange: shifted(match.range(at: 1), by: offset),
      syntaxRanges: [
        shifted(NSRange(location: 0, length: 2), by: offset),
        shifted(NSRange(location: NSMaxRange(match.range(at: 1)), length: 1), by: offset)
      ]
    )
  }

  private static func autolinkTokens(
    in line: String,
    offset: Int,
    skippedRanges: [NSRange]
  ) -> [LiveMarkdownToken] {
    let source = line as NSString
    let fullRange = NSRange(location: 0, length: source.length)
    guard let regex = try? NSRegularExpression(
      pattern: "<((?:https?://[^>\\n]+|[^<>\\s@]+@[^<>\\s@]+\\.[^<>\\s@]+))>"
    ) else { return [] }
    return regex.matches(in: line, range: fullRange).compactMap { match in
      guard !skippedRanges.contains(where: { NSIntersectionRange($0, match.range).length > 0 }) else {
        return nil
      }
      var destination = source.substring(with: match.range(at: 1))
      if !destination.contains("://") && destination.contains("@") {
        destination = "mailto:" + destination
      }
      return LiveMarkdownToken(
        kind: .autolink(destination: destination),
        fullRange: shifted(match.range(at: 0), by: offset),
        contentRange: shifted(match.range(at: 1), by: offset),
        syntaxRanges: [
          shifted(NSRange(location: match.range(at: 0).location, length: 1), by: offset),
          shifted(NSRange(location: NSMaxRange(match.range(at: 0)) - 1, length: 1), by: offset)
        ]
      )
    }
  }

  private static func hardBreakToken(in line: String, offset: Int) -> LiveMarkdownToken? {
    let source = line as NSString
    guard source.length > 0, source.character(at: source.length - 1) == 92 else { return nil }
    var slashCount = 0
    var location = source.length - 1
    while location >= 0, source.character(at: location) == 92 {
      slashCount += 1
      location -= 1
    }
    guard slashCount % 2 == 1 else { return nil }
    let range = shifted(NSRange(location: source.length - 1, length: 1), by: offset)
    return LiveMarkdownToken(
      kind: .escapedCharacter,
      fullRange: range,
      contentRange: NSRange(location: NSMaxRange(range), length: 0),
      syntaxRanges: [range]
    )
  }

  private static func escapedCharacterTokens(in line: String, offset: Int) -> [LiveMarkdownToken] {
    let source = line as NSString
    var tokens: [LiveMarkdownToken] = []
    var location = 0

    while location + 1 < source.length {
      guard source.character(at: location) == 92,
            let character = UnicodeScalar(source.character(at: location + 1)),
            escapableCharacters.contains(character)
      else {
        location += 1
        continue
      }

      let fullRange = NSRange(location: location, length: 2)
      tokens.append(LiveMarkdownToken(
        kind: .escapedCharacter,
        fullRange: shifted(fullRange, by: offset),
        contentRange: shifted(NSRange(location: location + 1, length: 1), by: offset),
        syntaxRanges: [shifted(NSRange(location: location, length: 1), by: offset)]
      ))
      location += 2
    }

    return tokens
  }

  private static let escapableCharacters = Set(
    "!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~".unicodeScalars
  )

  private static func wikiLinkToken(
    match: NSTextCheckingResult,
    in line: String,
    offset: Int
  ) -> LiveMarkdownToken {
    let source = line as NSString
    let localFullRange = match.range(at: 0)
    let localContentRange = match.range(at: 1)
    let opening = NSRange(location: localFullRange.location, length: 2)
    let closing = NSRange(location: NSMaxRange(localFullRange) - 2, length: 2)
    return LiveMarkdownToken(
      kind: .wikiLink(target: source.substring(with: localContentRange)),
      fullRange: shifted(localFullRange, by: offset),
      contentRange: shifted(localContentRange, by: offset),
      syntaxRanges: [shifted(opening, by: offset), shifted(closing, by: offset)]
    )
  }

  private static func markdownLinkToken(
    match: NSTextCheckingResult,
    in line: String,
    offset: Int
  ) -> LiveMarkdownToken {
    let source = line as NSString
    let localFullRange = match.range(at: 0)
    let localContentRange = match.range(at: 1)
    let localDestinationRange = match.range(at: 2)
    let opening = NSRange(location: localFullRange.location, length: 1)
    let suffix = NSRange(
      location: NSMaxRange(localContentRange),
      length: NSMaxRange(localFullRange) - NSMaxRange(localContentRange)
    )
    return LiveMarkdownToken(
      kind: .markdownLink(
        destination: normalizedLinkDestination(source.substring(with: localDestinationRange))
      ),
      fullRange: shifted(localFullRange, by: offset),
      contentRange: shifted(localContentRange, by: offset),
      syntaxRanges: [shifted(opening, by: offset), shifted(suffix, by: offset)]
    )
  }

  private static func normalizedLinkDestination(_ rawDestination: String) -> String {
    let trimmed = rawDestination.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.hasPrefix("<"), let closing = trimmed.firstIndex(of: ">") {
      return String(trimmed[trimmed.index(after: trimmed.startIndex)..<closing])
    }
    return trimmed.split(whereSeparator: { $0 == " " || $0 == "\t" }).first.map(String.init) ?? trimmed
  }

  private static func bareLinkTokens(
    in line: String,
    offset: Int,
    skippedRanges: [NSRange]
  ) -> [LiveMarkdownToken] {
    guard line.range(of: "http://", options: .caseInsensitive) != nil
            || line.range(of: "https://", options: .caseInsensitive) != nil
    else { return [] }
    guard let regex = try? NSRegularExpression(
      pattern: "(?i)https?://[^\\s<>()\\[\\]{}]+"
    ) else { return [] }
    let source = line as NSString
    let fullRange = NSRange(location: 0, length: source.length)

    return regex.matches(in: line, range: fullRange).compactMap { match in
      var range = match.range
      while range.length > 0 {
        let trailing = source.substring(with: NSRange(location: NSMaxRange(range) - 1, length: 1))
        guard ".,!?;:".contains(trailing) else { break }
        range.length -= 1
      }
      guard range.length > 0,
            !skippedRanges.contains(where: { NSIntersectionRange($0, range).length > 0 })
      else { return nil }

      let destination = source.substring(with: range)
      return LiveMarkdownToken(
        kind: .bareLink(destination: destination),
        fullRange: shifted(range, by: offset),
        contentRange: shifted(range, by: offset),
        syntaxRanges: []
      )
    }
  }

  private static func token(
    kind: LiveMarkdownTokenKind,
    match: NSTextCheckingResult,
    contentGroup: Int,
    markerLength: Int,
    offset: Int
  ) -> LiveMarkdownToken {
    let localFullRange = match.range(at: 0)
    let opening = NSRange(location: localFullRange.location, length: markerLength)
    let closing = NSRange(location: NSMaxRange(localFullRange) - markerLength, length: markerLength)
    return LiveMarkdownToken(
      kind: kind,
      fullRange: shifted(localFullRange, by: offset),
      contentRange: shifted(match.range(at: contentGroup), by: offset),
      syntaxRanges: [shifted(opening, by: offset), shifted(closing, by: offset)]
    )
  }

  private static func matches(
    pattern: String,
    in text: String,
    range: NSRange,
    skippedRanges: [NSRange],
    makeToken: (NSTextCheckingResult) -> LiveMarkdownToken
  ) -> [LiveMarkdownToken] {
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
    return regex.matches(in: text, range: range)
      .filter { match in
        !skippedRanges.contains { NSIntersectionRange($0, match.range).length > 0 }
      }
      .map(makeToken)
  }

  private static func lineRange(
    in source: NSString,
    covering requestedRange: NSRange,
    adjacentLineCount: Int
  ) -> NSRange {
    guard source.length > 0 else { return NSRange(location: 0, length: 0) }
    let location = max(0, min(requestedRange.location, source.length))
    let length = max(0, min(requestedRange.length, source.length - location))
    let probeLocation = location == source.length ? max(0, source.length - 1) : location
    let probeLength = min(length, source.length - probeLocation)
    var result = source.lineRange(for: NSRange(location: probeLocation, length: probeLength))

    for _ in 0..<adjacentLineCount {
      if result.location > 0 {
        let previous = source.lineRange(for: NSRange(location: result.location - 1, length: 0))
        result = NSUnionRange(result, previous)
      }
      if NSMaxRange(result) < source.length {
        let next = source.lineRange(for: NSRange(location: NSMaxRange(result), length: 0))
        result = NSUnionRange(result, next)
      }
    }
    return result
  }

  private static func shifted(_ range: NSRange, by offset: Int) -> NSRange {
    guard range.location != NSNotFound else { return range }
    return NSRange(location: range.location + offset, length: range.length)
  }

  private static func combined(_ first: NSRange, _ second: NSRange, offset: Int) -> NSRange {
    let start = min(first.location, second.location)
    let end = max(NSMaxRange(first), NSMaxRange(second))
    return NSRange(location: start + offset, length: end - start)
  }
}

public enum LiveMarkdownLinkDestination {
  public static func webURL(for destination: String) -> URL? {
    guard let components = URLComponents(string: destination),
          let scheme = components.scheme?.lowercased()
    else { return nil }
    if scheme == "mailto" {
      return components.url
    }
    guard (scheme == "http" || scheme == "https"),
          components.host?.isEmpty == false
    else { return nil }
    return components.url
  }
}

public enum LiveMarkdownEditing {
  public struct LinkInsertion: Equatable, Sendable {
    public let replacementRange: NSRange
    public let replacement: String
    public let selection: NSRange

    public init(replacementRange: NSRange, replacement: String, selection: NSRange) {
      self.replacementRange = replacementRange
      self.replacement = replacement
      self.selection = selection
    }
  }

  public static func seededTitleInsertion(
    currentText: String,
    range: NSRange,
    replacement: String
  ) -> String {
    guard currentText.isEmpty,
          range.location == 0,
          range.length == 0,
          !replacement.isEmpty,
          !replacement.hasPrefix("\n"),
          !replacement.hasPrefix("\r")
    else { return replacement }

    let trimmed = replacement.drop(while: { $0 == " " || $0 == "\t" })
    let headingMarkerLength = trimmed.prefix(while: { $0 == "#" }).count
    if (1...6).contains(headingMarkerLength),
       trimmed.dropFirst(headingMarkerLength).first.map({ $0 == " " || $0 == "\t" }) == true {
      return replacement
    }
    return "# " + replacement
  }

  public static func linkInsertion(
    currentText: String,
    selection: NSRange,
    destinationPlaceholder: String = "https://"
  ) -> LinkInsertion? {
    guard selection.location != NSNotFound else { return nil }
    let source = currentText as NSString
    let location = max(0, min(selection.location, source.length))
    let range = NSRange(
      location: location,
      length: max(0, min(selection.length, source.length - location))
    )
    guard range.length > 0 else { return nil }

    let label = source.substring(with: range)
    guard !label.contains("\n"), !label.contains("\r") else { return nil }

    let replacement = "[\(label)](\(destinationPlaceholder))"
    let labelLength = (label as NSString).length
    let placeholderLength = (destinationPlaceholder as NSString).length
    return LinkInsertion(
      replacementRange: range,
      replacement: replacement,
      selection: NSRange(
        location: range.location + 1 + labelLength + 2,
        length: placeholderLength
      )
    )
  }
}
