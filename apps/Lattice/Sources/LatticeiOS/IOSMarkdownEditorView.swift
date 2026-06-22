import LatticeEditor
import SwiftUI
import UIKit

struct IOSMarkdownEditorView: UIViewRepresentable {
  @Binding var text: String
  @Binding var command: MarkdownCommand?

  func makeUIView(context: Context) -> IOSMarkdownTextView {
    let view = IOSMarkdownTextView()
    view.delegate = context.coordinator
    view.backgroundColor = .clear
    view.font = .systemFont(ofSize: 20)
    view.textContainerInset = UIEdgeInsets(top: 28, left: 18, bottom: 28, right: 18)
    view.alwaysBounceVertical = true
    view.keyboardDismissMode = .interactive
    view.autocorrectionType = .yes
    view.smartDashesType = .no
    view.smartQuotesType = .no
    view.onTextChange = { body in
      if text != body {
        text = body
      }
    }
    view.text = text
    view.renderMarkdown()
    return view
  }

  func updateUIView(_ uiView: IOSMarkdownTextView, context: Context) {
    if uiView.text != text {
      uiView.text = text
      uiView.renderMarkdown()
    }

    if let command {
      uiView.apply(command)
      DispatchQueue.main.async {
        self.command = nil
      }
    }
  }

  func makeCoordinator() -> Coordinator {
    Coordinator()
  }

  final class Coordinator: NSObject, UITextViewDelegate {
    func textViewDidChange(_ textView: UITextView) {
      guard let textView = textView as? IOSMarkdownTextView else {
        return
      }
      textView.renderMarkdown()
      textView.onTextChange?(textView.text)
    }

    func textViewDidChangeSelection(_ textView: UITextView) {
      (textView as? IOSMarkdownTextView)?.renderMarkdown()
    }
  }
}

final class IOSMarkdownTextView: UITextView {
  var onTextChange: ((String) -> Void)?
  private var isRenderingMarkdown = false

  override func insertText(_ text: String) {
    if text == "\n",
       let edit = MarkdownListContinuation.edit(in: self.text, selectedRange: selectedRange) {
      apply(edit)
      return
    }

    super.insertText(text)
  }

  func apply(_ command: MarkdownCommand) {
    apply(MarkdownCommandProcessor.edit(for: command, in: text, selectedRange: selectedRange))
  }

  func renderMarkdown() {
    guard !isRenderingMarkdown else {
      return
    }

    let storage = textStorage
    isRenderingMarkdown = true
    let currentSelection = selectedRange
    let fullRange = NSRange(location: 0, length: storage.length)
    let plan = MarkdownRenderEngine.renderPlan(for: storage.string, selectionRanges: [currentSelection])

    storage.beginEditing()
    if storage.length > 0 {
      storage.setAttributes(baseAttributes(), range: fullRange)
      for span in plan.spans where NSMaxRange(span.range) <= storage.length {
        storage.addAttributes(attributes(for: span.style), range: span.range)
      }
    }
    storage.endEditing()

    typingAttributes = baseAttributes()
    selectedRange = currentSelection
    isRenderingMarkdown = false
  }

  private func apply(_ edit: MarkdownEdit) {
    guard let textRange = self.textRange(from: edit.replacementRange) else {
      return
    }

    replace(textRange, withText: edit.replacement)
    selectedRange = edit.selectedRange
    renderMarkdown()
    onTextChange?(text)
  }

  private func textRange(from range: NSRange) -> UITextRange? {
    guard
      let start = position(from: beginningOfDocument, offset: range.location),
      let end = position(from: start, offset: range.length)
    else {
      return nil
    }

    return textRange(from: start, to: end)
  }

  private func baseAttributes() -> [NSAttributedString.Key: Any] {
    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.lineSpacing = 5
    paragraphStyle.paragraphSpacing = 12
    return [
      .font: UIFont.systemFont(ofSize: 20, weight: .regular),
      .foregroundColor: UIColor.label,
      .paragraphStyle: paragraphStyle
    ]
  }

