import Foundation
import LatticeCore
import LatticeEditor

extension NSAttributedString.Key {
  static let latticeThematicBreak = NSAttributedString.Key("lattice.thematicBreak")
}

#if os(macOS)
import AppKit

enum MarkdownAttributedRenderer {
  static let bodyFontSize: CGFloat = 14

  static func render(
    _ text: String,
    fontSize: CGFloat = bodyFontSize,
    activeRanges: [NSRange] = [],
    wikiLinkStates: [WikiLinkRenderState] = [],
    dimsInactiveText: Bool = false
  ) -> NSAttributedString {
    let attributed = NSMutableAttributedString(string: text, attributes: baseTypingAttributes(fontSize: fontSize))
    applyStyles(to: attributed, fontSize: fontSize, activeRanges: activeRanges, wikiLinkStates: wikiLinkStates)
    if dimsInactiveText {
      applyInactiveTextDimming(to: attributed, activeRanges: activeRanges)
    }
    return attributed
  }

  static func bodyFont(size: CGFloat = bodyFontSize, weight: NSFont.Weight = .regular) -> NSFont {
    NSFont.systemFont(ofSize: size, weight: weight)
  }

  private static func monospaceBodyFont(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
    NSFont.monospacedSystemFont(ofSize: size, weight: weight)
  }

  static func baseTypingAttributes(fontSize: CGFloat = bodyFontSize) -> [NSAttributedString.Key: Any] {
    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.lineSpacing = 5 * fontSize / bodyFontSize
    paragraphStyle.paragraphSpacing = 6 * fontSize / bodyFontSize
    return [
      .font: bodyFont(size: fontSize),
      .foregroundColor: NSColor.labelColor,
      .paragraphStyle: paragraphStyle
    ]
  }

  private static func applyStyles(
    to attributed: NSMutableAttributedString,
    fontSize: CGFloat,
    activeRanges: [NSRange],
    wikiLinkStates: [WikiLinkRenderState]
  ) {
    let nsString = attributed.string as NSString
    let codeBlocks = codeBlockRanges(in: nsString)
    applyBlockStyles(to: attributed, fontSize: fontSize, codeBlocks: codeBlocks, activeRanges: activeRanges)
    applyInlineStyles(to: attributed, fontSize: fontSize, skippedRanges: codeBlocks, activeRanges: activeRanges)
    applyWikiLinkStyles(to: attributed, fontSize: fontSize, states: wikiLinkStates, activeRanges: activeRanges)
    hideLatticeMetadataComments(in: attributed, fontSize: fontSize, activeRanges: activeRanges)
  }

