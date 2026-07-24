import LatticeEditor
import SwiftUI

#if os(macOS)
import AppKit

public struct RawMarkdownEditor: NSViewRepresentable {
  @Binding fileprivate var text: String
  @Binding fileprivate var selectedRange: NSRange
  @Binding fileprivate var vimState: VimEditorState
  fileprivate let fontSize: CGFloat
  fileprivate let focusToken: Int
  fileprivate let isVimModeEnabled: Bool
  fileprivate let showsRelativeLineNumbers: Bool
  fileprivate let theme: LatticeTheme
  fileprivate let keyboardAccessoryActions: [MarkdownKeyboardAccessoryAction]
  fileprivate let onTextChange: () -> Void
  fileprivate let onSelectionChange: () -> Void
  fileprivate let onVimWrite: () -> Void

  public init(
    text: Binding<String>,
    selectedRange: Binding<NSRange>,
    vimState: Binding<VimEditorState>,
    fontSize: CGFloat,
    focusToken: Int,
    isVimModeEnabled: Bool,
    showsRelativeLineNumbers: Bool,
    theme: LatticeTheme,
    keyboardAccessoryActions: [MarkdownKeyboardAccessoryAction] = [],
    onTextChange: @escaping () -> Void,
    onSelectionChange: @escaping () -> Void,
    onVimWrite: @escaping () -> Void
  ) {
    self._text = text
    self._selectedRange = selectedRange
    self._vimState = vimState
    self.fontSize = fontSize
    self.focusToken = focusToken
    self.isVimModeEnabled = isVimModeEnabled
    self.showsRelativeLineNumbers = showsRelativeLineNumbers
    self.theme = theme
    self.keyboardAccessoryActions = keyboardAccessoryActions
    self.onTextChange = onTextChange
    self.onSelectionChange = onSelectionChange
    self.onVimWrite = onVimWrite
  }

  public func makeCoordinator() -> Coordinator {
    Coordinator(parent: self)
  }

  public func makeNSView(context: Context) -> NSScrollView {
    let scrollView = NSScrollView()
    scrollView.hasVerticalScroller = true
    scrollView.hasHorizontalScroller = false
    scrollView.autohidesScrollers = true
    scrollView.drawsBackground = true
    scrollView.backgroundColor = theme.nsColor(.editorBackground)

    let textView = RawMarkdownTextView()
    textView.rawCoordinator = context.coordinator
    textView.delegate = context.coordinator
    textView.isRichText = false
    textView.importsGraphics = false
    textView.allowsUndo = true
    textView.usesFindPanel = true
    textView.isEditable = true
    textView.isSelectable = true
    textView.isAutomaticDashSubstitutionEnabled = false
    textView.isAutomaticQuoteSubstitutionEnabled = false
    textView.isAutomaticTextReplacementEnabled = false
    textView.isAutomaticSpellingCorrectionEnabled = false
    textView.drawsBackground = true
    textView.textContainerInset = NSSize(width: 36, height: 34)
    textView.minSize = .zero
    textView.maxSize = NSSize(
      width: CGFloat.greatestFiniteMagnitude,
      height: CGFloat.greatestFiniteMagnitude
    )
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
    context.coordinator.synchronizeText(text, selection: selectedRange, in: textView)
    context.coordinator.applyAppearance(to: textView, scrollView: scrollView)
    textView.configureRelativeLineNumbers(showsRelativeLineNumbers)
    return scrollView
  }

