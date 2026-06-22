import Foundation
import Testing
@testable import LatticeEditor

@Suite("Markdown editor engine")
struct MarkdownEditorTests {
  @Test("renders heading content and hides inactive heading token")
  func rendersHeading() {
    let source = "# Heading"
    let plan = MarkdownRenderEngine.renderPlan(for: source, selectionRanges: [
      NSRange(location: source.utf16.count, length: 0)
    ])

    #expect(plan.contains(style: .hiddenToken, substring: "#", in: source))
    #expect(plan.contains(style: .heading(level: 1), substring: "Heading", in: source))
  }

  @Test("reveals markdown tokens when selection intersects syntax")
  func revealsActiveInlineSyntax() {
    let source = "**Bold**"
    let plan = MarkdownRenderEngine.renderPlan(for: source, selectionRanges: [
      NSRange(location: 1, length: 0)
    ])

    #expect(plan.contains(style: .visibleToken, substring: "**Bold**", in: source))
    #expect(plan.contains(style: .bold, substring: "Bold", in: source))
  }

  @Test("renders inline code links emphasis and strike")
  func rendersInlineStyles() {
    let source = "`code` [link](url) *em* ~~gone~~"
    let plan = MarkdownRenderEngine.renderPlan(for: source, selectionRanges: [])

    #expect(plan.contains(style: .inlineCode, substring: "code", in: source))
    #expect(plan.contains(style: .link, substring: "link", in: source))
    #expect(plan.contains(style: .italic, substring: "em", in: source))
    #expect(plan.contains(style: .strikethrough, substring: "gone", in: source))
  }

  @Test("does not render inline styles inside code blocks")
  func skipsInlineStylesInsideCodeBlocks() {
    let source = "```\n**not bold**\n```"
    let plan = MarkdownRenderEngine.renderPlan(for: source, selectionRanges: [])

    #expect(plan.contains(style: .codeBlock, substring: "**not bold**", in: source))
    #expect(!plan.contains(style: .bold, substring: "not bold", in: source))
  }

  @Test("renders task lists and completed task content")
  func rendersTaskLists() {
    let source = "- [x] Done"
    let plan = MarkdownRenderEngine.renderPlan(for: source, selectionRanges: [])

    #expect(plan.contains(style: .renderedBullet, substring: "-", in: source))
    #expect(plan.contains(style: .hiddenToken, substring: "[x]", in: source))
    #expect(plan.contains(style: .completedTask, substring: "Done", in: source))
  }

  @Test("applies markdown commands")
  func appliesMarkdownCommands() {
    let bold = MarkdownCommandProcessor.edit(
      for: .bold,
      in: "Hello",
      selectedRange: NSRange(location: 0, length: 5)
    )
    #expect(bold.applied(to: "Hello") == "**Hello**")
    #expect(bold.selectedRange == NSRange(location: 0, length: 9))

    let link = MarkdownCommandProcessor.edit(
      for: .link,
      in: "Hello",
      selectedRange: NSRange(location: 0, length: 5)
    )
    #expect(link.applied(to: "Hello") == "[Hello](url)")
    #expect(link.selectedRange == NSRange(location: 8, length: 3))
  }

  @Test("continues unordered task and ordered lists")
  func continuesLists() {
    let taskSource = "- [x] Done"
    let taskEdit = MarkdownListContinuation.edit(
      in: taskSource,
      selectedRange: NSRange(location: taskSource.utf16.count, length: 0)
    )
    #expect(taskEdit?.replacement == "\n- [ ] ")

    let orderedSource = "7. Item"
    let orderedEdit = MarkdownListContinuation.edit(
      in: orderedSource,
      selectedRange: NSRange(location: orderedSource.utf16.count, length: 0)
    )
    #expect(orderedEdit?.replacement == "\n8. ")
  }

  @Test("removes empty list marker on return")
  func removesEmptyListMarker() {
    let source = "- "
    let edit = MarkdownListContinuation.edit(
      in: source,
      selectedRange: NSRange(location: source.utf16.count, length: 0)
    )

    #expect(edit?.replacementRange == NSRange(location: 0, length: 2))
    #expect(edit?.replacement == "")
    #expect(edit?.applied(to: source) == "")
  }
}

private extension MarkdownRenderPlan {
  func contains(
    style: MarkdownSemanticStyle,
    substring: String,
    in source: String
  ) -> Bool {
    let nsString = source as NSString
    let range = nsString.range(of: substring)
    return spans.contains { span in
      span.style == style && NSIntersectionRange(span.range, range).length > 0
    }
  }
}
