import Foundation
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
    let attributed = MarkdownAttributedRenderer.render("- bullets", activeRanges: [NSRange(location: 9, length: 0)])
    let glyphInfo = attributed.attribute(.glyphInfo, at: 0, effectiveRange: nil) as? NSGlyphInfo
    let markerFont = attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
    let paragraphStyle = attributed.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle

    #expect(glyphInfo != nil)
    #expect(markerFont?.pointSize == 14)
    #expect(paragraphStyle?.headIndent == 28)
    #expect(paragraphStyle?.lineSpacing == 4)
    #expect(paragraphStyle?.paragraphSpacing == paragraphStyle?.lineSpacing)
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
    let attributed = MarkdownAttributedRenderer.render("- [x] done", activeRanges: [NSRange(location: 0, length: 0)])
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
    let attributed = MarkdownAttributedRenderer.render("- [ ] todo", activeRanges: [NSRange(location: 0, length: 0)])
    let string = attributed.string as NSString
    let contentRange = string.range(of: "todo")

    let markerGlyphInfo = attributed.attribute(.glyphInfo, at: 0, effectiveRange: nil) as? NSGlyphInfo
    let strikethrough = attributed.attribute(.strikethroughStyle, at: contentRange.location, effectiveRange: nil) as? Int

    #expect(markerGlyphInfo != nil)
    #expect(strikethrough == nil)
  }

  @Test("shows active task list markers as editable source")
  func showsActiveTaskListMarkersAsEditableSource() {
    let attributed = MarkdownAttributedRenderer.render("- [ ] todo", activeRanges: [NSRange(location: 4, length: 0)])

    let markerGlyphInfo = attributed.attribute(.glyphInfo, at: 0, effectiveRange: nil) as? NSGlyphInfo
    let markerColor = attributed.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
    let checkboxColor = attributed.attribute(.foregroundColor, at: 2, effectiveRange: nil) as? NSColor

    #expect(markerGlyphInfo == nil)
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
