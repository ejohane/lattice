import Foundation
import LatticeCore
import LatticeEditor

extension NSAttributedString.Key {
  static let latticeThematicBreak = NSAttributedString.Key("lattice.thematicBreak")
  static let latticeUnorderedListMarker = NSAttributedString.Key("lattice.unorderedListMarker")
  static let latticeUnorderedListIndent = NSAttributedString.Key("lattice.unorderedListIndent")
  static let latticeImagePreviewURL = NSAttributedString.Key("lattice.imagePreviewURL")
  static let latticeImagePreviewAltText = NSAttributedString.Key("lattice.imagePreviewAltText")
  static let latticeImagePreviewWidth = NSAttributedString.Key("lattice.imagePreviewWidth")
}

#if os(macOS)
import AppKit

enum MarkdownAttributedRenderer {
  static let bodyFontSize: CGFloat = 14
  static let imagePreviewHeight: CGFloat = 420

  static func render(
    _ text: String,
    fontSize: CGFloat = bodyFontSize,
    fontFamily: EditorFontFamily = .system,
    activeRanges: [NSRange] = [],
    wikiLinkStates: [WikiLinkRenderState] = [],
    dimsInactiveText: Bool = false,
    theme: LatticeTheme = LatticeTheme(id: .system),
    imagePreviewStates: [MarkdownImageRenderState] = []
  ) -> NSAttributedString {
    let attributed = NSMutableAttributedString(
      string: text,
      attributes: baseTypingAttributes(fontSize: fontSize, fontFamily: fontFamily, theme: theme)
    )
    applyStyles(
      to: attributed,
      fontSize: fontSize,
      fontFamily: fontFamily,
      activeRanges: activeRanges,
      wikiLinkStates: wikiLinkStates,
      theme: theme,
      imagePreviewStates: imagePreviewStates
    )
    if dimsInactiveText {
      applyInactiveTextDimming(to: attributed, activeRanges: activeRanges, theme: theme)
    }
    return attributed
  }

  static func bodyFont(
    size: CGFloat = bodyFontSize,
    weight: NSFont.Weight = .regular,
    family: EditorFontFamily = .system
  ) -> NSFont {
    switch family {
    case .system:
      return NSFont.systemFont(ofSize: size, weight: weight)
    case .monospaced:
      return NSFont.monospacedSystemFont(ofSize: size, weight: weight)
    }
  }

  private static func monospaceBodyFont(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
    NSFont.monospacedSystemFont(ofSize: size, weight: weight)
  }

  static func baseTypingAttributes(
    fontSize: CGFloat = bodyFontSize,
    fontFamily: EditorFontFamily = .system,
    theme: LatticeTheme = LatticeTheme(id: .system)
  ) -> [NSAttributedString.Key: Any] {
    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.lineSpacing = 5 * fontSize / bodyFontSize
    paragraphStyle.paragraphSpacing = 6 * fontSize / bodyFontSize
    return [
      .font: bodyFont(size: fontSize, family: fontFamily),
      .foregroundColor: theme.nsColor(.primaryText),
      .paragraphStyle: paragraphStyle
    ]
  }

  private static func applyStyles(
    to attributed: NSMutableAttributedString,
    fontSize: CGFloat,
    fontFamily: EditorFontFamily,
    activeRanges: [NSRange],
    wikiLinkStates: [WikiLinkRenderState],
    theme: LatticeTheme,
    imagePreviewStates: [MarkdownImageRenderState]
  ) {
    let nsString = attributed.string as NSString
    let codeBlocks = codeBlockRanges(in: nsString)
    applyBlockStyles(to: attributed, fontSize: fontSize, fontFamily: fontFamily, codeBlocks: codeBlocks, activeRanges: activeRanges, theme: theme)
    applyInlineStyles(to: attributed, fontSize: fontSize, fontFamily: fontFamily, skippedRanges: codeBlocks, activeRanges: activeRanges, theme: theme)
    applyWikiLinkStyles(to: attributed, fontSize: fontSize, fontFamily: fontFamily, states: wikiLinkStates, activeRanges: activeRanges, theme: theme)
    hideLatticeMetadataComments(in: attributed, fontSize: fontSize, fontFamily: fontFamily, activeRanges: activeRanges, theme: theme)
    applyImagePreviewStyles(to: attributed, fontSize: fontSize, fontFamily: fontFamily, states: imagePreviewStates, activeRanges: activeRanges)
  }

