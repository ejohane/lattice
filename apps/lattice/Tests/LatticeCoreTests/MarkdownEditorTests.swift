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

  @Test("inserts a horizontal rule")
  func insertsHorizontalRule() {
    let result = MarkdownTextEditing.apply(
      .horizontalRule,
      to: "Before",
      selection: NSRange(location: 6, length: 0)
    )

    #expect(result.body == "Before\n---\n")
    #expect(result.selection == NSRange(location: 11, length: 0))
  }

  @Test("replaces blank lines with a horizontal rule")
  func insertsHorizontalRuleOnBlankLine() {
    let result = MarkdownTextEditing.apply(
      .horizontalRule,
      to: "Before\n\nAfter",
      selection: NSRange(location: 7, length: 0)
    )

    #expect(result.body == "Before\n---\nAfter")
    #expect(result.selection == NSRange(location: 11, length: 0))
  }
}

@Suite("VimTextEditing")
struct VimTextEditingTests {
  @Test("escape switches from insert to normal mode")
  func escapeSwitchesToNormalMode() {
    let result = VimTextEditing.handle(
      .escape,
      body: "Hello",
      selection: NSRange(location: 5, length: 0),
      state: VimEditorState(mode: .insert)
    )

    #expect(result.state.mode == .normal)
    #expect(result.body == "Hello")
  }

  @Test("normal mode enters insert mode with append and line append")
  func entersInsertMode() {
    let append = VimTextEditing.handle(
      .character("a"),
      body: "One\nTwo",
      selection: NSRange(location: 1, length: 0),
      state: VimEditorState(mode: .normal)
    )
    let lineAppend = VimTextEditing.handle(
      .character("A"),
      body: "One\nTwo",
      selection: NSRange(location: 1, length: 0),
      state: VimEditorState(mode: .normal)
    )

    #expect(append.state.mode == .insert)
    #expect(append.selection == NSRange(location: 2, length: 0))
    #expect(lineAppend.state.mode == .insert)
    #expect(lineAppend.selection == NSRange(location: 3, length: 0))
  }

  @Test("moves by line and document")
  func movesByLineAndDocument() {
    let down = VimTextEditing.handle(
      .character("j"),
      body: "One\nTwo longer\nThree",
      selection: NSRange(location: 1, length: 0),
      state: VimEditorState(mode: .normal)
    )
    let up = VimTextEditing.handle(
      .character("k"),
      body: "One\nTwo longer\nThree",
      selection: down.selection,
      state: down.state
    )
    let last = VimTextEditing.handle(
      .character("G"),
      body: "One\nTwo longer\nThree",
      selection: NSRange(location: 0, length: 0),
      state: VimEditorState(mode: .normal)
    )
    let firstPending = VimTextEditing.handle(
      .character("g"),
      body: "One\nTwo",
      selection: NSRange(location: 4, length: 0),
      state: VimEditorState(mode: .normal)
    )
    let first = VimTextEditing.handle(
      .character("g"),
      body: "One\nTwo",
      selection: firstPending.selection,
      state: firstPending.state
    )

    #expect(down.selection == NSRange(location: 5, length: 0))
    #expect(up.selection == NSRange(location: 1, length: 0))
    #expect(last.selection == NSRange(location: 15, length: 0))
    #expect(first.selection == NSRange(location: 0, length: 0))
  }

  @Test("deletes characters, words, and counted lines")
  func deletesText() {
    let deleteCharacter = VimTextEditing.handle(
      .character("x"),
      body: "abc",
      selection: NSRange(location: 1, length: 0),
      state: VimEditorState(mode: .normal)
    )
    let deleteWordPending = VimTextEditing.handle(
      .character("d"),
      body: "alpha beta",
      selection: NSRange(location: 0, length: 0),
      state: VimEditorState(mode: .normal)
    )
    let deleteWord = VimTextEditing.handle(
      .character("w"),
      body: "alpha beta",
      selection: deleteWordPending.selection,
      state: deleteWordPending.state
    )
    let deleteLinePending = VimTextEditing.handle(
      .character("d"),
      body: "one\ntwo\nthree",
      selection: NSRange(location: 4, length: 0),
      state: VimEditorState(mode: .normal)
    )
    let deleteLine = VimTextEditing.handle(
      .character("d"),
      body: "one\ntwo\nthree",
      selection: deleteLinePending.selection,
      state: deleteLinePending.state
    )
    let countedDeleteLinePending = VimTextEditing.handle(
      .character("2"),
      body: "one\ntwo\nthree",
      selection: NSRange(location: 0, length: 0),
      state: VimEditorState(mode: .normal)
    )
    let countedDeleteLineOperator = VimTextEditing.handle(
      .character("d"),
      body: "one\ntwo\nthree",
      selection: countedDeleteLinePending.selection,
      state: countedDeleteLinePending.state
    )
    let countedDeleteLine = VimTextEditing.handle(
      .character("d"),
      body: "one\ntwo\nthree",
      selection: countedDeleteLineOperator.selection,
      state: countedDeleteLineOperator.state
    )

    #expect(deleteCharacter.body == "ac")
    #expect(deleteCharacter.replacementRange == NSRange(location: 1, length: 1))
    #expect(deleteWord.body == "beta")
    #expect(deleteLine.body == "one\nthree")
    #expect(countedDeleteLine.body == "three")
  }

