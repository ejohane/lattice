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

  @Test("inserts task list prefixes at the active line")
  func insertsTaskListPrefix() {
    let result = MarkdownTextEditing.apply(
      .taskList,
      to: "One\nTwo",
      selection: NSRange(location: 4, length: 0)
    )

    #expect(result.body == "One\n- [ ] Two")
    #expect(result.selection == NSRange(location: 10, length: 0))
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

@Suite("MarkdownTaskList")
struct MarkdownTaskListTests {
  @Test("toggles unchecked task items")
  func togglesUncheckedTaskItems() throws {
    let result = try #require(MarkdownTaskList.toggleTask(
      at: 1,
      in: "- [ ] item",
      selection: NSRange(location: 10, length: 0)
    ))

    #expect(result.body == "- [x] item")
    #expect(result.selection == NSRange(location: 10, length: 0))
    #expect(result.replacementRange == NSRange(location: 2, length: 3))
    #expect(result.replacement == "[x]")
  }

  @Test("toggles checked task items")
  func togglesCheckedTaskItems() throws {
    let result = try #require(MarkdownTaskList.toggleTask(
      at: 4,
      in: "- [X] item",
      selection: NSRange(location: 0, length: 0)
    ))

    #expect(result.body == "- [ ] item")
    #expect(result.replacement == "[ ]")
  }

  @Test("ignores task item content")
  func ignoresTaskItemContent() {
    let result = MarkdownTaskList.toggleTask(
      at: 6,
      in: "- [ ] item",
      selection: NSRange(location: 6, length: 0)
    )

    #expect(result == nil)
  }
}

@Suite("MarkdownListContinuation")
struct MarkdownListContinuationTests {
  @Test("continues unordered lists")
  func continuesUnorderedLists() throws {
    let result = try #require(MarkdownListContinuation.applyReturn(
      to: "- item",
      selection: NSRange(location: 6, length: 0)
    ))

    #expect(result.body == "- item\n- ")
    #expect(result.selection == NSRange(location: 9, length: 0))
    #expect(result.replacementRange == NSRange(location: 6, length: 0))
    #expect(result.replacement == "\n- ")
  }

  @Test("continues ordered lists with the next number")
  func continuesOrderedLists() throws {
    let result = try #require(MarkdownListContinuation.applyReturn(
      to: "1. item",
      selection: NSRange(location: 7, length: 0)
    ))

    #expect(result.body == "1. item\n2. ")
    #expect(result.selection == NSRange(location: 11, length: 0))
  }

  @Test("continues task lists unchecked")
  func continuesTaskListsUnchecked() throws {
    let result = try #require(MarkdownListContinuation.applyReturn(
      to: "- [x] item",
      selection: NSRange(location: 10, length: 0)
    ))

    #expect(result.body == "- [x] item\n- [ ] ")
    #expect(result.selection == NSRange(location: 17, length: 0))
  }

  @Test("exits empty unordered list items")
  func exitsEmptyUnorderedListItems() throws {
    let result = try #require(MarkdownListContinuation.applyReturn(
      to: "- ",
      selection: NSRange(location: 2, length: 0)
    ))

    #expect(result.body == "")
    #expect(result.selection == NSRange(location: 0, length: 0))
    #expect(result.replacementRange == NSRange(location: 0, length: 2))
    #expect(result.replacement == "")
  }

  @Test("ignores non-list lines")
  func ignoresNonListLines() {
    let result = MarkdownListContinuation.applyReturn(
      to: "plain text",
      selection: NSRange(location: 10, length: 0)
    )

    #expect(result == nil)
  }
}

@Suite("MarkdownListIndentation")
struct MarkdownListIndentationTests {
  @Test("indents the active unordered list item")
  func indentsActiveUnorderedListItem() throws {
    let result = try #require(MarkdownListIndentation.applyIndent(
      to: "- Parent\n- Child",
      selection: NSRange(location: 16, length: 0)
    ))

    #expect(result.body == "- Parent\n    - Child")
    #expect(result.selection == NSRange(location: 20, length: 0))
    #expect(result.replacementRange == NSRange(location: 9, length: 7))
    #expect(result.replacement == "    - Child")
  }

  @Test("outdents the active unordered list item")
  func outdentsActiveUnorderedListItem() throws {
    let result = try #require(MarkdownListIndentation.applyOutdent(
      to: "- Parent\n    - Child",
      selection: NSRange(location: 20, length: 0)
    ))

    #expect(result.body == "- Parent\n- Child")
    #expect(result.selection == NSRange(location: 16, length: 0))
  }

  @Test("indents selected list lines without changing plain text lines")
  func indentsSelectedListLinesOnly() throws {
    let result = try #require(MarkdownListIndentation.applyIndent(
      to: "- One\nplain\n1. Two",
      selection: NSRange(location: 6, length: 12)
    ))

    #expect(result.body == "- One\nplain\n    1. Two")
    #expect(result.selection == NSRange(location: 6, length: 16))
  }

  @Test("ignores non-list lines")
  func ignoresNonListLinesForIndentation() {
    let result = MarkdownListIndentation.applyIndent(
      to: "plain text",
      selection: NSRange(location: 5, length: 0)
    )

    #expect(result == nil)
  }
}

@Suite("MarkdownStyler")
struct MarkdownStylerTests {
  @Test("generates style spans for core live markdown")
  func generatesCoreSpans() {
    let text = """
    # Heading
    - item
    - [x] done
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
    #expect(kinds.contains(.taskCheckbox))
    #expect(kinds.contains(.completedTask))
    #expect(kinds.contains(.blockquote))
    #expect(kinds.contains(.bold))
    #expect(kinds.contains(.italic))
    #expect(kinds.contains(.inlineCode))
    #expect(kinds.contains(.link))
    #expect(kinds.contains(.thematicBreak))
    #expect(kinds.contains(.codeBlock))
  }

  @Test("generates task checkbox spans")
  func stylesTaskCheckboxes() {
    let text = "- [x] done\n- [ ] next"
    let spans = MarkdownStyler.spans(in: text)
    let checkboxSpans = spans.filter { $0.kind == .taskCheckbox }
    let completedSpans = spans.filter { $0.kind == .completedTask }

    #expect(checkboxSpans.count == 2)
    #expect(completedSpans.count == 1)
    #expect((text as NSString).substring(with: completedSpans[0].range) == "done")
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