  public func updateNSView(_ scrollView: NSScrollView, context: Context) {
    context.coordinator.parent = self
    guard let textView = context.coordinator.textView else {
      return
    }

    if textView.string != text {
      context.coordinator.synchronizeText(text, selection: selectedRange, in: textView)
    } else {
      let selection = rawClampedRange(selectedRange, length: (text as NSString).length)
      if textView.selectedRange() != selection {
        context.coordinator.synchronizeSelection(selection, in: textView)
      }
    }

    context.coordinator.applyAppearance(to: textView, scrollView: scrollView)
    textView.configureRelativeLineNumbers(showsRelativeLineNumbers)
    textView.needsDisplay = true

    if context.coordinator.lastFocusToken != focusToken {
      context.coordinator.lastFocusToken = focusToken
      DispatchQueue.main.async { [weak textView] in
        guard let textView else { return }
        textView.window?.makeFirstResponder(textView)
        textView.scrollRangeToVisible(textView.selectedRange())
      }
    }
  }

  @MainActor
  public final class Coordinator: NSObject, NSTextViewDelegate {
    fileprivate var parent: RawMarkdownEditor
    fileprivate weak var textView: RawMarkdownTextView?
    fileprivate var lastFocusToken = 0
    fileprivate var isSynchronizing = false

    fileprivate init(parent: RawMarkdownEditor) {
      self.parent = parent
    }

    fileprivate func synchronizeText(
      _ text: String,
      selection: NSRange,
      in textView: RawMarkdownTextView
    ) {
      isSynchronizing = true
      textView.string = text
      applyTextAttributes(to: textView)
      textView.setSelectedRange(rawClampedRange(selection, length: (text as NSString).length))
      textView.invalidateRelativeLineNumbers()
      isSynchronizing = false
    }

    fileprivate func synchronizeSelection(_ selection: NSRange, in textView: RawMarkdownTextView) {
      isSynchronizing = true
      textView.setSelectedRange(selection)
      textView.invalidateRelativeLineNumbers()
      isSynchronizing = false
    }

    fileprivate func applyAppearance(to textView: RawMarkdownTextView, scrollView: NSScrollView) {
      let backgroundColor = parent.theme.nsColor(.editorBackground)
      let textColor = parent.theme.nsColor(.primaryText)
      textView.rawTheme = parent.theme
      textView.backgroundColor = backgroundColor
      textView.textColor = textColor
      textView.insertionPointColor = parent.theme.nsColor(.accent)
      scrollView.backgroundColor = backgroundColor
      scrollView.contentView.backgroundColor = backgroundColor
      scrollView.contentView.drawsBackground = true
      applyTextAttributes(to: textView)
      textView.invalidateRelativeLineNumbers()
    }

    private func applyTextAttributes(to textView: NSTextView) {
      let font = NSFont.monospacedSystemFont(ofSize: parent.fontSize, weight: .regular)
      let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: parent.theme.nsColor(.primaryText)
      ]
      textView.font = font
      textView.textColor = parent.theme.nsColor(.primaryText)
      guard !textView.hasMarkedText() else {
        textView.typingAttributes = attributes
        return
      }
      if let textStorage = textView.textStorage, textStorage.length > 0 {
        textStorage.setAttributes(attributes, range: NSRange(location: 0, length: textStorage.length))
        let hiddenAttributes: [NSAttributedString.Key: Any] = [
          .font: NSFont.monospacedSystemFont(ofSize: 0.1, weight: .regular),
          .foregroundColor: NSColor.clear
        ]
        for range in rawLatticeMetadataRanges(in: textView.string) {
          textStorage.addAttributes(hiddenAttributes, range: range)
        }
      }
      textView.typingAttributes = attributes
    }

    public func textDidChange(_ notification: Notification) {
      guard let textView = notification.object as? RawMarkdownTextView, !isSynchronizing else {
        return
      }
      parent.text = textView.string
      parent.selectedRange = textView.selectedRange()
      isSynchronizing = true
      applyTextAttributes(to: textView)
      isSynchronizing = false
      textView.invalidateRelativeLineNumbers()
      parent.onTextChange()
    }

    public func textViewDidChangeSelection(_ notification: Notification) {
      guard let textView = notification.object as? RawMarkdownTextView, !isSynchronizing else {
        return
      }
      parent.selectedRange = textView.selectedRange()
      textView.invalidateRelativeLineNumbers()
      textView.needsDisplay = true
      parent.onSelectionChange()
    }
  }
}

