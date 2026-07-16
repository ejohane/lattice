import Foundation
import LatticeCore
@testable import LatticeShared
import Testing

#if os(macOS)
import AppKit

@Suite("MarkdownAttributedRenderer")
struct MarkdownAttributedRendererTests {
  @Test("uses moderate paragraph spacing for body text")
  func usesModerateParagraphSpacingForBodyText() {
    let attributed = MarkdownAttributedRenderer.render("what is\nThe line spacing\nhere?")
    let paragraphStyle = attributed.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle

    #expect(paragraphStyle?.lineSpacing == 5)
    #expect(paragraphStyle?.paragraphSpacing == 6)
  }

  @Test("uses selected editor font family for body text")
  func usesSelectedEditorFontFamilyForBodyText() throws {
    let systemAttributed = MarkdownAttributedRenderer.render("plain `code`", fontFamily: .system)
    let monospacedAttributed = MarkdownAttributedRenderer.render("plain `code`", fontFamily: .monospaced)
    let codeRange = (systemAttributed.string as NSString).range(of: "code")

    let systemBodyFont = try #require(systemAttributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
    let monospacedBodyFont = try #require(monospacedAttributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
    let codeFont = try #require(systemAttributed.attribute(.font, at: codeRange.location, effectiveRange: nil) as? NSFont)

    #expect(!systemBodyFont.fontDescriptor.symbolicTraits.contains(.monoSpace))
    #expect(monospacedBodyFont.fontDescriptor.symbolicTraits.contains(.monoSpace))
    #expect(codeFont.fontDescriptor.symbolicTraits.contains(.monoSpace))
  }

  @Test("dims inactive zen lines while preserving active line color")
  func dimsInactiveZenLinesWhilePreservingActiveLineColor() {
    let text = "Previous paragraph\nActive line\nNext paragraph"
    let string = text as NSString
    let theme = LatticeTheme(id: .graphite)
    let activeLineRange = string.lineRange(for: string.range(of: "Active line"))
    let attributed = MarkdownAttributedRenderer.render(
      text,
      activeRanges: [activeLineRange],
      dimsInactiveText: true,
      theme: theme
    )
    let expectedInactiveColor = theme.nsColor(.primaryText)
      .blended(withFraction: 0.74, of: theme.nsColor(.editorBackground))

    let pastColor = attributed.attribute(.foregroundColor, at: string.range(of: "Previous").location, effectiveRange: nil) as? NSColor
    let activeColor = attributed.attribute(.foregroundColor, at: string.range(of: "Active").location, effectiveRange: nil) as? NSColor
    let futureColor = attributed.attribute(.foregroundColor, at: string.range(of: "Next").location, effectiveRange: nil) as? NSColor

    #expect(pastColor == expectedInactiveColor)
    #expect(activeColor == theme.nsColor(.primaryText))
    #expect(futureColor == expectedInactiveColor)
  }

  @Test("renders inactive unordered list markers as bullets")
  func rendersInactiveListMarkersAsBullets() {
    let attributed = MarkdownAttributedRenderer.render("- bullets\nnext", activeRanges: [NSRange(location: 10, length: 0)])
    let glyphInfo = attributed.attribute(.glyphInfo, at: 0, effectiveRange: nil) as? NSGlyphInfo
    let markerFont = attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
    let paragraphStyle = attributed.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle

    #expect(glyphInfo != nil)
    #expect(markerFont?.pointSize == 14)
    #expect(paragraphStyle?.headIndent == 28)
    #expect(paragraphStyle?.lineSpacing == 4)
    #expect(paragraphStyle?.paragraphSpacing == paragraphStyle?.lineSpacing)
  }