  private static func applyBlockStyles(
    to attributed: NSMutableAttributedString,
    fontSize: CGFloat,
    codeBlocks: [NSRange],
    activeRanges: [NSRange]
  ) {
    let nsString = attributed.string as NSString
    var location = 0
    while location < nsString.length {
      let lineRange = nsString.lineRange(for: NSRange(location: location, length: 0))
      let line = nsString.substring(with: lineRange)
      let isActiveLine = lineRangeContainsActiveRange(lineRange, activeRanges: activeRanges, in: nsString)
      let tokenAttributes = isActiveLine
        ? tokenAttributes(fontSize: fontSize)
        : hiddenTokenAttributes(fontSize: fontSize)

      if range(lineRange, intersectsAny: codeBlocks) {
        attributed.addAttributes(codeBlockAttributes(fontSize: fontSize), range: lineRange)
      } else if let match = firstMatch("^\\s*(#{1,6})(\\s+)(.+)$", in: line) {
        let level = min(match.range(at: 1).length, 6)
        attributed.addAttributes(tokenAttributes, range: shifted(match.range(at: 1), by: lineRange.location))
        attributed.addAttributes(tokenAttributes, range: shifted(match.range(at: 2), by: lineRange.location))
        attributed.addAttributes(headingAttributes(level: level, fontSize: fontSize), range: shifted(match.range(at: 3), by: lineRange.location))
      } else if let match = firstMatch("^\\s{0,3}>\\s?(.+)$", in: line) {
        attributed.addAttributes(blockQuoteAttributes(fontSize: fontSize), range: lineRange)
        attributed.addAttributes(tokenAttributes, range: shifted(NSRange(location: 0, length: 1), by: lineRange.location))
        attributed.addAttributes([.font: italicBodyFont(size: fontSize)], range: shifted(match.range(at: 1), by: lineRange.location))
      } else if let match = firstMatch("^\\s*([-*+])\\s+(\\[[ xX]\\])\\s+(.*)$", in: line) {
        let markerRange = shifted(match.range(at: 1), by: lineRange.location)
        let checkboxRange = shifted(match.range(at: 2), by: lineRange.location)
        let contentRange = shifted(match.range(at: 3), by: lineRange.location)
        let checkbox = (line as NSString).substring(with: match.range(at: 2))
        let isChecked = checkbox.lowercased() == "[x]"
        let shouldRenderMarker = !isActiveLine

        attributed.addAttributes(listAttributes(fontSize: fontSize), range: lineRange)
        attributed.addAttributes(
          shouldRenderMarker ? renderedTaskCheckboxAttributes(isChecked: isChecked, fontSize: fontSize) : bulletAttributes(fontSize: fontSize),
          range: markerRange
        )
        attributed.addAttributes(isActiveLine ? bulletAttributes(fontSize: fontSize) : hiddenTokenAttributes(fontSize: fontSize), range: checkboxRange)
        if isChecked {
          attributed.addAttributes(completedTaskAttributes(), range: contentRange)
        }
      } else if let match = firstMatch("^\\s*([-*+])\\s+(.*)$", in: line) {
        let contentRange = match.range(at: 2)
        let shouldRenderMarker = !isActiveLine || contentRange.length == 0

        attributed.addAttributes(listAttributes(fontSize: fontSize), range: lineRange)
        attributed.addAttributes(
          shouldRenderMarker ? renderedBulletAttributes(fontSize: fontSize) : bulletAttributes(fontSize: fontSize),
          range: shifted(match.range(at: 1), by: lineRange.location)
        )
      } else if let match = firstMatch("^\\s*(\\d+[.)])\\s+(.*)$", in: line) {
        attributed.addAttributes(listAttributes(fontSize: fontSize), range: lineRange)
        attributed.addAttributes(
          isActiveLine ? bulletAttributes(fontSize: fontSize) : hiddenTokenAttributes(fontSize: fontSize),
          range: shifted(match.range(at: 1), by: lineRange.location)
        )
      } else if firstMatch("^\\s{0,3}(([-*_])\\s*){3,}$", in: line) != nil {
        attributed.addAttributes(
          isActiveLine ? thematicBreakAttributes(fontSize: fontSize) : thematicBreakLineAttributes(fontSize: fontSize),
          range: lineRange
        )
      }

      location = NSMaxRange(lineRange)
    }
  }

