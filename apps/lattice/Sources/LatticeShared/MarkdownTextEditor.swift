import LatticeEditor
import LatticeCore
import SwiftUI

#if os(macOS)
import AppKit

public struct MarkdownTextEditor: NSViewRepresentable {
  @Binding var text: String
  @Binding var selectedRange: NSRange
  let fontSize: CGFloat
  let focusToken: Int
  let wikiLinkStates: [WikiLinkRenderState]
  let onTextChange: () -> Void
  let onSelectionChange: () -> Void
  let onWikiLinkActivated: (Int) -> Void
  let onMarkdownLinkActivated: (Int) -> Void

  public init(
    text: Binding<String>,
    selectedRange: Binding<NSRange>,
    fontSize: CGFloat,
    focusToken: Int,
    wikiLinkStates: [WikiLinkRenderState],
    onTextChange: @escaping () -> Void,
    onSelectionChange: @escaping () -> Void,
    onWikiLinkActivated: @escaping (Int) -> Void,
    onMarkdownLinkActivated: @escaping (Int) -> Void
  ) {
    self._text = text
    self._selectedRange = selectedRange
    self.fontSize = fontSize
    self.focusToken = focusToken
    self.wikiLinkStates = wikiLinkStates
    self.onTextChange = onTextChange
    self.onSelectionChange = onSelectionChange
    self.onWikiLinkActivated = onWikiLinkActivated
    self.onMarkdownLinkActivated = onMarkdownLinkActivated
  }

  public func makeCoordinator() -> Coordinator {
    Coordinator(parent: self)
  }

  public func makeNSView(context: Context) -> NSScrollView {
    let scrollView = NSScrollView()
    scrollView.drawsBackground = false
    scrollView.hasVerticalScroller = true
    scrollView.autohidesScrollers = true

    let textView = MarkdownTextView()
    textView.delegate = context.coordinator
    textView.coordinator = context.coordinator
    textView.isRichText = false
    textView.importsGraphics = false
    textView.allowsUndo = true
    textView.usesFindPanel = true
    textView.isAutomaticDashSubstitutionEnabled = false
    textView.isAutomaticQuoteSubstitutionEnabled = false
    textView.isAutomaticTextReplacementEnabled = false
    textView.backgroundColor = .clear
    textView.textColor = .labelColor
    textView.insertionPointColor = .controlAccentColor
    textView.font = MarkdownAttributedRenderer.bodyFont(size: fontSize)
    textView.textContainerInset = NSSize(width: 36, height: 34)
    textView.minSize = NSSize(width: 0, height: 0)
    textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    textView.isVerticallyResizable = true
    textView.isHorizontallyResizable = false
    textView.textContainer?.widthTracksTextView = true
    textView.textContainer?.containerSize = NSSize(
      width: CGFloat.greatestFiniteMagnitude,
      height: CGFloat.greatestFiniteMagnitude
    )
    textView.setAccessibilityIdentifier("noteEditor")

    scrollView.documentView = textView
    context.coordinator.textView = textView
    return scrollView
  }

  public func updateNSView(_ scrollView: NSScrollView, context: Context) {
    context.coordinator.parent = self
    guard let textView = context.coordinator.textView else {
      return
    }
    if textView.string != text
      || context.coordinator.lastRenderedFontSize != fontSize
      || context.coordinator.lastRenderedWikiLinkStates != wikiLinkStates {
      context.coordinator.render(text, in: textView, preserving: selectedRange)
    }
    if context.coordinator.lastFocusToken != focusToken {
      context.coordinator.lastFocusToken = focusToken
      DispatchQueue.main.async {
        textView.window?.makeFirstResponder(textView)
      }
    }
  }

  @MainActor
  public final class Coordinator: NSObject, NSTextViewDelegate {
    var parent: MarkdownTextEditor
    weak var textView: NSTextView?
    var lastFocusToken = 0
    var lastRenderedFontSize: CGFloat?
    var lastRenderedWikiLinkStates: [WikiLinkRenderState] = []
    private var isRendering = false

    init(parent: MarkdownTextEditor) {
      self.parent = parent
    }

    public func textDidChange(_ notification: Notification) {
      guard let textView = notification.object as? NSTextView, !isRendering else {
        return
      }
      parent.text = textView.string
      parent.selectedRange = textView.selectedRange()
      parent.onTextChange()
      render(textView.string, in: textView, preserving: textView.selectedRange())
    }

    public func textViewDidChangeSelection(_ notification: Notification) {
      guard let textView = notification.object as? NSTextView else {
        return
      }
      let selection = textView.selectedRange()
      parent.selectedRange = selection
      parent.onSelectionChange()
      render(textView.string, in: textView, preserving: selection)
    }