  @Test("shows unordered list markers as editable source at line boundaries")
  func showsUnorderedListMarkersAsEditableSourceAtLineBoundaries() {
    let startAttributed = MarkdownAttributedRenderer.render("- bullets", activeRanges: [NSRange(location: 0, length: 0)])
    let endAttributed = MarkdownAttributedRenderer.render("- bullets", activeRanges: [NSRange(location: 9, length: 0)])

    let startGlyphInfo = startAttributed.attribute(.glyphInfo, at: 0, effectiveRange: nil) as? NSGlyphInfo
    let endGlyphInfo = endAttributed.attribute(.glyphInfo, at: 0, effectiveRange: nil) as? NSGlyphInfo

    #expect(startGlyphInfo == nil)
    #expect(endGlyphInfo == nil)
  }

  @Test("shows active unordered list markers as editable source")
  func showsActiveListMarkersAsEditableSource() {
    let attributed = MarkdownAttributedRenderer.render("- bullets", activeRanges: [NSRange(location: 1, length: 0)])
    let glyphInfo = attributed.attribute(.glyphInfo, at: 0, effectiveRange: nil) as? NSGlyphInfo
    let markerFont = attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
    let markerColor = attributed.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor

    #expect(glyphInfo == nil)
    #expect(markerFont?.pointSize == 14)
    #expect(markerColor == NSColor.controlAccentColor)
  }

  @Test("keeps inactive ordered list markers visible")
  func keepsInactiveOrderedListMarkersVisible() {
    let attributed = MarkdownAttributedRenderer.render("1. Define PRD\n2. test", activeRanges: [NSRange(location: 17, length: 0)])
    let markerFont = attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
    let markerColor = attributed.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
    let paragraphStyle = attributed.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle

    #expect(markerFont?.pointSize == 14)
    #expect(markerColor == NSColor.controlAccentColor)
    #expect(paragraphStyle?.headIndent == 28)
  }

  @Test("shows active empty ordered list markers as editable source")
  func showsActiveEmptyOrderedListMarkersAsEditableSource() {
    let attributed = MarkdownAttributedRenderer.render("1. Define PRD\n2. ", activeRanges: [NSRange(location: 17, length: 0)])
    let secondMarkerLocation = ("1. Define PRD\n" as NSString).length
    let markerFont = attributed.attribute(.font, at: secondMarkerLocation, effectiveRange: nil) as? NSFont
    let markerColor = attributed.attribute(.foregroundColor, at: secondMarkerLocation, effectiveRange: nil) as? NSColor
    let paragraphStyle = attributed.attribute(.paragraphStyle, at: secondMarkerLocation, effectiveRange: nil) as? NSParagraphStyle

    #expect(markerFont?.pointSize == 14)
    #expect(markerColor == NSColor.controlAccentColor)
    #expect(paragraphStyle?.headIndent == 28)
  }

  @Test("styles checked task list content as completed")
  func stylesCheckedTaskListContentAsCompleted() {
    let attributed = MarkdownAttributedRenderer.render("- [x] done\nnext", activeRanges: [NSRange(location: 11, length: 0)])
    let string = attributed.string as NSString
    let markerRange = string.range(of: "-")
    let checkboxRange = string.range(of: "[x]")
    let contentRange = string.range(of: "done")

    let markerColor = attributed.attribute(.foregroundColor, at: markerRange.location, effectiveRange: nil) as? NSColor
    let rendersCheckbox = attributed.attribute(.latticeTaskCheckbox, at: checkboxRange.location, effectiveRange: nil) as? Bool
    let isChecked = attributed.attribute(.latticeTaskCheckboxChecked, at: checkboxRange.location, effectiveRange: nil) as? Bool
    let checkboxColor = attributed.attribute(.foregroundColor, at: checkboxRange.location, effectiveRange: nil) as? NSColor
    let checkboxFont = attributed.attribute(.font, at: checkboxRange.location, effectiveRange: nil) as? NSFont
    let color = attributed.attribute(.foregroundColor, at: contentRange.location, effectiveRange: nil) as? NSColor
    let strikethrough = attributed.attribute(.strikethroughStyle, at: contentRange.location, effectiveRange: nil) as? Int

    #expect(markerColor == NSColor.clear)
    #expect(rendersCheckbox == true)
    #expect(isChecked == true)
    #expect(checkboxColor == NSColor.clear)
    #expect(checkboxFont?.pointSize == MarkdownAttributedRenderer.bodyFontSize)
    #expect(color == NSColor.secondaryLabelColor)
    #expect(strikethrough == NSUnderlineStyle.single.rawValue)
  }

