import Foundation
import LatticeEditor
import Testing

@Suite("MarkdownTextEditing")
struct MarkdownTextEditingTests {
  @Test("wraps a selected range")
  func wrapsSelection() {
    let result = MarkdownTextEditing.apply(
      .bold,
      to: "Hello world",
      selection: NSRange(location: 6, length: 5)
    )

    #expect(result.body == "Hello **world**")
    #expect(result.selection == NSRange(location: 6, length: 9))
  }

  @Test("inserts line prefixes at the active line")
  func insertsLinePrefix() {
    let result = MarkdownTextEditing.apply(
      .bulletList,
      to: "One\nTwo",
      selection: NSRange(location: 4, length: 0)
    )

    #expect(result.body == "One\n- Two")
    #expect(result.selection == NSRange(location: 6, length: 0))
  }

  @Test("inserts links with the URL selected")
  func insertsLink() {
    let result = MarkdownTextEditing.apply(
      .link,
      to: "OpenAI",
      selection: NSRange(location: 0, length: 6)
    )

    #expect(result.body == "[OpenAI](url)")
    #expect(result.selection == NSRange(location: 9, length: 3))
  }
}

@Suite("MarkdownStyler")
struct MarkdownStylerTests {
  @Test("generates style spans for core live markdown")
  func generatesCoreSpans() {
    let text = """
    # Heading
    - item
    > quote
    **bold** *italic* `code` [link](https://example.com)
    ---
    ```
    let value = 1
    ```
    """

    let kinds = Set(MarkdownStyler.spans(in: text).map(\.kind))

    #expect(kinds.contains(.heading))
    #expect(kinds.contains(.headingMarker))
    #expect(kinds.contains(.listMarker))
    #expect(kinds.contains(.blockquote))
    #expect(kinds.contains(.bold))
    #expect(kinds.contains(.italic))
    #expect(kinds.contains(.inlineCode))
    #expect(kinds.contains(.link))
    #expect(kinds.contains(.thematicBreak))
    #expect(kinds.contains(.codeBlock))
  }

  @Test("does not style inline markdown inside fenced code blocks")
  func skipsInlineStylesInCodeBlocks() {
    let text = """
    ```
    **not bold**
    ```
    **bold**
    """

    let spans = MarkdownStyler.spans(in: text)
    let boldSpans = spans.filter { $0.kind == .bold }

    #expect(boldSpans.count == 1)
    #expect((text as NSString).substring(with: boldSpans[0].range) == "bold")
  }

  @Test("generates italic spans for underscore emphasis")
  func stylesUnderscoreItalic() {
    let text = "inline _rendering_ works"
    let italicSpans = MarkdownStyler.spans(in: text).filter { $0.kind == .italic }

    #expect(italicSpans.count == 1)
    #expect((text as NSString).substring(with: italicSpans[0].range) == "rendering")
  }
}