    func render(_ text: String, in textView: NSTextView, preserving selection: NSRange) {
      guard !isRendering else {
        return
      }
      isRendering = true
      let attributed = MarkdownAttributedRenderer.render(
        text,
        fontSize: parent.fontSize,
        activeRanges: [selection],
        wikiLinkStates: parent.wikiLinkStates
      )
      textView.textStorage?.setAttributedString(attributed)
      textView.setSelectedRange(clamped(selection, length: (text as NSString).length))
      textView.typingAttributes = MarkdownAttributedRenderer.baseTypingAttributes(fontSize: parent.fontSize)
      lastRenderedFontSize = parent.fontSize
      lastRenderedWikiLinkStates = parent.wikiLinkStates
      isRendering = false
    }
  }
}

private final class MarkdownTextView: NSTextView {
  weak var coordinator: MarkdownTextEditor.Coordinator?

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
    drawThematicBreaks()
  }

  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    if handlePasteboardShortcut(event) {
      return true
    }

    return super.performKeyEquivalent(with: event)
  }

  override func mouseDown(with event: NSEvent) {
    if toggleTaskCheckbox(at: event) {
      return
    }

    if let characterIndex = characterIndex(at: event),
       WikiLinkParser.link(at: characterIndex, in: string) != nil {
      coordinator?.parent.onWikiLinkActivated(characterIndex)
      return
    }

    if let characterIndex = characterIndex(at: event),
       MarkdownLocalLinkParser.link(at: characterIndex, in: string) != nil {
      coordinator?.parent.onMarkdownLinkActivated(characterIndex)
      return
    }

    super.mouseDown(with: event)
  }

  override func insertTab(_ sender: Any?) {
    if applyMarkdownListIndentation(direction: .indent) {
      return
    }

    super.insertTab(sender)
  }

  override func insertBacktab(_ sender: Any?) {
    if applyMarkdownListIndentation(direction: .outdent) {
      return
    }

    super.insertBacktab(sender)
  }

  override func insertNewline(_ sender: Any?) {
    if continueMarkdownList() {
      return
    }

    super.insertNewline(sender)
  }

  private func handlePasteboardShortcut(_ event: NSEvent) -> Bool {
    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    guard flags == .command, let key = event.charactersIgnoringModifiers?.lowercased() else {
      return false
    }

    switch key {
    case "x":
      cut(nil)
    case "c":
      copy(nil)
    case "v":
      paste(nil)
    case "a":
      selectAll(nil)
    default:
      return false
    }

    return true
  }

  private func toggleTaskCheckbox(at event: NSEvent) -> Bool {
    guard let characterIndex = characterIndex(at: event) else {
      return false
    }

    guard let result = MarkdownTaskList.toggleTask(at: characterIndex, in: string, selection: selectedRange()) else {
      return false
    }

    guard shouldChangeText(in: result.replacementRange, replacementString: result.replacement) else {
      return true
    }

    textStorage?.replaceCharacters(in: result.replacementRange, with: result.replacement)
    setSelectedRange(result.selection)
    didChangeText()
    return true
  }

  private enum IndentationDirection {
    case indent
    case outdent
  }

  private func applyMarkdownListIndentation(direction: IndentationDirection) -> Bool {
    let result: MarkdownListIndentationResult?
    switch direction {
    case .indent:
      result = MarkdownListIndentation.applyIndent(to: string, selection: selectedRange())
    case .outdent:
      result = MarkdownListIndentation.applyOutdent(to: string, selection: selectedRange())
    }

    guard let result else {
      return false
    }

    guard shouldChangeText(in: result.replacementRange, replacementString: result.replacement) else {
      return true
    }

    textStorage?.replaceCharacters(in: result.replacementRange, with: result.replacement)
    setSelectedRange(result.selection)
    didChangeText()
    return true
  }

  private func continueMarkdownList() -> Bool {
    guard let result = MarkdownListContinuation.applyReturn(to: string, selection: selectedRange()) else {
      return false
    }

    guard shouldChangeText(in: result.replacementRange, replacementString: result.replacement) else {
      return true
    }

    textStorage?.replaceCharacters(in: result.replacementRange, with: result.replacement)
    setSelectedRange(result.selection)
    didChangeText()
    return true
  }

  private func characterIndex(at event: NSEvent) -> Int? {
    guard
      let layoutManager,
      let textContainer
    else {
      return nil
    }

    var location = convert(event.locationInWindow, from: nil)
    location.x -= textContainerOrigin.x
    location.y -= textContainerOrigin.y

    let glyphIndex = layoutManager.glyphIndex(for: location, in: textContainer)
    let lineRange = layoutManager.lineFragmentUsedRect(forGlyphAt: glyphIndex, effectiveRange: nil)
    guard lineRange.contains(location) else {
      return nil
    }

    let characterIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
    return characterIndex < string.utf16.count ? characterIndex : nil
  }

  private func drawThematicBreaks() {
    guard let layoutManager, let textContainer, let textStorage else {
      return
    }

    let visibleGlyphRange = layoutManager.glyphRange(
      forBoundingRect: visibleRect.offsetBy(dx: -textContainerOrigin.x, dy: -textContainerOrigin.y),
      in: textContainer
    )
    let visibleCharacterRange = layoutManager.characterRange(
      forGlyphRange: visibleGlyphRange,
      actualGlyphRange: nil
    )

    textStorage.enumerateAttribute(.latticeThematicBreak, in: visibleCharacterRange) { value, range, _ in
      guard value as? Bool == true else {
        return
      }

      let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
      guard glyphRange.length > 0 else {
        return
      }

      let lineRect = layoutManager.lineFragmentUsedRect(forGlyphAt: glyphRange.location, effectiveRange: nil)
      let ruleWidth = max(0, bounds.width - textContainerInset.width - 2)
      let y = textContainerOrigin.y + lineRect.midY
      let pixelAlignedY = y.rounded(.down) + 0.5
      let path = NSBezierPath()
      path.lineWidth = 1
      path.move(to: NSPoint(x: textContainerOrigin.x, y: pixelAlignedY))
      path.line(to: NSPoint(x: textContainerOrigin.x + ruleWidth, y: pixelAlignedY))
      NSColor.separatorColor.withAlphaComponent(0.85).setStroke()
      path.stroke()
    }
  }
}