@MainActor
private final class RawMarkdownTextView: NSTextView {
  weak var rawCoordinator: RawMarkdownEditor.Coordinator?
  var rawTheme = LatticeTheme(id: .system)

  override func keyDown(with event: NSEvent) {
    guard let rawCoordinator, rawCoordinator.parent.isVimModeEnabled else {
      super.keyDown(with: event)
      return
    }

    if rawCoordinator.parent.vimState.mode == .insert, event.keyCode != 53 {
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
      state: rawCoordinator.parent.vimState
    )
    applyVimResult(result, coordinator: rawCoordinator)
  }

  override func drawInsertionPoint(
    in rect: NSRect,
    color: NSColor,
    turnedOn flag: Bool
  ) {
    guard showsVimNormalCursor else {
      super.drawInsertionPoint(in: rect, color: color, turnedOn: flag)
      return
    }
    guard flag else { return }

    rawTheme.nsColor(.accent).setFill()
    halfWidthCursorRect(fallback: rect).fill()
  }

  override func setNeedsDisplay(_ rect: NSRect, avoidAdditionalLayout flag: Bool) {
    guard showsVimNormalCursor else {
      super.setNeedsDisplay(rect, avoidAdditionalLayout: flag)
      return
    }
    super.setNeedsDisplay(rect.insetBy(dx: -8, dy: -1), avoidAdditionalLayout: flag)
  }

  fileprivate func configureRelativeLineNumbers(_ isVisible: Bool) {
    guard let scrollView = enclosingScrollView else { return }
    if isVisible {
      if !(scrollView.verticalRulerView is RawRelativeLineNumberRulerView) {
        scrollView.verticalRulerView = RawRelativeLineNumberRulerView(textView: self)
      }
      scrollView.hasVerticalRuler = true
      scrollView.rulersVisible = true
      invalidateRelativeLineNumbers()
    } else {
      scrollView.rulersVisible = false
      scrollView.hasVerticalRuler = false
      scrollView.verticalRulerView = nil
    }
  }

  fileprivate func invalidateRelativeLineNumbers() {
    enclosingScrollView?.verticalRulerView?.needsDisplay = true
  }

  fileprivate var showsVimNormalCursor: Bool {
    guard let rawCoordinator else { return false }
    return rawCoordinator.parent.isVimModeEnabled
      && rawCoordinator.parent.vimState.mode == .normal
  }

  private func vimInput(from event: NSEvent) -> VimKeyInput? {
    let flags = event.modifierFlags
      .intersection(.deviceIndependentFlagsMask)
      .subtracting(.shift)
    guard flags.isEmpty else { return nil }

    switch event.keyCode {
    case 53:
      return .escape
    case 36, 76:
      return .returnKey
    case 51:
      return .deleteBackward
    default:
      guard let characters = event.characters, characters.count == 1 else { return nil }
      return .character(characters)
    }
  }

  private func applyVimResult(
    _ result: VimEditResult,
    coordinator: RawMarkdownEditor.Coordinator
  ) {
    coordinator.parent.vimState = result.state

    if let replacementRange = result.replacementRange,
       let replacement = result.replacement {
      guard shouldChangeText(in: replacementRange, replacementString: replacement) else {
        return
      }
      textStorage?.replaceCharacters(in: replacementRange, with: replacement)
      setSelectedRange(rawClampedRange(result.selection, length: (string as NSString).length))
      didChangeText()
    } else {
      setSelectedRange(rawClampedRange(result.selection, length: (string as NSString).length))
      coordinator.parent.selectedRange = selectedRange()
      coordinator.parent.onSelectionChange()
      invalidateRelativeLineNumbers()
      needsDisplay = true
    }

    if result.action == .write {
      coordinator.parent.onVimWrite()
    }
  }