  private static func applyInlineStyles(
    to attributed: NSMutableAttributedString,
    fontSize: CGFloat,
    skippedRanges: [NSRange],
    activeRanges: [NSRange]
  ) {
    let fullRange = NSRange(location: 0, length: attributed.length)
    let inlineCodeRanges = rangesMatching(
      pattern: "`([^`\\n]+)`",
      in: attributed.string,
      fullRange: fullRange,
      skippedRanges: skippedRanges
    )
    let markdownLinkRanges = rangesMatching(
      pattern: "!?\\[[^\\]\\n]+\\]\\([^)\\n]+\\)",
      in: attributed.string,
      fullRange: fullRange,
      skippedRanges: skippedRanges
    )
    applyInlineStyle(
      pattern: "`([^`\\n]+)`",
      to: attributed,
      fontSize: fontSize,
      skippedRanges: skippedRanges,
      activeRanges: activeRanges,
      contentAttributes: inlineCodeAttributes(fontSize: fontSize),
      tokenGroups: [0],
      contentGroups: [1]
    )
    applyInlineLinkStyle(
      pattern: "!\\[([^\\]\\n]*)\\]\\(([^)\\n]+)\\)",
      to: attributed,
      fontSize: fontSize,
      skippedRanges: skippedRanges,
      activeRanges: activeRanges,
      tokenGroups: [0],
      labelGroup: 1,
      urlGroup: 2
    )
    applyInlineLinkStyle(
      pattern: "\\[([^\\]\\n]+)\\]\\(([^)\\n]+)\\)",
      to: attributed,
      fontSize: fontSize,
      skippedRanges: skippedRanges,
      activeRanges: activeRanges,
      tokenGroups: [0],
      labelGroup: 1,
      urlGroup: 2
    )
    applyAutolinkStyles(
      to: attributed,
      fontSize: fontSize,
      skippedRanges: skippedRanges + inlineCodeRanges + markdownLinkRanges
    )
    applyInlineStyle(
      pattern: "(\\*\\*|__)(.+?)\\1",
      to: attributed,
      fontSize: fontSize,
      skippedRanges: skippedRanges,
      activeRanges: activeRanges,
      contentAttributes: [.font: bodyFont(size: fontSize, weight: .semibold), .foregroundColor: NSColor.labelColor],
      tokenGroups: [0],
      contentGroups: [2]
    )
    applyInlineStyle(
      pattern: "(~~)(.+?)\\1",
      to: attributed,
      fontSize: fontSize,
      skippedRanges: skippedRanges,
      activeRanges: activeRanges,
      contentAttributes: [
        .font: bodyFont(size: fontSize),
        .foregroundColor: NSColor.labelColor,
        .strikethroughStyle: NSUnderlineStyle.single.rawValue
      ],
      tokenGroups: [0],
      contentGroups: [2]
    )
    applyInlineStyle(
      pattern: "(?<!\\*)\\*(?!\\*)([^*\\n]+)(?<!\\*)\\*(?!\\*)",
      to: attributed,
      fontSize: fontSize,
      skippedRanges: skippedRanges,
      activeRanges: activeRanges,
      contentAttributes: [.font: italicBodyFont(size: fontSize), .foregroundColor: NSColor.labelColor],
      tokenGroups: [0],
      contentGroups: [1]
    )
    applyInlineStyle(
      pattern: "(?<!_)_(?!_)([^_\\n]+)(?<!_)_(?!_)",
      to: attributed,
      fontSize: fontSize,
      skippedRanges: skippedRanges,
      activeRanges: activeRanges,
      contentAttributes: [.font: italicBodyFont(size: fontSize), .foregroundColor: NSColor.labelColor],
      tokenGroups: [0],
      contentGroups: [1]
    )
  }

  private static func applyInlineStyle(
    pattern: String,
    to attributed: NSMutableAttributedString,
    fontSize: CGFloat,
    skippedRanges: [NSRange],
    activeRanges: [NSRange],
    contentAttributes: [NSAttributedString.Key: Any],
    tokenGroups: [Int],
    contentGroups: [Int]
  ) {
    guard let regex = try? NSRegularExpression(pattern: pattern) else {
      return
    }

    let fullRange = NSRange(location: 0, length: attributed.length)
    for match in regex.matches(in: attributed.string, range: fullRange) where !range(match.range, intersectsAny: skippedRanges) {
      let markdownTokenAttributes = range(match.range, containsAnyActive: activeRanges)
        ? tokenAttributes(fontSize: fontSize)
        : hiddenTokenAttributes(fontSize: fontSize)

      for group in tokenGroups {
        let tokenRange = match.range(at: group)
        if tokenRange.location != NSNotFound {
          attributed.addAttributes(markdownTokenAttributes, range: tokenRange)
        }
      }

      for group in contentGroups {
        let contentRange = match.range(at: group)
        if contentRange.location != NSNotFound {
          attributed.addAttributes(contentAttributes, range: contentRange)
        }
      }
    }
  }

  private static func applyInlineLinkStyle(
    pattern: String,
    to attributed: NSMutableAttributedString,
    fontSize: CGFloat,
    skippedRanges: [NSRange],
    activeRanges: [NSRange],
    tokenGroups: [Int],
    labelGroup: Int,
    urlGroup: Int
  ) {
    guard let regex = try? NSRegularExpression(pattern: pattern) else {
      return
    }

    let nsString = attributed.string as NSString
    let fullRange = NSRange(location: 0, length: attributed.length)
    for match in regex.matches(in: attributed.string, range: fullRange) where !range(match.range, intersectsAny: skippedRanges) {
      let markdownTokenAttributes = range(match.range, containsAnyActive: activeRanges)
        ? tokenAttributes(fontSize: fontSize)
        : hiddenTokenAttributes(fontSize: fontSize)

      for group in tokenGroups {
        let tokenRange = match.range(at: group)
        if tokenRange.location != NSNotFound {
          attributed.addAttributes(markdownTokenAttributes, range: tokenRange)
        }
      }

      let labelRange = match.range(at: labelGroup)
      let urlRange = match.range(at: urlGroup)
      guard labelRange.location != NSNotFound, urlRange.location != NSNotFound else {
        continue
      }

      let urlString = nsString.substring(with: urlRange)
      attributed.addAttributes(linkAttributes(fontSize: fontSize, urlString: urlString), range: labelRange)
    }
  }