  @Test("supports operator motions and text objects")
  func supportsOperatorMotionsAndTextObjects() {
    let deleteToEndPending = VimTextEditing.handle(
      .character("d"),
      body: "alpha beta",
      selection: NSRange(location: 2, length: 0),
      state: VimEditorState(mode: .normal)
    )
    let deleteToEnd = VimTextEditing.handle(
      .character("$"),
      body: "alpha beta",
      selection: deleteToEndPending.selection,
      state: deleteToEndPending.state
    )
    let changeInnerWordPending = VimTextEditing.handle(
      .character("c"),
      body: "alpha beta",
      selection: NSRange(location: 7, length: 0),
      state: VimEditorState(mode: .normal)
    )
    let changeInnerWordPrefix = VimTextEditing.handle(
      .character("i"),
      body: "alpha beta",
      selection: changeInnerWordPending.selection,
      state: changeInnerWordPending.state
    )
    let changeInnerWord = VimTextEditing.handle(
      .character("w"),
      body: "alpha beta",
      selection: changeInnerWordPrefix.selection,
      state: changeInnerWordPrefix.state
    )
    let deleteAroundWordPending = VimTextEditing.handle(
      .character("d"),
      body: "alpha beta gamma",
      selection: NSRange(location: 6, length: 0),
      state: VimEditorState(mode: .normal)
    )
    let deleteAroundWordPrefix = VimTextEditing.handle(
      .character("a"),
      body: "alpha beta gamma",
      selection: deleteAroundWordPending.selection,
      state: deleteAroundWordPending.state
    )
    let deleteAroundWord = VimTextEditing.handle(
      .character("w"),
      body: "alpha beta gamma",
      selection: deleteAroundWordPrefix.selection,
      state: deleteAroundWordPrefix.state
    )

    #expect(deleteToEnd.body == "al")
    #expect(changeInnerWord.body == "alpha ")
    #expect(changeInnerWord.state.mode == .insert)
    #expect(deleteAroundWord.body == "alpha gamma")
  }

  @Test("visual mode extends selection and applies operators")
  func visualModeAppliesOperators() {
    let visual = VimTextEditing.handle(
      .character("v"),
      body: "alpha beta",
      selection: NSRange(location: 0, length: 0),
      state: VimEditorState(mode: .normal)
    )
    let visualWord = VimTextEditing.handle(
      .character("w"),
      body: "alpha beta",
      selection: visual.selection,
      state: visual.state
    )
    let deleted = VimTextEditing.handle(
      .character("d"),
      body: "alpha beta",
      selection: visualWord.selection,
      state: visualWord.state
    )

    #expect(visual.state.mode == .visual)
    #expect(visual.selection == NSRange(location: 0, length: 1))
    #expect(visualWord.selection == NSRange(location: 0, length: 6))
    #expect(deleted.body == "beta")
    #expect(deleted.selection == NSRange(location: 0, length: 0))
    #expect(deleted.state.mode == .normal)
  }

  @Test("yanks and pastes with the unnamed register")
  func yanksAndPastes() {
    let yankPending = VimTextEditing.handle(
      .character("y"),
      body: "alpha beta",
      selection: NSRange(location: 0, length: 0),
      state: VimEditorState(mode: .normal)
    )
    let yanked = VimTextEditing.handle(
      .character("w"),
      body: "alpha beta",
      selection: yankPending.selection,
      state: yankPending.state
    )
    let pasted = VimTextEditing.handle(
      .character("p"),
      body: "alpha beta",
      selection: NSRange(location: 10, length: 0),
      state: yanked.state
    )

    #expect(yanked.body == "alpha beta")
    #expect(yanked.state.unnamedRegister == "alpha ")
    #expect(yanked.statusMessage == "Yanked")
    #expect(pasted.body == "alpha betaalpha ")
  }