  private static func applyBlockStyles(
    to attributed: NSMutableAttributedString,
    fontSize: CGFloat,
    fontFamily: EditorFontFamily,
    codeBlocks: [NSRange],
    activeRanges: [NSRange],
    theme: LatticeTheme
  ) {
    let nsString = attributed.string as NSString
    var location = 0
    while location < nsString.length {
      let lineRange = nsString.lineRange(for: NSRange(location: location, length: 0))
      let line = nsString.substring(with: lineRange)
      let isActiveLine = lineRangeContainsActiveRange(lineRange, activeRanges: activeRanges, in: nsString)
      let tokenAttributes = isActiveLine
        ? tokenAttributes(fontSize: fontSize, theme: theme)
        : hiddenTokenAttributes(fontSize: fontSize, fontFamily: fontFamily)

      if range(lineRange, intersectsAny: codeBlocks) {
        attributed.addAttributes(codeBlockAttributes(fontSize: fontSize, theme: theme), range: lineRange)
      } else if let match = firstMatch("^\\s*(#{1,6})(\\s+)(.+)$", in: line) {
        let level = min(match.range(at: 1).length, 6)
        attributed.addAttributes(tokenAttributes, range: shifted(match.range(at: 1), by: lineRange.location))
        attributed.addAttributes(tokenAttributes, range: shifted(match.range(at: 2), by: lineRange.location))
        attributed.addAttributes(headingAttributes(level: level, fontSize: fontSize, fontFamily: fontFamily, theme: theme), range: shifted(match.range(at: 3), by: lineRange.location))
      } else if let match = firstMatch("^\\s{0,3}>\\s?(.+)$", in: line) {
        attributed.addAttributes(blockQuoteAttributes(fontSize: fontSize, theme: theme), range: lineRange)
        attributed.addAttributes(tokenAttributes, range: shifted(NSRange(location: 0, length: 1), by: lineRange.location))
        attributed.addAttributes([.font: italicBodyFont(size: fontSize, fontFamily: fontFamily), .foregroundColor: theme.nsColor(.quoteText)], range: shifted(match.range(at: 1), by: lineRange.location))
      } else if let match = firstMatch("^\\s*([-*+])\\s+(\\[[ xX]\\])\\s+(.*)$", in: line) {
        let markerRange = shifted(match.range(at: 1), by: lineRange.location)
        let checkboxRange = shifted(match.range(at: 2), by: lineRange.location)
        let contentRange = shifted(match.range(at: 3), by: lineRange.location)
        let checkbox = (line as NSString).substring(with: match.range(at: 2))
        let isChecked = checkbox.lowercased() == "[x]"
        let shouldRenderMarker = !isActiveLine

        attributed.addAttributes(listAttributes(fontSize: fontSize), range: lineRange)
        attributed.addAttributes(
          shouldRenderMarker ? renderedTaskCheckboxAttributes(isChecked: isChecked, fontSize: fontSize, fontFamily: fontFamily, theme: theme) : bulletAttributes(fontSize: fontSize, fontFamily: fontFamily, theme: theme),
          range: markerRange
        )
        attributed.addAttributes(isActiveLine ? bulletAttributes(fontSize: fontSize, fontFamily: fontFamily, theme: theme) : hiddenTokenAttributes(fontSize: fontSize, fontFamily: fontFamily), range: checkboxRange)
        if isChecked {
          attributed.addAttributes(completedTaskAttributes(theme: theme), range: contentRange)
        }
      } else if let match = firstMatch("^\\s*([-*+])\\s+(.*)$", in: line) {
        let contentRange = match.range(at: 2)
        let shouldRenderMarker = !isActiveLine || contentRange.length == 0

        attributed.addAttributes(listAttributes(fontSize: fontSize), range: lineRange)
        attributed.addAttributes(
          shouldRenderMarker ? renderedBulletAttributes(fontSize: fontSize, fontFamily: fontFamily, theme: theme) : bulletAttributes(fontSize: fontSize, fontFamily: fontFamily, theme: theme),
          range: shifted(match.range(at: 1), by: lineRange.location)
        )
      } else if let match = firstMatch("^\\s*(\\d+[.)])\\s+(.*)$", in: line) {
        attributed.addAttributes(listAttributes(fontSize: fontSize), range: lineRange)
        attributed.addAttributes(
          isActiveLine ? bulletAttributes(fontSize: fontSize, fontFamily: fontFamily, theme: theme) : hiddenTokenAttributes(fontSize: fontSize, fontFamily: fontFamily),
          range: shifted(match.range(at: 1), by: lineRange.location)
        )
      } else if firstMatch("^\\s{0,3}(([-*_])\\s*){3,}$", in: line) != nil {
        attributed.addAttributes(
          isActiveLine ? thematicBreakAttributes(fontSize: fontSize, theme: theme) : thematicBreakLineAttributes(fontSize: fontSize, fontFamily: fontFamily),
          range: lineRange
        )
      }

      location = NSMaxRange(lineRange)
    }
  }