#elseif os(iOS)
import UIKit

public struct MarkdownTextEditor: UIViewRepresentable {
  @Binding var text: String
  @Binding var selectedRange: NSRange
  let fontSize: CGFloat
  let focusToken: Int
  let wikiLinkStates: [WikiLinkRenderState]
  let onTextChange: () -> Void
  let onSelectionChange: () -> Void
  let onWikiLinkActivated: (Int) -> Void
  let onMarkdownLinkActivated: (Int) -> Void

  public init(
    text: Binding<String>,
    selectedRange: Binding<NSRange>,
    fontSize: CGFloat,
    focusToken: Int,
    wikiLinkStates: [WikiLinkRenderState],
    onTextChange: @escaping () -> Void,
    onSelectionChange: @escaping () -> Void,
    onWikiLinkActivated: @escaping (Int) -> Void,
    onMarkdownLinkActivated: @escaping (Int) -> Void
  ) {
    self._text = text
    self._selectedRange = selectedRange
    self.fontSize = fontSize
    self.focusToken = focusToken
    self.wikiLinkStates = wikiLinkStates
    self.onTextChange = onTextChange
    self.onSelectionChange = onSelectionChange
    self.onWikiLinkActivated = onWikiLinkActivated
    self.onMarkdownLinkActivated = onMarkdownLinkActivated
  }

  public func makeCoordinator() -> Coordinator {
    Coordinator(parent: self)
  }

  public func makeUIView(context: Context) -> UITextView {
    let textView = MarkdownUIKitTextView()
    textView.delegate = context.coordinator
    textView.backgroundColor = .clear
    textView.isScrollEnabled = true
    textView.alwaysBounceVertical = true
    textView.keyboardDismissMode = .interactive
    textView.textContainerInset = UIEdgeInsets(top: 34, left: 22, bottom: 34, right: 22)
    textView.font = .preferredFont(forTextStyle: .title3)
    textView.adjustsFontForContentSizeCategory = true
    textView.autocorrectionType = .yes
    textView.smartDashesType = .no
    textView.smartQuotesType = .no
    textView.accessibilityIdentifier = "noteEditor"

    let tapRecognizer = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
    tapRecognizer.delegate = context.coordinator
    tapRecognizer.cancelsTouchesInView = true
    textView.addGestureRecognizer(tapRecognizer)

    return textView
  }

  public func updateUIView(_ textView: UITextView, context: Context) {
    context.coordinator.parent = self
    if textView.text != text || context.coordinator.lastRenderedWikiLinkStates != wikiLinkStates {
      context.coordinator.render(text, in: textView, preserving: selectedRange)
    }
    if context.coordinator.lastFocusToken != focusToken {
      context.coordinator.lastFocusToken = focusToken
      DispatchQueue.main.async {
        textView.becomeFirstResponder()
      }
    }
  }

  @MainActor
  public final class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate {
    var parent: MarkdownTextEditor
    var lastFocusToken = 0
    var lastRenderedWikiLinkStates: [WikiLinkRenderState] = []
    private var isRendering = false