  @Test("normal mode deletes or changes an existing selection")
  func normalModeDeletesExistingSelection() {
    let deleted = VimTextEditing.handle(
      .character("x"),
      body: "alpha beta",
      selection: NSRange(location: 6, length: 4),
      state: VimEditorState(mode: .normal)
    )
    let changed = VimTextEditing.handle(
      .character("c"),
      body: "alpha beta",
      selection: NSRange(location: 0, length: 5),
      state: VimEditorState(mode: .normal)
    )
    let deleteKey = VimTextEditing.handle(
      .deleteBackward,
      body: "alpha beta",
      selection: NSRange(location: 6, length: 4),
      state: VimEditorState(mode: .normal)
    )

    #expect(deleted.body == "alpha ")
    #expect(deleted.state.mode == .normal)
    #expect(changed.body == " beta")
    #expect(changed.state.mode == .insert)
    #expect(deleteKey.body == "alpha ")
  }

  @Test("opens blank lines above and below")
  func opensBlankLines() {
    let below = VimTextEditing.handle(
      .character("o"),
      body: "one\ntwo",
      selection: NSRange(location: 1, length: 0),
      state: VimEditorState(mode: .normal)
    )
    let above = VimTextEditing.handle(
      .character("O"),
      body: "one\ntwo",
      selection: NSRange(location: 4, length: 0),
      state: VimEditorState(mode: .normal)
    )

    #expect(below.body == "one\n\ntwo")
    #expect(below.selection == NSRange(location: 4, length: 0))
    #expect(below.state.mode == .insert)
    #expect(above.body == "one\n\ntwo")
    #expect(above.selection == NSRange(location: 4, length: 0))
  }

  @Test("write command returns write action")
  func writeCommandReturnsWriteAction() {
    let commandLine = VimTextEditing.handle(
      .character(":"),
      body: "Body",
      selection: NSRange(location: 0, length: 0),
      state: VimEditorState(mode: .normal)
    )
    let typed = VimTextEditing.handle(
      .character("w"),
      body: "Body",
      selection: commandLine.selection,
      state: commandLine.state
    )
    let written = VimTextEditing.handle(
      .returnKey,
      body: "Body",
      selection: typed.selection,
      state: typed.state
    )

    #expect(written.action == .write)
    #expect(written.state.mode == .normal)
    #expect(written.statusMessage == "Saved")
  }

  @Test("calculates relative line numbers")
  func calculatesRelativeLineNumbers() {
    #expect(VimTextEditing.relativeLineNumber(lineNumber: 8, activeLineNumber: 8) == 8)
    #expect(VimTextEditing.relativeLineNumber(lineNumber: 6, activeLineNumber: 8) == 2)
    #expect(VimTextEditing.relativeLineNumber(lineNumber: 11, activeLineNumber: 8) == 3)
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

  @Test("recognizes top-level list selections that cannot outdent further")
  func recognizesTopLevelListSelection() {
    let body = "- Parent\nplain text"

    #expect(MarkdownListIndentation.applyOutdent(
      to: body,
      selection: NSRange(location: 5, length: 0)
    ) == nil)
    #expect(MarkdownListIndentation.containsListItem(
      in: body,
      selection: NSRange(location: 5, length: 0)
    ))
    #expect(!MarkdownListIndentation.containsListItem(
      in: body,
      selection: NSRange(location: 15, length: 0)
    ))
  }
}

