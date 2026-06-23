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

  @Test("hides inactive inline tokens while styling content")
  func hidesInactiveInlineTokens() {
    let attributed = MarkdownAttributedRenderer.render(
      "**bold** inline _rendering_",
      activeRanges: [NSRange(location: 27, length: 0)]
    )

    let openingColor = attributed.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
    let boldFont = try? #require(attributed.attribute(.font, at: 2, effectiveRange: nil) as? NSFont)
    let italicFont = try? #require(attributed.attribute(.font, at: 17, effectiveRange: nil) as? NSFont)

    #expect(openingColor == NSColor.clear)
    #expect(boldFont?.fontDescriptor.symbolicTraits.contains(.bold) == true)
    #expect(italicFont?.fontDescriptor.symbolicTraits.contains(.italic) == true)
  }
}
#endif
