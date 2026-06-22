import AppKit
import LatticeEditor
import SwiftUI

struct MacMarkdownEditorView: NSViewRepresentable {
  @Binding var text: String

  func makeNSView(context: Context) -> MacMarkdownEditorContainerView {
    let view = MacMarkdownEditorContainerView()
    view.onTextChange = { body in
      if text != body {
        text = body
      }
    }
    view.setText(text)
    return view
  }

  func updateNSView(_ nsView: MacMarkdownEditorContainerView, context: Context) {
    if nsView.text != text {
      nsView.setText(text)
    }
  }
}

final class MacMarkdownEditorContainerView: NSView, NSTextViewDelegate {
  private let scrollView = NSScrollView()
  private let textView = MacMarkdownTextView()
  private var isRenderingMarkdown = false
  var onTextChange: ((String) -> Void)?

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    buildView()
    renderMarkdown()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override var isFlipped: Bool {
    true
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    DispatchQueue.main.async { [weak self] in
      guard let self else {
        return
      }
      self.window?.makeFirstResponder(self.textView)
    }
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    updateBackgroundColor()
    textView.insertionPointColor = .controlAccentColor
    renderMarkdown()
  }

  var text: String {
    textView.string
  }

  func setText(_ body: String) {
    textView.string = body
    renderMarkdown()
  }

  func textDidChange(_ notification: Notification) {
    renderMarkdown()
    onTextChange?(textView.string)
  }

  func textViewDidChangeSelection(_ notification: Notification) {
    renderMarkdown()
  }

  private func buildView() {
    wantsLayer = true
    updateBackgroundColor()

    scrollView.drawsBackground = false
    scrollView.hasVerticalScroller = true
    scrollView.hasHorizontalScroller = false
    scrollView.autohidesScrollers = true
    scrollView.translatesAutoresizingMaskIntoConstraints = false

    textView.delegate = self
    textView.string = ""
    textView.font = .systemFont(ofSize: 21, weight: .regular)
    textView.textColor = .labelColor
    textView.backgroundColor = .clear
    textView.insertionPointColor = .controlAccentColor
    textView.isRichText = false
    textView.importsGraphics = false
    textView.allowsUndo = true
    textView.usesFindPanel = true
    textView.isAutomaticDashSubstitutionEnabled = false
    textView.isAutomaticQuoteSubstitutionEnabled = false
    textView.isAutomaticTextReplacementEnabled = false
    textView.isVerticallyResizable = true
    textView.isHorizontallyResizable = false
    textView.minSize = NSSize(width: 0, height: 0)
    textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    textView.textContainerInset = NSSize(width: 36, height: 72)
    textView.textContainer?.widthTracksTextView = true
    textView.textContainer?.containerSize = NSSize(
      width: CGFloat.greatestFiniteMagnitude,
      height: CGFloat.greatestFiniteMagnitude
    )
    textView.typingAttributes = editorTypingAttributes()

    scrollView.documentView = textView
    addSubview(scrollView)

    NSLayoutConstraint.activate([
      scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
      scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
      scrollView.topAnchor.constraint(equalTo: topAnchor),
      scrollView.bottomAnchor.constraint(equalTo: bottomAnchor)
    ])
  }

  private func updateBackgroundColor() {
    effectiveAppearance.performAsCurrentDrawingAppearance {
      layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    }
  }

  private func editorTypingAttributes() -> [NSAttributedString.Key: Any] {
    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.lineSpacing = 5
    paragraphStyle.paragraphSpacing = 12

    return [
      .font: NSFont.systemFont(ofSize: 21, weight: .regular),
      .foregroundColor: NSColor.labelColor,
      .paragraphStyle: paragraphStyle
    ]
  }

  private func renderMarkdown() {
    guard !isRenderingMarkdown, let storage = textView.textStorage else {
      return
    }

    isRenderingMarkdown = true
    let selectedRanges = textView.selectedRanges.map(\.rangeValue)
    let fullRange = NSRange(location: 0, length: storage.length)
    let plan = MarkdownRenderEngine.renderPlan(for: storage.string, selectionRanges: selectedRanges)

    storage.beginEditing()
    if storage.length > 0 {
      storage.setAttributes(editorTypingAttributes(), range: fullRange)
      for span in plan.spans where NSMaxRange(span.range) <= storage.length {
        storage.addAttributes(attributes(for: span.style), range: span.range)
      }
    }
    storage.endEditing()

    textView.typingAttributes = editorTypingAttributes()
    isRenderingMarkdown = false
  }