  private func halfWidthCursorRect(fallback: NSRect) -> NSRect {
    let location = min(selectedRange().location, (string as NSString).length)
    var characterWidth = max(4, (font ?? .monospacedSystemFont(ofSize: 14, weight: .regular)).maximumAdvancement.width)

    if let layoutManager, let textContainer, location < (string as NSString).length {
      let characterRange = NSRange(location: location, length: 1)
      let glyphRange = layoutManager.glyphRange(
        forCharacterRange: characterRange,
        actualCharacterRange: nil
      )
      if glyphRange.length > 0 {
        let glyphRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        if glyphRect.width.isFinite, glyphRect.width > 0 {
          characterWidth = glyphRect.width
        }
      }
    }

    var cursorRect = fallback
    cursorRect.size.width = max(2, ceil(characterWidth / 2))
    return cursorRect.integral
  }
}

@MainActor
private final class RawRelativeLineNumberRulerView: NSRulerView {
  private weak var textView: RawMarkdownTextView?
  private let rulerWidth: CGFloat = 44

  init(textView: RawMarkdownTextView) {
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

    textView.rawTheme.nsColor(.editorBackground).setFill()
    rect.fill()

    let source = textView.string as NSString
    let activeLine = lineNumber(at: textView.selectedRange().location, in: source)
    let origin = textView.textContainerOrigin
    let visibleRect = textView.visibleRect
    layoutManager.ensureLayout(for: textContainer)

    let normalAttributes: [NSAttributedString.Key: Any] = [
      .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular),
      .foregroundColor: textView.rawTheme.nsColor(.secondaryText)
    ]
    let activeAttributes: [NSAttributedString.Key: Any] = [
      .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold),
      .foregroundColor: textView.showsVimNormalCursor
        ? textView.rawTheme.nsColor(.accent)
        : textView.rawTheme.nsColor(.primaryText)
    ]

    if source.length == 0 {
      drawLineNumber(
        1,
        activeLine: activeLine,
        y: layoutManager.extraLineFragmentRect.minY + origin.y,
        visibleRect: visibleRect,
        normalAttributes: normalAttributes,
        activeAttributes: activeAttributes
      )
      return
    }

    var number = 1
    var location = 0
    while location < source.length {
      let lineRange = source.lineRange(for: NSRange(location: location, length: 0))
      let glyphRange = layoutManager.glyphRange(
        forCharacterRange: lineRange,
        actualCharacterRange: nil
      )
      let lineRect = glyphRange.length > 0
        ? layoutManager.lineFragmentRect(forGlyphAt: glyphRange.location, effectiveRange: nil)
        : layoutManager.extraLineFragmentRect
      drawLineNumber(
        number,
        activeLine: activeLine,
        y: lineRect.minY + origin.y,
        visibleRect: visibleRect,
        normalAttributes: normalAttributes,
        activeAttributes: activeAttributes
      )

      let nextLocation = NSMaxRange(lineRange)
      guard nextLocation > location else { break }
      location = nextLocation
      number += 1
    }

    if location == source.length,
       let scalar = Unicode.Scalar(source.character(at: source.length - 1)),
       CharacterSet.newlines.contains(scalar) {
      drawLineNumber(
        number,
        activeLine: activeLine,
        y: layoutManager.extraLineFragmentRect.minY + origin.y,
        visibleRect: visibleRect,
        normalAttributes: normalAttributes,
        activeAttributes: activeAttributes
      )
    }
  }

  private func drawLineNumber(
    _ number: Int,
    activeLine: Int,
    y: CGFloat,
    visibleRect: NSRect,
    normalAttributes: [NSAttributedString.Key: Any],
    activeAttributes: [NSAttributedString.Key: Any]
  ) {
    guard y.isFinite, y >= visibleRect.minY - 24, y <= visibleRect.maxY + 24 else {
      return
    }
    let value = VimTextEditing.relativeLineNumber(
      lineNumber: number,
      activeLineNumber: activeLine
    )
    let attributes = number == activeLine ? activeAttributes : normalAttributes
    let label = NSAttributedString(string: "\(value)", attributes: attributes)
    let size = label.size()
    label.draw(at: NSPoint(x: max(4, bounds.width - size.width - 8), y: y))
  }

  private func lineNumber(at location: Int, in source: NSString) -> Int {
    var line = 1
    let end = max(0, min(location, source.length))
    guard end > 0 else { return line }

    for index in 0..<end {
      guard
        let scalar = Unicode.Scalar(source.character(at: index)),
        CharacterSet.newlines.contains(scalar)
      else {
        continue
      }
      line += 1
    }
    return line
  }
}