  private static func applyAutolinkStyles(
    to attributed: NSMutableAttributedString,
    fontSize: CGFloat,
    skippedRanges: [NSRange]
  ) {
    guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
      return
    }

    let fullRange = NSRange(location: 0, length: attributed.length)
    for match in detector.matches(in: attributed.string, range: fullRange)
    where match.resultType == .link && !range(match.range, intersectsAny: skippedRanges) {
      attributed.addAttributes(linkAttributes(fontSize: fontSize, url: match.url), range: match.range)
    }
  }

  private static func headingAttributes(level: Int, fontSize: CGFloat) -> [NSAttributedString.Key: Any] {
    let sizes: [CGFloat] = [34, 30, 26, 23, 21, 20]
    let index = max(0, min(level - 1, sizes.count - 1))
    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.paragraphSpacingBefore = (level <= 2 ? 20 : 14) * fontSize / bodyFontSize
    paragraphStyle.paragraphSpacing = 14 * fontSize / bodyFontSize
    paragraphStyle.lineSpacing = 3 * fontSize / bodyFontSize

    return [
      .font: bodyFont(size: sizes[index] * fontSize / bodyFontSize, weight: .bold),
      .foregroundColor: NSColor.labelColor,
      .paragraphStyle: paragraphStyle
    ]
  }

  private static func tokenAttributes(fontSize: CGFloat) -> [NSAttributedString.Key: Any] {
    [
      .foregroundColor: NSColor.tertiaryLabelColor,
      .font: NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
    ]
  }

  private static func hiddenTokenAttributes(fontSize: CGFloat) -> [NSAttributedString.Key: Any] {
    [
      .foregroundColor: NSColor.clear,
      .font: bodyFont(size: max(0.1, 0.1 * fontSize / bodyFontSize), weight: .regular)
    ]
  }

  private static func bulletAttributes(fontSize: CGFloat) -> [NSAttributedString.Key: Any] {
    [
      .foregroundColor: NSColor.controlAccentColor,
      .font: bodyFont(size: 14 * fontSize / bodyFontSize, weight: .semibold)
    ]
  }

  private static func renderedBulletAttributes(fontSize: CGFloat) -> [NSAttributedString.Key: Any] {
    let font = bodyFont(size: 14 * fontSize / bodyFontSize, weight: .semibold)
    var attributes: [NSAttributedString.Key: Any] = [
      .foregroundColor: NSColor.controlAccentColor,
      .font: font
    ]

    if let glyphInfo = NSGlyphInfo(glyphName: "bullet", for: font, baseString: "-") {
      attributes[.glyphInfo] = glyphInfo
    }

    return attributes
  }

  private static func renderedTaskCheckboxAttributes(
    isChecked: Bool,
    fontSize: CGFloat
  ) -> [NSAttributedString.Key: Any] {
    let font = bodyFont(size: 15 * fontSize / bodyFontSize, weight: .semibold)
    var attributes: [NSAttributedString.Key: Any] = [
      .foregroundColor: NSColor.controlAccentColor,
      .font: font
    ]

    let glyphName = isChecked ? "uni2611" : "uni25A1"
    if let glyphInfo = NSGlyphInfo(glyphName: glyphName, for: font, baseString: "-") {
      attributes[.glyphInfo] = glyphInfo
    }

    return attributes
  }

  private static func listAttributes(fontSize: CGFloat) -> [NSAttributedString.Key: Any] {
    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.lineSpacing = 4 * fontSize / bodyFontSize
    paragraphStyle.paragraphSpacing = paragraphStyle.lineSpacing
    paragraphStyle.headIndent = 28 * fontSize / bodyFontSize
    paragraphStyle.firstLineHeadIndent = 0
    return [.paragraphStyle: paragraphStyle]
  }

  private static func blockQuoteAttributes(fontSize: CGFloat) -> [NSAttributedString.Key: Any] {
    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.lineSpacing = 5 * fontSize / bodyFontSize
    paragraphStyle.paragraphSpacing = 10 * fontSize / bodyFontSize
    paragraphStyle.headIndent = 20 * fontSize / bodyFontSize
    paragraphStyle.firstLineHeadIndent = 20 * fontSize / bodyFontSize

    return [
      .foregroundColor: NSColor.secondaryLabelColor,
      .paragraphStyle: paragraphStyle
    ]
  }

  private static func thematicBreakAttributes(fontSize: CGFloat) -> [NSAttributedString.Key: Any] {
    [
      .foregroundColor: NSColor.tertiaryLabelColor,
      .font: NSFont.monospacedSystemFont(ofSize: 18 * fontSize / bodyFontSize, weight: .medium)
    ]
  }

  private static func thematicBreakLineAttributes(fontSize: CGFloat) -> [NSAttributedString.Key: Any] {
    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.lineSpacing = 8 * fontSize / bodyFontSize
    paragraphStyle.paragraphSpacing = 8 * fontSize / bodyFontSize
    return [
      .foregroundColor: NSColor.clear,
      .font: bodyFont(size: fontSize),
      .paragraphStyle: paragraphStyle,
      .latticeThematicBreak: true
    ]
  }

  private static func codeBlockAttributes(fontSize: CGFloat) -> [NSAttributedString.Key: Any] {
    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.lineSpacing = 3 * fontSize / bodyFontSize
    paragraphStyle.paragraphSpacing = 0

    return [
      .font: monospaceBodyFont(size: fontSize),
      .foregroundColor: NSColor.labelColor,
      .backgroundColor: NSColor.controlBackgroundColor.withAlphaComponent(0.8),
      .paragraphStyle: paragraphStyle
    ]
  }

  private static func inlineCodeAttributes(fontSize: CGFloat) -> [NSAttributedString.Key: Any] {
    [
      .font: monospaceBodyFont(size: fontSize),
      .foregroundColor: NSColor.systemPink,
      .backgroundColor: NSColor.controlBackgroundColor.withAlphaComponent(0.8)
    ]
  }

  private static func linkAttributes(
    fontSize: CGFloat,
    urlString: String? = nil,
    url: URL? = nil
  ) -> [NSAttributedString.Key: Any] {
    var attributes: [NSAttributedString.Key: Any] = [
      .font: bodyFont(size: fontSize),
      .foregroundColor: NSColor.systemBlue,
      .underlineStyle: NSUnderlineStyle.single.rawValue
    ]

    if let url = url ?? urlString.flatMap(URL.init(string:)) {
      attributes[.link] = url
    }

    return attributes
  }

  private static func applyWikiLinkStyles(
    to attributed: NSMutableAttributedString,
    fontSize: CGFloat,
    states: [WikiLinkRenderState],
    activeRanges: [NSRange]
  ) {
    for link in WikiLinkParser.links(in: attributed.string) where NSMaxRange(link.range) <= attributed.length {
      let status = states.first { $0.range == link.range }?.status ?? .resolved
      attributed.addAttributes(
        wikiLinkAttributes(fontSize: fontSize, status: status),
        range: linkContentRange(for: link.range)
      )

      let delimiterAttributes = range(link.range, containsAnyActive: activeRanges)
        ? tokenAttributes(fontSize: fontSize)
        : hiddenTokenAttributes(fontSize: fontSize)
      for delimiterRange in linkDelimiterRanges(for: link.range) {
        attributed.addAttributes(delimiterAttributes, range: delimiterRange)
      }
    }
  }

  private static func wikiLinkAttributes(
    fontSize: CGFloat,
    status: WikiLinkRenderStatus
  ) -> [NSAttributedString.Key: Any] {
    switch status {
    case .resolved:
      return [
        .font: bodyFont(size: fontSize),
        .foregroundColor: NSColor.systemBlue,
        .underlineStyle: NSUnderlineStyle.single.rawValue
      ]
    case .ambiguous:
      return [
        .font: bodyFont(size: fontSize),
        .foregroundColor: NSColor.systemBlue.withAlphaComponent(0.85),
        .underlineStyle: NSUnderlineStyle.patternDot.rawValue | NSUnderlineStyle.single.rawValue
      ]
    case .broken:
      return [
        .font: bodyFont(size: fontSize),
        .foregroundColor: NSColor.secondaryLabelColor,
        .underlineColor: NSColor.systemOrange.withAlphaComponent(0.65),
        .underlineStyle: NSUnderlineStyle.patternDash.rawValue | NSUnderlineStyle.single.rawValue
      ]
    }
  }

  private static func hideLatticeMetadataComments(
    in attributed: NSMutableAttributedString,
    fontSize: CGFloat,
    activeRanges: [NSRange]
  ) {
    guard let regex = try? NSRegularExpression(pattern: #"<!--\s*lattice:[^>]*-->"#) else {
      return
    }
    let fullRange = NSRange(location: 0, length: attributed.length)
    for match in regex.matches(in: attributed.string, range: fullRange) {
      let attributes = range(match.range, containsAnyActive: activeRanges)
        ? tokenAttributes(fontSize: fontSize)
        : hiddenTokenAttributes(fontSize: fontSize)
      attributed.addAttributes(attributes, range: match.range)
    }
  }

  private static func completedTaskAttributes() -> [NSAttributedString.Key: Any] {
    [
      .foregroundColor: NSColor.secondaryLabelColor,
      .strikethroughStyle: NSUnderlineStyle.single.rawValue
    ]
  }

  private static func italicBodyFont(size: CGFloat) -> NSFont {
    NSFontManager.shared.convert(bodyFont(size: size), toHaveTrait: .italicFontMask)
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

    return regex.firstMatch(in: string, range: NSRange(location: 0, length: (string as NSString).length))
  }

  private static func rangesMatching(
    pattern: String,
    in string: String,
    fullRange: NSRange,
    skippedRanges: [NSRange]
  ) -> [NSRange] {
    guard let regex = try? NSRegularExpression(pattern: pattern) else {
      return []
    }
    return regex.matches(in: string, range: fullRange)
      .filter { !range($0.range, intersectsAny: skippedRanges) }
      .map(\.range)
  }

  private static func shifted(_ range: NSRange, by offset: Int) -> NSRange {
    NSRange(location: range.location + offset, length: range.length)
  }

  private static func linkContentRange(for range: NSRange) -> NSRange {
    guard range.length >= 4 else {
      return range
    }
    return NSRange(location: range.location + 2, length: range.length - 4)
  }

  private static func linkDelimiterRanges(for range: NSRange) -> [NSRange] {
    guard range.length >= 4 else {
      return []
    }
    return [
      NSRange(location: range.location, length: 2),
      NSRange(location: NSMaxRange(range) - 2, length: 2)
    ]
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

  private static func lineRangeContainsActiveRange(
    _ lineRange: NSRange,
    activeRanges: [NSRange],
    in nsString: NSString
  ) -> Bool {
    let contentRange = contentRangeWithoutLineEnding(lineRange, in: nsString)
    return activeRanges.contains { activeRange in
      if activeRange.length > 0 {
        return NSIntersectionRange(lineRange, activeRange).length > 0
      }

      return activeRange.location >= contentRange.location && activeRange.location <= NSMaxRange(contentRange)
    }
  }

  private static func contentRangeWithoutLineEnding(_ lineRange: NSRange, in nsString: NSString) -> NSRange {
    var end = NSMaxRange(lineRange)
    while end > lineRange.location {
      let character = nsString.character(at: end - 1)
      if character == 10 || character == 13 {
        end -= 1
      } else {
        break
      }
    }

    return NSRange(location: lineRange.location, length: end - lineRange.location)
  }

  private static func applyInactiveTextDimming(
    to attributed: NSMutableAttributedString,
    activeRanges: [NSRange]
  ) {
    guard attributed.length > 0, !activeRanges.isEmpty else {
      return
    }

    let inactiveColor = NSColor.secondaryLabelColor.withAlphaComponent(0.68)
    let fullRange = NSRange(location: 0, length: attributed.length)
    var cursor = 0
    for activeRange in activeRanges.sorted(by: { $0.location < $1.location }) {
      let clampedActiveRange = NSIntersectionRange(activeRange, fullRange)
      guard clampedActiveRange.location != NSNotFound else {
        continue
      }
      if cursor < clampedActiveRange.location {
        attributed.addAttribute(
          .foregroundColor,
          value: inactiveColor,
          range: NSRange(location: cursor, length: clampedActiveRange.location - cursor)
        )
      }
      cursor = max(cursor, NSMaxRange(clampedActiveRange))
    }
    if cursor < attributed.length {
      attributed.addAttribute(
        .foregroundColor,
        value: inactiveColor,
        range: NSRange(location: cursor, length: attributed.length - cursor)
      )
    }
  }
}

