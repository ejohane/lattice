import LatticeEditor
import LatticeCore
import SwiftUI

#if os(macOS)
import AppKit

public struct MarkdownTextEditor: NSViewRepresentable {
  @Binding var text: String
  @Binding var selectedRange: NSRange
  @Binding var vimState: VimEditorState
  let fontSize: CGFloat
  let focusToken: Int
  let isVimModeEnabled: Bool
  let showsRelativeLineNumbers: Bool
  let hasAutocompleteSuggestions: Bool
  let wikiLinkStates: [WikiLinkRenderState]
  let onTextChange: () -> Void
  let onSelectionChange: () -> Void
  let onWikiLinkActivated: (Int) -> Void
  let onMarkdownLinkActivated: (Int) -> Void
  let onDismissAutocomplete: () -> Void
  let onVimWrite: () -> Void
  let onVimStatusChange: (String?) -> Void

  public init(
    text: Binding<String>,
    selectedRange: Binding<NSRange>,
    vimState: Binding<VimEditorState>,
    fontSize: CGFloat,
    focusToken: Int,
    isVimModeEnabled: Bool,
    showsRelativeLineNumbers: Bool,
    hasAutocompleteSuggestions: Bool,
    wikiLinkStates: [WikiLinkRenderState],
    onTextChange: @escaping () -> Void,
    onSelectionChange: @escaping () -> Void,
    onWikiLinkActivated: @escaping (Int) -> Void,
    onMarkdownLinkActivated: @escaping (Int) -> Void,
    onDismissAutocomplete: @escaping () -> Void,
    onVimWrite: @escaping () -> Void,
    onVimStatusChange: @escaping (String?) -> Void
  ) {
    self._text = text
    self._selectedRange = selectedRange
    self._vimState = vimState
    self.fontSize = fontSize
    self.focusToken = focusToken
    self.isVimModeEnabled = isVimModeEnabled
    self.showsRelativeLineNumbers = showsRelativeLineNumbers
    self.hasAutocompleteSuggestions = hasAutocompleteSuggestions
    self.wikiLinkStates = wikiLinkStates
    self.onTextChange = onTextChange
    self.onSelectionChange = onSelectionChange
    self.onWikiLinkActivated = onWikiLinkActivated
    self.onMarkdownLinkActivated = onMarkdownLinkActivated
    self.onDismissAutocomplete = onDismissAutocomplete
    self.onVimWrite = onVimWrite
    self.onVimStatusChange = onVimStatusChange
  }

  public func makeCoordinator() -> Coordinator {
    Coordinator(parent: self)
  }

  public func makeNSView(context: Context) -> NSScrollView {
    let scrollView = NSScrollView()
    scrollView.drawsBackground = false
    scrollView.hasVerticalScroller = true
    scrollView.autohidesScrollers = true
    scrollView.contentView.postsBoundsChangedNotifications = true

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
    textView.configureLineNumberRuler(isVisible: showsRelativeLineNumbers)
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
    textView.configureLineNumberRuler(isVisible: showsRelativeLineNumbers)
    textView.invalidateVimCursor()
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
    fileprivate weak var textView: MarkdownTextView?
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
      (textView as? MarkdownTextView)?.invalidateLineNumberRuler()
      lastRenderedFontSize = parent.fontSize
      lastRenderedWikiLinkStates = parent.wikiLinkStates
      isRendering = false
    }
  }
}

private final class MarkdownTextView: NSTextView {
  weak var coordinator: MarkdownTextEditor.Coordinator?
  private var lastBlockCursorRect: NSRect?

  override func keyDown(with event: NSEvent) {
    guard let coordinator else {
      super.keyDown(with: event)
      return
    }

    if coordinator.parent.hasAutocompleteSuggestions, Self.isEscape(event) {
      coordinator.parent.onDismissAutocomplete()
      return
    }

    guard coordinator.parent.isVimModeEnabled else {
      super.keyDown(with: event)
      return
    }

    if coordinator.parent.vimState.mode == .insert, !Self.isEscape(event) {
      super.keyDown(with: event)
      return
    }

    guard let input = vimInput(from: event) else {
      super.keyDown(with: event)
      return
    }

    let result = VimTextEditing.handle(
      input,
      body: string,
      selection: selectedRange(),
      state: coordinator.parent.vimState
    )
    applyVimResult(result)
  }

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

  override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
    guard usesVimBlockCursor else {
      super.drawInsertionPoint(in: rect, color: color, turnedOn: flag)
      return
    }

    let cursorRect = blockCursorRect(fallback: rect)
    lastBlockCursorRect = cursorRect
    guard flag else {
      setNeedsDisplay(cursorRect.insetBy(dx: -1, dy: -1))
      return
    }