#elseif os(iOS)
import UIKit

public struct RawMarkdownEditor: UIViewRepresentable {
  @Binding fileprivate var text: String
  @Binding fileprivate var selectedRange: NSRange
  @Binding fileprivate var vimState: VimEditorState
  fileprivate let fontSize: CGFloat
  fileprivate let focusToken: Int
  fileprivate let isVimModeEnabled: Bool
  fileprivate let showsRelativeLineNumbers: Bool
  fileprivate let theme: LatticeTheme
  fileprivate let keyboardAccessoryActions: [MarkdownKeyboardAccessoryAction]
  fileprivate let onTextChange: () -> Void
  fileprivate let onSelectionChange: () -> Void
  fileprivate let onVimWrite: () -> Void

  public init(
    text: Binding<String>,
    selectedRange: Binding<NSRange>,
    vimState: Binding<VimEditorState>,
    fontSize: CGFloat,
    focusToken: Int,
    isVimModeEnabled: Bool,
    showsRelativeLineNumbers: Bool,
    theme: LatticeTheme,
    keyboardAccessoryActions: [MarkdownKeyboardAccessoryAction] = [],
    onTextChange: @escaping () -> Void,
    onSelectionChange: @escaping () -> Void,
    onVimWrite: @escaping () -> Void
  ) {
    self._text = text
    self._selectedRange = selectedRange
    self._vimState = vimState
    self.fontSize = fontSize
    self.focusToken = focusToken
    self.isVimModeEnabled = isVimModeEnabled
    self.showsRelativeLineNumbers = showsRelativeLineNumbers
    self.theme = theme
    self.keyboardAccessoryActions = keyboardAccessoryActions
    self.onTextChange = onTextChange
    self.onSelectionChange = onSelectionChange
    self.onVimWrite = onVimWrite
  }

  public func makeCoordinator() -> Coordinator {
    Coordinator(parent: self)
  }

  public func makeUIView(context: Context) -> UITextView {
    let textView = UITextView()
    textView.delegate = context.coordinator
    textView.isEditable = true
    textView.isSelectable = true
    textView.isScrollEnabled = true
    textView.alwaysBounceVertical = true
    textView.keyboardDismissMode = .interactive
    textView.textContainerInset = UIEdgeInsets(top: 34, left: 22, bottom: 34, right: 22)
    textView.smartDashesType = .no
    textView.smartQuotesType = .no
    textView.autocorrectionType = .yes
    textView.spellCheckingType = .yes
    textView.accessibilityIdentifier = "noteEditor"
    context.coordinator.synchronizeText(text, selection: selectedRange, in: textView)
    context.coordinator.applyAppearance(to: textView)
    context.coordinator.updateKeyboardAccessory(for: textView)
    return textView
  }

  public func updateUIView(_ textView: UITextView, context: Context) {
    context.coordinator.parent = self
    if textView.text != text {
      context.coordinator.synchronizeText(text, selection: selectedRange, in: textView)
    } else {
      let selection = rawClampedRange(selectedRange, length: (text as NSString).length)
      if textView.selectedRange != selection {
        context.coordinator.synchronizeSelection(selection, in: textView)
      }
    }
    context.coordinator.applyAppearance(to: textView)
    context.coordinator.updateKeyboardAccessory(for: textView)

    if context.coordinator.lastFocusToken != focusToken {
      context.coordinator.lastFocusToken = focusToken
      DispatchQueue.main.async { [weak textView] in
        guard let textView else { return }
        textView.becomeFirstResponder()
        textView.scrollRangeToVisible(textView.selectedRange)
      }
    }
  }