  @Test("does not complete unchecked task list content")
  func doesNotCompleteUncheckedTaskListContent() {
    let attributed = MarkdownAttributedRenderer.render("- [ ] todo\nnext", activeRanges: [NSRange(location: 11, length: 0)])
    let string = attributed.string as NSString
    let checkboxRange = string.range(of: "[ ]")
    let contentRange = string.range(of: "todo")

    let rendersCheckbox = attributed.attribute(.latticeTaskCheckbox, at: checkboxRange.location, effectiveRange: nil) as? Bool
    let isChecked = attributed.attribute(.latticeTaskCheckboxChecked, at: checkboxRange.location, effectiveRange: nil) as? Bool
    let strikethrough = attributed.attribute(.strikethroughStyle, at: contentRange.location, effectiveRange: nil) as? Int

    #expect(rendersCheckbox == true)
    #expect(isChecked == false)
    #expect(strikethrough == nil)
  }

  @Test("shows active task list markers as editable source")
  func showsActiveTaskListMarkersAsEditableSource() {
    let startAttributed = MarkdownAttributedRenderer.render("- [ ] todo", activeRanges: [NSRange(location: 0, length: 0)])
    let attributed = MarkdownAttributedRenderer.render("- [ ] todo", activeRanges: [NSRange(location: 4, length: 0)])
    let endAttributed = MarkdownAttributedRenderer.render("- [ ] todo", activeRanges: [NSRange(location: 10, length: 0)])

    let startMarkerGlyphInfo = startAttributed.attribute(.glyphInfo, at: 0, effectiveRange: nil) as? NSGlyphInfo
    let markerGlyphInfo = attributed.attribute(.glyphInfo, at: 0, effectiveRange: nil) as? NSGlyphInfo
    let endMarkerGlyphInfo = endAttributed.attribute(.glyphInfo, at: 0, effectiveRange: nil) as? NSGlyphInfo
    let markerColor = attributed.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
    let checkboxColor = attributed.attribute(.foregroundColor, at: 2, effectiveRange: nil) as? NSColor
    let rendersCheckbox = attributed.attribute(.latticeTaskCheckbox, at: 2, effectiveRange: nil) as? Bool

    #expect(startMarkerGlyphInfo == nil)
    #expect(markerGlyphInfo == nil)
    #expect(endMarkerGlyphInfo == nil)
    #expect(markerColor == NSColor.controlAccentColor)
    #expect(checkboxColor == NSColor.controlAccentColor)
    #expect(rendersCheckbox == nil)
  }

  @Test("shows active empty task list markers as editable source")
  func showsActiveEmptyTaskListMarkersAsEditableSource() {
    let attributed = MarkdownAttributedRenderer.render("- [ ] ", activeRanges: [NSRange(location: 6, length: 0)])

    let markerGlyphInfo = attributed.attribute(.glyphInfo, at: 0, effectiveRange: nil) as? NSGlyphInfo
    let markerColor = attributed.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
    let checkboxColor = attributed.attribute(.foregroundColor, at: 2, effectiveRange: nil) as? NSColor

    #expect(markerGlyphInfo == nil)
    #expect(markerColor == NSColor.controlAccentColor)
    #expect(checkboxColor == NSColor.controlAccentColor)
  }