  private func attributes(for style: MarkdownSemanticStyle) -> [NSAttributedString.Key: Any] {
    switch style {
    case .visibleToken:
      return [
        .foregroundColor: NSColor.tertiaryLabelColor,
        .font: NSFont.monospacedSystemFont(ofSize: 17, weight: .regular)
      ]
    case .hiddenToken:
      return [
        .foregroundColor: NSColor.clear,
        .font: NSFont.systemFont(ofSize: 1, weight: .regular)
      ]
    case .heading(let level):
      let sizes: [CGFloat] = [34, 30, 26, 23, 21, 20]
      let paragraphStyle = NSMutableParagraphStyle()
      paragraphStyle.paragraphSpacingBefore = level <= 2 ? 20 : 14
      paragraphStyle.paragraphSpacing = 14
      paragraphStyle.lineSpacing = 3
      return [
        .font: NSFont.systemFont(ofSize: sizes[level - 1], weight: .bold),
        .foregroundColor: NSColor.labelColor,
        .paragraphStyle: paragraphStyle
      ]
    case .list:
      let paragraphStyle = NSMutableParagraphStyle()
      paragraphStyle.lineSpacing = 5
      paragraphStyle.paragraphSpacing = 8
      paragraphStyle.headIndent = 28
      paragraphStyle.firstLineHeadIndent = 0
      return [.paragraphStyle: paragraphStyle]
    case .bullet:
      return [
        .foregroundColor: NSColor.controlAccentColor,
        .font: NSFont.systemFont(ofSize: 22, weight: .bold)
      ]
    case .renderedBullet:
      var attributes: [NSAttributedString.Key: Any] = [
        .foregroundColor: NSColor.controlAccentColor,
        .font: NSFont.systemFont(ofSize: 22, weight: .bold)
      ]
      if let glyphInfo = NSGlyphInfo(
        glyphName: "bullet",
        for: NSFont.systemFont(ofSize: 22, weight: .bold),
        baseString: "-"
      ) {
        attributes[.glyphInfo] = glyphInfo
      }
      return attributes
    case .blockQuote:
      let paragraphStyle = NSMutableParagraphStyle()
      paragraphStyle.lineSpacing = 5
      paragraphStyle.paragraphSpacing = 10
      paragraphStyle.headIndent = 20
      paragraphStyle.firstLineHeadIndent = 20
      return [
        .foregroundColor: NSColor.secondaryLabelColor,
        .paragraphStyle: paragraphStyle
      ]
    case .rule:
      return [
        .foregroundColor: NSColor.tertiaryLabelColor,
        .font: NSFont.monospacedSystemFont(ofSize: 18, weight: .medium)
      ]
    case .inlineCode:
      return [
        .font: NSFont.monospacedSystemFont(ofSize: 19, weight: .regular),
        .foregroundColor: NSColor.systemPink,
        .backgroundColor: NSColor.controlBackgroundColor.withAlphaComponent(0.8)
      ]
    case .codeBlock:
      let paragraphStyle = NSMutableParagraphStyle()
      paragraphStyle.lineSpacing = 3
      paragraphStyle.paragraphSpacing = 0
      return [
        .font: NSFont.monospacedSystemFont(ofSize: 19, weight: .regular),
        .foregroundColor: NSColor.labelColor,
        .backgroundColor: NSColor.controlBackgroundColor.withAlphaComponent(0.8),
        .paragraphStyle: paragraphStyle
      ]
    case .link:
      return [
        .font: NSFont.systemFont(ofSize: 21, weight: .regular),
        .foregroundColor: NSColor.systemBlue,
        .underlineStyle: NSUnderlineStyle.single.rawValue
      ]
    case .bold:
      return [
        .font: NSFont.systemFont(ofSize: 21, weight: .semibold),
        .foregroundColor: NSColor.labelColor
      ]
    case .italic:
      return [
        .font: NSFontManager.shared.convert(NSFont.systemFont(ofSize: 21, weight: .regular), toHaveTrait: .italicFontMask),
        .foregroundColor: NSColor.labelColor
      ]
    case .strikethrough:
      return [
        .font: NSFont.systemFont(ofSize: 21, weight: .regular),
        .foregroundColor: NSColor.labelColor,
        .strikethroughStyle: NSUnderlineStyle.single.rawValue
      ]
    case .completedTask:
      return [
        .foregroundColor: NSColor.secondaryLabelColor,
        .strikethroughStyle: NSUnderlineStyle.single.rawValue
      ]
    }
  }
}

final class MacMarkdownTextView: NSTextView {
  override var acceptsFirstResponder: Bool {
    true
  }

  override func insertNewline(_ sender: Any?) {
    if let edit = MarkdownListContinuation.edit(in: string, selectedRange: selectedRange()) {
      apply(edit)
      return
    }

    super.insertNewline(sender)
  }

  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    if modifiers == .command,
       event.charactersIgnoringModifiers?.lowercased() == "a" {
      selectAll(nil)
      return true
    }

    return super.performKeyEquivalent(with: event)
  }

  override func viewDidMoveToSuperview() {
    super.viewDidMoveToSuperview()
    if let bounds = superview?.bounds {
      frame = bounds
      minSize = bounds.size
    }
    autoresizingMask = [.width]
  }

  static func send(_ command: MarkdownCommand) {
    NSApp.sendAction(selector(for: command), to: nil, from: nil)
  }

  @objc func insertHeading(_ sender: Any?) {
    apply(.heading)
  }

  @objc func insertBold(_ sender: Any?) {
    apply(.bold)
  }

  @objc func insertItalic(_ sender: Any?) {
    apply(.italic)
  }

  @objc func insertBulletList(_ sender: Any?) {
    apply(.bulletList)
  }

  @objc func insertCode(_ sender: Any?) {
    apply(.code)
  }

  @objc func insertLink(_ sender: Any?) {
    apply(.link)
  }

  private func apply(_ command: MarkdownCommand) {
    apply(MarkdownCommandProcessor.edit(for: command, in: string, selectedRange: selectedRange()))
  }

  private func apply(_ edit: MarkdownEdit) {
    guard shouldChangeText(in: edit.replacementRange, replacementString: edit.replacement) else {
      return
    }

    textStorage?.replaceCharacters(in: edit.replacementRange, with: edit.replacement)
    setSelectedRange(edit.selectedRange)
    didChangeText()
  }

  private static func selector(for command: MarkdownCommand) -> Selector {
    switch command {
    case .heading:
      #selector(insertHeading(_:))
    case .bold:
      #selector(insertBold(_:))
    case .italic:
      #selector(insertItalic(_:))
    case .bulletList:
      #selector(insertBulletList(_:))
    case .code:
      #selector(insertCode(_:))
    case .link:
      #selector(insertLink(_:))
    }
  }
}