    NSColor.controlAccentColor.setFill()
    cursorRect.fill()
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

  private func vimInput(from event: NSEvent) -> VimKeyInput? {
    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting(.shift)
    guard flags.isEmpty else {
      return nil
    }

    if Self.isEscape(event) {
      return .escape
    }
    if event.keyCode == 36 {
      return .returnKey
    }
    if event.keyCode == 51 {
      return .deleteBackward
    }
    guard let characters = event.characters, characters.count == 1 else {
      return nil
    }
    return .character(characters)
  }

  private func applyVimResult(_ result: VimEditResult) {
    guard let coordinator else {
      return
    }

    coordinator.parent.vimState = result.state
    coordinator.parent.onVimStatusChange(result.statusMessage)

    if let replacementRange = result.replacementRange,
       let replacement = result.replacement {
      guard shouldChangeText(in: replacementRange, replacementString: replacement) else {
        return
      }
      textStorage?.replaceCharacters(in: replacementRange, with: replacement)
      setSelectedRange(result.selection)
      didChangeText()
    } else {
      setSelectedRange(clamped(result.selection, length: (string as NSString).length))
      coordinator.parent.selectedRange = selectedRange()
      coordinator.parent.onSelectionChange()
      invalidateLineNumberRuler()
    }

    if result.action == .write {
      coordinator.parent.onVimWrite()
    }
  }

  private static func isEscape(_ event: NSEvent) -> Bool {
    event.keyCode == 53
  }

  func configureLineNumberRuler(isVisible: Bool) {
    guard let scrollView = enclosingScrollView else {
      return
    }

    if isVisible {
      if !(scrollView.verticalRulerView is RelativeLineNumberRulerView) {
        scrollView.verticalRulerView = RelativeLineNumberRulerView(textView: self)
      }
      scrollView.hasVerticalRuler = true
      scrollView.rulersVisible = true
      invalidateLineNumberRuler()
    } else {
      scrollView.rulersVisible = false
      scrollView.hasVerticalRuler = false
      scrollView.verticalRulerView = nil
    }
  }

  func invalidateLineNumberRuler() {
    enclosingScrollView?.verticalRulerView?.needsDisplay = true
  }

  func invalidateVimCursor() {
    if let lastBlockCursorRect {
      setNeedsDisplay(lastBlockCursorRect.insetBy(dx: -1, dy: -1))
    }
    setNeedsDisplay(blockCursorRect(fallback: NSRect.zero).insetBy(dx: -1, dy: -1))
  }

  private var usesVimBlockCursor: Bool {
    guard
      let coordinator,
      coordinator.parent.isVimModeEnabled,
      coordinator.parent.vimState.mode == .normal,
      selectedRange().length == 0
    else {
      return false
    }
    return true
  }

