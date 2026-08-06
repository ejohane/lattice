import AppKit
import LatticeEditor

@MainActor
final class LiveMarkdownTextView: NSTextView {
  static func makeForEditing() -> LiveMarkdownTextView {
    // The live presentation layer rewrites NSTextStorage attributes after edits.
    // TextKit 2 can crash during a concurrent viewport layout with an invalid
    // NSRLEArray run index, so keep this editor on TextKit 1's layout manager.
    LiveMarkdownTextView(usingTextLayoutManager: false)
  }

  var presentationDecorations: [LiveMarkdownDecoration] = []
  var presentationLinks: [LiveMarkdownLinkTarget] = [] {
    didSet {
      guard let window else { return }
      window.invalidateCursorRects(for: self)
    }
  }
  var onTaskToggle: ((Int) -> Void)?
  var onInsertLink: (() -> Void)?
  var onOpenLink: ((LiveMarkdownLinkTarget.Destination) -> Void)?
  var onFocusChange: ((Bool) -> Void)?
  var onCancelSlashCommandPalette: (() -> Bool)?
  var onMoveEditorCompletion: ((Int) -> Bool)?
  var onCommitEditorCompletion: (() -> Bool)?
  var onCancelEditorCompletion: (() -> Bool)?
  var onSubmit: (() -> Void)?
  var onCancel: (() -> Void)?
  var seedsTitleOnFirstInsertion = true

  private var taskHitTargets: [(range: NSRange, rect: NSRect)] = []

  override func insertText(_ insertString: Any, replacementRange: NSRange) {
    let replacement: String
    if let attributed = insertString as? NSAttributedString {
      replacement = attributed.string
    } else {
      replacement = String(describing: insertString)
    }

    let selection = selectedRange()
    let hasStaleTypingRange = !hasMarkedText()
      && selection.length == 0
      && replacementRange.length == 0
      && replacementRange.location != selection.location
    let effectiveRange = replacementRange.location == NSNotFound || hasStaleTypingRange
      ? selection
      : replacementRange
    let seeded = seedsTitleOnFirstInsertion
      ? LiveMarkdownEditing.seededTitleInsertion(
        currentText: string,
        range: effectiveRange,
        replacement: replacement
      )
      : replacement
    super.insertText(seeded, replacementRange: effectiveRange)
    if !hasMarkedText() {
      let nextLocation = min(
        effectiveRange.location + (seeded as NSString).length,
        (string as NSString).length
      )
      setSelectedRange(NSRange(location: nextLocation, length: 0))
    }
  }