#elseif os(iOS)
import UIKit

enum MarkdownAttributedRenderer {
  static func render(
    _ text: String,
    activeRanges: [NSRange] = [],
    wikiLinkStates: [WikiLinkRenderState] = [],
    dimsInactiveText: Bool = false
  ) -> NSAttributedString {
    let attributed = NSMutableAttributedString(string: text, attributes: baseTypingAttributes())
    applyStyles(to: attributed, activeRanges: activeRanges, wikiLinkStates: wikiLinkStates)
    return attributed
  }

  static func baseTypingAttributes() -> [NSAttributedString.Key: Any] {
    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.lineSpacing = 2
    paragraphStyle.paragraphSpacing = 6
    return [
      .font: UIFont.preferredFont(forTextStyle: .title3),
      .foregroundColor: UIColor.label,
      .paragraphStyle: paragraphStyle
    ]
  }

  private static func applyStyles(
    to attributed: NSMutableAttributedString,
    activeRanges: [NSRange],
    wikiLinkStates: [WikiLinkRenderState]
  ) {
    for span in MarkdownStyler.spans(in: attributed.string) {
      guard NSMaxRange(span.range) <= attributed.length else {
        continue
      }
      attributed.addAttributes(attributes(for: span), range: span.range)
    }
    applyWikiLinkStyles(to: attributed, activeRanges: activeRanges, states: wikiLinkStates)
    hideLatticeMetadataComments(in: attributed)
  }

