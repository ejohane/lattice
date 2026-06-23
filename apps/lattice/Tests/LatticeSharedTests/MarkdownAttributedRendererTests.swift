import Foundation
@testable import LatticeShared
import Testing

#if os(macOS)
import AppKit

@Suite("MarkdownAttributedRenderer")
struct MarkdownAttributedRendererTests {
  @Test("renders inactive unordered list markers as bullets")
  func rendersInactiveListMarkersAsBullets() {
    let attributed = MarkdownAttributedRenderer.render("- bullets", activeRanges: [NSRange(location: 9, length: 0)])
    let glyphInfo = attributed.attribute(.glyphInfo, at: 0, effectiveRange: nil) as? NSGlyphInfo
    let paragraphStyle = attributed.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle

    #expect(glyphInfo != nil)
    #expect(paragraphStyle?.headIndent == 28)
    #expect(paragraphStyle?.paragraphSpacing == paragraphStyle?.lineSpacing)
  }

  @Test("shows active unordered list markers as editable source")
  func showsActiveListMarkersAsEditableSource() {
    let attributed = MarkdownAttributedRenderer.render("- bullets", activeRanges: [NSRange(location: 1, length: 0)])
    let glyphInfo = attributed.attribute(.glyphInfo, at: 0, effectiveRange: nil) as? NSGlyphInfo
    let markerColor = attributed.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor

    #expect(glyphInfo == nil)
    #expect(markerColor == NSColor.controlAccentColor)
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
    let boldFont = try #require(attributed.attribute(.font, at: boldRange.location, effectiveRange: nil) as? NSFont)
    let italicFont = try #require(attributed.attribute(.font, at: italicRange.location, effectiveRange: nil) as? NSFont)
    let codeFont = try #require(attributed.attribute(.font, at: codeRange.location, effectiveRange: nil) as? NSFont)
    let linkColor = attributed.attribute(.foregroundColor, at: linkRange.location, effectiveRange: nil) as? NSColor
    let linkUnderline = attributed.attribute(.underlineStyle, at: linkRange.location, effectiveRange: nil) as? Int

    #expect(openingColor == NSColor.clear)
    #expect(italicTokenColor == NSColor.clear)
    #expect(codeTokenColor == NSColor.clear)
    #expect(linkTokenColor == NSColor.clear)
    #expect(boldFont.fontDescriptor.symbolicTraits.contains(.bold))
    #expect(italicFont.fontDescriptor.symbolicTraits.contains(.italic))
    #expect(codeFont.fontDescriptor.symbolicTraits.contains(.monoSpace))
    #expect(linkColor == NSColor.systemBlue)
    #expect(linkUnderline == NSUnderlineStyle.single.rawValue)
  }

  @Test("shows active inline tokens as editable source")
  func showsActiveInlineTokensAsEditableSource() {
    let attributed = MarkdownAttributedRenderer.render(
      "**bold**",
      activeRanges: [NSRange(location: 2, length: 0)]
    )
    let openingColor = attributed.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor

    #expect(openingColor == NSColor.tertiaryLabelColor)
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