@Suite("Markdown slash command trigger")
struct MarkdownSlashCommandTriggerTests {
  @Test("opens for a slash at a token boundary")
  func opensAtTokenBoundary() {
    #expect(MarkdownSlashCommandTrigger.context(
      in: "/",
      selection: NSRange(location: 1, length: 0)
    ) == MarkdownSlashCommandContext(triggerLocation: 0))

    #expect(MarkdownSlashCommandTrigger.context(
      in: "Hello /pla",
      selection: NSRange(location: 10, length: 0)
    ) == MarkdownSlashCommandContext(triggerLocation: 6))
  }

  @Test("ignores URLs, repeated slashes, and selections")
  func ignoresNonCommandSlashes() {
    #expect(MarkdownSlashCommandTrigger.context(
      in: "https://example.com",
      selection: NSRange(location: 8, length: 0)
    ) == nil)
    #expect(MarkdownSlashCommandTrigger.context(
      in: "//",
      selection: NSRange(location: 2, length: 0)
    ) == nil)
    #expect(MarkdownSlashCommandTrigger.context(
      in: "/command",
      selection: NSRange(location: 0, length: 8)
    ) == nil)
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

  @Test("styles empty ordered list markers")
  func stylesEmptyOrderedListMarkers() throws {
    let spans = MarkdownStyler.spans(in: "1. ")

    let marker = try #require(spans.first { $0.kind == .listMarker })
    #expect(marker.range == NSRange(location: 0, length: 2))
  }

  @Test("detects bare URLs without restyling markdown destinations")
  func detectsBareURLsWithoutRestylingMarkdownDestinations() {
    let text = """
    Visit https://example.com and [label](https://hidden.example)
    ```
    https://code.example
    ```
    """
    let nsString = text as NSString
    let linkSpans = MarkdownStyler.spans(in: text).filter { $0.kind == .link }
    let linkTexts = linkSpans.map { nsString.substring(with: $0.range) }

    #expect(linkTexts == ["https://example.com", "label"])
    #expect(linkSpans.map(\.linkDestination) == ["https://example.com", "https://hidden.example"])
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

@Suite("MarkdownTableParser")
struct MarkdownTableParserTests {
  @Test("parses pipe tables into header and body rows")
  func parsesPipeTables() throws {
    let text = """
    Intro
    | Project | Status |
    | --- | --- |
    | Lattice | Shipping |
    | Tables | Rendered |
    Outro
    """

    let table = try #require(MarkdownTableParser.tables(in: text).first)

    #expect(table.columnCount == 2)
    #expect(table.rows == [
      MarkdownTableRow(cells: ["Project", "Status"], isHeader: true),
      MarkdownTableRow(cells: ["Lattice", "Shipping"], isHeader: false),
      MarkdownTableRow(cells: ["Tables", "Rendered"], isHeader: false)
    ])
  }

  @Test("ignores table syntax inside fenced code blocks")
  func ignoresTablesInsideFencedCodeBlocks() {
    let text = """
    ```
    | Project | Status |
    | --- | --- |
    ```
    """

    #expect(MarkdownTableParser.tables(in: text).isEmpty)
  }
}