  override func becomeFirstResponder() -> Bool {
    let becameFirstResponder = super.becomeFirstResponder()
    if becameFirstResponder {
      onFocusChange?(true)
    }
    return becameFirstResponder
  }

  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    if modifiers.contains(.command),
       !modifiers.contains(.option),
       !modifiers.contains(.control),
       (event.keyCode == 36 || event.keyCode == 76),
       let onSubmit {
      onSubmit()
      return true
    }
    if modifiers.contains(.command),
       !modifiers.contains(.option),
       !modifiers.contains(.control),
       event.charactersIgnoringModifiers?.lowercased() == "k",
       let onInsertLink {
      onInsertLink()
      return true
    }
    return super.performKeyEquivalent(with: event)
  }

  override func insertTab(_ sender: Any?) {
    if onCommitEditorCompletion?() == true {
      return
    }
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

  override func moveUp(_ sender: Any?) {
    if onMoveEditorCompletion?(-1) == true { return }
    super.moveUp(sender)
  }

  override func moveDown(_ sender: Any?) {
    if onMoveEditorCompletion?(1) == true { return }
    super.moveDown(sender)
  }

  override func cancelOperation(_ sender: Any?) {
    if onCancelEditorCompletion?() == true {
      return
    }
    if onCancelSlashCommandPalette?() == true {
      return
    }
    if let onCancel {
      onCancel()
      return
    }

    super.cancelOperation(sender)
  }

  override func resignFirstResponder() -> Bool {
    let resignedFirstResponder = super.resignFirstResponder()
    if resignedFirstResponder {
      onFocusChange?(false)
    }
    return resignedFirstResponder
  }

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
    taskHitTargets = []

    for decoration in presentationDecorations {
      switch decoration.kind {
      case .bullet:
        guard let markerRect = localRect(for: decoration.range), markerRect.intersects(dirtyRect) else {
          continue
        }
        drawBullet(in: markerRect, usesOutline: decoration.usesOutline)
      case .task(let isChecked):
        guard let markerRect = localRect(for: decoration.range), markerRect.intersects(dirtyRect) else {
          continue
        }
        let checkboxRect = drawTask(in: markerRect, isChecked: isChecked)
        taskHitTargets.append((decoration.range, checkboxRect.insetBy(dx: -4, dy: -4)))
      case .thematicBreak:
        guard let markerRect = localRect(for: decoration.range), markerRect.intersects(dirtyRect) else {
          continue
        }
        drawThematicBreak(in: markerRect)
      case .blockquote(let level):
        guard let quoteRect = blockquoteRect(for: decoration.range, level: level),
              quoteRect.intersects(dirtyRect)
        else { continue }
        drawBlockquote(in: quoteRect, level: level)
      }
    }
  }

  func prepareForDecorationDrawing() {
    guard let layoutManager, let textContainer else { return }
    layoutManager.ensureLayout(for: textContainer)
  }

  override func mouseDown(with event: NSEvent) {
    let location = convert(event.locationInWindow, from: nil)
    if let target = taskHitTargets.first(where: { $0.rect.contains(location) }) {
      onTaskToggle?(target.range.location)
      return
    }
    let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    if event.clickCount == 1,
       !modifiers.contains(.option),
       activateLink(at: characterIndexForInsertion(at: location)) {
      return
    }
    super.mouseDown(with: event)
  }

  @discardableResult
  func activateLink(at characterIndex: Int) -> Bool {
    guard let target = linkTarget(at: characterIndex) else { return false }
    onOpenLink?(target.destination)
    return true
  }

  override func resetCursorRects() {
    super.resetCursorRects()
    for target in taskHitTargets {
      addCursorRect(target.rect, cursor: .pointingHand)
    }
    for target in presentationLinks {
      guard let rect = localRect(for: target.range) else { continue }
      addCursorRect(rect, cursor: .pointingHand)
    }
  }

  private func localRect(for range: NSRange) -> NSRect? {
    guard range.location != NSNotFound,
          range.location < (string as NSString).length,
          let window
    else { return nil }

    var actualRange = NSRange(location: NSNotFound, length: 0)
    let screenRect = firstRect(forCharacterRange: range, actualRange: &actualRange)
    guard !screenRect.isEmpty, actualRange.location != NSNotFound else { return nil }
    let windowRect = window.convertFromScreen(screenRect)
    return convert(windowRect, from: nil)
  }

  private func blockquoteRect(for range: NSRange, level: Int) -> NSRect? {
    guard range.location != NSNotFound,
          range.location < (string as NSString).length,
          let layoutManager
    else { return nil }

    // `draw(_:)` is already called after AppKit has prepared the visible
    // layout. Forcing layout here can invalidate the same text view while it
    // is being drawn, which produces a visible flash after each edit.
    let lastCharacter = min(NSMaxRange(range) - 1, (string as NSString).length - 1)
    guard lastCharacter >= range.location else { return nil }
    let firstGlyphRange = layoutManager.glyphRange(
      forCharacterRange: NSRange(location: range.location, length: 1),
      actualCharacterRange: nil
    )
    let lastGlyphRange = layoutManager.glyphRange(
      forCharacterRange: NSRange(location: lastCharacter, length: 1),
      actualCharacterRange: nil
    )
    guard firstGlyphRange.location != NSNotFound,
          lastGlyphRange.location != NSNotFound
    else { return nil }

    let firstLine = layoutManager.lineFragmentRect(
      forGlyphAt: firstGlyphRange.location,
      effectiveRange: nil
    )
    let lastLine = layoutManager.lineFragmentRect(
      forGlyphAt: lastGlyphRange.location,
      effectiveRange: nil
    )
    let origin = textContainerOrigin
    let x = origin.x
      + LiveMarkdownQuoteLayout.barIndent
      + CGFloat(max(0, level - 1)) * LiveMarkdownQuoteLayout.levelSpacing
    let y = origin.y + firstLine.minY
    return NSRect(
      x: x,
      y: y,
      width: 3,
      height: max(1, origin.y + lastLine.maxY - y)
    )
  }

  private func linkTarget(at characterIndex: Int) -> LiveMarkdownLinkTarget? {
    presentationLinks.first { NSLocationInRange(characterIndex, $0.range) }
  }

  private enum IndentationDirection: Equatable {
    case indent
    case outdent
  }

  private func applyMarkdownListIndentation(
    direction: IndentationDirection
  ) -> Bool {
    let source = string
    let selection = selectedRange()
    let result: MarkdownListIndentationResult?
    switch direction {
    case .indent:
      result = MarkdownListIndentation.applyIndent(
        to: source,
        selection: selection
      )
    case .outdent:
      result = MarkdownListIndentation.applyOutdent(
        to: source,
        selection: selection
      )
    }

    guard let result else {
      return direction == .outdent
        && MarkdownListIndentation.containsListItem(
          in: source,
          selection: selection
        )
    }
    guard shouldChangeText(
      in: result.replacementRange,
      replacementString: result.replacement
    ) else { return true }

    textStorage?.replaceCharacters(
      in: result.replacementRange,
      with: result.replacement
    )
    setSelectedRange(result.selection)
    didChangeText()
    return true
  }

  private func drawBullet(in markerRect: NSRect, usesOutline: Bool) {
    let diameter: CGFloat = usesOutline ? 9 : 5
    let rect = NSRect(
      x: markerRect.midX - diameter / 2,
      y: markerRect.midY - diameter / 2,
      width: diameter,
      height: diameter
    )
    if usesOutline {
      let outline = NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1))
      outline.lineWidth = 2
      NSColor.controlAccentColor.setStroke()
      outline.stroke()
    } else {
      NSColor.controlAccentColor.setFill()
      NSBezierPath(ovalIn: rect).fill()
    }
  }

  private func drawThematicBreak(in markerRect: NSRect) {
    let pixelAlignedY = markerRect.midY.rounded(.down) + 0.5
    let path = NSBezierPath()
    path.lineWidth = 1
    path.move(to: NSPoint(x: bounds.minX + 1, y: pixelAlignedY))
    path.line(to: NSPoint(x: bounds.maxX - 1, y: pixelAlignedY))
    NSColor.separatorColor.withAlphaComponent(0.85).setStroke()
    path.stroke()
  }

  private func drawBlockquote(in markerRect: NSRect, level _: Int) {
    let bar = NSBezierPath(
      roundedRect: markerRect,
      xRadius: markerRect.width / 2,
      yRadius: markerRect.width / 2
    )
    NSColor.controlAccentColor.setFill()
    bar.fill()
  }

  @discardableResult
  private func drawTask(in markerRect: NSRect, isChecked: Bool) -> NSRect {
    let size: CGFloat = 24
    let rect = NSRect(
      x: markerRect.midX - size / 2,
      y: markerRect.midY - size / 2,
      width: size,
      height: size
    )
    let symbolName = isChecked ? "checkmark.square" : "square"
    guard let image = NSImage(
      systemSymbolName: symbolName,
      accessibilityDescription: isChecked ? "Completed task" : "Incomplete task"
    ) else { return rect }

    let configuration = NSImage.SymbolConfiguration(
      pointSize: 22,
      weight: .regular,
      scale: .medium
    ).applying(
      NSImage.SymbolConfiguration(paletteColors: [NSColor.secondaryLabelColor])
    )
    let configuredImage = image.withSymbolConfiguration(configuration) ?? image
    let context = NSGraphicsContext.current?.cgContext
    context?.saveGState()
    context?.translateBy(x: rect.midX, y: rect.midY)
    context?.scaleBy(x: 1, y: -1)
    context?.translateBy(x: -rect.midX, y: -rect.midY)
    configuredImage.draw(
      in: rect,
      from: .zero,
      operation: .sourceOver,
      fraction: 1
    )
    context?.restoreGState()
    return rect
  }
}