  @Test("hides inactive inline tokens while styling content")
  func hidesInactiveInlineTokens() throws {
    let text = "**bold** _italic_ `code` [link](https://example.com)"
    let attributed = MarkdownAttributedRenderer.render(
      text,
      activeRanges: [NSRange(location: (text as NSString).length, length: 0)]
    )
    let string = attributed.string as NSString
    let boldRange = string.range(of: "bold")
    let italicRange = string.range(of: "italic")
    let codeRange = string.range(of: "code")
    let linkRange = string.range(of: "link")

    let openingColor = attributed.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
    let italicTokenColor = attributed.attribute(.foregroundColor, at: string.range(of: "_").location, effectiveRange: nil) as? NSColor
    let codeTokenColor = attributed.attribute(.foregroundColor, at: string.range(of: "`").location, effectiveRange: nil) as? NSColor
    let linkTokenColor = attributed.attribute(.foregroundColor, at: string.range(of: "[").location, effectiveRange: nil) as? NSColor
    let linkTokenFont = try #require(attributed.attribute(.font, at: string.range(of: "(").location, effectiveRange: nil) as? NSFont)
    let boldFont = try #require(attributed.attribute(.font, at: boldRange.location, effectiveRange: nil) as? NSFont)
    let italicFont = try #require(attributed.attribute(.font, at: italicRange.location, effectiveRange: nil) as? NSFont)
    let codeFont = try #require(attributed.attribute(.font, at: codeRange.location, effectiveRange: nil) as? NSFont)
    let linkColor = attributed.attribute(.foregroundColor, at: linkRange.location, effectiveRange: nil) as? NSColor
    let linkUnderline = attributed.attribute(.underlineStyle, at: linkRange.location, effectiveRange: nil) as? Int
    let linkURL = attributed.attribute(.link, at: linkRange.location, effectiveRange: nil) as? URL

    #expect(openingColor == NSColor.clear)
    #expect(italicTokenColor == NSColor.clear)
    #expect(codeTokenColor == NSColor.clear)
    #expect(linkTokenColor == NSColor.clear)
    #expect(linkTokenFont.pointSize <= 0.2)
    #expect(boldFont.fontDescriptor.symbolicTraits.contains(.bold))
    #expect(italicFont.fontDescriptor.symbolicTraits.contains(.italic))
    #expect(codeFont.fontDescriptor.symbolicTraits.contains(.monoSpace))
    #expect(linkColor == NSColor.systemBlue)
    #expect(linkUnderline == NSUnderlineStyle.single.rawValue)
    #expect(linkURL == URL(string: "https://example.com"))
  }

  @Test("hides inactive wiki link delimiters while styling content")
  func hidesInactiveWikiLinkDelimiters() throws {
    let text = "Linked [[Project Plan]]"
    let string = text as NSString
    let linkRange = string.range(of: "[[Project Plan]]")
    let contentRange = string.range(of: "Project Plan")
    let attributed = MarkdownAttributedRenderer.render(
      text,
      activeRanges: [NSRange(location: string.length, length: 0)],
      wikiLinkStates: [WikiLinkRenderState(range: linkRange, status: .resolved)]
    )

    let openingColor = attributed.attribute(.foregroundColor, at: linkRange.location, effectiveRange: nil) as? NSColor
    let openingFont = try #require(attributed.attribute(.font, at: linkRange.location, effectiveRange: nil) as? NSFont)
    let closingColor = attributed.attribute(.foregroundColor, at: NSMaxRange(linkRange) - 1, effectiveRange: nil) as? NSColor
    let linkColor = attributed.attribute(.foregroundColor, at: contentRange.location, effectiveRange: nil) as? NSColor
    let linkUnderline = attributed.attribute(.underlineStyle, at: contentRange.location, effectiveRange: nil) as? Int

    #expect(openingColor == NSColor.clear)
    #expect(openingFont.pointSize <= 0.2)
    #expect(closingColor == NSColor.clear)
    #expect(linkColor == NSColor.systemBlue)
    #expect(linkUnderline == NSUnderlineStyle.single.rawValue)
  }