  private static func applyInlineStyles(
    to attributed: NSMutableAttributedString,
    fontSize: CGFloat,
    fontFamily: EditorFontFamily,
    skippedRanges: [NSRange],
    activeRanges: [NSRange],
    theme: LatticeTheme
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
      contentAttributes: inlineCodeAttributes(fontSize: fontSize, theme: theme),
      tokenGroups: [0],
      contentGroups: [1],
      theme: theme
    )
    applyInlineLinkStyle(
      pattern: "!\\[([^\\]\\n]*)\\]\\(([^)\\n]+)\\)",
      to: attributed,
      fontSize: fontSize,
      fontFamily: fontFamily,
      skippedRanges: skippedRanges,
      activeRanges: activeRanges,
      tokenGroups: [0],
      labelGroup: 1,
      urlGroup: 2,
      theme: theme
    )
    applyInlineLinkStyle(
      pattern: "\\[([^\\]\\n]+)\\]\\(([^)\\n]+)\\)",
      to: attributed,
      fontSize: fontSize,
      fontFamily: fontFamily,
      skippedRanges: skippedRanges,
      activeRanges: activeRanges,
      tokenGroups: [0],
      labelGroup: 1,
      urlGroup: 2,
      theme: theme
    )
    applyAutolinkStyles(
      to: attributed,
      fontSize: fontSize,
      fontFamily: fontFamily,
      skippedRanges: skippedRanges + inlineCodeRanges + markdownLinkRanges,
      theme: theme
    )
    applyInlineStyle(
      pattern: "(\\*\\*|__)(.+?)\\1",
      to: attributed,
      fontSize: fontSize,
      skippedRanges: skippedRanges,
      activeRanges: activeRanges,
      contentAttributes: [.font: bodyFont(size: fontSize, weight: .semibold, family: fontFamily), .foregroundColor: theme.nsColor(.primaryText)],
      tokenGroups: [0],
      contentGroups: [2],
      theme: theme
    )
    applyInlineStyle(
      pattern: "(~~)(.+?)\\1",
      to: attributed,
      fontSize: fontSize,
      skippedRanges: skippedRanges,
      activeRanges: activeRanges,
      contentAttributes: [
        .font: bodyFont(size: fontSize, family: fontFamily),
        .foregroundColor: theme.nsColor(.primaryText),
        .strikethroughStyle: NSUnderlineStyle.single.rawValue
      ],
      tokenGroups: [0],
      contentGroups: [2],
      theme: theme
    )
    applyInlineStyle(
      pattern: "(?<!\\*)\\*(?!\\*)([^*\\n]+)(?<!\\*)\\*(?!\\*)",
      to: attributed,
      fontSize: fontSize,
      skippedRanges: skippedRanges,
      activeRanges: activeRanges,
      contentAttributes: [.font: italicBodyFont(size: fontSize, fontFamily: fontFamily), .foregroundColor: theme.nsColor(.primaryText)],
      tokenGroups: [0],
      contentGroups: [1],
      theme: theme
    )
    applyInlineStyle(
      pattern: "(?<!_)_(?!_)([^_\\n]+)(?<!_)_(?!_)",
      to: attributed,
      fontSize: fontSize,
      skippedRanges: skippedRanges,
      activeRanges: activeRanges,
      contentAttributes: [.font: italicBodyFont(size: fontSize, fontFamily: fontFamily), .foregroundColor: theme.nsColor(.primaryText)],
      tokenGroups: [0],
      contentGroups: [1],
      theme: theme
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
    contentGroups: [Int],
    theme: LatticeTheme
  ) {
    guard let regex = try? NSRegularExpression(pattern: pattern) else {
      return
    }

    let fullRange = NSRange(location: 0, length: attributed.length)
    for match in regex.matches(in: attributed.string, range: fullRange) where !range(match.range, intersectsAny: skippedRanges) {
      let markdownTokenAttributes = range(match.range, containsAnyActive: activeRanges)
        ? tokenAttributes(fontSize: fontSize, theme: theme)
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
    fontFamily: EditorFontFamily,
    skippedRanges: [NSRange],
    activeRanges: [NSRange],
    tokenGroups: [Int],
    labelGroup: Int,
    urlGroup: Int,
    theme: LatticeTheme
  ) {
    guard let regex = try? NSRegularExpression(pattern: pattern) else {
      return
    }

    let nsString = attributed.string as NSString
    let fullRange = NSRange(location: 0, length: attributed.length)
    for match in regex.matches(in: attributed.string, range: fullRange) where !range(match.range, intersectsAny: skippedRanges) {
      let markdownTokenAttributes = range(match.range, containsAnyActive: activeRanges)
        ? tokenAttributes(fontSize: fontSize, theme: theme)
        : hiddenTokenAttributes(fontSize: fontSize, fontFamily: fontFamily)

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
      attributed.addAttributes(linkAttributes(fontSize: fontSize, fontFamily: fontFamily, urlString: urlString, theme: theme), range: labelRange)
    }
  }

  private static func applyAutolinkStyles(
    to attributed: NSMutableAttributedString,
    fontSize: CGFloat,
    fontFamily: EditorFontFamily,
    skippedRanges: [NSRange],
    theme: LatticeTheme
  ) {
    guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
      return
    }

    let fullRange = NSRange(location: 0, length: attributed.length)
    for match in detector.matches(in: attributed.string, range: fullRange)
    where match.resultType == .link && !range(match.range, intersectsAny: skippedRanges) {
      attributed.addAttributes(linkAttributes(fontSize: fontSize, fontFamily: fontFamily, url: match.url, theme: theme), range: match.range)
    }
  }