  private static func attributes(for span: MarkdownStyleSpan) -> [NSAttributedString.Key: Any] {
    switch span.kind {
    case .heading:
      let sizes: [CGFloat] = [34, 30, 26, 23, 21, 20]
      let index = max(0, min((span.level ?? 1) - 1, sizes.count - 1))
      return [.font: UIFont.systemFont(ofSize: sizes[index], weight: .bold)]
    case .headingMarker:
      return [.foregroundColor: UIColor.tertiaryLabel, .font: UIFont.monospacedSystemFont(ofSize: 16, weight: .regular)]
    case .listMarker:
      return [.foregroundColor: UIColor.tintColor, .font: UIFont.systemFont(ofSize: 21, weight: .semibold)]
    case .taskCheckbox:
      return [.foregroundColor: UIColor.tintColor, .font: UIFont.monospacedSystemFont(ofSize: 18, weight: .semibold)]
    case .completedTask:
      return [.foregroundColor: UIColor.secondaryLabel, .strikethroughStyle: NSUnderlineStyle.single.rawValue]
    case .blockquote:
      return [.foregroundColor: UIColor.secondaryLabel]
    case .thematicBreak:
      return thematicBreakAttributes()
    case .codeBlock:
      return [.font: UIFont.monospacedSystemFont(ofSize: 18, weight: .regular), .backgroundColor: UIColor.secondarySystemBackground]
    case .inlineCode:
      return [.font: UIFont.monospacedSystemFont(ofSize: 18, weight: .regular), .foregroundColor: UIColor.systemPink]
    case .bold:
      return [.font: UIFont.systemFont(ofSize: 21, weight: .semibold)]
    case .italic:
      return [.font: italicBodyFont()]
    case .link:
      return linkAttributes(destination: span.linkDestination)
    }
  }

