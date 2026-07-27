import AppKit
import LatticeEditor

@MainActor
final class LiveMarkdownTextView: NSTextView {
  var presentationDecorations: [LiveMarkdownDecoration] = [] {
    didSet { needsDisplay = true }
  }
  var presentationLinks: [LiveMarkdownLinkTarget] = [] {
    didSet {
      guard let window else { return }
      window.invalidateCursorRects(for: self)
    }
  }
  var onTaskToggle: ((Int) -> Void)?
  var onInsertLink: (() -> Void)?
  var onOpenLink: ((URL) -> Void)?
  var onFocusChange: ((Bool) -> Void)?

  private var taskHitTargets: [(range: NSRange, rect: NSRect)] = []

  override func insertText(_ insertString: Any, replacementRange: NSRange) {
    let replacement: String
    if let attributed = insertString as? NSAttributedString {
      replacement = attributed.string
    } else {
      replacement = String(describing: insertString)
    }

    let effectiveRange = replacementRange.location == NSNotFound
      ? selectedRange()
      : replacementRange
    let seeded = LiveMarkdownEditing.seededTitleInsertion(
      currentText: string,
      range: effectiveRange,
      replacement: replacement
    )
    super.insertText(seeded, replacementRange: effectiveRange)
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
       event.charactersIgnoringModifiers?.lowercased() == "k",
       let onInsertLink {
      onInsertLink()
      return true
    }
    return super.performKeyEquivalent(with: event)
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
      guard let markerRect = localRect(for: decoration.range), markerRect.intersects(dirtyRect) else {
        continue
      }
      switch decoration.kind {
      case .bullet:
        drawBullet(in: markerRect)
      case .task(let isChecked):
        let checkboxRect = drawTask(in: markerRect, isChecked: isChecked)
        taskHitTargets.append((decoration.range, checkboxRect.insetBy(dx: -4, dy: -4)))
      }
    }
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
       let target = linkTarget(at: characterIndexForInsertion(at: location)) {
      onOpenLink?(target.url)
      return
    }
    super.mouseDown(with: event)
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

  private func drawBullet(in markerRect: NSRect) {
    let diameter: CGFloat = 5
    let rect = NSRect(
      x: markerRect.midX - diameter / 2,
      y: markerRect.midY - diameter / 2,
      width: diameter,
      height: diameter
    )
    NSColor.controlAccentColor.setFill()
    NSBezierPath(ovalIn: rect).fill()
  }

  @discardableResult
  private func drawTask(in markerRect: NSRect, isChecked: Bool) -> NSRect {
    let size: CGFloat = 14
    let rect = NSRect(
      x: markerRect.midX - size / 2,
      y: markerRect.midY - size / 2,
      width: size,
      height: size
    )
    let outline = NSBezierPath(roundedRect: rect, xRadius: 3.5, yRadius: 3.5)
    outline.lineWidth = 1.4

    if isChecked {
      NSColor.controlAccentColor.setFill()
      outline.fill()
      NSColor.white.setStroke()
      let check = NSBezierPath()
      check.lineWidth = 1.7
      check.lineCapStyle = .round
      check.lineJoinStyle = .round
      check.move(to: NSPoint(x: rect.minX + 3.2, y: rect.midY))
      check.line(to: NSPoint(x: rect.minX + 6.1, y: rect.minY + 3.5))
      check.line(to: NSPoint(x: rect.maxX - 2.7, y: rect.maxY - 3.1))
      check.stroke()
    } else {
      NSColor.tertiaryLabelColor.setStroke()
      outline.stroke()
    }
    return rect
  }
}