  @Test("styles person mentions and hides durable target metadata")
  func stylesPersonMentions() throws {
    let text = "Met @Erik Johansson<!-- lattice:mention=person-1 --> today"
    let string = text as NSString
    let mentionRange = string.range(of: "@Erik Johansson")
    let metadataRange = string.range(of: "<!-- lattice:mention=person-1 -->")
    let attributed = MarkdownAttributedRenderer.render(
      text,
      activeRanges: [NSRange(location: string.length, length: 0)]
    )

    let mentionColor = attributed.attribute(.foregroundColor, at: mentionRange.location, effectiveRange: nil) as? NSColor
    let underline = attributed.attribute(.underlineStyle, at: mentionRange.location, effectiveRange: nil) as? Int
    let metadataColor = attributed.attribute(.foregroundColor, at: metadataRange.location, effectiveRange: nil) as? NSColor
    let metadataFont = try #require(attributed.attribute(.font, at: metadataRange.location, effectiveRange: nil) as? NSFont)

    #expect(mentionColor == NSColor.controlAccentColor)
    #expect(underline == NSUnderlineStyle.single.rawValue)
    #expect(metadataColor == NSColor.clear)
    #expect(metadataFont.pointSize <= 0.2)
  }

  @Test("shows active wiki link delimiters as editable source")
  func showsActiveWikiLinkDelimiters() throws {
    let text = "Linked [[Project Plan]]"
    let string = text as NSString
    let linkRange = string.range(of: "[[Project Plan]]")
    let contentRange = string.range(of: "Project Plan")
    let attributed = MarkdownAttributedRenderer.render(
      text,
      activeRanges: [NSRange(location: contentRange.location + 2, length: 0)],
      wikiLinkStates: [WikiLinkRenderState(range: linkRange, status: .resolved)]
    )

    let openingColor = attributed.attribute(.foregroundColor, at: linkRange.location, effectiveRange: nil) as? NSColor
    let openingFont = try #require(attributed.attribute(.font, at: linkRange.location, effectiveRange: nil) as? NSFont)
    let closingColor = attributed.attribute(.foregroundColor, at: NSMaxRange(linkRange) - 1, effectiveRange: nil) as? NSColor

    #expect(openingColor == NSColor.tertiaryLabelColor)
    #expect(openingFont.pointSize == 14)
    #expect(closingColor == NSColor.tertiaryLabelColor)
  }

  @Test("renders bare URLs as links")
  func rendersBareURLsAsLinks() throws {
    let text = "Open https://example.com/path?query=1 now"
    let attributed = MarkdownAttributedRenderer.render(text)
    let string = attributed.string as NSString
    let urlRange = string.range(of: "https://example.com/path?query=1")

    let color = attributed.attribute(.foregroundColor, at: urlRange.location, effectiveRange: nil) as? NSColor
    let underline = attributed.attribute(.underlineStyle, at: urlRange.location, effectiveRange: nil) as? Int
    let url = attributed.attribute(.link, at: urlRange.location, effectiveRange: nil) as? URL

    #expect(color == NSColor.systemBlue)
    #expect(underline == NSUnderlineStyle.single.rawValue)
    #expect(url == URL(string: "https://example.com/path?query=1"))
  }

  @Test("does not auto-link markdown link destinations")
  func doesNotAutolinkMarkdownLinkDestinations() throws {
    let text = "[Example](https://example.com)"
    let attributed = MarkdownAttributedRenderer.render(
      text,
      activeRanges: [NSRange(location: (text as NSString).length, length: 0)]
    )
    let string = attributed.string as NSString
    let labelRange = string.range(of: "Example")
    let destinationRange = string.range(of: "https://example.com")

    let labelURL = attributed.attribute(.link, at: labelRange.location, effectiveRange: nil) as? URL
    let destinationURL = attributed.attribute(.link, at: destinationRange.location, effectiveRange: nil) as? URL
    let destinationColor = attributed.attribute(.foregroundColor, at: destinationRange.location, effectiveRange: nil) as? NSColor

    #expect(labelURL == URL(string: "https://example.com"))
    #expect(destinationURL == nil)
    #expect(destinationColor == NSColor.clear)
  }