  private static func linkAttributes(destination: String?) -> [NSAttributedString.Key: Any] {
    var attributes: [NSAttributedString.Key: Any] = [
      .foregroundColor: UIColor.systemBlue,
      .underlineStyle: NSUnderlineStyle.single.rawValue
    ]

    if let destination,
       let url = URL(string: destination),
       url.scheme != nil {
      attributes[.link] = url
    }

    return attributes
  }

  private static func italicBodyFont() -> UIFont {
    let descriptor = UIFont.systemFont(ofSize: 21).fontDescriptor.withSymbolicTraits(.traitItalic)
      ?? UIFont.systemFont(ofSize: 21).fontDescriptor
    return UIFont(descriptor: descriptor, size: 21)
  }

  private static func thematicBreakAttributes() -> [NSAttributedString.Key: Any] {
    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.lineSpacing = 8
    paragraphStyle.paragraphSpacing = 8
    return [
      .foregroundColor: UIColor.clear,
      .font: UIFont.preferredFont(forTextStyle: .title3),
      .paragraphStyle: paragraphStyle,
      .latticeThematicBreak: true
    ]
  }

  private static func wikiLinkAttributes(for status: WikiLinkRenderStatus) -> [NSAttributedString.Key: Any] {
    switch status {
    case .resolved:
      return [.foregroundColor: UIColor.systemBlue, .underlineStyle: NSUnderlineStyle.single.rawValue]
    case .ambiguous:
      return [.foregroundColor: UIColor.systemBlue.withAlphaComponent(0.85), .underlineStyle: NSUnderlineStyle.patternDot.rawValue | NSUnderlineStyle.single.rawValue]
    case .broken:
      return [
        .foregroundColor: UIColor.secondaryLabel,
        .underlineColor: UIColor.systemOrange.withAlphaComponent(0.65),
        .underlineStyle: NSUnderlineStyle.patternDash.rawValue | NSUnderlineStyle.single.rawValue
      ]
    }
  }