@Suite("MarkdownTableFormatter")
struct MarkdownTableFormatterTests {
  @Test("formats table columns to consistent widths")
  func formatsTableColumns() throws {
    let text = """
    | Project | Status | Notes |
    | --- | --- | --- |
    | Lattice | Ship | Preserved |
    | Markdown tables | Rendered | Easier to read |

    After
    """
    let result = try #require(MarkdownTableFormatter.formatTables(
      in: text,
      selection: NSRange(location: (text as NSString).range(of: "After").location, length: 0)
    ))

    #expect(result.body == """
    | Project         | Status   | Notes          |
    | --------------- | -------- | -------------- |
    | Lattice         | Ship     | Preserved      |
    | Markdown tables | Rendered | Easier to read |

    After
    """)
  }

  @Test("skips the active table while editing")
  func skipsActiveTable() {
    let text = """
    | Project | Status |
    | --- | --- |
    | Lattice | Ship |
    """
    let selection = NSRange(location: (text as NSString).range(of: "Status").location, length: 0)

    #expect(MarkdownTableFormatter.formatTables(in: text, selection: selection) == nil)
  }

  @Test("keeps selection stable after formatting earlier tables")
  func keepsSelectionStable() throws {
    let text = """
    | A | Longer |
    | --- | --- |
    | x | y |

    After
    """
    let selection = NSRange(location: (text as NSString).range(of: "After").location, length: 0)
    let result = try #require(MarkdownTableFormatter.formatTables(in: text, selection: selection))

    #expect((result.body as NSString).substring(with: result.selection) == "")
    #expect((result.body as NSString).substring(from: result.selection.location).hasPrefix("After"))
  }
}

@Suite("Live Markdown parser")
struct LiveMarkdownParserTests {
  @Test("finds the initial rich Markdown slice")
  func findsInitialRichMarkdownTokens() throws {
    let text = """
    # Hello World

    **bold** _italic_ `code`
    - bullet
    - [x] complete
    """
    let tokens = LiveMarkdownParser.tokens(in: text)

    #expect(tokens.contains { $0.kind == .heading(level: 1) })
    #expect(tokens.contains { $0.kind == .bold })
    #expect(tokens.contains { $0.kind == .italic })
    #expect(tokens.contains { $0.kind == .inlineCode })
    #expect(tokens.contains { $0.kind == .bullet })
    #expect(tokens.contains { $0.kind == .task(isChecked: true) })

    let bold = try #require(tokens.first { $0.kind == .bold })
    #expect((text as NSString).substring(with: bold.contentRange) == "bold")
    #expect(bold.syntaxRanges.map { (text as NSString).substring(with: $0) } == ["**", "**"])
  }

  @Test("reveals syntax only while the caret touches its construct")
  func tracksActiveSyntax() throws {
    let text = "Before **bold** after"
    let token = try #require(LiveMarkdownParser.tokens(in: text).first { $0.kind == .bold })

    #expect(!token.isActive(selection: NSRange(location: 2, length: 0)))
    #expect(token.isActive(selection: NSRange(location: token.contentRange.location, length: 0)))
    #expect(token.isActive(selection: NSRange(location: NSMaxRange(token.fullRange), length: 0)))
    #expect(!token.isActive(selection: NSRange(location: NSMaxRange(token.fullRange) + 1, length: 0)))
  }

  @Test("parses Markdown links and bare web URLs without double matching destinations")
  func parsesLinks() throws {
    let text = "Read [Lattice](https://example.com/docs) or visit https://openai.com."
    let tokens = LiveMarkdownParser.tokens(in: text)
    let markdownLink = try #require(tokens.first {
      if case .markdownLink = $0.kind { return true }
      return false
    })
    let bareLink = try #require(tokens.first {
      if case .bareLink = $0.kind { return true }
      return false
    })

    #expect(markdownLink.kind == .markdownLink(destination: "https://example.com/docs"))
    #expect((text as NSString).substring(with: markdownLink.contentRange) == "Lattice")
    #expect(markdownLink.syntaxRanges.map { (text as NSString).substring(with: $0) } == [
      "[",
      "](https://example.com/docs)"
    ])
    #expect(bareLink.kind == .bareLink(destination: "https://openai.com"))
    #expect((text as NSString).substring(with: bareLink.contentRange) == "https://openai.com")
    #expect(tokens.filter {
      if case .bareLink = $0.kind { return true }
      return false
    }.count == 1)
  }

  @Test("ignores link-looking text inside inline code")
  func ignoresLinksInCode() {
    let tokens = LiveMarkdownParser.tokens(in: "`https://example.com` and https://openai.com")

    #expect(tokens.filter {
      switch $0.kind {
      case .markdownLink, .bareLink: true
      default: false
      }
    }.count == 1)
  }

  @Test("accepts only absolute HTTP and HTTPS destinations for opening")
  func validatesOpenableLinks() {
    #expect(LiveMarkdownLinkDestination.webURL(for: "https://example.com/path")?.absoluteString
      == "https://example.com/path")
    #expect(LiveMarkdownLinkDestination.webURL(for: "HTTP://localhost:3000") != nil)
    #expect(LiveMarkdownLinkDestination.webURL(for: "javascript:alert(1)") == nil)
    #expect(LiveMarkdownLinkDestination.webURL(for: "/relative/path") == nil)
    #expect(LiveMarkdownLinkDestination.webURL(for: "https://") == nil)
  }

  @Test("parses only the requested lines in a large note")
  func parsesRequestedLinesOnly() {
    let prefix = String(repeating: "ordinary line\n", count: 20_000)
    let text = prefix + "**target**\n" + String(repeating: "ordinary line\n", count: 20_000)
    let targetRange = (text as NSString).range(of: "target")
    let tokens = LiveMarkdownParser.tokens(in: text, range: targetRange)

    #expect(tokens.count == 1)
    #expect(tokens.first?.kind == .bold)
    #expect(tokens.first?.contentRange == targetRange)
  }

  @Test("seeds an empty note with a real Markdown title")
  func seedsMarkdownTitle() {
    #expect(LiveMarkdownEditing.seededTitleInsertion(
      currentText: "",
      range: NSRange(location: 0, length: 0),
      replacement: "Hello"
    ) == "# Hello")
    #expect(LiveMarkdownEditing.seededTitleInsertion(
      currentText: "",
      range: NSRange(location: 0, length: 0),
      replacement: "### Existing"
    ) == "### Existing")
    #expect(LiveMarkdownEditing.seededTitleInsertion(
      currentText: "Body",
      range: NSRange(location: 4, length: 0),
      replacement: " text"
    ) == " text")
  }

  @Test("wraps selected text as a Markdown link and selects the destination")
  func insertsMarkdownLink() throws {
    let text = "Read Lattice today"
    let selectedRange = (text as NSString).range(of: "Lattice")
    let result = try #require(LiveMarkdownEditing.linkInsertion(
      currentText: text,
      selection: selectedRange
    ))

    let updated = (text as NSString).replacingCharacters(
      in: result.replacementRange,
      with: result.replacement
    )
    #expect(updated == "Read [Lattice](https://) today")
    #expect((updated as NSString).substring(with: result.selection) == "https://")
    #expect(LiveMarkdownEditing.linkInsertion(
      currentText: text,
      selection: NSRange(location: selectedRange.location, length: 0)
    ) == nil)
  }
}