  @Test("marks inactive image links for inline previews")
  func marksInactiveImageLinksForInlinePreviews() throws {
    let text = "Before\n![Screenshot](../../attachments/2026-06-17/screenshot.png)\nAfter"
    let image = try #require(MarkdownImageParser.links(in: text).first)
    let imageURL = URL(fileURLWithPath: "/tmp/screenshot.png")
    let attributed = MarkdownAttributedRenderer.render(
      text,
      activeRanges: [NSRange(location: (text as NSString).length, length: 0)],
      imagePreviewStates: [MarkdownImageRenderState(link: image, url: imageURL)]
    )

    let previewURL = attributed.attribute(.latticeImagePreviewURL, at: image.range.location, effectiveRange: nil) as? URL
    let color = attributed.attribute(.foregroundColor, at: image.range.location, effectiveRange: nil) as? NSColor
    let paragraphStyle = attributed.attribute(.paragraphStyle, at: image.range.location, effectiveRange: nil) as? NSParagraphStyle

    #expect(previewURL == imageURL)
    #expect(color == NSColor.clear)
    #expect(paragraphStyle?.minimumLineHeight == MarkdownAttributedRenderer.imagePreviewHeight)
  }

  @Test("carries image preview widths into renderer attributes")
  func carriesImagePreviewWidthsIntoRendererAttributes() throws {
    let text = "![Screenshot|640](../../attachments/2026-06-17/screenshot.png)\nAfter"
    let image = try #require(MarkdownImageParser.links(in: text).first)
    let attributed = MarkdownAttributedRenderer.render(
      text,
      activeRanges: [NSRange(location: (text as NSString).length, length: 0)],
      imagePreviewStates: [MarkdownImageRenderState(link: image, url: URL(fileURLWithPath: "/tmp/screenshot.png"))]
    )

    let width = attributed.attribute(.latticeImagePreviewWidth, at: image.range.location, effectiveRange: nil) as? Double

    #expect(width == 640)
  }

  @Test("sizes image preview line height from stored width")
  func sizesImagePreviewLineHeightFromStoredWidth() throws {
    let imageURL = try writeTestPNG(width: 400, height: 200)
    defer { try? FileManager.default.removeItem(at: imageURL) }

    let text = "![Screenshot|200](../../attachments/2026-06-17/screenshot.png)\nAfter"
    let image = try #require(MarkdownImageParser.links(in: text).first)
    let attributed = MarkdownAttributedRenderer.render(
      text,
      activeRanges: [NSRange(location: (text as NSString).length, length: 0)],
      imagePreviewStates: [MarkdownImageRenderState(link: image, url: imageURL)]
    )

    let paragraphStyle = attributed.attribute(.paragraphStyle, at: image.range.location, effectiveRange: nil) as? NSParagraphStyle

    #expect(paragraphStyle?.minimumLineHeight == 118)
    #expect(paragraphStyle?.maximumLineHeight == 118)
  }

  @Test("shows active image links as editable markdown")
  func showsActiveImageLinksAsEditableMarkdown() throws {
    let text = "![Screenshot](../../attachments/2026-06-17/screenshot.png)"
    let image = try #require(MarkdownImageParser.links(in: text).first)
    let attributed = MarkdownAttributedRenderer.render(
      text,
      activeRanges: [NSRange(location: image.range.location + 2, length: 0)],
      imagePreviewStates: [MarkdownImageRenderState(link: image, url: URL(fileURLWithPath: "/tmp/screenshot.png"))]
    )

    let previewURL = attributed.attribute(.latticeImagePreviewURL, at: image.range.location, effectiveRange: nil) as? URL
    let openingColor = attributed.attribute(.foregroundColor, at: image.range.location, effectiveRange: nil) as? NSColor

    #expect(previewURL == nil)
    #expect(openingColor == NSColor.tertiaryLabelColor)
  }