  private static func applyWikiLinkStyles(
    to attributed: NSMutableAttributedString,
    activeRanges: [NSRange],
    states: [WikiLinkRenderState]
  ) {
    for link in WikiLinkParser.links(in: attributed.string) where NSMaxRange(link.range) <= attributed.length {
      let status = states.first { $0.range == link.range }?.status ?? .resolved
      attributed.addAttributes(wikiLinkAttributes(for: status), range: linkContentRange(for: link.range))

      let delimiterAttributes = range(link.range, containsAnyActive: activeRanges)
        ? wikiLinkDelimiterAttributes()
        : hiddenWikiLinkDelimiterAttributes()
      for delimiterRange in linkDelimiterRanges(for: link.range) {
        attributed.addAttributes(delimiterAttributes, range: delimiterRange)
      }
    }
  }

  private static func wikiLinkDelimiterAttributes() -> [NSAttributedString.Key: Any] {
    [
      .foregroundColor: UIColor.tertiaryLabel,
      .font: UIFont.monospacedSystemFont(ofSize: 16, weight: .regular)
    ]
  }

  private static func hiddenWikiLinkDelimiterAttributes() -> [NSAttributedString.Key: Any] {
    [
      .foregroundColor: UIColor.clear,
      .font: UIFont.systemFont(ofSize: 0.1)
    ]
  }

  private static func range(_ range: NSRange, containsAnyActive activeRanges: [NSRange]) -> Bool {
    activeRanges.contains { activeRange in
      if activeRange.length > 0 {
        return NSIntersectionRange(range, activeRange).length > 0
      }

      return activeRange.location > range.location && activeRange.location < NSMaxRange(range)
    }
  }

  private static func linkContentRange(for range: NSRange) -> NSRange {
    guard range.length >= 4 else {
      return range
    }
    return NSRange(location: range.location + 2, length: range.length - 4)
  }

  private static func linkDelimiterRanges(for range: NSRange) -> [NSRange] {
    guard range.length >= 4 else {
      return []
    }
    return [
      NSRange(location: range.location, length: 2),
      NSRange(location: NSMaxRange(range) - 2, length: 2)
    ]
  }

  private static func hideLatticeMetadataComments(in attributed: NSMutableAttributedString) {
    guard let regex = try? NSRegularExpression(pattern: #"<!--\s*lattice:[^>]*-->"#) else {
      return
    }
    let fullRange = NSRange(location: 0, length: attributed.length)
    for match in regex.matches(in: attributed.string, range: fullRange) {
      attributed.addAttributes([
        .foregroundColor: UIColor.clear,
        .font: UIFont.systemFont(ofSize: 0.1)
      ], range: match.range)
    }
  }
}
#endif