  @MainActor
  public final class Coordinator: NSObject, UITextViewDelegate {
    fileprivate var parent: RawMarkdownEditor
    fileprivate var lastFocusToken = 0
    private var isSynchronizing = false
    private weak var accessoryTextView: UITextView?
    private var accessoryView: RawMarkdownKeyboardAccessoryView?

    fileprivate init(parent: RawMarkdownEditor) {
      self.parent = parent
    }

    fileprivate func synchronizeText(
      _ text: String,
      selection: NSRange,
      in textView: UITextView
    ) {
      isSynchronizing = true
      textView.text = text
      textView.selectedRange = rawClampedRange(selection, length: (text as NSString).length)
      isSynchronizing = false
    }

    fileprivate func synchronizeSelection(_ selection: NSRange, in textView: UITextView) {
      isSynchronizing = true
      textView.selectedRange = selection
      isSynchronizing = false
    }

    fileprivate func applyAppearance(to textView: UITextView) {
      let wasSynchronizing = isSynchronizing
      isSynchronizing = true
      defer { isSynchronizing = wasSynchronizing }
      let font = UIFont.monospacedSystemFont(ofSize: parent.fontSize, weight: .regular)
      let textColor = parent.theme.uiColor(.primaryText)
      textView.font = font
      textView.backgroundColor = parent.theme.uiColor(.editorBackground)
      textView.textColor = textColor
      textView.tintColor = parent.theme.uiColor(.accent)
      textView.typingAttributes = [
        .font: font,
        .foregroundColor: textColor
      ]
      guard textView.markedTextRange == nil else { return }
      let storage = textView.textStorage
      guard storage.length > 0 else { return }
      storage.setAttributes(
        [.font: font, .foregroundColor: textColor],
        range: NSRange(location: 0, length: storage.length)
      )
      let hiddenAttributes: [NSAttributedString.Key: Any] = [
        .font: UIFont.monospacedSystemFont(ofSize: 0.1, weight: .regular),
        .foregroundColor: UIColor.clear
      ]
      for range in rawLatticeMetadataRanges(in: textView.text) {
        storage.addAttributes(hiddenAttributes, range: range)
      }
    }

    fileprivate func updateKeyboardAccessory(for textView: UITextView) {
      accessoryTextView = textView
      guard !parent.keyboardAccessoryActions.isEmpty else {
        if textView.inputAccessoryView != nil {
          textView.inputAccessoryView = nil
          textView.reloadInputViews()
        }
        accessoryView = nil
        return
      }

      let view = accessoryView ?? RawMarkdownKeyboardAccessoryView()
      accessoryView = view
      view.configure(actions: parent.keyboardAccessoryActions, theme: parent.theme)
      if textView.inputAccessoryView !== view {
        textView.inputAccessoryView = view
        textView.reloadInputViews()
      }
    }

    public func textViewDidChange(_ textView: UITextView) {
      guard !isSynchronizing else { return }
      parent.text = textView.text
      parent.selectedRange = textView.selectedRange
      applyAppearance(to: textView)
      parent.onTextChange()
    }

    public func textViewDidChangeSelection(_ textView: UITextView) {
      guard !isSynchronizing else { return }
      parent.selectedRange = textView.selectedRange
      parent.onSelectionChange()
    }
  }
}

@MainActor
private final class RawMarkdownKeyboardAccessoryView: UIInputView {
  private let scrollView = UIScrollView()
  private let stackView = UIStackView()

