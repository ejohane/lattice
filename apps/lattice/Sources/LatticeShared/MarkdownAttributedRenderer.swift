import Foundation
import LatticeEditor

#if os(macOS)
import AppKit

enum MarkdownAttributedRenderer {
  static let bodyFontSize: CGFloat = 14

  static func render(
    _ text: String,
    fontSize: CGFloat = bodyFontSize,
    activeRanges: [NSRange] = []
  ) -> NSAttributedString {
    let attributed = NSMutableAttributedString(string: text, attributes: baseTypingAttributes(fontSize: fontSize))
    applyStyles(to: attributed, fontSize: fontSize, activeRanges: activeRanges)
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
    paragraphStyle.paragraphSpacing = 12 * fontSize / bodyFontSize
    return [
      .font: bodyFont(size: fontSize),
      .foregroundColor: NSColor.labelColor,
      .paragraphStyle: paragraphStyle
    ]
  }

  private static func applyStyles(
    to attributed: NSMutableAttributedString,
    fontSize: CGFloat,
    activeRanges: [NSRange]
  ) {
    let nsString = attributed.string as NSString
    let codeBlocks = codeBlockRanges(in: nsString)
    applyBlockStyles(to: attributed, fontSize: fontSize, codeBlocks: codeBlocks, activeRanges: activeRanges)
    applyInlineStyles(to: attributed, fontSize: fontSize, skippedRanges: codeBlocks, activeRanges: activeRanges)
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
      let tokenAttributes = range(lineRange, containsAnyActive: activeRanges)
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
        let isActive = range(lineRange, containsAnyActive: activeRanges)
        let shouldRenderMarker = !isActive || contentRange.length == 0

        attributed.addAttributes(listAttributes(fontSize: fontSize), range: lineRange)
        attributed.addAttributes(shouldRenderMarker ? renderedBulletAttributes(fontSize: fontSize) : bulletAttributes(fontSize: fontSize), range: markerRange)
        attributed.addAttributes(isActive ? bulletAttributes(fontSize: fontSize) : hiddenTokenAttributes(fontSize: fontSize), range: checkboxRange)
        if line.contains("[x]") || line.contains("[X]") {
          attributed.addAttributes(completedTaskAttributes(), range: contentRange)
        }
      } else if let match = firstMatch("^\\s*([-*+])\\s+(.*)$", in: line) {
        let isActive = range(lineRange, containsAnyActive: activeRanges)
        let contentRange = match.range(at: 2)
        let shouldRenderMarker = !isActive || contentRange.length == 0

        attributed.addAttributes(listAttributes(fontSize: fontSize), range: lineRange)
        attributed.addAttributes(
          shouldRenderMarker ? renderedBulletAttributes(fontSize: fontSize) : bulletAttributes(fontSize: fontSize),
          range: shifted(match.range(at: 1), by: lineRange.location)
        )
      } else if let match = firstMatch("^\\s*(\\d+[.)])\\s+(.*)$", in: line) {
        attributed.addAttributes(listAttributes(fontSize: fontSize), range: lineRange)
        attributed.addAttributes(
          range(lineRange, containsAnyActive: activeRanges) ? bulletAttributes(fontSize: fontSize) : hiddenTokenAttributes(fontSize: fontSize),
          range: shifted(match.range(at: 1), by: lineRange.location)
        )
      } else if firstMatch("^\\s{0,3}(([-*_])\\s*){3,}$", in: line) != nil {
        attributed.addAttributes(
          range(lineRange, containsAnyActive: activeRanges) ? thematicBreakAttributes(fontSize: fontSize) : hiddenTokenAttributes(fontSize: fontSize),
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
    applyInlineStyle(
      pattern: "!\\[([^\\]\\n]*)\\]\\(([^)\\n]+)\\)",
      to: attributed,
      fontSize: fontSize,
      skippedRanges: skippedRanges,
      activeRanges: activeRanges,
      contentAttributes: linkAttributes(fontSize: fontSize),
      tokenGroups: [0],
      contentGroups: [1]
    )
    applyInlineStyle(
      pattern: "\\[([^\\]\\n]+)\\]\\(([^)\\n]+)\\)",
      to: attributed,
      fontSize: fontSize,
      skippedRanges: skippedRanges,
      activeRanges: activeRanges,
      contentAttributes: linkAttributes(fontSize: fontSize),
      tokenGroups: [0],
      contentGroups: [1]
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
      .font: NSFont.monospacedSystemFont(ofSize: 17 * fontSize / bodyFontSize, weight: .regular)
    ]
  }

  private static func hiddenTokenAttributes(fontSize: CGFloat) -> [NSAttributedString.Key: Any] {
    [
      .foregroundColor: NSColor.clear,
      .font: bodyFont(size: max(1, fontSize / bodyFontSize), weight: .regular)
    ]
  }

  private static func bulletAttributes(fontSize: CGFloat) -> [NSAttributedString.Key: Any] {
    [
      .foregroundColor: NSColor.controlAccentColor,
      .font: bodyFont(size: 22 * fontSize / bodyFontSize, weight: .bold)
    ]
  }

  private static func renderedBulletAttributes(fontSize: CGFloat) -> [NSAttributedString.Key: Any] {
    let font = bodyFont(size: 22 * fontSize / bodyFontSize, weight: .bold)
    var attributes: [NSAttributedString.Key: Any] = [
      .foregroundColor: NSColor.controlAccentColor,
      .font: font
    ]

    if let glyphInfo = NSGlyphInfo(glyphName: "bullet", for: font, baseString: "-") {
      attributes[.glyphInfo] = glyphInfo
    }

    return attributes
  }

  private static func listAttributes(fontSize: CGFloat) -> [NSAttributedString.Key: Any] {
    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.lineSpacing = 5 * fontSize / bodyFontSize
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

  private static func linkAttributes(fontSize: CGFloat) -> [NSAttributedString.Key: Any] {
    [
      .font: bodyFont(size: fontSize),
      .foregroundColor: NSColor.systemBlue,
      .underlineStyle: NSUnderlineStyle.single.rawValue
    ]
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

#elseif os(iOS)
import UIKit

enum MarkdownAttributedRenderer {
  static func render(_ text: String) -> NSAttributedString {
    let attributed = NSMutableAttributedString(string: text, attributes: baseTypingAttributes())
    applyStyles(to: attributed)
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

  private static func applyStyles(to attributed: NSMutableAttributedString) {
    for span in MarkdownStyler.spans(in: attributed.string) {
      guard NSMaxRange(span.range) <= attributed.length else {
        continue
      }
      attributed.addAttributes(attributes(for: span), range: span.range)
    }
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
    case .blockquote:
      return [.foregroundColor: UIColor.secondaryLabel]
    case .thematicBreak:
      return [.foregroundColor: UIColor.tertiaryLabel]
    case .codeBlock:
      return [.font: UIFont.monospacedSystemFont(ofSize: 18, weight: .regular), .backgroundColor: UIColor.secondarySystemBackground]
    case .inlineCode:
      return [.font: UIFont.monospacedSystemFont(ofSize: 18, weight: .regular), .foregroundColor: UIColor.systemPink]
    case .bold:
      return [.font: UIFont.systemFont(ofSize: 21, weight: .semibold)]
    case .italic:
      return [.font: italicBodyFont()]
    case .link:
      return [.foregroundColor: UIColor.systemBlue, .underlineStyle: NSUnderlineStyle.single.rawValue]
    }
  }

  private static func italicBodyFont() -> UIFont {
    let descriptor = UIFont.systemFont(ofSize: 21).fontDescriptor.withSymbolicTraits(.traitItalic)
      ?? UIFont.systemFont(ofSize: 21).fontDescriptor
    return UIFont(descriptor: descriptor, size: 21)
  }
}
#endif