  private static func headingAttributes(
    level: Int,
    fontSize: CGFloat,
    fontFamily: EditorFontFamily,
    theme: LatticeTheme
  ) -> [NSAttributedString.Key: Any] {
    let sizes: [CGFloat] = [34, 30, 26, 23, 21, 20]
    let index = max(0, min(level - 1, sizes.count - 1))
    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.paragraphSpacingBefore = (level <= 2 ? 20 : 14) * fontSize / bodyFontSize
    paragraphStyle.paragraphSpacing = 14 * fontSize / bodyFontSize
    paragraphStyle.lineSpacing = 3 * fontSize / bodyFontSize

    return [
      .font: bodyFont(size: sizes[index] * fontSize / bodyFontSize, weight: .bold, family: fontFamily),
      .foregroundColor: theme.nsColor(.primaryText),
      .paragraphStyle: paragraphStyle
    ]
  }

  private static func tokenAttributes(fontSize: CGFloat, theme: LatticeTheme) -> [NSAttributedString.Key: Any] {
    [
      .foregroundColor: theme.nsColor(.tertiaryText),
      .font: NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
    ]
  }

  private static func hiddenTokenAttributes(
    fontSize: CGFloat,
    fontFamily: EditorFontFamily = .system
  ) -> [NSAttributedString.Key: Any] {
    [
      .foregroundColor: NSColor.clear,
      .font: bodyFont(size: max(0.1, 0.1 * fontSize / bodyFontSize), weight: .regular, family: fontFamily)
    ]
  }

  private static func bulletAttributes(
    fontSize: CGFloat,
    fontFamily: EditorFontFamily,
    theme: LatticeTheme
  ) -> [NSAttributedString.Key: Any] {
    [
      .foregroundColor: theme.nsColor(.accent),
      .font: bodyFont(size: 14 * fontSize / bodyFontSize, weight: .semibold, family: fontFamily)
    ]
  }

  private static func renderedBulletAttributes(
    fontSize: CGFloat,
    fontFamily: EditorFontFamily,
    theme: LatticeTheme
  ) -> [NSAttributedString.Key: Any] {
    let font = bodyFont(size: 14 * fontSize / bodyFontSize, weight: .semibold, family: fontFamily)
    var attributes: [NSAttributedString.Key: Any] = [
      .foregroundColor: theme.nsColor(.accent),
      .font: font
    ]

    if let glyphInfo = NSGlyphInfo(glyphName: "bullet", for: font, baseString: "-") {
      attributes[.glyphInfo] = glyphInfo
    }

    return attributes
  }