  private func attributes(for style: MarkdownSemanticStyle) -> [NSAttributedString.Key: Any] {
    switch style {
    case .visibleToken:
      return [
        .foregroundColor: UIColor.tertiaryLabel,
        .font: UIFont.monospacedSystemFont(ofSize: 16, weight: .regular)
      ]
    case .hiddenToken:
      return [
        .foregroundColor: UIColor.clear,
        .font: UIFont.systemFont(ofSize: 1)
      ]
    case .heading(let level):
      let sizes: [CGFloat] = [32, 28, 25, 22, 20, 19]
      let paragraphStyle = NSMutableParagraphStyle()
      paragraphStyle.paragraphSpacingBefore = level <= 2 ? 18 : 12
      paragraphStyle.paragraphSpacing = 14
      paragraphStyle.lineSpacing = 3
      return [
        .font: UIFont.systemFont(ofSize: sizes[level - 1], weight: .bold),
        .foregroundColor: UIColor.label,
        .paragraphStyle: paragraphStyle
      ]
    case .list:
      let paragraphStyle = NSMutableParagraphStyle()
      paragraphStyle.lineSpacing = 5
      paragraphStyle.paragraphSpacing = 8
      paragraphStyle.headIndent = 28
      paragraphStyle.firstLineHeadIndent = 0
      return [.paragraphStyle: paragraphStyle]
    case .bullet, .renderedBullet:
      return [
        .foregroundColor: UIColor.tintColor,
        .font: UIFont.systemFont(ofSize: 21, weight: .bold)
      ]
    case .blockQuote:
      let paragraphStyle = NSMutableParagraphStyle()
      paragraphStyle.lineSpacing = 5
      paragraphStyle.paragraphSpacing = 10
      paragraphStyle.headIndent = 20
      paragraphStyle.firstLineHeadIndent = 20
      return [
        .foregroundColor: UIColor.secondaryLabel,
        .paragraphStyle: paragraphStyle
      ]
    case .rule:
      return [
        .foregroundColor: UIColor.tertiaryLabel,
        .font: UIFont.monospacedSystemFont(ofSize: 17, weight: .medium)
      ]
    case .inlineCode:
      return [
        .font: UIFont.monospacedSystemFont(ofSize: 18, weight: .regular),
        .foregroundColor: UIColor.systemPink,
        .backgroundColor: UIColor.secondarySystemBackground
      ]
    case .codeBlock:
      let paragraphStyle = NSMutableParagraphStyle()
      paragraphStyle.lineSpacing = 3
      paragraphStyle.paragraphSpacing = 0
      return [
        .font: UIFont.monospacedSystemFont(ofSize: 18, weight: .regular),
        .foregroundColor: UIColor.label,
        .backgroundColor: UIColor.secondarySystemBackground,
        .paragraphStyle: paragraphStyle
      ]
    case .link:
      return [
        .font: UIFont.systemFont(ofSize: 20),
        .foregroundColor: UIColor.systemBlue,
        .underlineStyle: NSUnderlineStyle.single.rawValue
      ]
    case .bold:
      return [
        .font: UIFont.systemFont(ofSize: 20, weight: .semibold),
        .foregroundColor: UIColor.label
      ]
    case .italic:
      return [
        .font: UIFont.italicSystemFont(ofSize: 20),
        .foregroundColor: UIColor.label
      ]
    case .strikethrough:
      return [
        .font: UIFont.systemFont(ofSize: 20),
        .foregroundColor: UIColor.label,
        .strikethroughStyle: NSUnderlineStyle.single.rawValue
      ]
    case .completedTask:
      return [
        .foregroundColor: UIColor.secondaryLabel,
        .strikethroughStyle: NSUnderlineStyle.single.rawValue
      ]
    }
  }
}