    init(parent: MarkdownTextEditor) {
      self.parent = parent
    }

    public func textViewDidChange(_ textView: UITextView) {
      guard !isRendering else {
        return
      }
      parent.text = textView.text
      parent.selectedRange = textView.selectedRange
      parent.onTextChange()
      render(textView.text, in: textView, preserving: textView.selectedRange)
    }

    public func textViewDidChangeSelection(_ textView: UITextView) {
      parent.selectedRange = textView.selectedRange
      parent.onSelectionChange()
    }

    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
      guard
        let textView = gestureRecognizer.view as? UITextView,
        let location = textView.characterIndex(at: touch.location(in: textView))
      else {
        return false
      }

      return MarkdownTaskList.toggleTask(at: location, in: textView.text, selection: textView.selectedRange) != nil
        || WikiLinkParser.link(at: location, in: textView.text) != nil
        || MarkdownLocalLinkParser.link(at: location, in: textView.text) != nil
    }

    @objc func handleTap(_ gesture: UITapGestureRecognizer) {
      guard
        gesture.state == .ended,
        let textView = gesture.view as? UITextView,
        let location = textView.characterIndex(at: gesture.location(in: textView))
      else {
        return
      }

      if WikiLinkParser.link(at: location, in: textView.text) != nil {
        parent.onWikiLinkActivated(location)
        return
      }

      if MarkdownLocalLinkParser.link(at: location, in: textView.text) != nil {
        parent.onMarkdownLinkActivated(location)
        return
      }

      guard let result = MarkdownTaskList.toggleTask(at: location, in: textView.text, selection: textView.selectedRange) else {
        return
      }

      textView.textStorage.replaceCharacters(in: result.replacementRange, with: result.replacement)
      textView.selectedRange = result.selection
      parent.text = textView.text
      parent.selectedRange = textView.selectedRange
      parent.onTextChange()
      render(textView.text, in: textView, preserving: textView.selectedRange)
    }

    func render(_ text: String, in textView: UITextView, preserving selection: NSRange) {
      guard !isRendering else {
        return
      }
      isRendering = true
      textView.attributedText = MarkdownAttributedRenderer.render(text, wikiLinkStates: parent.wikiLinkStates)
      textView.selectedRange = clamped(selection, length: (text as NSString).length)
      textView.typingAttributes = MarkdownAttributedRenderer.baseTypingAttributes()
      lastRenderedWikiLinkStates = parent.wikiLinkStates
      isRendering = false
    }
  }
}

private extension UITextView {
  func characterIndex(at point: CGPoint) -> Int? {
    guard let position = closestPosition(to: point) else {
      return nil
    }

    let index = offset(from: beginningOfDocument, to: position)
    guard index >= 0 && index < (text as NSString).length else {
      return nil
    }

    return index
  }
}

private final class MarkdownUIKitTextView: UITextView {
  override func draw(_ rect: CGRect) {
    super.draw(rect)
    drawThematicBreaks()
  }

  private func drawThematicBreaks() {
    guard let context = UIGraphicsGetCurrentContext() else {
      return
    }

    let visibleBounds = bounds.inset(by: textContainerInset)
    let visibleGlyphRange = layoutManager.glyphRange(
      forBoundingRect: visibleBounds.offsetBy(dx: -textContainerInset.left, dy: -textContainerInset.top),
      in: textContainer
    )
    let visibleCharacterRange = layoutManager.characterRange(
      forGlyphRange: visibleGlyphRange,
      actualGlyphRange: nil
    )

    textStorage.enumerateAttribute(.latticeThematicBreak, in: visibleCharacterRange) { value, range, _ in
      guard value as? Bool == true else {
        return
      }

      let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
      guard glyphRange.length > 0 else {
        return
      }

      let lineRect = layoutManager.lineFragmentUsedRect(forGlyphAt: glyphRange.location, effectiveRange: nil)
      let y = textContainerInset.top + lineRect.midY
      let startX = textContainerInset.left + textContainer.lineFragmentPadding
      let endX = bounds.width - textContainerInset.right - textContainer.lineFragmentPadding
      context.setStrokeColor(UIColor.separator.withAlphaComponent(0.85).cgColor)
      context.setLineWidth(1 / UIScreen.main.scale)
      context.move(to: CGPoint(x: startX, y: y))
      context.addLine(to: CGPoint(x: endX, y: y))
      context.strokePath()
    }
  }
}
#endif

private func clamped(_ range: NSRange, length: Int) -> NSRange {
  let location = max(0, min(range.location, length))
  return NSRange(location: location, length: max(0, min(range.length, length - location)))
}