  @Test("renders inactive thematic breaks as rule lines")
  func rendersInactiveThematicBreaksAsRuleLines() throws {
    let text = "Before\n---\nAfter"
    let attributed = MarkdownAttributedRenderer.render(
      text,
      activeRanges: [NSRange(location: (text as NSString).length, length: 0)]
    )
    let string = attributed.string as NSString
    let ruleRange = string.range(of: "---")

    let hasRuleAttribute = try #require(attributed.attribute(.latticeThematicBreak, at: ruleRange.location, effectiveRange: nil) as? Bool)
    let color = attributed.attribute(.foregroundColor, at: ruleRange.location, effectiveRange: nil) as? NSColor
    let font = try #require(attributed.attribute(.font, at: ruleRange.location, effectiveRange: nil) as? NSFont)

    #expect(hasRuleAttribute)
    #expect(color == NSColor.clear)
    #expect(font.pointSize == 14)
  }

  @Test("shows active thematic break source")
  func showsActiveThematicBreakSource() {
    let attributed = MarkdownAttributedRenderer.render(
      "Before\n---\nAfter",
      activeRanges: [NSRange(location: 8, length: 0)]
    )
    let string = attributed.string as NSString
    let ruleRange = string.range(of: "---")

    let hasRuleAttribute = attributed.attribute(.latticeThematicBreak, at: ruleRange.location, effectiveRange: nil) as? Bool
    let color = attributed.attribute(.foregroundColor, at: ruleRange.location, effectiveRange: nil) as? NSColor

    #expect(hasRuleAttribute == nil)
    #expect(color == NSColor.tertiaryLabelColor)
  }

  @Test("marks inactive markdown tables for grid rendering")
  func marksInactiveMarkdownTablesForGridRendering() throws {
    let text = """
    Before
    | Project | Status |
    | --- | --- |
    | Lattice | Shipping |
    After
    """
    let string = text as NSString
    let headerRange = string.range(of: "| Project | Status |")
    let separatorRange = string.range(of: "| --- | --- |")
    let attributed = MarkdownAttributedRenderer.render(
      text,
      activeRanges: [NSRange(location: string.length, length: 0)]
    )

    let hasTableAttribute = try #require(attributed.attribute(.latticeMarkdownTable, at: headerRange.location, effectiveRange: nil) as? Bool)
    let headerColor = attributed.attribute(.foregroundColor, at: headerRange.location, effectiveRange: nil) as? NSColor
    let headerParagraphStyle = attributed.attribute(.paragraphStyle, at: headerRange.location, effectiveRange: nil) as? NSParagraphStyle
    let separatorParagraphStyle = attributed.attribute(.paragraphStyle, at: separatorRange.location, effectiveRange: nil) as? NSParagraphStyle

    #expect(hasTableAttribute)
    #expect(headerColor == NSColor.clear)
    #expect(headerParagraphStyle?.minimumLineHeight == 38)
    #expect(separatorParagraphStyle?.minimumLineHeight == 2)
  }

  @Test("shows active markdown table source")
  func showsActiveMarkdownTableSource() {
    let text = """
    | Project | Status |
    | --- | --- |
    | Lattice | Shipping |
    """
    let string = text as NSString
    let activeRange = string.range(of: "Status")
    let attributed = MarkdownAttributedRenderer.render(
      text,
      activeRanges: [NSRange(location: activeRange.location, length: 0)]
    )

    let hasTableAttribute = attributed.attribute(.latticeMarkdownTable, at: 0, effectiveRange: nil) as? Bool
    let color = attributed.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
    let font = attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont

    #expect(hasTableAttribute == nil)
    #expect(color == NSColor.labelColor)
    #expect(font?.fontDescriptor.symbolicTraits.contains(.monoSpace) == true)
  }

  @Test("shows active inline tokens as editable source")
  func showsActiveInlineTokensAsEditableSource() {
    let attributed = MarkdownAttributedRenderer.render(
      "**bold**",
      activeRanges: [NSRange(location: 2, length: 0)]
    )
    let openingColor = attributed.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
    let openingFont = attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont

    #expect(openingColor == NSColor.tertiaryLabelColor)
    #expect(openingFont?.pointSize == 14)
  }