  private static func renderedTaskCheckboxAttributes(
    isChecked: Bool,
    fontSize: CGFloat,
    fontFamily: EditorFontFamily,
    theme: LatticeTheme
  ) -> [NSAttributedString.Key: Any] {
    let font = bodyFont(size: 15 * fontSize / bodyFontSize, weight: .semibold, family: fontFamily)
    var attributes: [NSAttributedString.Key: Any] = [
      .foregroundColor: theme.nsColor(.accent),
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

  private static func blockQuoteAttributes(fontSize: CGFloat, theme: LatticeTheme) -> [NSAttributedString.Key: Any] {
    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.lineSpacing = 5 * fontSize / bodyFontSize
    paragraphStyle.paragraphSpacing = 10 * fontSize / bodyFontSize
    paragraphStyle.headIndent = 20 * fontSize / bodyFontSize
    paragraphStyle.firstLineHeadIndent = 20 * fontSize / bodyFontSize

    return [
      .foregroundColor: theme.nsColor(.quoteText),
      .paragraphStyle: paragraphStyle
    ]
  }

  private static func thematicBreakAttributes(fontSize: CGFloat, theme: LatticeTheme) -> [NSAttributedString.Key: Any] {
    [
      .foregroundColor: theme.nsColor(.tertiaryText),
      .font: NSFont.monospacedSystemFont(ofSize: 18 * fontSize / bodyFontSize, weight: .medium)
    ]
  }

  private static func thematicBreakLineAttributes(
    fontSize: CGFloat,
    fontFamily: EditorFontFamily
  ) -> [NSAttributedString.Key: Any] {
    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.lineSpacing = 8 * fontSize / bodyFontSize
    paragraphStyle.paragraphSpacing = 8 * fontSize / bodyFontSize
    return [
      .foregroundColor: NSColor.clear,
      .font: bodyFont(size: fontSize, family: fontFamily),
      .paragraphStyle: paragraphStyle,
      .latticeThematicBreak: true
    ]
  }

  private static func codeBlockAttributes(fontSize: CGFloat, theme: LatticeTheme) -> [NSAttributedString.Key: Any] {
    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.lineSpacing = 3 * fontSize / bodyFontSize
    paragraphStyle.paragraphSpacing = 0

    return [
      .font: monospaceBodyFont(size: fontSize),
      .foregroundColor: theme.nsColor(.codeText),
      .backgroundColor: theme.nsColor(.codeBackground).withAlphaComponent(0.8),
      .paragraphStyle: paragraphStyle
    ]
  }

  private static func inlineCodeAttributes(fontSize: CGFloat, theme: LatticeTheme) -> [NSAttributedString.Key: Any] {
    [
      .font: monospaceBodyFont(size: fontSize),
      .foregroundColor: theme.nsColor(.codeText),
      .backgroundColor: theme.nsColor(.codeBackground).withAlphaComponent(0.8)
    ]
  }

  private static func linkAttributes(
    fontSize: CGFloat,
    fontFamily: EditorFontFamily,
    urlString: String? = nil,
    url: URL? = nil,
    theme: LatticeTheme
  ) -> [NSAttributedString.Key: Any] {
    var attributes: [NSAttributedString.Key: Any] = [
      .font: bodyFont(size: fontSize, family: fontFamily),
      .foregroundColor: theme.nsColor(.link),
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
    fontFamily: EditorFontFamily,
    states: [WikiLinkRenderState],
    activeRanges: [NSRange],
    theme: LatticeTheme
  ) {
    for link in WikiLinkParser.links(in: attributed.string) where NSMaxRange(link.range) <= attributed.length {
      let status = states.first { $0.range == link.range }?.status ?? .resolved
      attributed.addAttributes(
        wikiLinkAttributes(fontSize: fontSize, fontFamily: fontFamily, status: status, theme: theme),
        range: linkContentRange(for: link.range)
      )

      let delimiterAttributes = range(link.range, containsAnyActive: activeRanges)
        ? tokenAttributes(fontSize: fontSize, theme: theme)
        : hiddenTokenAttributes(fontSize: fontSize, fontFamily: fontFamily)
      for delimiterRange in linkDelimiterRanges(for: link.range) {
        attributed.addAttributes(delimiterAttributes, range: delimiterRange)
      }
    }
  }

  private static func wikiLinkAttributes(
    fontSize: CGFloat,
    fontFamily: EditorFontFamily,
    status: WikiLinkRenderStatus,
    theme: LatticeTheme
  ) -> [NSAttributedString.Key: Any] {
    switch status {
    case .resolved:
      return [
        .font: bodyFont(size: fontSize, family: fontFamily),
        .foregroundColor: theme.nsColor(.link),
        .underlineStyle: NSUnderlineStyle.single.rawValue
      ]
    case .ambiguous:
      return [
        .font: bodyFont(size: fontSize, family: fontFamily),
        .foregroundColor: theme.nsColor(.link).withAlphaComponent(0.85),
        .underlineStyle: NSUnderlineStyle.patternDot.rawValue | NSUnderlineStyle.single.rawValue
      ]
    case .broken:
      return [
        .font: bodyFont(size: fontSize, family: fontFamily),
        .foregroundColor: theme.nsColor(.secondaryText),
        .underlineColor: theme.nsColor(.warning).withAlphaComponent(0.65),
        .underlineStyle: NSUnderlineStyle.patternDash.rawValue | NSUnderlineStyle.single.rawValue
      ]
    }
  }

  private static func hideLatticeMetadataComments(
    in attributed: NSMutableAttributedString,
    fontSize: CGFloat,
    fontFamily: EditorFontFamily,
    activeRanges: [NSRange],
    theme: LatticeTheme
  ) {
    guard let regex = try? NSRegularExpression(pattern: #"<!--\s*lattice:[^>]*-->"#) else {
      return
    }
    let fullRange = NSRange(location: 0, length: attributed.length)
    for match in regex.matches(in: attributed.string, range: fullRange) {
      let attributes = range(match.range, containsAnyActive: activeRanges)
        ? tokenAttributes(fontSize: fontSize, theme: theme)
        : hiddenTokenAttributes(fontSize: fontSize, fontFamily: fontFamily)
      attributed.addAttributes(attributes, range: match.range)
    }
  }

  private static func applyImagePreviewStyles(
    to attributed: NSMutableAttributedString,
    fontSize: CGFloat,
    fontFamily: EditorFontFamily,
    states: [MarkdownImageRenderState],
    activeRanges: [NSRange]
  ) {
    let nsString = attributed.string as NSString
    for state in states {
      let lineRange = state.link.lineRange
      guard
        NSMaxRange(lineRange) <= attributed.length,
        !lineRangeContainsActiveRange(lineRange, activeRanges: activeRanges, in: nsString)
      else {
        continue
      }

      let contentRange = contentRangeWithoutLineEnding(lineRange, in: nsString)
      guard contentRange.length > 0 else {
        continue
      }
      attributed.addAttributes(
        imagePreviewAttributes(fontSize: fontSize, fontFamily: fontFamily, url: state.url, altText: state.link.altText, width: state.link.width),
        range: contentRange
      )
      if let width = state.link.width {
        attributed.addAttributes([.latticeImagePreviewWidth: width], range: contentRange)
      }
    }
  }

  private static func completedTaskAttributes(theme: LatticeTheme) -> [NSAttributedString.Key: Any] {
    [
      .foregroundColor: theme.nsColor(.secondaryText),
      .strikethroughStyle: NSUnderlineStyle.single.rawValue
    ]
  }

  private static func imagePreviewAttributes(
    fontSize: CGFloat,
    fontFamily: EditorFontFamily,
    url: URL,
    altText: String,
    width: Double?
  ) -> [NSAttributedString.Key: Any] {
    let paragraphStyle = NSMutableParagraphStyle()
    let previewHeight = imagePreviewLineHeight(url: url, width: width, fontSize: fontSize)
    paragraphStyle.minimumLineHeight = previewHeight
    paragraphStyle.maximumLineHeight = previewHeight
    paragraphStyle.paragraphSpacing = 12 * fontSize / bodyFontSize
    paragraphStyle.lineSpacing = 0
    return [
      .foregroundColor: NSColor.clear,
      .font: bodyFont(size: max(0.1, 0.1 * fontSize / bodyFontSize), family: fontFamily),
      .paragraphStyle: paragraphStyle,
      .latticeImagePreviewURL: url,
      .latticeImagePreviewAltText: altText
    ]
  }

  private static func imagePreviewLineHeight(url: URL, width: Double?, fontSize: CGFloat) -> CGFloat {
    let defaultHeight = imagePreviewHeight * fontSize / bodyFontSize
    guard
      let width,
      width.isFinite,
      width > 0,
      let image = NSImage(contentsOf: url),
      image.size.width > 0,
      image.size.height > 0
    else {
      return defaultHeight
    }

    let verticalPadding = 18 * fontSize / bodyFontSize
    let scaledHeight = image.size.height * CGFloat(width) / image.size.width
    return max(96 * fontSize / bodyFontSize, scaledHeight + verticalPadding)
  }

  private static func italicBodyFont(size: CGFloat, fontFamily: EditorFontFamily) -> NSFont {
    NSFontManager.shared.convert(bodyFont(size: size, family: fontFamily), toHaveTrait: .italicFontMask)
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
    activeRanges: [NSRange],
    theme: LatticeTheme
  ) {
    guard attributed.length > 0, !activeRanges.isEmpty else {
      return
    }

    let inactiveColor = inactiveTextColor(theme: theme)
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

  private static func inactiveTextColor(theme: LatticeTheme) -> NSColor {
    let primary = theme.nsColor(.primaryText)
    let background = theme.nsColor(.editorBackground)
    return primary.blended(withFraction: 0.74, of: background) ?? primary.withAlphaComponent(0.28)
  }
}

#elseif os(iOS)
import UIKit

enum MarkdownAttributedRenderer {
  static func render(
    _ text: String,
    fontFamily: EditorFontFamily = .system,
    activeRanges: [NSRange] = [],
    wikiLinkStates: [WikiLinkRenderState] = [],
    dimsInactiveText: Bool = false,
    theme: LatticeTheme = LatticeTheme(id: .system),
    imagePreviewStates: [MarkdownImageRenderState] = []
  ) -> NSAttributedString {
    _ = imagePreviewStates
    let attributed = NSMutableAttributedString(string: text, attributes: baseTypingAttributes(fontFamily: fontFamily, theme: theme))
    applyStyles(to: attributed, fontFamily: fontFamily, activeRanges: activeRanges, wikiLinkStates: wikiLinkStates, theme: theme)
    if dimsInactiveText {
      applyInactiveTextDimming(to: attributed, activeRanges: activeRanges, theme: theme)
    }
    return attributed
  }

  static func bodyFont(
    size: CGFloat = UIFont.preferredFont(forTextStyle: .title3).pointSize,
    weight: UIFont.Weight = .regular,
    fontFamily: EditorFontFamily = .system
  ) -> UIFont {
    switch fontFamily {
    case .system:
      return UIFont.systemFont(ofSize: size, weight: weight)
    case .monospaced:
      return UIFont.monospacedSystemFont(ofSize: size, weight: weight)
    }
  }

  static func baseTypingAttributes(
    fontFamily: EditorFontFamily = .system,
    theme: LatticeTheme = LatticeTheme(id: .system)
  ) -> [NSAttributedString.Key: Any] {
    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.lineSpacing = 2
    paragraphStyle.paragraphSpacing = 6
    return [
      .font: bodyFont(fontFamily: fontFamily),
      .foregroundColor: theme.uiColor(.primaryText),
      .paragraphStyle: paragraphStyle
    ]
  }

  private static func applyStyles(
    to attributed: NSMutableAttributedString,
    fontFamily: EditorFontFamily,
    activeRanges: [NSRange],
    wikiLinkStates: [WikiLinkRenderState],
    theme: LatticeTheme
  ) {
    for span in MarkdownStyler.spans(in: attributed.string) {
      guard NSMaxRange(span.range) <= attributed.length else {
        continue
      }
      attributed.addAttributes(attributes(for: span, fontFamily: fontFamily, theme: theme), range: span.range)
    }
    applyBlockStyles(to: attributed, fontFamily: fontFamily, activeRanges: activeRanges, theme: theme)
    applyWikiLinkStyles(to: attributed, fontFamily: fontFamily, activeRanges: activeRanges, states: wikiLinkStates, theme: theme)
    hideLatticeMetadataComments(in: attributed, fontFamily: fontFamily, theme: theme)
  }

  private static func applyBlockStyles(
    to attributed: NSMutableAttributedString,
    fontFamily: EditorFontFamily,
    activeRanges: [NSRange],
    theme: LatticeTheme
  ) {
    let nsString = attributed.string as NSString
    var location = 0
    while location < nsString.length {
      let lineRange = nsString.lineRange(for: NSRange(location: location, length: 0))
      let line = nsString.substring(with: lineRange)
      let isActiveLine = range(lineRange, containsAnyActive: activeRanges)

      if let match = firstMatch("^([ \\t]*)([-*+])\\s+(?!\\[[ xX]\\]\\s)(.+)$", in: line) {
        let nestingIndent = unorderedListNestingIndent(
          from: nsString.substring(with: shifted(match.range(at: 1), by: lineRange.location))
        )
        attributed.addAttributes(unorderedListAttributes(), range: lineRange)
        attributed.addAttributes(
          isActiveLine
            ? listMarkerAttributes(fontFamily: fontFamily, theme: theme)
            : hiddenListMarkerAttributes(fontFamily: fontFamily, nestingIndent: nestingIndent),
          range: shifted(match.range(at: 2), by: lineRange.location)
        )
      }

      location = NSMaxRange(lineRange)
    }
  }

  private static func attributes(
    for span: MarkdownStyleSpan,
    fontFamily: EditorFontFamily,
    theme: LatticeTheme
  ) -> [NSAttributedString.Key: Any] {
    switch span.kind {
    case .heading:
      let sizes: [CGFloat] = [34, 30, 26, 23, 21, 20]
      let index = max(0, min((span.level ?? 1) - 1, sizes.count - 1))
      return [.font: bodyFont(size: sizes[index], weight: .bold, fontFamily: fontFamily)]
    case .headingMarker:
      return [.foregroundColor: theme.uiColor(.tertiaryText), .font: UIFont.monospacedSystemFont(ofSize: 16, weight: .regular)]
    case .listMarker:
      return listMarkerAttributes(fontFamily: fontFamily, theme: theme)
    case .taskCheckbox:
      return [.foregroundColor: theme.uiColor(.accent), .font: UIFont.monospacedSystemFont(ofSize: 18, weight: .semibold)]
    case .completedTask:
      return [.foregroundColor: theme.uiColor(.secondaryText), .strikethroughStyle: NSUnderlineStyle.single.rawValue]
    case .blockquote:
      return [.foregroundColor: theme.uiColor(.quoteText)]
    case .thematicBreak:
      return thematicBreakAttributes()
    case .codeBlock:
      return [
        .font: UIFont.monospacedSystemFont(ofSize: 18, weight: .regular),
        .foregroundColor: theme.uiColor(.codeText),
        .backgroundColor: theme.uiColor(.codeBackground)
      ]
    case .inlineCode:
      return [.font: UIFont.monospacedSystemFont(ofSize: 18, weight: .regular), .foregroundColor: theme.uiColor(.codeText)]
    case .bold:
      return [.font: bodyFont(size: 21, weight: .semibold, fontFamily: fontFamily)]
    case .italic:
      return [.font: italicBodyFont(fontFamily: fontFamily)]
    case .link:
      return linkAttributes(destination: span.linkDestination, theme: theme)
    }
  }

  private static func linkAttributes(destination: String?, theme: LatticeTheme) -> [NSAttributedString.Key: Any] {
    var attributes: [NSAttributedString.Key: Any] = [
      .foregroundColor: theme.uiColor(.link),
      .underlineStyle: NSUnderlineStyle.single.rawValue
    ]

    if let destination,
       let url = URL(string: destination),
       url.scheme != nil {
      attributes[.link] = url
    }

    return attributes
  }

  private static func italicBodyFont(fontFamily: EditorFontFamily) -> UIFont {
    let baseFont = bodyFont(size: 21, fontFamily: fontFamily)
    let descriptor = baseFont.fontDescriptor.withSymbolicTraits(.traitItalic)
      ?? baseFont.fontDescriptor
    return UIFont(descriptor: descriptor, size: 21)
  }

  private static func listMarkerAttributes(
    fontFamily: EditorFontFamily,
    theme: LatticeTheme
  ) -> [NSAttributedString.Key: Any] {
    [
      .foregroundColor: theme.uiColor(.accent),
      .font: bodyFont(size: 21, weight: .semibold, fontFamily: fontFamily)
    ]
  }

  private static func hiddenListMarkerAttributes(
    fontFamily: EditorFontFamily,
    nestingIndent: CGFloat
  ) -> [NSAttributedString.Key: Any] {
    [
      .foregroundColor: UIColor.clear,
      .font: bodyFont(size: 0.1, fontFamily: fontFamily),
      .latticeUnorderedListMarker: true,
      .latticeUnorderedListIndent: nestingIndent
    ]
  }

  private static func unorderedListNestingIndent(from sourceIndent: String) -> CGFloat {
    sourceIndent.reduce(CGFloat.zero) { width, character in
      switch character {
      case "\t":
        return width + 28
      default:
        return width + 7
      }
    }
  }

  private static func unorderedListAttributes() -> [NSAttributedString.Key: Any] {
    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.lineSpacing = 2
    paragraphStyle.paragraphSpacing = 6
    paragraphStyle.headIndent = 28
    paragraphStyle.firstLineHeadIndent = 28
    return [.paragraphStyle: paragraphStyle]
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

  private static func wikiLinkAttributes(for status: WikiLinkRenderStatus, theme: LatticeTheme) -> [NSAttributedString.Key: Any] {
    switch status {
    case .resolved:
      return [.foregroundColor: theme.uiColor(.link), .underlineStyle: NSUnderlineStyle.single.rawValue]
    case .ambiguous:
      return [.foregroundColor: theme.uiColor(.link).withAlphaComponent(0.85), .underlineStyle: NSUnderlineStyle.patternDot.rawValue | NSUnderlineStyle.single.rawValue]
    case .broken:
      return [
        .foregroundColor: theme.uiColor(.secondaryText),
        .underlineColor: theme.uiColor(.warning).withAlphaComponent(0.65),
        .underlineStyle: NSUnderlineStyle.patternDash.rawValue | NSUnderlineStyle.single.rawValue
      ]
    }
  }

  private static func applyWikiLinkStyles(
    to attributed: NSMutableAttributedString,
    fontFamily: EditorFontFamily,
    activeRanges: [NSRange],
    states: [WikiLinkRenderState],
    theme: LatticeTheme
  ) {
    for link in WikiLinkParser.links(in: attributed.string) where NSMaxRange(link.range) <= attributed.length {
      let status = states.first { $0.range == link.range }?.status ?? .resolved
      attributed.addAttributes(wikiLinkAttributes(for: status, theme: theme), range: linkContentRange(for: link.range))

      let delimiterAttributes = range(link.range, containsAnyActive: activeRanges)
        ? wikiLinkDelimiterAttributes(theme: theme)
        : hiddenWikiLinkDelimiterAttributes(fontFamily: fontFamily)
      for delimiterRange in linkDelimiterRanges(for: link.range) {
        attributed.addAttributes(delimiterAttributes, range: delimiterRange)
      }
    }
  }

  private static func wikiLinkDelimiterAttributes(theme: LatticeTheme) -> [NSAttributedString.Key: Any] {
    [
      .foregroundColor: theme.uiColor(.tertiaryText),
      .font: UIFont.monospacedSystemFont(ofSize: 16, weight: .regular)
    ]
  }

  private static func hiddenWikiLinkDelimiterAttributes(fontFamily: EditorFontFamily) -> [NSAttributedString.Key: Any] {
    [
      .foregroundColor: UIColor.clear,
      .font: bodyFont(size: 0.1, fontFamily: fontFamily)
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

  private static func firstMatch(_ pattern: String, in string: String) -> NSTextCheckingResult? {
    guard let regex = try? NSRegularExpression(pattern: pattern) else {
      return nil
    }
    return regex.firstMatch(in: string, range: NSRange(location: 0, length: (string as NSString).length))
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

  private static func hideLatticeMetadataComments(
    in attributed: NSMutableAttributedString,
    fontFamily: EditorFontFamily,
    theme _: LatticeTheme
  ) {
    guard let regex = try? NSRegularExpression(pattern: #"<!--\s*lattice:[^>]*-->"#) else {
      return
    }
    let fullRange = NSRange(location: 0, length: attributed.length)
    for match in regex.matches(in: attributed.string, range: fullRange) {
      attributed.addAttributes([
        .foregroundColor: UIColor.clear,
        .font: bodyFont(size: 0.1, fontFamily: fontFamily)
      ], range: match.range)
    }
  }

  private static func applyInactiveTextDimming(
    to attributed: NSMutableAttributedString,
    activeRanges: [NSRange],
    theme: LatticeTheme
  ) {
    guard attributed.length > 0, !activeRanges.isEmpty else {
      return
    }

    let inactiveColor = inactiveTextColor(theme: theme)
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

  private static func inactiveTextColor(theme: LatticeTheme) -> UIColor {
    theme.uiColor(.primaryText).withAlphaComponent(0.28)
  }
}
#endif
