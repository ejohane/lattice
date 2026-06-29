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

  @Test("styles checked task list content as completed")
  func stylesCheckedTaskListContentAsCompleted() {
    let attributed = MarkdownAttributedRenderer.render("- [x] done\nnext", activeRanges: [NSRange(location: 11, length: 0)])
    let string = attributed.string as NSString
    let contentRange = string.range(of: "done")

    let markerGlyphInfo = attributed.attribute(.glyphInfo, at: 0, effectiveRange: nil) as? NSGlyphInfo
    let color = attributed.attribute(.foregroundColor, at: contentRange.location, effectiveRange: nil) as? NSColor
    let strikethrough = attributed.attribute(.strikethroughStyle, at: contentRange.location, effectiveRange: nil) as? Int

    #expect(markerGlyphInfo != nil)
    #expect(color == NSColor.secondaryLabelColor)
    #expect(strikethrough == NSUnderlineStyle.single.rawValue)
  }

  @Test("does not complete unchecked task list content")
  func doesNotCompleteUncheckedTaskListContent() {
    let attributed = MarkdownAttributedRenderer.render("- [ ] todo\nnext", activeRanges: [NSRange(location: 11, length: 0)])
    let string = attributed.string as NSString
    let contentRange = string.range(of: "todo")

    let markerGlyphInfo = attributed.attribute(.glyphInfo, at: 0, effectiveRange: nil) as? NSGlyphInfo
    let strikethrough = attributed.attribute(.strikethroughStyle, at: contentRange.location, effectiveRange: nil) as? Int

    #expect(markerGlyphInfo != nil)
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

    #expect(startMarkerGlyphInfo == nil)
    #expect(markerGlyphInfo == nil)
    #expect(endMarkerGlyphInfo == nil)
    #expect(markerColor == NSColor.controlAccentColor)
    #expect(checkboxColor == NSColor.controlAccentColor)
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
}
#endif