  @Test("does not apply inline markdown inside fenced code blocks")
  func skipsInlineMarkdownInsideFencedCodeBlocks() throws {
    let attributed = MarkdownAttributedRenderer.render(
      """
      ```
      **not bold**
      ```
      **bold**
      """,
      activeRanges: [NSRange(location: 26, length: 0)]
    )
    let string = attributed.string as NSString
    let notBoldRange = string.range(of: "not bold")
    let boldRange = string.range(of: "bold", options: [], range: NSRange(location: NSMaxRange(notBoldRange), length: string.length - NSMaxRange(notBoldRange)))
    let notBoldFont = try #require(attributed.attribute(.font, at: notBoldRange.location, effectiveRange: nil) as? NSFont)
    let boldFont = try #require(attributed.attribute(.font, at: boldRange.location, effectiveRange: nil) as? NSFont)

    #expect(notBoldFont.fontDescriptor.symbolicTraits.contains(.monoSpace))
    #expect(!notBoldFont.fontDescriptor.symbolicTraits.contains(.bold))
    #expect(boldFont.fontDescriptor.symbolicTraits.contains(.bold))
  }

  @Test("uses selected theme colors for markdown syntax")
  func usesSelectedThemeColorsForMarkdownSyntax() {
    let theme = LatticeTheme(id: .solarizedDark)
    let text = "`code` [link](https://example.com)"
    let attributed = MarkdownAttributedRenderer.render(text, theme: theme)
    let string = attributed.string as NSString
    let codeRange = string.range(of: "code")
    let linkRange = string.range(of: "link")

    let codeColor = attributed.attribute(.foregroundColor, at: codeRange.location, effectiveRange: nil) as? NSColor
    let codeBackground = attributed.attribute(.backgroundColor, at: codeRange.location, effectiveRange: nil) as? NSColor
    let linkColor = attributed.attribute(.foregroundColor, at: linkRange.location, effectiveRange: nil) as? NSColor

    #expect(codeColor == theme.nsColor(.codeText))
    #expect(codeBackground == theme.nsColor(.codeBackground).withAlphaComponent(0.8))
    #expect(linkColor == theme.nsColor(.link))
  }

  @Test("styles inline tags without styling code examples")
  func stylesInlineTags() throws {
    let theme = LatticeTheme(id: .system)
    let text = "#work `#example`"
    let attributed = MarkdownAttributedRenderer.render(text, theme: theme)
    let string = text as NSString
    let tagRange = string.range(of: "#work")
    let codeRange = string.range(of: "#example")

    let tagColor = attributed.attribute(.foregroundColor, at: tagRange.location, effectiveRange: nil) as? NSColor
    let tagFont = try #require(attributed.attribute(.font, at: tagRange.location, effectiveRange: nil) as? NSFont)
    let codeColor = attributed.attribute(.foregroundColor, at: codeRange.location, effectiveRange: nil) as? NSColor

    #expect(tagColor == theme.nsColor(.accent))
    #expect(tagFont.fontDescriptor.symbolicTraits.contains(.bold))
    #expect(codeColor != theme.nsColor(.accent))
  }

  private func writeTestPNG(width: Int, height: Int) throws -> URL {
    let bitmap = try #require(NSBitmapImageRep(
      bitmapDataPlanes: nil,
      pixelsWide: width,
      pixelsHigh: height,
      bitsPerSample: 8,
      samplesPerPixel: 4,
      hasAlpha: true,
      isPlanar: false,
      colorSpaceName: .deviceRGB,
      bytesPerRow: 0,
      bitsPerPixel: 0
    ))
    bitmap.size = NSSize(width: width, height: height)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSColor.systemBlue.setFill()
    NSRect(x: 0, y: 0, width: width, height: height).fill()
    NSGraphicsContext.restoreGraphicsState()

    let data = try #require(bitmap.representation(using: .png, properties: [:]))
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("lattice-preview-\(UUID().uuidString)")
      .appendingPathExtension("png")
    try data.write(to: url)
    return url
  }
}
#endif