  init() {
    super.init(frame: CGRect(x: 0, y: 0, width: 0, height: 56), inputViewStyle: .keyboard)
    autoresizingMask = [.flexibleWidth]
    setupView()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    nil
  }

  override var intrinsicContentSize: CGSize {
    CGSize(width: UIView.noIntrinsicMetric, height: 56)
  }

  func configure(actions: [MarkdownKeyboardAccessoryAction], theme: LatticeTheme) {
    backgroundColor = theme.uiColor(.editorBackground)
    stackView.arrangedSubviews.forEach { view in
      stackView.removeArrangedSubview(view)
      view.removeFromSuperview()
    }

    for action in actions {
      stackView.addArrangedSubview(makeButton(for: action, theme: theme))
    }
  }

  private func setupView() {
    addSubview(scrollView)
    scrollView.translatesAutoresizingMaskIntoConstraints = false
    scrollView.showsHorizontalScrollIndicator = false
    scrollView.addSubview(stackView)
    stackView.translatesAutoresizingMaskIntoConstraints = false
    stackView.axis = .horizontal
    stackView.alignment = .center
    stackView.spacing = 8

    NSLayoutConstraint.activate([
      scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
      scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
      scrollView.topAnchor.constraint(equalTo: topAnchor),
      scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
      stackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 12),
      stackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -12),
      stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 6),
      stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -6),
      stackView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor, constant: -12)
    ])
  }

  private func makeButton(
    for action: MarkdownKeyboardAccessoryAction,
    theme: LatticeTheme
  ) -> UIButton {
    let button = UIButton(type: .system)
    var configuration = UIButton.Configuration.tinted()
    configuration.baseForegroundColor = theme.uiColor(.primaryText)
    configuration.baseBackgroundColor = theme.uiColor(.surfaceBackground)
    configuration.cornerStyle = .capsule
    configuration.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12)
    if let systemImage = action.systemImage {
      configuration.image = UIImage(systemName: systemImage)
      configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(
        pointSize: action.symbolPointSize ?? 17,
        weight: .semibold
      )
    } else {
      configuration.title = action.displayTitle ?? action.title
    }
    button.configuration = configuration
    button.accessibilityLabel = action.title

    if action.menuChildren.isEmpty {
      button.isEnabled = action.isEnabled
      button.addAction(UIAction { _ in
        Task { @MainActor in action.perform() }
      }, for: .touchUpInside)
    } else {
      button.isEnabled = action.isEnabled
        && action.menuChildren.contains(where: { $0.isEnabled })
      button.showsMenuAsPrimaryAction = true
      button.menu = UIMenu(
        title: action.title,
        options: .displayInline,
        children: action.menuChildren.map(menuElement(for:))
      )
    }
    return button
  }

  private func menuElement(for action: MarkdownKeyboardAccessoryAction) -> UIMenuElement {
    if !action.menuChildren.isEmpty {
      return UIMenu(
        title: action.title,
        image: action.systemImage.flatMap(UIImage.init(systemName:)),
        children: action.menuChildren.map(menuElement(for:))
      )
    }

    return UIAction(
      title: action.title,
      image: action.systemImage.flatMap(UIImage.init(systemName:)),
      attributes: action.isEnabled ? [] : [.disabled]
    ) { _ in
      Task { @MainActor in action.perform() }
    }
  }
}

#endif

private func rawClampedRange(_ range: NSRange, length: Int) -> NSRange {
  let location = min(max(0, range.location), length)
  let availableLength = max(0, length - location)
  return NSRange(location: location, length: min(max(0, range.length), availableLength))
}

private func rawLatticeMetadataRanges(in text: String) -> [NSRange] {
  guard let expression = try? NSRegularExpression(pattern: #"<!--\s*lattice:[^>]*-->"#) else {
    return []
  }
  let range = NSRange(location: 0, length: (text as NSString).length)
  return expression.matches(in: text, range: range).map(\.range)
}