  private func blockCursorRect(fallback: NSRect) -> NSRect {
    guard
      let layoutManager,
      let textContainer
    else {
      return fallback
    }

    let nsString = string as NSString
    let location = max(0, min(selectedRange().location, nsString.length))
    let bodyFont = font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
    let characterWidth = max(
      8,
      ("M" as NSString).size(withAttributes: [.font: bodyFont]).width
    )
    let lineHeight = max(16, bodyFont.ascender - bodyFont.descender + bodyFont.leading)

    guard nsString.length > 0, location < nsString.length else {
      var rect = fallback == .zero ? NSRect(x: textContainerOrigin.x, y: textContainerOrigin.y, width: characterWidth, height: lineHeight) : fallback
      rect.size.width = max(characterWidth, rect.width)
      return rect.integral
    }

    let glyphRange = layoutManager.glyphRange(
      forCharacterRange: NSRange(location: location, length: 1),
      actualCharacterRange: nil
    )
    var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
    rect.origin.x += textContainerOrigin.x
    rect.origin.y += textContainerOrigin.y
    rect.size.width = max(characterWidth, rect.width)
    rect.size.height = max(lineHeight, rect.height)

    if rect.isEmpty || !rect.origin.x.isFinite || !rect.origin.y.isFinite {
      rect = fallback
      rect.size.width = max(characterWidth, rect.width)
    }

    rect.size.width = max(2, rect.width * 0.5)
    return rect.integral
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

private final class RelativeLineNumberRulerView: NSRulerView {
  private weak var textView: NSTextView?
  private let rulerWidth: CGFloat = 44

  init(textView: NSTextView) {
    self.textView = textView
    super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
    clientView = textView
    ruleThickness = rulerWidth
  }

  @available(*, unavailable)
  required init(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override var requiredThickness: CGFloat {
    rulerWidth
  }

  override func drawHashMarksAndLabels(in rect: NSRect) {
    guard
      let textView,
      let layoutManager = textView.layoutManager,
      let textContainer = textView.textContainer
    else {
      return
    }

    NSColor.clear.setFill()
    rect.fill()

    let nsString = textView.string as NSString
    let selectedLine = lineNumber(at: textView.selectedRange().location, in: nsString)
    let visibleRect = textView.visibleRect
    let origin = textView.textContainerOrigin
    let attributes: [NSAttributedString.Key: Any] = [
      .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular),
      .foregroundColor: NSColor.secondaryLabelColor
    ]
    let activeAttributes: [NSAttributedString.Key: Any] = [
      .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
      .foregroundColor: NSColor.labelColor
    ]

    var lineNumber = 1
    var location = 0
    while location <= nsString.length {
      let lineRange = nsString.lineRange(for: NSRange(location: location, length: 0))
      let glyphRange = layoutManager.glyphRange(
        forCharacterRange: NSRange(location: lineRange.location, length: max(0, lineRange.length)),
        actualCharacterRange: nil
      )
      let lineRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
      let y = lineRect.minY + origin.y

      if y >= visibleRect.minY - 24, y <= visibleRect.maxY + 24 {
        let value = VimTextEditing.relativeLineNumber(
          lineNumber: lineNumber,
          activeLineNumber: selectedLine
        )
        draw("\(value)", y: y, attributes: lineNumber == selectedLine ? activeAttributes : attributes)
      }

      let nextLocation = NSMaxRange(lineRange)
      if nextLocation >= nsString.length {
        break
      }
      location = nextLocation
      lineNumber += 1
    }
  }

  private func draw(
    _ label: String,
    y: CGFloat,
    attributes: [NSAttributedString.Key: Any]
  ) {
    let attributed = NSAttributedString(string: label, attributes: attributes)
    let size = attributed.size()
    let point = NSPoint(
      x: max(4, bounds.width - size.width - 8),
      y: y
    )
    attributed.draw(at: point)
  }

  private func lineNumber(at location: Int, in nsString: NSString) -> Int {
    var line = 1
    var offset = 0
    let clampedLocation = max(0, min(location, nsString.length))
    while offset < clampedLocation {
      let range = nsString.lineRange(for: NSRange(location: offset, length: 0))
      let nextOffset = NSMaxRange(range)
      if nextOffset > clampedLocation || nextOffset <= offset {
        break
      }
      offset = nextOffset
      line += 1
    }
    return line
  }
}

#elseif os(iOS)
import UIKit

public struct MarkdownTextEditor: UIViewRepresentable {
  @Binding var text: String
  @Binding var selectedRange: NSRange
  @Binding var vimState: VimEditorState
  let fontSize: CGFloat
  let focusToken: Int
  let isVimModeEnabled: Bool
  let showsRelativeLineNumbers: Bool
  let hasAutocompleteSuggestions: Bool
  let wikiLinkStates: [WikiLinkRenderState]
  let onTextChange: () -> Void
  let onSelectionChange: () -> Void
  let onWikiLinkActivated: (Int) -> Void
  let onMarkdownLinkActivated: (Int) -> Void
  let onDismissAutocomplete: () -> Void
  let onVimWrite: () -> Void
  let onVimStatusChange: (String?) -> Void

  public init(
    text: Binding<String>,
    selectedRange: Binding<NSRange>,
    vimState: Binding<VimEditorState>,
    fontSize: CGFloat,
    focusToken: Int,
    isVimModeEnabled: Bool,
    showsRelativeLineNumbers: Bool,
    hasAutocompleteSuggestions: Bool,
    wikiLinkStates: [WikiLinkRenderState],
    onTextChange: @escaping () -> Void,
    onSelectionChange: @escaping () -> Void,
    onWikiLinkActivated: @escaping (Int) -> Void,
    onMarkdownLinkActivated: @escaping (Int) -> Void,
    onDismissAutocomplete: @escaping () -> Void,
    onVimWrite: @escaping () -> Void,
    onVimStatusChange: @escaping (String?) -> Void
  ) {
    self._text = text
    self._selectedRange = selectedRange
    self._vimState = vimState
    self.fontSize = fontSize
    self.focusToken = focusToken
    self.isVimModeEnabled = isVimModeEnabled
    self.showsRelativeLineNumbers = showsRelativeLineNumbers
    self.hasAutocompleteSuggestions = hasAutocompleteSuggestions
    self.wikiLinkStates = wikiLinkStates
    self.onTextChange = onTextChange
    self.onSelectionChange = onSelectionChange
    self.onWikiLinkActivated = onWikiLinkActivated
    self.onMarkdownLinkActivated = onMarkdownLinkActivated
    self.onDismissAutocomplete = onDismissAutocomplete
    self.onVimWrite = onVimWrite
    self.onVimStatusChange = onVimStatusChange
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
