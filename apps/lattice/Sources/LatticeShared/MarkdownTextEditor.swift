import LatticeEditor
import LatticeCore
import SwiftUI

#if os(iOS)
import UIKit
import UniformTypeIdentifiers
#endif

public struct MarkdownKeyboardAccessoryAction {
  public let id: String
  public let title: String
  public let systemImage: String?
  public let displayTitle: String?
  public let isEnabled: Bool
  public let menuChildren: [MarkdownKeyboardAccessoryAction]
  public let symbolPointSize: CGFloat?
  private let handler: @MainActor () -> Void

  public init(
    id: String,
    title: String,
    systemImage: String?,
    displayTitle: String? = nil,
    isEnabled: Bool = true,
    menuChildren: [MarkdownKeyboardAccessoryAction] = [],
    symbolPointSize: CGFloat? = nil,
    handler: @escaping @MainActor () -> Void = {}
  ) {
    self.id = id
    self.title = title
    self.systemImage = systemImage
    self.displayTitle = displayTitle
    self.isEnabled = isEnabled
    self.menuChildren = menuChildren
    self.symbolPointSize = symbolPointSize
    self.handler = handler
  }

  @MainActor
  func perform() {
    handler()
  }
}

#if os(iOS)
private extension MarkdownKeyboardAccessoryAction {
  var menuImage: UIImage? {
    guard let systemImage else {
      return nil
    }
    return UIImage(systemName: systemImage)
  }
}

private enum MarkdownKeyboardAccessoryHaptics {
  static func perform() {
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
  }
}
#endif

#if os(macOS)
import AppKit
import QuartzCore

public struct MarkdownTextEditor: NSViewRepresentable {
  @Binding var text: String
  @Binding var selectedRange: NSRange
  @Binding var vimState: VimEditorState
  let fontSize: CGFloat
  let fontFamily: EditorFontFamily
  let focusToken: Int
  let isVimModeEnabled: Bool
  let showsRelativeLineNumbers: Bool
  let dimsInactiveParagraphs: Bool
  let caretAnchorFraction: CGFloat?
  @Binding var autocompleteAnchor: CGRect?
  let keyboardAccessoryActions: [MarkdownKeyboardAccessoryAction]
  let hasAutocompleteSuggestions: Bool
  let wikiLinkStates: [WikiLinkRenderState]
  let theme: LatticeTheme
  let imagePreviewStates: [MarkdownImageRenderState]
  let onTextChange: () -> Void
  let onSelectionChange: () -> Void
  let onWikiLinkActivated: (Int) -> Void
  let onMarkdownLinkActivated: (Int) -> Void
  let onDismissAutocomplete: () -> Void
  let onMoveAutocompleteSelection: (Int) -> Void
  let onCommitAutocomplete: () -> Void
  let onVimWrite: () -> Void
  let onVimStatusChange: (String?) -> Void
  let onImageAttachmentsImported: ([ImageAttachmentImport]) -> Void
  let onImageAttachmentResized: (Int, Double) -> Void

  public init(
    text: Binding<String>,
    selectedRange: Binding<NSRange>,
    vimState: Binding<VimEditorState>,
    fontSize: CGFloat,
    fontFamily: EditorFontFamily,
    focusToken: Int,
    isVimModeEnabled: Bool,
    showsRelativeLineNumbers: Bool,
    dimsInactiveParagraphs: Bool = false,
    caretAnchorFraction: CGFloat? = nil,
    autocompleteAnchor: Binding<CGRect?> = .constant(nil),
    keyboardAccessoryActions: [MarkdownKeyboardAccessoryAction] = [],
    hasAutocompleteSuggestions: Bool,
    wikiLinkStates: [WikiLinkRenderState],
    theme: LatticeTheme,
    imagePreviewStates: [MarkdownImageRenderState],
    onTextChange: @escaping () -> Void,
    onSelectionChange: @escaping () -> Void,
    onWikiLinkActivated: @escaping (Int) -> Void,
    onMarkdownLinkActivated: @escaping (Int) -> Void,
    onDismissAutocomplete: @escaping () -> Void,
    onMoveAutocompleteSelection: @escaping (Int) -> Void = { _ in },
    onCommitAutocomplete: @escaping () -> Void = {},
    onVimWrite: @escaping () -> Void,
    onVimStatusChange: @escaping (String?) -> Void,
    onImageAttachmentsImported: @escaping ([ImageAttachmentImport]) -> Void,
    onImageAttachmentResized: @escaping (Int, Double) -> Void
  ) {
    self._text = text
    self._selectedRange = selectedRange
    self._vimState = vimState
    self.fontSize = fontSize
    self.fontFamily = fontFamily
    self.focusToken = focusToken
    self.isVimModeEnabled = isVimModeEnabled
    self.showsRelativeLineNumbers = showsRelativeLineNumbers
    self.dimsInactiveParagraphs = dimsInactiveParagraphs
    self.caretAnchorFraction = caretAnchorFraction
    self._autocompleteAnchor = autocompleteAnchor
    self.keyboardAccessoryActions = keyboardAccessoryActions
    self.hasAutocompleteSuggestions = hasAutocompleteSuggestions
    self.wikiLinkStates = wikiLinkStates
    self.theme = theme
    self.imagePreviewStates = imagePreviewStates
    self.onTextChange = onTextChange
    self.onSelectionChange = onSelectionChange
    self.onWikiLinkActivated = onWikiLinkActivated
    self.onMarkdownLinkActivated = onMarkdownLinkActivated
    self.onDismissAutocomplete = onDismissAutocomplete
    self.onMoveAutocompleteSelection = onMoveAutocompleteSelection
    self.onCommitAutocomplete = onCommitAutocomplete
    self.onVimWrite = onVimWrite
    self.onVimStatusChange = onVimStatusChange
    self.onImageAttachmentsImported = onImageAttachmentsImported
    self.onImageAttachmentResized = onImageAttachmentResized
  }

  public func makeCoordinator() -> Coordinator {
    Coordinator(parent: self)
  }

  public func makeNSView(context: Context) -> NSScrollView {
    let scrollView = NSScrollView()
    scrollView.drawsBackground = true
    scrollView.backgroundColor = theme.nsColor(.editorBackground)
    configureNativeOverlayScrollers(for: scrollView)
    scrollView.contentView = MarkdownClipView()
    scrollView.contentView.drawsBackground = true
    scrollView.contentView.backgroundColor = theme.nsColor(.editorBackground)
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
    configureNativeTextChecking(for: textView)
    textView.theme = theme
    textView.drawsBackground = true
    textView.backgroundColor = theme.nsColor(.editorBackground)
    textView.textColor = theme.nsColor(.primaryText)
    textView.insertionPointColor = theme.nsColor(.accent)
    textView.font = MarkdownAttributedRenderer.bodyFont(size: fontSize, family: fontFamily)
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
    textView.registerForDraggedTypes([.fileURL, .png, .tiff])

    scrollView.documentView = textView
    context.coordinator.attachScrollView(scrollView)
    textView.configureRuler(showsRelativeLineNumbers: showsRelativeLineNumbers)
    context.coordinator.textView = textView
    return scrollView
  }

  public func updateNSView(_ scrollView: NSScrollView, context: Context) {
    context.coordinator.parent = self
    guard let textView = context.coordinator.textView else {
      return
    }
    let clampedSelectedRange = clamped(selectedRange, length: (text as NSString).length)
    context.coordinator.configureCaretAnchorLayout(in: textView, scrollView: scrollView)
    if textView.string != text
      || context.coordinator.lastRenderedFontSize != fontSize
      || context.coordinator.lastRenderedFontFamily != fontFamily
      || context.coordinator.lastRenderedWikiLinkStates != wikiLinkStates
      || context.coordinator.lastRenderedDimsInactiveParagraphs != dimsInactiveParagraphs
      || context.coordinator.lastRenderedTheme != theme
      || context.coordinator.lastRenderedImagePreviewStates != imagePreviewStates {
      context.coordinator.render(text, in: textView, preserving: clampedSelectedRange)
    } else if textView.selectedRange() != clampedSelectedRange {
      textView.setSelectedRange(clampedSelectedRange)
      context.coordinator.scheduleDeferredRender(in: textView, preserving: clampedSelectedRange)
    }
    textView.theme = theme
    configureNativeTextChecking(for: textView)
    scrollView.backgroundColor = theme.nsColor(.editorBackground)
    configureNativeOverlayScrollers(for: scrollView)
    scrollView.contentView.backgroundColor = theme.nsColor(.editorBackground)
    textView.backgroundColor = theme.nsColor(.editorBackground)
    textView.insertionPointColor = theme.nsColor(.accent)
    textView.configureRuler(showsRelativeLineNumbers: showsRelativeLineNumbers)
    textView.needsDisplay = true
    if context.coordinator.lastFocusToken != focusToken {
      context.coordinator.lastFocusToken = focusToken
      DispatchQueue.main.async {
        textView.window?.makeFirstResponder(textView)
        context.coordinator.scheduleCaretAnchor(selection: clampedSelectedRange, animated: false)
        context.coordinator.updateAutocompleteAnchor(in: textView, selection: clampedSelectedRange)
      }
    }
    context.coordinator.updateAutocompleteAnchor(in: textView, selection: clampedSelectedRange)
  }

  @MainActor
  public final class Coordinator: NSObject, NSTextViewDelegate {
    var parent: MarkdownTextEditor
    fileprivate weak var textView: MarkdownTextView?
    private weak var scrollView: NSScrollView?
    var lastFocusToken = 0
    var lastRenderedFontSize: CGFloat?
    var lastRenderedFontFamily: EditorFontFamily?
    var lastRenderedWikiLinkStates: [WikiLinkRenderState] = []
    var lastRenderedDimsInactiveParagraphs = false
    var lastRenderedTheme = LatticeTheme(id: .system)
    var lastRenderedImagePreviewStates: [MarkdownImageRenderState] = []
    private var isRendering = false
    private let defaultTextContainerInset = NSSize(width: 36, height: 34)
    private let defaultCaretBottomPadding: CGFloat = 12
    private let defaultCaretTopPadding: CGFloat = 12
    private let defaultManualScrollBottomSlackFraction: CGFloat = 0.45
    private let deferredRenderDelayNanoseconds: UInt64 = 75_000_000
    private var pendingRenderTask: Task<Void, Never>?
    private var pendingAnchorTask: Task<Void, Never>?

    init(parent: MarkdownTextEditor) {
      self.parent = parent
    }

    func attachScrollView(_ scrollView: NSScrollView) {
      guard self.scrollView !== scrollView else {
        return
      }
      if let existing = self.scrollView {
        NotificationCenter.default.removeObserver(
          self,
          name: NSView.boundsDidChangeNotification,
          object: existing.contentView
        )
      }
      self.scrollView = scrollView
      scrollView.contentView.postsBoundsChangedNotifications = true
      NotificationCenter.default.addObserver(
        self,
        selector: #selector(scrollViewBoundsDidChange(_:)),
        name: NSView.boundsDidChangeNotification,
        object: scrollView.contentView
      )
      scheduleCaretAnchor(animated: false)
    }

    public func textDidChange(_ notification: Notification) {
      guard let textView = notification.object as? NSTextView, !isRendering else {
        return
      }
      parent.text = textView.string
      parent.selectedRange = textView.selectedRange()
      parent.onTextChange()
      applyBaseTypingAttributes(to: textView)
      (textView as? MarkdownTextView)?.invalidateLineNumberRuler()
      textView.needsDisplay = true
      updateAutocompleteAnchor(in: textView, selection: textView.selectedRange())
      scheduleDeferredRender(in: textView, preserving: textView.selectedRange())
      scheduleCaretAnchor(animated: true)
    }

    public func textViewDidChangeSelection(_ notification: Notification) {
      guard let textView = notification.object as? NSTextView, !isRendering else {
        return
      }
      let selection = textView.selectedRange()
      parent.selectedRange = selection
      parent.onSelectionChange()
      updateAutocompleteAnchor(in: textView, selection: selection)
      scheduleDeferredRender(in: textView, preserving: selection)
      scheduleCaretAnchor(animated: true)
    }

    @objc private func scrollViewBoundsDidChange(_ notification: Notification) {
      if let textView {
        updateAutocompleteAnchor(in: textView, selection: textView.selectedRange())
      }
      guard parent.normalizedCaretAnchorFraction != nil else { return }
      scheduleCaretAnchor(animated: false)
    }

    func configureCaretAnchorLayout(in textView: NSTextView, scrollView: NSScrollView) {
      guard let anchor = parent.normalizedCaretAnchorFraction else {
        if textView.textContainerInset != defaultTextContainerInset {
          textView.textContainerInset = defaultTextContainerInset
        }
        if let clipView = scrollView.contentView as? MarkdownClipView {
          clipView.verticalBoundsLimits = nil
        }
        ensureDefaultCaretScrollSlack(in: textView, visibleHeight: scrollView.contentView.bounds.height)
        return
      }

      let visibleHeight = scrollView.contentView.bounds.height
      guard visibleHeight > 0 else {
        return
      }

      if textView.textContainerInset != defaultTextContainerInset {
        textView.textContainerInset = defaultTextContainerInset
      }
      ensureBottomAnchorSlack(in: textView, visibleHeight: visibleHeight, anchor: anchor)
      configureAnchorScrollLimits(
        in: scrollView,
        textView: textView,
        visibleHeight: visibleHeight,
        anchor: anchor
      )
    }

    func render(_ text: String, in textView: NSTextView, preserving selection: NSRange) {
      guard !isRendering else {
        return
      }
      guard !textView.hasMarkedText() else {
        scheduleDeferredRender(in: textView, preserving: textView.selectedRange())
        return
      }
      pendingRenderTask?.cancel()
      pendingRenderTask = nil
      isRendering = true
      let activeRanges = parent.dimsInactiveParagraphs
        ? [Self.lineRange(containing: selection, in: text)]
        : [selection]
      let attributed = MarkdownAttributedRenderer.render(
        text,
        fontSize: parent.fontSize,
        fontFamily: parent.fontFamily,
        activeRanges: activeRanges,
        wikiLinkStates: parent.wikiLinkStates,
        dimsInactiveText: parent.dimsInactiveParagraphs,
        theme: parent.theme,
        imagePreviewStates: parent.imagePreviewStates
      )
      textView.textColor = parent.theme.nsColor(.primaryText)
      textView.textStorage?.setAttributedString(attributed)
      textView.setSelectedRange(clamped(selection, length: (text as NSString).length))
      textView.typingAttributes = MarkdownAttributedRenderer.baseTypingAttributes(
        fontSize: parent.fontSize,
        fontFamily: parent.fontFamily,
        theme: parent.theme
      )
      (textView as? MarkdownTextView)?.invalidateLineNumberRuler()
      lastRenderedFontSize = parent.fontSize
      lastRenderedFontFamily = parent.fontFamily
      lastRenderedWikiLinkStates = parent.wikiLinkStates
      lastRenderedDimsInactiveParagraphs = parent.dimsInactiveParagraphs
      lastRenderedTheme = parent.theme
      lastRenderedImagePreviewStates = parent.imagePreviewStates
      isRendering = false
      updateAutocompleteAnchor(in: textView, selection: selection)
      scheduleCaretAnchor(selection: selection, animated: true)
    }

    func scheduleDeferredRender(in textView: NSTextView, preserving selection: NSRange) {
      pendingRenderTask?.cancel()
      pendingRenderTask = Task { @MainActor [weak self, weak textView] in
        try? await Task.sleep(nanoseconds: self?.deferredRenderDelayNanoseconds ?? 75_000_000)
        guard !Task.isCancelled, let self, let textView, !self.isRendering else {
          return
        }
        guard !textView.hasMarkedText() else {
          self.scheduleDeferredRender(in: textView, preserving: textView.selectedRange())
          return
        }
        self.render(textView.string, in: textView, preserving: textView.selectedRange())
      }
    }

    private func applyBaseTypingAttributes(to textView: NSTextView) {
      textView.typingAttributes = MarkdownAttributedRenderer.baseTypingAttributes(
        fontSize: parent.fontSize,
        fontFamily: parent.fontFamily,
        theme: parent.theme
      )
    }

    func scheduleCaretAnchor(selection: NSRange? = nil, animated: Bool) {
      pendingAnchorTask?.cancel()
      pendingAnchorTask = Task { @MainActor [weak self] in
        await Task.yield()
        guard !Task.isCancelled, let self, let textView = self.textView else {
          return
        }
        let targetSelection = selection ?? textView.selectedRange()
        self.scrollCaretIntoView(in: textView, selection: targetSelection, animated: animated)
        self.updateAutocompleteAnchor(in: textView, selection: targetSelection)
      }
    }

    func scrollCaretIntoView(in textView: NSTextView, selection: NSRange, animated: Bool) {
      if parent.normalizedCaretAnchorFraction != nil {
        scrollCaretToAnchor(in: textView, selection: selection, animated: animated)
      } else {
        scrollCaretToEditableBounds(in: textView, selection: selection, animated: animated)
      }
    }

    func scrollCaretToAnchor(in textView: NSTextView, selection: NSRange, animated: Bool) {
      guard let anchor = parent.normalizedCaretAnchorFraction,
            let scrollView = scrollView ?? textView.enclosingScrollView
      else {
        return
      }

      let clipView = scrollView.contentView
      let visibleRect = clipView.bounds
      guard visibleRect.height > 0 else {
        return
      }

      guard let caretRect = caretRect(for: selection, in: textView) else {
        return
      }

      ensureBottomAnchorSlack(in: textView, visibleHeight: visibleRect.height, anchor: anchor)
      configureAnchorScrollLimits(
        in: scrollView,
        textView: textView,
        visibleHeight: visibleRect.height,
        anchor: anchor
      )
      let targetOriginY = constrainedAnchorOrigin(
        caretRect.midY - visibleRect.height * anchor,
        in: scrollView
      )
      guard abs(visibleRect.origin.y - targetOriginY) > 0.5 else {
        return
      }

      let targetOrigin = NSPoint(x: visibleRect.origin.x, y: targetOriginY)
      if animated, textView.window != nil {
        NSAnimationContext.runAnimationGroup { context in
          context.duration = 0.12
          context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
          clipView.animator().setBoundsOrigin(targetOrigin)
        } completionHandler: {
          Task { @MainActor in
            scrollView.reflectScrolledClipView(clipView)
          }
        }
      } else {
        clipView.setBoundsOrigin(targetOrigin)
        scrollView.reflectScrolledClipView(clipView)
      }
    }

    private func scrollCaretToEditableBounds(in textView: NSTextView, selection: NSRange, animated: Bool) {
      guard let scrollView = scrollView ?? textView.enclosingScrollView else {
        return
      }

      let clipView = scrollView.contentView
      let visibleRect = clipView.bounds
      guard visibleRect.height > 0 else {
        return
      }

      ensureDefaultCaretScrollSlack(in: textView, visibleHeight: visibleRect.height)
      guard let caretRect = caretRect(for: selection, in: textView) else {
        return
      }

      let lowerVisibleY = visibleRect.minY + defaultCaretTopPadding
      let upperVisibleY = visibleRect.maxY - defaultCaretBottomPadding
      let maximumOriginY = max(0, textView.frame.height - visibleRect.height)
      var targetOriginY = visibleRect.origin.y

      if caretRect.maxY > upperVisibleY {
        targetOriginY = min(maximumOriginY, caretRect.maxY + defaultCaretBottomPadding - visibleRect.height)
      } else if caretRect.minY < lowerVisibleY {
        targetOriginY = max(0, caretRect.minY - defaultCaretTopPadding)
      } else {
        return
      }

      guard abs(visibleRect.origin.y - targetOriginY) > 0.5 else {
        return
      }

      let targetOrigin = NSPoint(x: visibleRect.origin.x, y: targetOriginY)
      if animated, textView.window != nil {
        NSAnimationContext.runAnimationGroup { context in
          context.duration = 0.08
          context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
          clipView.animator().setBoundsOrigin(targetOrigin)
        } completionHandler: {
          Task { @MainActor in
            scrollView.reflectScrolledClipView(clipView)
          }
        }
      } else {
        clipView.setBoundsOrigin(targetOrigin)
        scrollView.reflectScrolledClipView(clipView)
      }
    }

    private func configureAnchorScrollLimits(
      in scrollView: NSScrollView,
      textView: NSTextView,
      visibleHeight: CGFloat,
      anchor: CGFloat
    ) {
      guard let clipView = scrollView.contentView as? MarkdownClipView else {
        return
      }

      let topSlack = visibleHeight * anchor
      let bottomSlack = visibleHeight * (1 - anchor)
      let maximumNaturalOrigin = max(0, textView.frame.height - visibleHeight)
      clipView.verticalBoundsLimits = -topSlack...maximumNaturalOrigin + bottomSlack
    }

    private func constrainedAnchorOrigin(_ originY: CGFloat, in scrollView: NSScrollView) -> CGFloat {
      guard let clipView = scrollView.contentView as? MarkdownClipView,
            let limits = clipView.verticalBoundsLimits
      else {
        return max(0, originY)
      }

      return min(max(originY, limits.lowerBound), limits.upperBound)
    }

    private func ensureDefaultCaretScrollSlack(in textView: NSTextView, visibleHeight: CGFloat) {
      guard visibleHeight > 0,
            let layoutManager = textView.layoutManager,
            let textContainer = textView.textContainer
      else {
        return
      }

      layoutManager.ensureLayout(for: textContainer)
      let usedRect = layoutManager.usedRect(for: textContainer)
      let bottomSlack = max(
        defaultTextContainerInset.height,
        visibleHeight * defaultManualScrollBottomSlackFraction
      )
      let currentWidth = max(textView.frame.width, textView.enclosingScrollView?.contentView.bounds.width ?? 0)
      let targetHeight = max(
        visibleHeight,
        usedRect.maxY + textView.textContainerOrigin.y + bottomSlack
      )
      textView.minSize = NSSize(width: 0, height: targetHeight)
      guard abs(textView.frame.height - targetHeight) > 1 || abs(textView.frame.width - currentWidth) > 1 else {
        return
      }
      textView.setFrameSize(NSSize(width: currentWidth, height: targetHeight))
    }

    private func ensureBottomAnchorSlack(in textView: NSTextView, visibleHeight: CGFloat, anchor: CGFloat) {
      guard let layoutManager = textView.layoutManager,
            let textContainer = textView.textContainer
      else {
        return
      }

      layoutManager.ensureLayout(for: textContainer)
      let usedRect = layoutManager.usedRect(for: textContainer)
      let bottomSlack = visibleHeight * (1 - anchor) + defaultTextContainerInset.height
      let currentWidth = max(textView.frame.width, textView.enclosingScrollView?.contentView.bounds.width ?? 0)
      let targetHeight = max(
        visibleHeight,
        usedRect.maxY + textView.textContainerOrigin.y + bottomSlack
      )
      textView.minSize = NSSize(width: 0, height: targetHeight)
      guard abs(textView.frame.height - targetHeight) > 1 || abs(textView.frame.width - currentWidth) > 1 else {
        return
      }
      textView.setFrameSize(NSSize(width: currentWidth, height: targetHeight))
    }

    private func caretRect(for selection: NSRange, in textView: NSTextView) -> NSRect? {
      let nsString = textView.string as NSString
      let location = min(max(selection.location, 0), nsString.length)
      guard let layoutManager = textView.layoutManager,
            let textContainer = textView.textContainer
      else {
        return nil
      }

      layoutManager.ensureLayout(for: textContainer)
      let origin = textView.textContainerOrigin
      if nsString.length == 0 {
        let font = MarkdownAttributedRenderer.bodyFont(size: parent.fontSize)
        return NSRect(
          x: origin.x,
          y: origin.y,
          width: 1,
          height: font.ascender - font.descender + font.leading
        )
      }

      if location == nsString.length,
         location > 0,
         let scalar = Unicode.Scalar(nsString.character(at: location - 1)),
         CharacterSet.newlines.contains(scalar) {
        return layoutManager.extraLineFragmentRect.offsetBy(dx: origin.x, dy: origin.y)
      }

      let characterLocation = min(location, nsString.length - 1)
      let glyphRange = layoutManager.glyphRange(
        forCharacterRange: NSRange(location: characterLocation, length: 1),
        actualCharacterRange: nil
      )
      guard glyphRange.length > 0 else {
        return nil
      }
      let lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphRange.location, effectiveRange: nil)
      return lineRect.offsetBy(dx: origin.x, dy: origin.y)
    }

    func updateAutocompleteAnchor(in textView: NSTextView, selection: NSRange) {
      guard parent.hasAutocompleteSuggestions else {
        if parent.autocompleteAnchor != nil {
          parent.autocompleteAnchor = nil
        }
        return
      }

      guard let scrollView = scrollView ?? textView.enclosingScrollView,
            let caretRect = caretRect(for: selection, in: textView)
      else {
        parent.autocompleteAnchor = nil
        return
      }

      let caretInScrollView = scrollView.convert(caretRect, from: textView)
      guard
        caretInScrollView.minX.isFinite,
        caretInScrollView.minY.isFinite,
        caretInScrollView.width.isFinite,
        caretInScrollView.height.isFinite
      else {
        parent.autocompleteAnchor = nil
        return
      }

      parent.autocompleteAnchor = CGRect(
        x: caretInScrollView.minX,
        y: caretInScrollView.minY,
        width: max(1, caretInScrollView.width),
        height: caretInScrollView.height
      )
    }

    private static func lineRange(containing selection: NSRange, in text: String) -> NSRange {
      let nsString = text as NSString
      guard nsString.length > 0 else {
        return NSRange(location: 0, length: 0)
      }
      let location = min(max(selection.location, 0), nsString.length)
      return nsString.lineRange(for: NSRange(location: location, length: 0))
    }

  }

  private var normalizedCaretAnchorFraction: CGFloat? {
    guard let caretAnchorFraction else {
      return nil
    }
    return min(max(caretAnchorFraction, 0.05), 0.95)
  }

  private func configureNativeOverlayScrollers(for scrollView: NSScrollView) {
    scrollView.hasVerticalScroller = true
    scrollView.hasHorizontalScroller = false
    scrollView.autohidesScrollers = true
    scrollView.scrollerStyle = .overlay
    scrollView.scrollerKnobStyle = .default
  }

  private func configureNativeTextChecking(for textView: NSTextView) {
    textView.isContinuousSpellCheckingEnabled = false
    textView.isGrammarCheckingEnabled = false
    textView.isAutomaticSpellingCorrectionEnabled = false
    textView.isAutomaticTextCompletionEnabled = false
    textView.enabledTextCheckingTypes = 0
  }
}

private final class MarkdownClipView: NSClipView {
  var verticalBoundsLimits: ClosedRange<CGFloat>?

  override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
    var bounds = super.constrainBoundsRect(proposedBounds)
    guard let verticalBoundsLimits else {
      return bounds
    }

    bounds.origin.y = min(max(proposedBounds.origin.y, verticalBoundsLimits.lowerBound), verticalBoundsLimits.upperBound)
    return bounds
  }
}

private final class MarkdownTextView: NSTextView {
  weak var coordinator: MarkdownTextEditor.Coordinator?
  var theme = LatticeTheme(id: .system)
  private var activeImageResize: ImageResizeDrag?

  override func keyDown(with event: NSEvent) {
    guard let coordinator else {
      super.keyDown(with: event)
      return
    }

    if coordinator.parent.hasAutocompleteSuggestions {
      switch Self.autocompleteKeyAction(for: event) {
      case .dismiss:
        coordinator.parent.onDismissAutocomplete()
        return
      case .move(let delta):
        coordinator.parent.onMoveAutocompleteSelection(delta)
        return
      case .commit:
        coordinator.parent.onCommitAutocomplete()
        return
      case .none:
        break
      }
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

  override func complete(_ sender: Any?) {
  }

  override func doCommand(by selector: Selector) {
    guard let coordinator, coordinator.parent.hasAutocompleteSuggestions else {
      super.doCommand(by: selector)
      return
    }

    switch selector {
    case #selector(NSResponder.moveDown(_:)):
      coordinator.parent.onMoveAutocompleteSelection(1)
    case #selector(NSResponder.moveUp(_:)):
      coordinator.parent.onMoveAutocompleteSelection(-1)
    case #selector(NSResponder.insertNewline(_:)),
         #selector(NSResponder.insertTab(_:)):
      coordinator.parent.onCommitAutocomplete()
    case #selector(NSResponder.cancelOperation(_:)):
      coordinator.parent.onDismissAutocomplete()
    default:
      super.doCommand(by: selector)
    }
  }

  override func completions(
    forPartialWordRange charRange: NSRange,
    indexOfSelectedItem index: UnsafeMutablePointer<Int>?
  ) -> [String]? {
    index?.pointee = -1
    return []
  }

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
    drawMarkdownTables()
    drawTaskCheckboxes()
    drawThematicBreaks()
    drawImagePreviews()
  }

  override func paste(_ sender: Any?) {
    if importImages(from: .general) {
      return
    }
    super.paste(sender)
  }

  override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
    imageImports(from: sender.draggingPasteboard).isEmpty ? super.draggingEntered(sender) : .copy
  }

  override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
    if importImages(from: sender.draggingPasteboard, dropLocation: sender.draggingLocation) {
      return true
    }
    return super.performDragOperation(sender)
  }

  override func scrollRangeToVisible(_ range: NSRange) {
    if coordinator?.parent.caretAnchorFraction != nil {
      coordinator?.scheduleCaretAnchor(selection: selectedRange(), animated: false)
      return
    }

    super.scrollRangeToVisible(range)
  }

  override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
    guard showsVimNormalModeIndicator else {
      super.drawInsertionPoint(in: rect, color: color, turnedOn: flag)
      return
    }

    guard flag else {
      return
    }

    theme.nsColor(.accent).setFill()
    vimBlockCursorRect(fallbackRect: rect).fill()
  }

  override func setNeedsDisplay(_ rect: NSRect, avoidAdditionalLayout flag: Bool) {
    guard showsVimNormalModeIndicator else {
      super.setNeedsDisplay(rect, avoidAdditionalLayout: flag)
      return
    }

    super.setNeedsDisplay(
      rect.insetBy(dx: -vimFallbackCursorWidth, dy: -1),
      avoidAdditionalLayout: flag
    )
  }

  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    if handlePasteboardShortcut(event) {
      return true
    }

    return super.performKeyEquivalent(with: event)
  }

  override func mouseDown(with event: NSEvent) {
    if beginImageResize(at: event) {
      return
    }

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

  override func mouseDragged(with event: NSEvent) {
    guard let activeImageResize else {
      super.mouseDragged(with: event)
      return
    }
    let location = convert(event.locationInWindow, from: nil)
    let width = min(activeImageResize.maxWidth, max(activeImageResize.minWidth, location.x - activeImageResize.imageMinX))
    coordinator?.parent.onImageAttachmentResized(activeImageResize.lineLocation, Double(width))
  }

  override func mouseUp(with event: NSEvent) {
    if activeImageResize != nil {
      activeImageResize = nil
      return
    }
    super.mouseUp(with: event)
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

  private func importImages(from pasteboard: NSPasteboard, dropLocation: NSPoint? = nil) -> Bool {
    let imports = imageImports(from: pasteboard)
    guard !imports.isEmpty else {
      return false
    }
    if let dropLocation {
      let location = characterIndex(atWindowPoint: dropLocation) ?? (string as NSString).length
      setSelectedRange(NSRange(location: location, length: 0))
      coordinator?.parent.selectedRange = selectedRange()
    }
    coordinator?.parent.onImageAttachmentsImported(imports)
    return true
  }

  private func imageImports(from pasteboard: NSPasteboard) -> [ImageAttachmentImport] {
    if let urls = pasteboard.readObjects(
      forClasses: [NSURL.self],
      options: [.urlReadingFileURLsOnly: true]
    ) as? [URL] {
      let fileImports = urls.compactMap(Self.imageImport(fromFileURL:))
      if !fileImports.isEmpty {
        return fileImports
      }
    }

    if let pngData = pasteboard.data(forType: .png) {
      return [ImageAttachmentImport(data: pngData, suggestedFilename: "screenshot.png", preferredExtension: "png")]
    }
    if let tiffData = pasteboard.data(forType: .tiff),
       let image = NSImage(data: tiffData),
       let pngData = image.pngData() {
      return [ImageAttachmentImport(data: pngData, suggestedFilename: "screenshot.png", preferredExtension: "png")]
    }
    return []
  }

  private static func imageImport(fromFileURL url: URL) -> ImageAttachmentImport? {
    let supportedExtensions = Set(["png", "jpg", "jpeg", "gif", "heic", "tif", "tiff", "webp"])
    let fileExtension = url.pathExtension.lowercased()
    guard supportedExtensions.contains(fileExtension),
          let data = try? Data(contentsOf: url) else {
      return nil
    }
    return ImageAttachmentImport(
      data: data,
      suggestedFilename: url.lastPathComponent,
      preferredExtension: fileExtension
    )
  }

  private func beginImageResize(at event: NSEvent) -> Bool {
    let location = convert(event.locationInWindow, from: nil)
    guard let layout = imagePreviewLayout(at: location) else {
      return false
    }
    activeImageResize = ImageResizeDrag(
      lineLocation: layout.lineLocation,
      imageMinX: layout.imageRect.minX,
      minWidth: 96,
      maxWidth: layout.maxWidth
    )
    NSCursor.resizeLeftRight.set()
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
      needsDisplay = true
    }

    if result.action == .write {
      coordinator.parent.onVimWrite()
    }
  }

  private static func isEscape(_ event: NSEvent) -> Bool {
    event.keyCode == 53
  }

  private enum AutocompleteKeyAction {
    case dismiss
    case move(Int)
    case commit
  }

  private static func autocompleteKeyAction(for event: NSEvent) -> AutocompleteKeyAction? {
    let modifiers = event.modifierFlags
      .intersection(.deviceIndependentFlagsMask)
      .subtracting([.function, .numericPad, .shift])
    guard modifiers.isEmpty else {
      return nil
    }

    switch event.keyCode {
    case 53:
      return .dismiss
    case 125:
      return .move(1)
    case 126:
      return .move(-1)
    case 36, 48, 76:
      return .commit
    default:
      return nil
    }
  }

  func configureRuler(showsRelativeLineNumbers: Bool) {
    guard let scrollView = enclosingScrollView else {
      return
    }

    if showsRelativeLineNumbers {
      if !(scrollView.verticalRulerView is RelativeLineNumberRulerView) {
        scrollView.verticalRulerView = RelativeLineNumberRulerView(textView: self)
      }
      scrollView.hasHorizontalRuler = false
      scrollView.horizontalRulerView = nil
      scrollView.hasVerticalRuler = true
      scrollView.rulersVisible = true
      invalidateLineNumberRuler()
    } else {
      scrollView.rulersVisible = false
      scrollView.hasVerticalRuler = false
      scrollView.hasHorizontalRuler = false
      scrollView.verticalRulerView = nil
      scrollView.horizontalRulerView = nil
    }
  }

  func invalidateLineNumberRuler() {
    enclosingScrollView?.verticalRulerView?.needsDisplay = true
  }

  var showsVimNormalModeIndicator: Bool {
    guard let coordinator else {
      return false
    }

    return coordinator.parent.isVimModeEnabled
      && coordinator.parent.vimState.mode == .normal
  }

  private func vimBlockCursorRect(fallbackRect: NSRect) -> NSRect {
    let location = min(selectedRange().location, (string as NSString).length)
    let cursorFont = vimCursorFont(at: location)
    let fallbackWidth = vimFallbackCursorWidth(for: cursorFont)
    let fallbackHeight = max(2, ceil(cursorFont.ascender - cursorFont.descender))
    var cursorRect = fallbackRect
    cursorRect.size.width = max(fallbackWidth, fallbackRect.width)
    cursorRect.size.height = min(fallbackRect.height, fallbackHeight)
    cursorRect.origin.y = fallbackRect.midY - (cursorRect.height / 2)

    guard
      let layoutManager,
      let textContainer
    else {
      return cursorRect.integral
    }

    layoutManager.ensureLayout(for: textContainer)

    let nsString = string as NSString
    guard location < nsString.length else {
      return cursorRect.integral
    }

    guard let scalar = Unicode.Scalar(nsString.character(at: location)),
          !CharacterSet.newlines.contains(scalar) else {
      return cursorRect.integral
    }

    let characterRange = NSRange(location: location, length: 1)
    let glyphRange = layoutManager.glyphRange(
      forCharacterRange: characterRange,
      actualCharacterRange: nil
    )
    guard glyphRange.length > 0 else {
      return cursorRect.integral
    }

    let glyphLocation = layoutManager.location(forGlyphAt: glyphRange.location)
    let glyphBounds = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
    cursorRect.origin.x = textContainerOrigin.x + glyphLocation.x
    cursorRect.size.width = glyphBounds.width > 1
      ? max(2, ceil(glyphBounds.width) + 2)
      : fallbackWidth

    let nextGlyphIndex = NSMaxRange(glyphRange)
    if glyphBounds.width <= 1, nextGlyphIndex < layoutManager.numberOfGlyphs {
      let lineRect = layoutManager.lineFragmentUsedRect(forGlyphAt: glyphRange.location, effectiveRange: nil)
      let nextLineRect = layoutManager.lineFragmentUsedRect(forGlyphAt: nextGlyphIndex, effectiveRange: nil)
      if abs(nextLineRect.minY - lineRect.minY) < 0.5 {
        let nextGlyphLocation = layoutManager.location(forGlyphAt: nextGlyphIndex)
        cursorRect.size.width = max(cursorRect.size.width, nextGlyphLocation.x - glyphLocation.x)
      }
    }

    return cursorRect.integral
  }

  private var vimFallbackCursorWidth: CGFloat {
    let location = min(selectedRange().location, (string as NSString).length)
    return vimFallbackCursorWidth(for: vimCursorFont(at: location))
  }

  private func vimFallbackCursorWidth(for cursorFont: NSFont) -> CGFloat {
    let measuredWidth = ("m" as NSString).size(withAttributes: [.font: cursorFont]).width
    return max(2, ceil(measuredWidth))
  }

  private func vimCursorFont(at location: Int) -> NSFont {
    if let textStorage, textStorage.length > 0 {
      let clampedLocation = min(location, textStorage.length - 1)
      if let attributedFont = textStorage.attribute(
        .font,
        at: clampedLocation,
        effectiveRange: nil
      ) as? NSFont {
        return attributedFont
      }
    }

    return font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
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
    characterIndex(atWindowPoint: event.locationInWindow)
  }

  private func characterIndex(atWindowPoint point: NSPoint) -> Int? {
    guard
      let layoutManager,
      let textContainer
    else {
      return nil
    }

    var location = convert(point, from: nil)
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

  private func drawMarkdownTables() {
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

    var drawnTableLocations: Set<Int> = []
    textStorage.enumerateAttribute(.latticeMarkdownTable, in: visibleCharacterRange) { value, range, _ in
      guard
        value as? Bool == true,
        let table = MarkdownTableParser.table(containing: range, in: textStorage.string),
        !drawnTableLocations.contains(table.range.location)
      else {
        return
      }

      drawnTableLocations.insert(table.range.location)
      drawMarkdownTable(table, layoutManager: layoutManager)
    }
  }

  private func drawMarkdownTable(_ table: MarkdownTableBlock, layoutManager: NSLayoutManager) {
    let rowLineRanges = [table.headerLineRange] + table.bodyLineRanges
    guard rowLineRanges.count == table.rows.count else {
      return
    }

    let maxWidth = max(0, bounds.width - textContainerInset.width - 2)
    let columnWidths = markdownTableColumnWidths(for: table, maxWidth: maxWidth)
    let tableWidth = columnWidths.reduce(0, +)
    let separatorColor = theme.nsColor(.separator).withAlphaComponent(0.9)
    let rowBackground = theme.nsColor(.editorBackground)
    let headerBackground = theme.nsColor(.surfaceBackground).withAlphaComponent(0.8)

    for (rowIndex, row) in table.rows.enumerated() {
      let lineRange = rowLineRanges[rowIndex]
      let glyphRange = layoutManager.glyphRange(forCharacterRange: lineRange, actualCharacterRange: nil)
      guard glyphRange.length > 0 else {
        continue
      }

      let lineRect = layoutManager.lineFragmentUsedRect(forGlyphAt: glyphRange.location, effectiveRange: nil)
      let rowRect = NSRect(
        x: textContainerOrigin.x,
        y: textContainerOrigin.y + lineRect.minY,
        width: tableWidth,
        height: lineRect.height
      )
      (row.isHeader ? headerBackground : rowBackground).setFill()
      rowRect.fill()

      var cellX = rowRect.minX
      for columnIndex in 0..<table.columnCount {
        let width = columnWidths[columnIndex]
        let cellRect = NSRect(x: cellX, y: rowRect.minY, width: width, height: rowRect.height)
        separatorColor.setStroke()
        NSBezierPath(rect: cellRect).stroke()

        let value = columnIndex < row.cells.count ? row.cells[columnIndex] : ""
        let attributes = markdownTableTextAttributes(isHeader: row.isHeader)
        let textSize = (value as NSString).size(withAttributes: attributes)
        let textRect = NSRect(
          x: cellRect.minX + 10,
          y: cellRect.midY - min(textSize.height, cellRect.height - 8) / 2,
          width: max(0, cellRect.width - 20),
          height: max(0, cellRect.height - 8)
        )
        (value as NSString).draw(in: textRect, withAttributes: attributes)
        cellX += width
      }
    }
  }

  private func markdownTableColumnWidths(for table: MarkdownTableBlock, maxWidth: CGFloat) -> [CGFloat] {
    let minimumWidth: CGFloat = 64
    let padding: CGFloat = 24
    let headerFont = NSFont.systemFont(ofSize: 13, weight: .semibold)
    let bodyFont = NSFont.systemFont(ofSize: 13, weight: .regular)
    var widths = Array(repeating: minimumWidth, count: table.columnCount)

    for row in table.rows {
      let attributes: [NSAttributedString.Key: Any] = [.font: row.isHeader ? headerFont : bodyFont]
      for columnIndex in 0..<table.columnCount {
        let value = columnIndex < row.cells.count ? row.cells[columnIndex] : ""
        widths[columnIndex] = max(widths[columnIndex], (value as NSString).size(withAttributes: attributes).width + padding)
      }
    }

    let totalWidth = widths.reduce(0, +)
    guard totalWidth > maxWidth, maxWidth > 0 else {
      return widths
    }

    let minimumTotal = minimumWidth * CGFloat(table.columnCount)
    if maxWidth <= minimumTotal {
      return Array(repeating: maxWidth / CGFloat(table.columnCount), count: table.columnCount)
    }

    let extraWidth = maxWidth - minimumTotal
    let currentExtra = totalWidth - minimumTotal
    return widths.map { minimumWidth + (($0 - minimumWidth) / currentExtra * extraWidth) }
  }

  private func markdownTableTextAttributes(isHeader: Bool) -> [NSAttributedString.Key: Any] {
    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.lineBreakMode = .byTruncatingTail
    return [
      .font: NSFont.systemFont(ofSize: 13, weight: isHeader ? .semibold : .regular),
      .foregroundColor: theme.nsColor(.primaryText),
      .paragraphStyle: paragraphStyle
    ]
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
      theme.nsColor(.separator).withAlphaComponent(0.85).setStroke()
      path.stroke()
    }
  }

  private func drawTaskCheckboxes() {
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

    textStorage.enumerateAttribute(.latticeTaskCheckbox, in: visibleCharacterRange) { value, range, _ in
      guard value as? Bool == true else {
        return
      }

      let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
      guard glyphRange.length > 0 else {
        return
      }

      let lineRect = layoutManager.lineFragmentUsedRect(forGlyphAt: glyphRange.location, effectiveRange: nil)
      let checkboxBounds = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
      let isChecked = textStorage.attribute(.latticeTaskCheckboxChecked, at: range.location, effectiveRange: nil) as? Bool == true
      let size = min(15, max(10, lineRect.height - 5))
      let origin = NSPoint(
        x: textContainerOrigin.x + checkboxBounds.minX,
        y: textContainerOrigin.y + lineRect.midY - size / 2
      )
      let rect = NSRect(origin: origin, size: NSSize(width: size, height: size)).integral
      let path = NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3)
      path.lineWidth = 1.4
      theme.nsColor(.accent).setStroke()
      path.stroke()

      guard isChecked else {
        return
      }

      let check = NSBezierPath()
      check.lineWidth = 1.8
      check.lineCapStyle = .round
      check.lineJoinStyle = .round
      check.move(to: NSPoint(x: rect.minX + size * 0.25, y: rect.midY))
      check.line(to: NSPoint(x: rect.minX + size * 0.43, y: rect.maxY - size * 0.28))
      check.line(to: NSPoint(x: rect.maxX - size * 0.2, y: rect.minY + size * 0.28))
      theme.nsColor(.accent).setStroke()
      check.stroke()
    }
  }

  private func drawImagePreviews() {
    guard let layoutManager, let textContainer else {
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

    for layout in imagePreviewLayouts(in: visibleCharacterRange) {
      let backgroundRect = layout.imageRect.insetBy(dx: -6, dy: -6)
      NSColor.controlBackgroundColor.withAlphaComponent(0.72).setFill()
      NSBezierPath(roundedRect: backgroundRect, xRadius: 6, yRadius: 6).fill()
      layout.image.draw(in: layout.imageRect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
      drawResizeHandle(in: layout.handleRect)
    }
  }

  private func imagePreviewLayout(at location: NSPoint) -> ImagePreviewLayout? {
    guard let textStorage else {
      return nil
    }
    let range = NSRange(location: 0, length: textStorage.length)
    return imagePreviewLayouts(in: range).first {
      $0.handleRect.contains(location) || $0.imageRect.contains(location)
    }
  }

  private func imagePreviewLayouts(in characterRange: NSRange) -> [ImagePreviewLayout] {
    guard let layoutManager, let textStorage else {
      return []
    }
    var layouts: [ImagePreviewLayout] = []
    textStorage.enumerateAttribute(.latticeImagePreviewURL, in: characterRange) { value, range, _ in
      guard
        let url = value as? URL,
        let image = NSImage(contentsOf: url)
      else {
        return
      }

      let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
      guard glyphRange.length > 0 else {
        return
      }

      let lineRect = layoutManager.lineFragmentUsedRect(forGlyphAt: glyphRange.location, effectiveRange: nil)
      let maxWidth = max(0, bounds.width - textContainerInset.width - 2)
      let maxHeight = max(0, lineRect.height - 18)
      guard image.size.width > 0, image.size.height > 0, maxWidth > 0, maxHeight > 0 else {
        return
      }

      let storedWidth = textStorage.attribute(.latticeImagePreviewWidth, at: range.location, effectiveRange: nil) as? Double
      let widthLimit = storedWidth.map { min(maxWidth, max(96, CGFloat($0))) } ?? maxWidth
      let scale = min(widthLimit / image.size.width, maxHeight / image.size.height)
      let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
      let rect = NSRect(
        x: textContainerOrigin.x,
        y: textContainerOrigin.y + lineRect.minY + max(0, (lineRect.height - size.height) / 2),
        width: size.width,
        height: size.height
      )
      let handleRect = NSRect(x: rect.maxX - 12, y: rect.minY, width: 24, height: rect.height)
      layouts.append(ImagePreviewLayout(
        lineLocation: range.location,
        image: image,
        imageRect: rect,
        handleRect: handleRect,
        maxWidth: maxWidth
      ))
    }
    return layouts
  }

  private func drawResizeHandle(in rect: NSRect) {
    let handleRect = NSRect(
      x: rect.midX - 2,
      y: rect.midY - 28,
      width: 4,
      height: 56
    )
    NSColor.separatorColor.withAlphaComponent(0.85).setFill()
    NSBezierPath(roundedRect: handleRect, xRadius: 2, yRadius: 2).fill()
  }
}

private struct ImagePreviewLayout {
  let lineLocation: Int
  let image: NSImage
  let imageRect: NSRect
  let handleRect: NSRect
  let maxWidth: CGFloat
}

private struct ImageResizeDrag {
  let lineLocation: Int
  let imageMinX: CGFloat
  let minWidth: CGFloat
  let maxWidth: CGFloat
}

private extension NSImage {
  func pngData() -> Data? {
    guard
      let tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiffRepresentation)
    else {
      return nil
    }
    return bitmap.representation(using: .png, properties: [:])
  }
}

private final class RelativeLineNumberRulerView: NSRulerView {
  private weak var textView: MarkdownTextView?
  private let rulerWidth: CGFloat = 44

  init(textView: MarkdownTextView) {
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

  override func draw(_ dirtyRect: NSRect) {
    drawHashMarksAndLabels(in: dirtyRect)
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
    layoutManager.ensureLayout(for: textContainer)
    let attributes: [NSAttributedString.Key: Any] = [
      .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular),
      .foregroundColor: textView.theme.nsColor(.secondaryText)
    ]
    let activeAttributes: [NSAttributedString.Key: Any] = [
      .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
      .foregroundColor: textView.theme.nsColor(.primaryText)
    ]
    let normalModeActiveAttributes: [NSAttributedString.Key: Any] = [
      .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold),
      .foregroundColor: textView.theme.nsColor(.accent)
    ]
    let showsNormalModeIndicator = textView.showsVimNormalModeIndicator

    if nsString.length == 0 {
      let lineRect = layoutManager.extraLineFragmentRect
      drawLineNumberIfVisible(
        1,
        selectedLine: selectedLine,
        y: lineRect.minY + origin.y,
        visibleRect: visibleRect,
        attributes: attributes,
        activeAttributes: activeAttributes,
        normalModeActiveAttributes: normalModeActiveAttributes,
        showsNormalModeIndicator: showsNormalModeIndicator
      )
      return
    }

    var lineNumber = 1
    var location = 0
    while location < nsString.length {
      let lineRange = nsString.lineRange(for: NSRange(location: location, length: 0))
      let lineRect = lineRect(
        forCharacterRange: lineRange,
        layoutManager: layoutManager,
        textContainer: textContainer
      )
      drawLineNumberIfVisible(
        lineNumber,
        selectedLine: selectedLine,
        y: lineRect.minY + origin.y,
        visibleRect: visibleRect,
        attributes: attributes,
        activeAttributes: activeAttributes,
        normalModeActiveAttributes: normalModeActiveAttributes,
        showsNormalModeIndicator: showsNormalModeIndicator
      )

      let nextLocation = NSMaxRange(lineRange)
      if nextLocation <= location {
        break
      }
      location = nextLocation
      lineNumber += 1
    }

    if location == nsString.length,
       let scalar = Unicode.Scalar(nsString.character(at: nsString.length - 1)),
       CharacterSet.newlines.contains(scalar) {
      let lineRect = layoutManager.extraLineFragmentRect
      drawLineNumberIfVisible(
        lineNumber,
        selectedLine: selectedLine,
        y: lineRect.minY + origin.y,
        visibleRect: visibleRect,
        attributes: attributes,
        activeAttributes: activeAttributes,
        normalModeActiveAttributes: normalModeActiveAttributes,
        showsNormalModeIndicator: showsNormalModeIndicator
      )
    }
  }

  private func lineRect(
    forCharacterRange characterRange: NSRange,
    layoutManager: NSLayoutManager,
    textContainer: NSTextContainer
  ) -> NSRect {
    let glyphRange = layoutManager.glyphRange(
      forCharacterRange: characterRange,
      actualCharacterRange: nil
    )
    guard glyphRange.length > 0 else {
      return layoutManager.extraLineFragmentRect
    }
    return layoutManager.lineFragmentRect(forGlyphAt: glyphRange.location, effectiveRange: nil)
  }

  private func drawLineNumberIfVisible(
    _ lineNumber: Int,
    selectedLine: Int,
    y: CGFloat,
    visibleRect: NSRect,
    attributes: [NSAttributedString.Key: Any],
    activeAttributes: [NSAttributedString.Key: Any],
    normalModeActiveAttributes: [NSAttributedString.Key: Any],
    showsNormalModeIndicator: Bool
  ) {
    guard y.isFinite, y >= visibleRect.minY - 24, y <= visibleRect.maxY + 24 else {
      return
    }

    let isActiveLine = lineNumber == selectedLine
    let value = VimTextEditing.relativeLineNumber(
      lineNumber: lineNumber,
      activeLineNumber: selectedLine
    )
    let lineAttributes: [NSAttributedString.Key: Any]
    if isActiveLine, showsNormalModeIndicator {
      lineAttributes = normalModeActiveAttributes
    } else if isActiveLine {
      lineAttributes = activeAttributes
    } else {
      lineAttributes = attributes
    }
    draw("\(value)", y: y, attributes: lineAttributes)
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
    let clampedLocation = max(0, min(location, nsString.length))

    guard clampedLocation > 0 else {
      return line
    }

    for index in 0..<clampedLocation {
      guard
        let scalar = Unicode.Scalar(nsString.character(at: index)),
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

public struct MarkdownTextEditor: UIViewRepresentable {
  @Binding var text: String
  @Binding var selectedRange: NSRange
  @Binding var vimState: VimEditorState
  let fontSize: CGFloat
  let fontFamily: EditorFontFamily
  let focusToken: Int
  let isVimModeEnabled: Bool
  let showsRelativeLineNumbers: Bool
  let dimsInactiveParagraphs: Bool
  let caretAnchorFraction: CGFloat?
  @Binding var autocompleteAnchor: CGRect?
  let keyboardAccessoryActions: [MarkdownKeyboardAccessoryAction]
  let hasAutocompleteSuggestions: Bool
  let wikiLinkStates: [WikiLinkRenderState]
  let theme: LatticeTheme
  let imagePreviewStates: [MarkdownImageRenderState]
  let onTextChange: () -> Void
  let onSelectionChange: () -> Void
  let onWikiLinkActivated: (Int) -> Void
  let onMarkdownLinkActivated: (Int) -> Void
  let onDismissAutocomplete: () -> Void
  let onMoveAutocompleteSelection: (Int) -> Void
  let onCommitAutocomplete: () -> Void
  let onVimWrite: () -> Void
  let onVimStatusChange: (String?) -> Void
  let onImageAttachmentsImported: ([ImageAttachmentImport]) -> Void
  let onImageAttachmentResized: (Int, Double) -> Void

  public init(
    text: Binding<String>,
    selectedRange: Binding<NSRange>,
    vimState: Binding<VimEditorState>,
    fontSize: CGFloat,
    fontFamily: EditorFontFamily,
    focusToken: Int,
    isVimModeEnabled: Bool,
    showsRelativeLineNumbers: Bool,
    dimsInactiveParagraphs: Bool = false,
    caretAnchorFraction: CGFloat? = nil,
    autocompleteAnchor: Binding<CGRect?> = .constant(nil),
    keyboardAccessoryActions: [MarkdownKeyboardAccessoryAction] = [],
    hasAutocompleteSuggestions: Bool,
    wikiLinkStates: [WikiLinkRenderState],
    theme: LatticeTheme,
    imagePreviewStates: [MarkdownImageRenderState],
    onTextChange: @escaping () -> Void,
    onSelectionChange: @escaping () -> Void,
    onWikiLinkActivated: @escaping (Int) -> Void,
    onMarkdownLinkActivated: @escaping (Int) -> Void,
    onDismissAutocomplete: @escaping () -> Void,
    onMoveAutocompleteSelection: @escaping (Int) -> Void = { _ in },
    onCommitAutocomplete: @escaping () -> Void = {},
    onVimWrite: @escaping () -> Void,
    onVimStatusChange: @escaping (String?) -> Void,
    onImageAttachmentsImported: @escaping ([ImageAttachmentImport]) -> Void,
    onImageAttachmentResized: @escaping (Int, Double) -> Void
  ) {
    self._text = text
    self._selectedRange = selectedRange
    self._vimState = vimState
    self.fontSize = fontSize
    self.fontFamily = fontFamily
    self.focusToken = focusToken
    self.isVimModeEnabled = isVimModeEnabled
    self.showsRelativeLineNumbers = showsRelativeLineNumbers
    self.dimsInactiveParagraphs = dimsInactiveParagraphs
    self.caretAnchorFraction = caretAnchorFraction
    self._autocompleteAnchor = autocompleteAnchor
    self.keyboardAccessoryActions = keyboardAccessoryActions
    self.hasAutocompleteSuggestions = hasAutocompleteSuggestions
    self.wikiLinkStates = wikiLinkStates
    self.theme = theme
    self.imagePreviewStates = imagePreviewStates
    self.onTextChange = onTextChange
    self.onSelectionChange = onSelectionChange
    self.onWikiLinkActivated = onWikiLinkActivated
    self.onMarkdownLinkActivated = onMarkdownLinkActivated
    self.onDismissAutocomplete = onDismissAutocomplete
    self.onMoveAutocompleteSelection = onMoveAutocompleteSelection
    self.onCommitAutocomplete = onCommitAutocomplete
    self.onVimWrite = onVimWrite
    self.onVimStatusChange = onVimStatusChange
    self.onImageAttachmentsImported = onImageAttachmentsImported
    self.onImageAttachmentResized = onImageAttachmentResized
  }

  public func makeCoordinator() -> Coordinator {
    Coordinator(parent: self)
  }

  public func makeUIView(context: Context) -> UITextView {
    let textView = MarkdownUIKitTextView()
    textView.delegate = context.coordinator
    textView.markdownCoordinator = context.coordinator
    textView.theme = theme
    textView.backgroundColor = theme.uiColor(.editorBackground)
    textView.isOpaque = true
    textView.textColor = theme.uiColor(.primaryText)
    textView.tintColor = theme.uiColor(.accent)
    textView.isScrollEnabled = true
    textView.alwaysBounceVertical = true
    textView.keyboardDismissMode = .interactive
    textView.textContainerInset = UIEdgeInsets(top: 34, left: 22, bottom: 34, right: 22)
    textView.font = MarkdownAttributedRenderer.bodyFont(fontFamily: fontFamily)
    textView.adjustsFontForContentSizeCategory = true
    textView.autocorrectionType = .yes
    textView.spellCheckingType = .yes
    textView.smartDashesType = .no
    textView.smartQuotesType = .no
    textView.accessibilityIdentifier = "noteEditor"
    textView.addInteraction(UIDropInteraction(delegate: context.coordinator))

    let tapRecognizer = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
    tapRecognizer.delegate = context.coordinator
    tapRecognizer.cancelsTouchesInView = true
    textView.addGestureRecognizer(tapRecognizer)

    context.coordinator.updateKeyboardAccessory(for: textView)
    context.coordinator.startKeyboardObserving()
    context.coordinator.configureCaretAnchorLayout(in: textView)
    context.coordinator.applyHostBackground(for: textView)

    return textView
  }

  public func updateUIView(_ textView: UITextView, context: Context) {
    context.coordinator.parent = self
    (textView as? MarkdownUIKitTextView)?.markdownCoordinator = context.coordinator
    textView.autocorrectionType = .yes
    textView.spellCheckingType = .yes
    context.coordinator.updateKeyboardAccessory(for: textView)
    context.coordinator.configureCaretAnchorLayout(in: textView)
    let clampedSelectedRange = clamped(selectedRange, length: (text as NSString).length)
    let needsTextOrLayoutRender = textView.text != text
      || context.coordinator.lastRenderedFontFamily != fontFamily
      || context.coordinator.lastRenderedDimsInactiveParagraphs != dimsInactiveParagraphs
      || context.coordinator.lastRenderedTheme != theme
    let needsDecorationRender = context.coordinator.lastRenderedWikiLinkStates != wikiLinkStates
      || context.coordinator.lastRenderedImagePreviewStates != imagePreviewStates
    if needsTextOrLayoutRender {
      context.coordinator.render(text, in: textView, preserving: clampedSelectedRange)
    } else if needsDecorationRender {
      if context.coordinator.canSkipFocusedSameLineDecorationRender(
        in: textView,
        text: text,
        selection: clampedSelectedRange
      ) {
        context.coordinator.acknowledgeDecorationInputs()
      } else {
        context.coordinator.render(text, in: textView, preserving: clampedSelectedRange)
      }
    } else if textView.selectedRange != clampedSelectedRange {
      let wikiLinkRange = WikiLinkParser.link(at: clampedSelectedRange.location, in: text)?.range
      if context.coordinator.needsSelectionRender(
        selection: clampedSelectedRange,
        text: text,
        wikiLinkRange: wikiLinkRange
      ) {
        context.coordinator.render(text, in: textView, preserving: clampedSelectedRange)
      } else {
        textView.selectedRange = clampedSelectedRange
        context.coordinator.scheduleCaretVisibility(selection: clampedSelectedRange, animated: false)
      }
    }
    (textView as? MarkdownUIKitTextView)?.theme = theme
    textView.backgroundColor = theme.uiColor(.editorBackground)
    textView.tintColor = theme.uiColor(.accent)
    context.coordinator.applyHostBackground(for: textView)
    context.coordinator.updateAutocompleteAnchor(in: textView, selection: clampedSelectedRange)
    if context.coordinator.lastFocusToken != focusToken {
      context.coordinator.lastFocusToken = focusToken
      DispatchQueue.main.async {
        textView.becomeFirstResponder()
        context.coordinator.applyHostBackground(for: textView)
        context.coordinator.scheduleCaretVisibility(selection: clampedSelectedRange, animated: false)
        context.coordinator.updateAutocompleteAnchor(in: textView, selection: clampedSelectedRange)
      }
    }
  }

  @MainActor
  public final class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate, UIDropInteractionDelegate {
    var parent: MarkdownTextEditor
    var lastFocusToken = 0
    var lastRenderedFontFamily: EditorFontFamily?
    var lastRenderedWikiLinkStates: [WikiLinkRenderState] = []
    var lastRenderedDimsInactiveParagraphs = false
    var lastRenderedTheme = LatticeTheme(id: .system)
    var lastRenderedImagePreviewStates: [MarkdownImageRenderState] = []
    private var lastRenderedActiveRanges: [NSRange] = []
    private var isRendering = false
    private var activeWikiLinkRange: NSRange?
    private var keyboardAccessoryView: MarkdownKeyboardAccessoryView?
    private weak var accessoryTextView: UITextView?
    private weak var textView: UITextView?
    private let defaultTextContainerInset = UIEdgeInsets(top: 34, left: 22, bottom: 34, right: 22)
    private var defaultContentInset: UIEdgeInsets?
    private var pendingAnchorTask: Task<Void, Never>?
    private var pendingViewportFreezeTask: Task<Void, Never>?
    private var pendingKeyboardRevealTask: Task<Void, Never>?
    private var keyboardFrameInScreen: CGRect?
    private var frozenTypingContentOffsetY: CGFloat?
    private var isApplyingProgrammaticContentOffset = false
    private var isObservingKeyboard = false

    private nonisolated static let imageTypeIdentifiers = [
      UTType.image.identifier,
      UTType.png.identifier,
      UTType.jpeg.identifier,
      UTType.heic.identifier,
      UTType.gif.identifier,
      UTType.tiff.identifier,
      "org.webmproject.webp"
    ]

    init(parent: MarkdownTextEditor) {
      self.parent = parent
    }

    deinit {
      pendingAnchorTask?.cancel()
      pendingViewportFreezeTask?.cancel()
      pendingKeyboardRevealTask?.cancel()
      NotificationCenter.default.removeObserver(self)
    }

    func startKeyboardObserving() {
      guard !isObservingKeyboard else {
        return
      }

      let center = NotificationCenter.default
      center.addObserver(
        self,
        selector: #selector(keyboardFrameDidChange(_:)),
        name: UIResponder.keyboardWillChangeFrameNotification,
        object: nil
      )
      center.addObserver(
        self,
        selector: #selector(keyboardFrameDidChange(_:)),
        name: UIResponder.keyboardDidChangeFrameNotification,
        object: nil
      )
      center.addObserver(
        self,
        selector: #selector(keyboardFrameDidChange(_:)),
        name: UIResponder.keyboardWillHideNotification,
        object: nil
      )
      isObservingKeyboard = true
    }

    @objc private func keyboardFrameDidChange(_ notification: Notification) {
      keyboardFrameInScreen = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
      guard let textView else {
        return
      }

      applyHostBackground(for: textView)
      configureCaretAnchorLayout(in: textView)
      scheduleCaretVisibility(selection: textView.selectedRange, animated: false)
      updateAutocompleteAnchor(in: textView, selection: textView.selectedRange)
    }

    func applyHostBackground(for textView: UITextView) {
      let color = parent.theme.uiColor(.editorBackground)
      textView.backgroundColor = color
      textView.superview?.backgroundColor = color
      textView.window?.backgroundColor = color
    }

    func updateKeyboardAccessory(for textView: UITextView) {
      self.textView = textView
      accessoryTextView = textView
      guard !parent.keyboardAccessoryActions.isEmpty else {
        if textView.inputAccessoryView != nil {
          textView.inputAccessoryView = nil
          textView.reloadInputViews()
        }
        keyboardAccessoryView = nil
        return
      }

      let accessoryView = keyboardAccessoryView ?? MarkdownKeyboardAccessoryView()
      keyboardAccessoryView = accessoryView
      accessoryView.configure(
        actions: parent.keyboardAccessoryActions,
        theme: parent.theme,
        target: self,
        action: #selector(handleKeyboardAccessoryButton(_:)),
        dismissAction: #selector(dismissKeyboardAccessoryButton(_:))
      )

      if textView.inputAccessoryView !== accessoryView {
        textView.inputAccessoryView = accessoryView
        textView.reloadInputViews()
      }
    }

    @objc private func handleKeyboardAccessoryButton(_ sender: MarkdownKeyboardAccessoryButton) {
      guard
        let id = sender.actionID,
        let action = parent.keyboardAccessoryActions.first(where: { $0.id == id })
      else {
        return
      }

      MarkdownKeyboardAccessoryHaptics.perform()
      performKeyboardAccessoryAction(action)
    }

    @objc private func dismissKeyboardAccessoryButton(_ sender: UIButton) {
      MarkdownKeyboardAccessoryHaptics.perform()
      accessoryTextView?.resignFirstResponder()
    }

    func performKeyboardAccessoryAction(_ action: MarkdownKeyboardAccessoryAction) {
      switch action.id {
      case "indent":
        if let accessoryTextView,
           applyMarkdownListIndentation(in: accessoryTextView, direction: .indent) {
          return
        }
      case "outdent":
        if let accessoryTextView,
           applyMarkdownListIndentation(in: accessoryTextView, direction: .outdent) {
          return
        }
      default:
        break
      }

      action.perform()
    }

    public func textViewDidChange(_ textView: UITextView) {
      guard !isRendering else {
        return
      }
      parent.text = textView.text
      parent.selectedRange = textView.selectedRange
      parent.onTextChange()
      updateAutocompleteAnchor(in: textView, selection: textView.selectedRange)
      guard !parent.dimsInactiveParagraphs else {
        let activeLineLocation = Self.lineRange(containing: textView.selectedRange, in: textView.text).location
        let didChangeActiveLine = activeLineLocation != lastRenderedActiveRanges.first?.location
        if didChangeActiveLine {
          render(textView.text, in: textView, preserving: textView.selectedRange)
        }
        return
      }
      render(textView.text, in: textView, preserving: textView.selectedRange)
    }

    public func textViewDidChangeSelection(_ textView: UITextView) {
      guard !isRendering else {
        return
      }
      parent.selectedRange = textView.selectedRange
      parent.onSelectionChange()
      let clampedSelection = clamped(textView.selectedRange, length: (textView.text as NSString).length)
      updateAutocompleteAnchor(in: textView, selection: clampedSelection)
      let nextActiveWikiLinkRange = WikiLinkParser.link(at: clampedSelection.location, in: textView.text)?.range
      if needsSelectionRender(selection: clampedSelection, text: textView.text, wikiLinkRange: nextActiveWikiLinkRange) {
        render(textView.text, in: textView, preserving: clampedSelection)
      } else if !parent.dimsInactiveParagraphs {
        scheduleCaretVisibility(selection: clampedSelection, animated: false)
      }
    }

    public func scrollViewDidChangeAdjustedContentInset(_ scrollView: UIScrollView) {
      guard let textView = scrollView as? UITextView else {
        return
      }
      configureCaretAnchorLayout(in: textView)
      scheduleCaretVisibility(selection: textView.selectedRange, animated: false)
      updateAutocompleteAnchor(in: textView, selection: textView.selectedRange)
    }

    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
      guard let textView = scrollView as? UITextView else {
        return
      }
      restoreFrozenViewportIfNeeded(in: textView)
      updateAutocompleteAnchor(in: textView, selection: textView.selectedRange)
    }

    public func textView(
      _ textView: UITextView,
      shouldChangeTextIn range: NSRange,
      replacementText text: String
    ) -> Bool {
      if text == "\t" {
        return !applyMarkdownListIndentation(in: textView, direction: .indent)
      }

      guard text == "\n",
            let result = MarkdownListContinuation.applyReturn(to: textView.text, selection: range)
      else {
        if applyAnchoredZenReplacement(in: textView, range: range, replacementText: text) {
          return false
        }
        return true
      }

      textView.textStorage.replaceCharacters(in: result.replacementRange, with: result.replacement)
      textView.selectedRange = result.selection
      parent.text = textView.text
      parent.selectedRange = textView.selectedRange
      parent.onTextChange()
      updateAutocompleteAnchor(in: textView, selection: textView.selectedRange)
      render(textView.text, in: textView, preserving: textView.selectedRange)
      return false
    }

    enum IndentationDirection {
      case indent
      case outdent
    }

    func applyMarkdownListIndentation(
      in textView: UITextView,
      direction: IndentationDirection
    ) -> Bool {
      let result: MarkdownListIndentationResult?
      switch direction {
      case .indent:
        result = MarkdownListIndentation.applyIndent(to: textView.text, selection: textView.selectedRange)
      case .outdent:
        result = MarkdownListIndentation.applyOutdent(to: textView.text, selection: textView.selectedRange)
      }

      guard let result else {
        return false
      }

      textView.textStorage.replaceCharacters(in: result.replacementRange, with: result.replacement)
      textView.selectedRange = result.selection
      parent.text = textView.text
      parent.selectedRange = textView.selectedRange
      parent.onTextChange()
      updateAutocompleteAnchor(in: textView, selection: textView.selectedRange)
      render(textView.text, in: textView, preserving: textView.selectedRange)
      return true
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
      updateAutocompleteAnchor(in: textView, selection: textView.selectedRange)
      render(textView.text, in: textView, preserving: textView.selectedRange)
    }

    func render(_ text: String, in textView: UITextView, preserving selection: NSRange) {
      guard !isRendering else {
        return
      }
      isRendering = true
      let clampedSelection = clamped(selection, length: (text as NSString).length)
      activeWikiLinkRange = WikiLinkParser.link(at: clampedSelection.location, in: text)?.range
      let activeRanges = activeRanges(for: clampedSelection, in: text)
      textView.textColor = parent.theme.uiColor(.primaryText)
      let renderedText = MarkdownAttributedRenderer.render(
        text,
        fontFamily: parent.fontFamily,
        activeRanges: activeRanges,
        wikiLinkStates: parent.wikiLinkStates,
        dimsInactiveText: parent.dimsInactiveParagraphs,
        theme: parent.theme,
        imagePreviewStates: parent.imagePreviewStates
      )
      let typingAttributes = MarkdownAttributedRenderer.baseTypingAttributes(
        fontFamily: parent.fontFamily,
        theme: parent.theme
      )
      if parent.normalizedCaretAnchorFraction != nil {
        let currentOffset = textView.contentOffset
        performProgrammaticContentOffsetChange {
          textView.textStorage.setAttributedString(renderedText)
          textView.selectedRange = clampedSelection
          textView.typingAttributes = typingAttributes
          textView.setContentOffset(currentOffset, animated: false)
          textView.layoutIfNeeded()
        }
      } else {
        textView.textStorage.setAttributedString(renderedText)
        textView.selectedRange = clampedSelection
        textView.typingAttributes = typingAttributes
      }
      textView.setNeedsDisplay()
      lastRenderedFontFamily = parent.fontFamily
      lastRenderedWikiLinkStates = parent.wikiLinkStates
      lastRenderedDimsInactiveParagraphs = parent.dimsInactiveParagraphs
      lastRenderedTheme = parent.theme
      lastRenderedImagePreviewStates = parent.imagePreviewStates
      lastRenderedActiveRanges = activeRanges
      isRendering = false
      scheduleCaretVisibility(selection: clampedSelection, animated: false)
      updateAutocompleteAnchor(in: textView, selection: clampedSelection)
    }

    private func applyAnchoredZenReplacement(
      in textView: UITextView,
      range: NSRange,
      replacementText: String
    ) -> Bool {
      guard
        parent.normalizedCaretAnchorFraction != nil,
        parent.dimsInactiveParagraphs,
        textView.markedTextRange == nil
      else {
        return false
      }

      let textLength = (textView.text as NSString).length
      let clampedRange = clamped(range, length: textLength)
      let previousActiveLineLocation = lastRenderedActiveRanges.first?.location
        ?? Self.lineRange(containing: clampedRange, in: textView.text).location
      let originalContentOffsetY = textView.contentOffset.y
      let replacementLength = (replacementText as NSString).length
      let nextSelection = NSRange(location: clampedRange.location + replacementLength, length: 0)
      let typingAttributes = MarkdownAttributedRenderer.baseTypingAttributes(
        fontFamily: parent.fontFamily,
        theme: parent.theme
      )

      freezeViewport(at: originalContentOffsetY)
      performProgrammaticContentOffsetChange {
        textView.textStorage.replaceCharacters(in: clampedRange, with: replacementText)
        if replacementLength > 0 {
          textView.textStorage.addAttributes(
            typingAttributes,
            range: NSRange(location: clampedRange.location, length: replacementLength)
          )
        }
        textView.selectedRange = clamped(nextSelection, length: (textView.text as NSString).length)
        textView.typingAttributes = typingAttributes
        textView.setContentOffset(
          CGPoint(x: textView.contentOffset.x, y: originalContentOffsetY),
          animated: false
        )
        textView.layoutIfNeeded()
        textView.setContentOffset(
          CGPoint(x: textView.contentOffset.x, y: originalContentOffsetY),
          animated: false
        )
      }

      let targetOffsetY = anchoredContentOffsetY(in: textView, selection: textView.selectedRange)
      if let targetOffsetY {
        freezeViewport(at: targetOffsetY)
        performProgrammaticContentOffsetChange {
          textView.setContentOffset(
            CGPoint(x: textView.contentOffset.x, y: targetOffsetY),
            animated: false
          )
          textView.layoutIfNeeded()
        }
      }

      parent.text = textView.text
      parent.selectedRange = textView.selectedRange
      parent.onTextChange()
      updateAutocompleteAnchor(in: textView, selection: textView.selectedRange)

      let activeLineRange = Self.lineRange(containing: textView.selectedRange, in: textView.text)
      if activeLineRange.location != previousActiveLineLocation {
        clearFrozenViewport()
        render(textView.text, in: textView, preserving: textView.selectedRange)
      } else {
        lastRenderedActiveRanges = [activeLineRange]
        textView.setNeedsDisplay()
        clearFrozenViewportAfterLayout()
      }

      return true
    }

    private func freezeViewport(at offsetY: CGFloat) {
      guard parent.normalizedCaretAnchorFraction != nil, parent.dimsInactiveParagraphs else {
        return
      }

      pendingViewportFreezeTask?.cancel()
      frozenTypingContentOffsetY = offsetY
    }

    private func clearFrozenViewportAfterLayout() {
      pendingViewportFreezeTask?.cancel()
      pendingViewportFreezeTask = Task { @MainActor [weak self] in
        await Task.yield()
        await Task.yield()
        guard !Task.isCancelled else {
          return
        }
        self?.frozenTypingContentOffsetY = nil
        self?.pendingViewportFreezeTask = nil
      }
    }

    private func anchoredContentOffsetY(in textView: UITextView, selection: NSRange) -> CGFloat? {
      guard let anchor = parent.normalizedCaretAnchorFraction else {
        return nil
      }

      textView.layoutIfNeeded()
      guard textView.bounds.height > 0,
            let caretRect = caretRect(for: selection, in: textView)
      else {
        return nil
      }

      let targetOffsetY = caretRect.midY - textView.bounds.height * anchor
      return constrainedContentOffsetY(targetOffsetY, in: textView)
    }

    private func constrainedContentOffsetY(_ offsetY: CGFloat, in textView: UITextView) -> CGFloat {
      let minOffsetY = -textView.adjustedContentInset.top
      let maxOffsetY = max(
        minOffsetY,
        textView.contentSize.height + textView.adjustedContentInset.bottom - textView.bounds.height
      )
      return min(max(offsetY, minOffsetY), maxOffsetY)
    }

    private func clearFrozenViewport() {
      pendingViewportFreezeTask?.cancel()
      pendingViewportFreezeTask = nil
      frozenTypingContentOffsetY = nil
    }

    @discardableResult
    func restoreFrozenViewportIfNeeded(in textView: UITextView) -> Bool {
      guard
        !isApplyingProgrammaticContentOffset,
        parent.normalizedCaretAnchorFraction != nil,
        parent.dimsInactiveParagraphs,
        let frozenTypingContentOffsetY,
        textView.isFirstResponder,
        !textView.isTracking,
        !textView.isDragging,
        !textView.isDecelerating,
        abs(textView.contentOffset.y - frozenTypingContentOffsetY) > 0.5
      else {
        return false
      }

      performProgrammaticContentOffsetChange {
        textView.setContentOffset(
          CGPoint(x: textView.contentOffset.x, y: frozenTypingContentOffsetY),
          animated: false
        )
        textView.layoutIfNeeded()
      }
      return true
    }

    func protectedContentOffset(for textView: UITextView, proposed offset: CGPoint) -> CGPoint? {
      guard
        !isApplyingProgrammaticContentOffset,
        parent.normalizedCaretAnchorFraction != nil,
        parent.dimsInactiveParagraphs,
        let frozenTypingContentOffsetY,
        textView.isFirstResponder,
        !textView.isTracking,
        !textView.isDragging,
        !textView.isDecelerating,
        abs(offset.y - frozenTypingContentOffsetY) > 0.5
      else {
        return nil
      }

      return CGPoint(x: offset.x, y: frozenTypingContentOffsetY)
    }

    private func performProgrammaticContentOffsetChange(_ body: () -> Void) {
      isApplyingProgrammaticContentOffset = true
      defer {
        isApplyingProgrammaticContentOffset = false
      }
      UIView.performWithoutAnimation {
        body()
      }
    }

    private func activeRanges(for selection: NSRange, in text: String) -> [NSRange] {
      parent.dimsInactiveParagraphs
        ? [Self.lineRange(containing: selection, in: text)]
        : [selection]
    }

    func canSkipFocusedSameLineDecorationRender(
      in textView: UITextView,
      text: String,
      selection: NSRange
    ) -> Bool {
      guard
        parent.normalizedCaretAnchorFraction != nil,
        parent.dimsInactiveParagraphs,
        textView.isFirstResponder,
        textView.text == text
      else {
        return false
      }

      return Self.lineRange(containing: selection, in: text).location == lastRenderedActiveRanges.first?.location
    }

    func acknowledgeDecorationInputs() {
      lastRenderedWikiLinkStates = parent.wikiLinkStates
      lastRenderedImagePreviewStates = parent.imagePreviewStates
    }

    func needsSelectionRender(selection: NSRange, text: String, wikiLinkRange: NSRange?) -> Bool {
      if wikiLinkRange != activeWikiLinkRange {
        return true
      }

      guard parent.dimsInactiveParagraphs else {
        return false
      }

      return Self.lineRange(containing: selection, in: text).location != lastRenderedActiveRanges.first?.location
    }

    func configureCaretAnchorLayout(in textView: UITextView) {
      self.textView = textView
      if defaultContentInset == nil {
        defaultContentInset = textView.contentInset
      }

      let keyboardBottomInset = keyboardOcclusionHeight(in: textView)
      let baseContentInset = defaultContentInset ?? .zero
      guard let anchor = parent.normalizedCaretAnchorFraction else {
        pendingAnchorTask?.cancel()
        let contentInset = UIEdgeInsets(
          top: baseContentInset.top,
          left: baseContentInset.left,
          bottom: baseContentInset.bottom + keyboardBottomInset,
          right: baseContentInset.right
        )
        applyInsets(
          textContainerInset: defaultTextContainerInset,
          contentInset: contentInset,
          to: textView
        )
        textView.showsVerticalScrollIndicator = true
        return
      }

      let visibleHeight = max(0, textView.bounds.height)
      guard visibleHeight > 0 else {
        return
      }

      let contentInset = UIEdgeInsets(
        top: baseContentInset.top + visibleHeight * anchor,
        left: baseContentInset.left,
        bottom: baseContentInset.bottom + keyboardBottomInset + visibleHeight * (1 - anchor),
        right: baseContentInset.right
      )
      applyInsets(
        textContainerInset: defaultTextContainerInset,
        contentInset: contentInset,
        to: textView
      )
      textView.showsVerticalScrollIndicator = false
    }

    func scheduleCaretVisibility(selection: NSRange? = nil, animated: Bool) {
      if parent.normalizedCaretAnchorFraction != nil {
        scheduleCaretAnchor(selection: selection, animated: animated)
      } else {
        scheduleKeyboardCaretReveal(selection: selection, animated: animated)
      }
    }

    func scheduleCaretAnchor(selection: NSRange? = nil, animated: Bool) {
      guard parent.normalizedCaretAnchorFraction != nil else {
        return
      }

      pendingAnchorTask?.cancel()
      pendingAnchorTask = Task { @MainActor [weak self] in
        await Task.yield()
        guard !Task.isCancelled, let self, let textView = self.textView else {
          return
        }
        self.configureCaretAnchorLayout(in: textView)
        let targetSelection = selection ?? textView.selectedRange
        self.scrollCaretToAnchor(in: textView, selection: targetSelection, animated: animated)
        self.updateAutocompleteAnchor(in: textView, selection: targetSelection)
      }
    }

    func scheduleKeyboardCaretReveal(selection: NSRange? = nil, animated: Bool) {
      pendingKeyboardRevealTask?.cancel()
      pendingKeyboardRevealTask = Task { @MainActor [weak self] in
        await Task.yield()
        guard !Task.isCancelled, let self, let textView = self.textView else {
          return
        }
        self.configureCaretAnchorLayout(in: textView)
        guard self.keyboardOcclusionHeight(in: textView) > 0 else {
          return
        }
        let targetSelection = selection ?? textView.selectedRange
        self.scrollCaretAboveKeyboard(in: textView, selection: targetSelection, animated: animated)
        self.updateAutocompleteAnchor(in: textView, selection: targetSelection)
      }
    }

    func scrollCaretToAnchor(in textView: UITextView, selection: NSRange, animated: Bool) {
      guard let anchor = parent.normalizedCaretAnchorFraction else {
        return
      }

      textView.layoutIfNeeded()
      guard textView.bounds.height > 0,
            let caretRect = caretRect(for: selection, in: textView)
      else {
        return
      }

      let targetOffsetY = caretRect.midY - textView.bounds.height * anchor
      let constrainedOffsetY = constrainedContentOffsetY(targetOffsetY, in: textView)
      guard abs(textView.contentOffset.y - constrainedOffsetY) > 0.5 else {
        return
      }

      let offset = CGPoint(x: textView.contentOffset.x, y: constrainedOffsetY)
      if animated {
        textView.setContentOffset(offset, animated: true)
      } else {
        performProgrammaticContentOffsetChange {
          textView.setContentOffset(offset, animated: false)
          textView.layoutIfNeeded()
        }
      }
    }

    func scrollCaretAboveKeyboard(in textView: UITextView, selection: NSRange, animated: Bool) {
      textView.layoutIfNeeded()
      guard textView.bounds.height > 0,
            let caretRect = caretRect(for: selection, in: textView)
      else {
        return
      }

      let verticalMargin = max(8, caretRect.height)
      let visibleTop = textView.contentOffset.y + textView.adjustedContentInset.top
      let visibleBottom = textView.contentOffset.y + textView.bounds.height - textView.adjustedContentInset.bottom
      var targetOffsetY = textView.contentOffset.y

      if caretRect.maxY + verticalMargin > visibleBottom {
        targetOffsetY += caretRect.maxY + verticalMargin - visibleBottom
      } else if caretRect.minY - verticalMargin < visibleTop {
        targetOffsetY -= visibleTop - (caretRect.minY - verticalMargin)
      } else {
        return
      }

      let constrainedOffsetY = constrainedContentOffsetY(targetOffsetY, in: textView)
      guard abs(textView.contentOffset.y - constrainedOffsetY) > 0.5 else {
        return
      }

      let offset = CGPoint(x: textView.contentOffset.x, y: constrainedOffsetY)
      if animated {
        textView.setContentOffset(offset, animated: true)
      } else {
        performProgrammaticContentOffsetChange {
          textView.setContentOffset(offset, animated: false)
          textView.layoutIfNeeded()
        }
      }
    }

    func updateAutocompleteAnchor(in textView: UITextView, selection: NSRange) {
      guard parent.hasAutocompleteSuggestions else {
        if parent.autocompleteAnchor != nil {
          parent.autocompleteAnchor = nil
        }
        return
      }

      textView.layoutIfNeeded()
      guard let caretRect = caretRect(for: selection, in: textView) else {
        parent.autocompleteAnchor = nil
        return
      }

      let visibleRect = CGRect(
        x: caretRect.minX - textView.contentOffset.x,
        y: caretRect.minY - textView.contentOffset.y,
        width: max(1, caretRect.width),
        height: caretRect.height
      )
      guard visibleRect.hasFiniteCoordinates else {
        parent.autocompleteAnchor = nil
        return
      }

      parent.autocompleteAnchor = visibleRect
    }

    private func keyboardOcclusionHeight(in textView: UITextView) -> CGFloat {
      guard textView.isFirstResponder else {
        return 0
      }

      let guideFrame = textView.keyboardLayoutGuide.layoutFrame
      if guideFrame.hasFiniteCoordinates,
         !guideFrame.isNull,
         guideFrame.minY < textView.bounds.maxY {
        return max(0, textView.bounds.maxY - max(textView.bounds.minY, guideFrame.minY))
      }

      guard
        let keyboardFrameInScreen,
        let window = textView.window
      else {
        return 0
      }

      let keyboardFrameInWindow = window.convert(keyboardFrameInScreen, from: nil)
      let keyboardFrameInTextView = textView.convert(keyboardFrameInWindow, from: window)
      guard keyboardFrameInTextView.hasFiniteCoordinates else {
        return 0
      }

      return max(0, textView.bounds.intersection(keyboardFrameInTextView).height)
    }

    private func caretRect(for selection: NSRange, in textView: UITextView) -> CGRect? {
      let nsString = textView.text as NSString
      let location = min(max(selection.location, 0), nsString.length)

      if let position = textView.position(from: textView.beginningOfDocument, offset: location) {
        let rect = textView.caretRect(for: position)
        if rect.hasFiniteCoordinates && !rect.isNull && rect.height > 0 {
          return rect
        }
      }

      guard let layoutManager = textView.layoutManager as NSLayoutManager?,
            let textContainer = textView.textContainer as NSTextContainer?
      else {
        return nil
      }

      layoutManager.ensureLayout(for: textContainer)
      if nsString.length == 0 {
        let font = MarkdownAttributedRenderer.bodyFont(fontFamily: parent.fontFamily)
        return CGRect(
          x: textView.textContainerInset.left,
          y: textView.textContainerInset.top,
          width: 1,
          height: font.lineHeight
        )
      }

      if location == nsString.length,
         location > 0,
         let scalar = Unicode.Scalar(nsString.character(at: location - 1)),
         CharacterSet.newlines.contains(scalar) {
        return layoutManager.extraLineFragmentRect.offsetBy(
          dx: textView.textContainerInset.left,
          dy: textView.textContainerInset.top
        )
      }

      let characterLocation = min(location, nsString.length - 1)
      let glyphRange = layoutManager.glyphRange(
        forCharacterRange: NSRange(location: characterLocation, length: 1),
        actualCharacterRange: nil
      )
      guard glyphRange.length > 0 else {
        return nil
      }

      let lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphRange.location, effectiveRange: nil)
      return lineRect.offsetBy(dx: textView.textContainerInset.left, dy: textView.textContainerInset.top)
    }

    private func applyInsets(
      textContainerInset: UIEdgeInsets,
      contentInset: UIEdgeInsets,
      to textView: UITextView
    ) {
      if !textView.textContainerInset.isApproximatelyEqual(to: textContainerInset) {
        textView.textContainerInset = textContainerInset
      }
      if !textView.contentInset.isApproximatelyEqual(to: contentInset) {
        textView.contentInset = contentInset
      }
      if !textView.verticalScrollIndicatorInsets.isApproximatelyEqual(to: contentInset) {
        textView.verticalScrollIndicatorInsets = contentInset
      }
    }

    public func dropInteraction(_ interaction: UIDropInteraction, canHandle session: UIDropSession) -> Bool {
      session.hasItemsConforming(toTypeIdentifiers: Self.imageTypeIdentifiers)
    }

    public func dropInteraction(_ interaction: UIDropInteraction, sessionDidUpdate session: UIDropSession) -> UIDropProposal {
      UIDropProposal(operation: .copy)
    }

    public func dropInteraction(_ interaction: UIDropInteraction, performDrop session: UIDropSession) {
      guard let textView = interaction.view as? UITextView else {
        return
      }

      let location = session.location(in: textView)
      if let position = textView.closestPosition(to: location) {
        let index = textView.offset(from: textView.beginningOfDocument, to: position)
        if index >= 0 {
          let clampedLocation = min(index, (textView.text as NSString).length)
          textView.selectedRange = NSRange(location: clampedLocation, length: 0)
          parent.selectedRange = textView.selectedRange
        }
      }

      importImages(from: session.items.map(\.itemProvider))
    }

    func importImages(from pasteboard: UIPasteboard) -> Bool {
      if let image = pasteboard.image,
         let pngData = image.pngData() {
        parent.onImageAttachmentsImported([
          ImageAttachmentImport(data: pngData, suggestedFilename: "screenshot.png", preferredExtension: "png")
        ])
        return true
      }

      let providers = pasteboard.itemProviders.filter(Self.canImportImage(from:))
      guard !providers.isEmpty else {
        return false
      }
      importImages(from: providers)
      return true
    }

    private func importImages(from itemProviders: [NSItemProvider]) {
      let providers = itemProviders.filter(Self.canImportImage(from:))
      guard !providers.isEmpty else {
        return
      }
      loadImageImports(from: providers, at: 0, imports: [])
    }

    private func loadImageImports(
      from providers: [NSItemProvider],
      at index: Int,
      imports: [ImageAttachmentImport]
    ) {
      guard index < providers.count else {
        guard !imports.isEmpty else {
          return
        }
        parent.onImageAttachmentsImported(imports)
        return
      }

      let provider = providers[index]
      Self.loadImageImport(from: provider) { [weak self] imageImport in
        Task { @MainActor in
          guard let self else {
            return
          }
          var nextImports = imports
          if let imageImport {
            nextImports.append(imageImport)
          }
          self.loadImageImports(from: providers, at: index + 1, imports: nextImports)
        }
      }
    }

    private nonisolated static func canImportImage(from provider: NSItemProvider) -> Bool {
      provider.canLoadObject(ofClass: UIImage.self)
        || imageTypeIdentifiers.contains { provider.hasItemConformingToTypeIdentifier($0) }
    }

    private nonisolated static func loadImageImport(
      from provider: NSItemProvider,
      completion: @escaping (ImageAttachmentImport?) -> Void
    ) {
      if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
        provider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { url, _ in
          if let url,
             let imageImport = imageImport(fromFileURL: url, suggestedFilename: provider.suggestedName) {
            completion(imageImport)
            return
          }

          loadImageObject(from: provider, completion: completion)
        }
        return
      }

      loadImageObject(from: provider, completion: completion)
    }

    private nonisolated static func loadImageObject(
      from provider: NSItemProvider,
      completion: @escaping (ImageAttachmentImport?) -> Void
    ) {
      guard provider.canLoadObject(ofClass: UIImage.self) else {
        completion(nil)
        return
      }

      provider.loadObject(ofClass: UIImage.self) { object, _ in
        guard let image = object as? UIImage,
              let pngData = image.pngData()
        else {
          completion(nil)
          return
        }
        completion(ImageAttachmentImport(
          data: pngData,
          suggestedFilename: provider.suggestedName ?? "screenshot.png",
          preferredExtension: "png"
        ))
      }
    }

    private nonisolated static func imageImport(fromFileURL url: URL, suggestedFilename: String?) -> ImageAttachmentImport? {
      let supportedExtensions = Set(["png", "jpg", "jpeg", "gif", "heic", "tif", "tiff", "webp"])
      let suggestedExtension = suggestedFilename.map { URL(fileURLWithPath: $0).pathExtension.lowercased() }
      let fileExtension = url.pathExtension.lowercased()
      let preferredExtension = supportedExtensions.contains(fileExtension) ? fileExtension : suggestedExtension
      guard let data = try? Data(contentsOf: url) else {
        return nil
      }
      return ImageAttachmentImport(
        data: data,
        suggestedFilename: suggestedFilename ?? url.lastPathComponent,
        preferredExtension: preferredExtension
      )
    }

    private static func lineRange(containing selection: NSRange, in text: String) -> NSRange {
      let nsString = text as NSString
      guard nsString.length > 0 else {
        return NSRange(location: 0, length: 0)
      }
      let location = min(max(selection.location, 0), nsString.length)
      return nsString.lineRange(for: NSRange(location: location, length: 0))
    }
  }

  private var normalizedCaretAnchorFraction: CGFloat? {
    guard let caretAnchorFraction else {
      return nil
    }
    return min(max(caretAnchorFraction, 0.05), 0.95)
  }
}

private final class MarkdownKeyboardAccessoryView: UIView {
  private let backgroundView = UIView()
  private let leadingKeyboardCornerUnderlay = UIView()
  private let trailingKeyboardCornerUnderlay = UIView()
  private let effectView = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
  private let leftButton = MarkdownKeyboardAccessoryButton(type: .system)
  private let dismissButton = UIButton(type: .system)
  private let rightButton = MarkdownKeyboardAccessoryButton(type: .system)

  init() {
    super.init(frame: CGRect(x: 0, y: 0, width: 0, height: 64))
    autoresizingMask = [.flexibleWidth]
    clipsToBounds = false
    isOpaque = true
    setupView()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    nil
  }

  override var intrinsicContentSize: CGSize {
    CGSize(width: UIView.noIntrinsicMetric, height: 64)
  }

  func configure(
    actions: [MarkdownKeyboardAccessoryAction],
    theme: LatticeTheme,
    target: Any?,
    action: Selector,
    dismissAction: Selector
  ) {
    applyBackground(theme: theme)
    configureActionButton(
      leftButton,
      action: actions.first,
      theme: theme,
      target: target,
      selector: action
    )
    configureActionButton(
      rightButton,
      action: actions.dropFirst().last,
      theme: theme,
      target: target,
      selector: action
    )

    configureDismissButton(theme: theme, target: target, action: dismissAction)
    effectView.layer.borderColor = theme.uiColor(.separator).withAlphaComponent(0.55).cgColor
  }

  private func setupView() {
    addSubview(leadingKeyboardCornerUnderlay)
    addSubview(trailingKeyboardCornerUnderlay)
    addSubview(backgroundView)
    addSubview(effectView)
    leadingKeyboardCornerUnderlay.translatesAutoresizingMaskIntoConstraints = false
    trailingKeyboardCornerUnderlay.translatesAutoresizingMaskIntoConstraints = false
    backgroundView.translatesAutoresizingMaskIntoConstraints = false
    effectView.translatesAutoresizingMaskIntoConstraints = false
    leadingKeyboardCornerUnderlay.isOpaque = true
    trailingKeyboardCornerUnderlay.isOpaque = true
    backgroundView.isOpaque = true
    effectView.clipsToBounds = true
    effectView.layer.cornerRadius = 24
    effectView.layer.borderWidth = 1 / UIScreen.main.scale

    let contentView = effectView.contentView
    contentView.addSubview(leftButton)
    contentView.addSubview(dismissButton)
    contentView.addSubview(rightButton)

    leftButton.translatesAutoresizingMaskIntoConstraints = false
    dismissButton.translatesAutoresizingMaskIntoConstraints = false
    rightButton.translatesAutoresizingMaskIntoConstraints = false
    dismissButton.accessibilityLabel = "Dismiss Keyboard"

    NSLayoutConstraint.activate([
      leadingKeyboardCornerUnderlay.leadingAnchor.constraint(equalTo: leadingAnchor),
      leadingKeyboardCornerUnderlay.topAnchor.constraint(equalTo: bottomAnchor, constant: -1),
      leadingKeyboardCornerUnderlay.widthAnchor.constraint(equalToConstant: 44),
      leadingKeyboardCornerUnderlay.heightAnchor.constraint(equalToConstant: 32),

      trailingKeyboardCornerUnderlay.trailingAnchor.constraint(equalTo: trailingAnchor),
      trailingKeyboardCornerUnderlay.topAnchor.constraint(equalTo: bottomAnchor, constant: -1),
      trailingKeyboardCornerUnderlay.widthAnchor.constraint(equalToConstant: 44),
      trailingKeyboardCornerUnderlay.heightAnchor.constraint(equalToConstant: 32),

      backgroundView.leadingAnchor.constraint(equalTo: leadingAnchor),
      backgroundView.trailingAnchor.constraint(equalTo: trailingAnchor),
      backgroundView.topAnchor.constraint(equalTo: topAnchor),
      backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor),

      effectView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
      effectView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
      effectView.topAnchor.constraint(equalTo: topAnchor, constant: 8),
      effectView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),

      leftButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
      leftButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
      leftButton.widthAnchor.constraint(equalToConstant: 48),
      leftButton.heightAnchor.constraint(equalToConstant: 44),

      dismissButton.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
      dismissButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
      dismissButton.widthAnchor.constraint(equalToConstant: 44),
      dismissButton.heightAnchor.constraint(equalToConstant: 44),

      rightButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
      rightButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
      rightButton.widthAnchor.constraint(equalToConstant: 48),
      rightButton.heightAnchor.constraint(equalToConstant: 44)
    ])
  }

  private func applyBackground(theme: LatticeTheme) {
    let color = theme.uiColor(.editorBackground)
    backgroundColor = color
    backgroundView.backgroundColor = color
    leadingKeyboardCornerUnderlay.backgroundColor = color
    trailingKeyboardCornerUnderlay.backgroundColor = color
  }

  private func configureActionButton(
    _ button: MarkdownKeyboardAccessoryButton,
    action: MarkdownKeyboardAccessoryAction?,
    theme: LatticeTheme,
    target: Any?,
    selector: Selector
  ) {
    guard let action else {
      button.actionID = nil
      button.isHidden = true
      return
    }

    button.isHidden = false
    button.actionID = action.id
    button.configure(
      action: action,
      theme: theme,
      target: target,
      selector: selector
    )
  }

  private func configureDismissButton(theme: LatticeTheme, target: Any?, action: Selector) {
    var configuration = UIButton.Configuration.plain()
    configuration.image = UIImage(systemName: "keyboard.chevron.compact.down")
    configuration.baseForegroundColor = theme.uiColor(.primaryText)
    configuration.cornerStyle = .capsule
    dismissButton.configuration = configuration
    dismissButton.removeTarget(nil, action: nil, for: .touchUpInside)
    dismissButton.addTarget(target, action: action, for: .touchUpInside)
  }
}

private final class MarkdownKeyboardAccessoryButton: UIButton {
  var actionID: String?

  func configure(
    action: MarkdownKeyboardAccessoryAction,
    theme: LatticeTheme,
    target: Any?,
    selector: Selector
  ) {
    var configuration = UIButton.Configuration.plain()
    if let systemImage = action.systemImage {
      configuration.image = UIImage(systemName: systemImage)
      configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(
        pointSize: action.symbolPointSize ?? 20,
        weight: .semibold
      )
    } else {
      configuration.title = action.displayTitle ?? action.title
      configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
        var outgoing = incoming
        outgoing.font = .systemFont(ofSize: 21, weight: .medium)
        return outgoing
      }
    }
    configuration.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
    configuration.baseForegroundColor = action.isEnabled
      ? theme.uiColor(.primaryText)
      : theme.uiColor(.tertiaryText)
    configuration.cornerStyle = .capsule

    self.configuration = configuration
    configureInteraction(for: action, target: target, selector: selector)
    titleLabel?.adjustsFontSizeToFitWidth = true
    titleLabel?.lineBreakMode = .byClipping
    titleLabel?.numberOfLines = 1
    isEnabled = action.isEnabled && (action.menuChildren.isEmpty || action.menuChildren.contains(where: \.isEnabled))
    accessibilityLabel = action.title
  }

  private func configureInteraction(
    for action: MarkdownKeyboardAccessoryAction,
    target: Any?,
    selector: Selector
  ) {
    removeTarget(nil, action: nil, for: .touchUpInside)
    removeAction(identifiedBy: .markdownKeyboardAccessoryMenuHaptic, for: .menuActionTriggered)

    guard !action.menuChildren.isEmpty else {
      menu = nil
      showsMenuAsPrimaryAction = false
      addTarget(target, action: selector, for: .touchUpInside)
      return
    }

    showsMenuAsPrimaryAction = true
    addAction(
      UIAction(identifier: .markdownKeyboardAccessoryMenuHaptic) { _ in
        MarkdownKeyboardAccessoryHaptics.perform()
      },
      for: .menuActionTriggered
    )
    menu = UIMenu(
      title: "",
      options: .displayInline,
      children: action.menuChildren.map { child in
        UIAction(
          title: child.title,
          image: child.menuImage,
          attributes: child.isEnabled ? [] : [.disabled]
        ) { _ in
          Task { @MainActor in
            MarkdownKeyboardAccessoryHaptics.perform()
            if let coordinator = target as? MarkdownTextEditor.Coordinator {
              coordinator.performKeyboardAccessoryAction(child)
            } else {
              child.perform()
            }
          }
        }
      }
    )
  }
}

private extension UIAction.Identifier {
  static let markdownKeyboardAccessoryMenuHaptic = UIAction.Identifier("MarkdownKeyboardAccessoryMenuHaptic")
}

private extension CGRect {
  var hasFiniteCoordinates: Bool {
    origin.x.isFinite
      && origin.y.isFinite
      && size.width.isFinite
      && size.height.isFinite
  }
}

private extension UIEdgeInsets {
  func isApproximatelyEqual(to other: UIEdgeInsets) -> Bool {
    abs(top - other.top) < 0.5
      && abs(left - other.left) < 0.5
      && abs(bottom - other.bottom) < 0.5
      && abs(right - other.right) < 0.5
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
  weak var markdownCoordinator: MarkdownTextEditor.Coordinator?
  var theme = LatticeTheme(id: .system)

  override var bounds: CGRect {
    didSet {
      if oldValue.origin != bounds.origin {
        if markdownCoordinator?.restoreFrozenViewportIfNeeded(in: self) == true {
          return
        }
        setNeedsDisplay()
      }
    }
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    markdownCoordinator?.configureCaretAnchorLayout(in: self)
  }

  override func scrollRangeToVisible(_ range: NSRange) {
    if markdownCoordinator?.parent.caretAnchorFraction != nil {
      return
    }

    super.scrollRangeToVisible(range)
  }

  override func setContentOffset(_ contentOffset: CGPoint, animated: Bool) {
    if let protectedOffset = markdownCoordinator?.protectedContentOffset(for: self, proposed: contentOffset) {
      super.setContentOffset(protectedOffset, animated: false)
      return
    }

    super.setContentOffset(contentOffset, animated: animated)
  }

  override var keyCommands: [UIKeyCommand]? {
    let indentCommand = UIKeyCommand(
      input: "\t",
      modifierFlags: UIKeyModifierFlags(),
      action: #selector(handleIndentKeyCommand(_:))
    )
    indentCommand.discoverabilityTitle = "Indent List Item"
    indentCommand.wantsPriorityOverSystemBehavior = true

    let outdentCommand = UIKeyCommand(
      input: "\t",
      modifierFlags: .shift,
      action: #selector(handleOutdentKeyCommand(_:))
    )
    outdentCommand.discoverabilityTitle = "Outdent List Item"
    outdentCommand.wantsPriorityOverSystemBehavior = true

    let markdownCommands = [indentCommand, outdentCommand]
    return (super.keyCommands ?? []) + markdownCommands
  }

  @objc private func handleIndentKeyCommand(_ command: UIKeyCommand) {
    guard markdownCoordinator?.applyMarkdownListIndentation(in: self, direction: .indent) != true else {
      return
    }

    insertText("\t")
  }

  @objc private func handleOutdentKeyCommand(_ command: UIKeyCommand) {
    _ = markdownCoordinator?.applyMarkdownListIndentation(in: self, direction: .outdent)
  }

  override func paste(_ sender: Any?) {
    if markdownCoordinator?.importImages(from: .general) == true {
      return
    }

    super.paste(sender)
  }

  override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
    guard let tabPress = presses.first(where: { $0.key?.keyCode == .keyboardTab }) else {
      super.pressesBegan(presses, with: event)
      return
    }

    if tabPress.key?.modifierFlags.contains(.shift) == true {
      guard markdownCoordinator?.applyMarkdownListIndentation(in: self, direction: .outdent) != true else {
        return
      }
      super.pressesBegan(presses, with: event)
      return
    }

    guard markdownCoordinator?.applyMarkdownListIndentation(in: self, direction: .indent) != true else {
      return
    }

    insertText("\t")
  }

  override func draw(_ rect: CGRect) {
    theme.uiColor(.editorBackground).setFill()
    UIRectFill(rect)
    super.draw(rect)
    drawMarkdownTables()
    drawTaskCheckboxes()
    drawUnorderedListMarkers()
    drawThematicBreaks()
  }

  private func drawTaskCheckboxes() {
    guard let context = UIGraphicsGetCurrentContext() else {
      return
    }

    let visibleBounds = visibleTextContainerRect
    let textContainerOrigin = textContainerDrawingOrigin
    let visibleGlyphRange = layoutManager.glyphRange(
      forBoundingRect: visibleBounds,
      in: textContainer
    )
    let visibleCharacterRange = layoutManager.characterRange(
      forGlyphRange: visibleGlyphRange,
      actualGlyphRange: nil
    )

    textStorage.enumerateAttribute(.latticeTaskCheckbox, in: visibleCharacterRange) { value, range, _ in
      guard value as? Bool == true else {
        return
      }

      let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
      guard glyphRange.length > 0 else {
        return
      }

      let lineRect = layoutManager.lineFragmentUsedRect(forGlyphAt: glyphRange.location, effectiveRange: nil)
      let checkboxBounds = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
      let isChecked = textStorage.attribute(.latticeTaskCheckboxChecked, at: range.location, effectiveRange: nil) as? Bool == true
      let size = min(CGFloat(17), max(CGFloat(11), lineRect.height - 6))
      let checkboxRect = CGRect(
        x: textContainerOrigin.x + checkboxBounds.minX,
        y: textContainerOrigin.y + lineRect.midY - size / 2,
        width: size,
        height: size
      ).integral

      context.saveGState()
      context.setStrokeColor(theme.uiColor(.accent).cgColor)
      context.setLineWidth(1.5)
      UIBezierPath(roundedRect: checkboxRect, cornerRadius: 3).stroke()

      guard isChecked else {
        context.restoreGState()
        return
      }

      context.setLineWidth(2)
      context.setLineCap(.round)
      context.setLineJoin(.round)
      context.move(to: CGPoint(x: checkboxRect.minX + size * 0.25, y: checkboxRect.midY))
      context.addLine(to: CGPoint(x: checkboxRect.minX + size * 0.43, y: checkboxRect.maxY - size * 0.28))
      context.addLine(to: CGPoint(x: checkboxRect.maxX - size * 0.2, y: checkboxRect.minY + size * 0.28))
      context.strokePath()
      context.restoreGState()
    }
  }

  private func drawMarkdownTables() {
    guard let context = UIGraphicsGetCurrentContext() else {
      return
    }

    let visibleBounds = visibleTextContainerRect
    let textContainerOrigin = textContainerDrawingOrigin
    let visibleGlyphRange = layoutManager.glyphRange(
      forBoundingRect: visibleBounds,
      in: textContainer
    )
    let visibleCharacterRange = layoutManager.characterRange(
      forGlyphRange: visibleGlyphRange,
      actualGlyphRange: nil
    )

    var drawnTableLocations: Set<Int> = []
    textStorage.enumerateAttribute(.latticeMarkdownTable, in: visibleCharacterRange) { value, range, _ in
      guard
        value as? Bool == true,
        let table = MarkdownTableParser.table(containing: range, in: textStorage.string),
        !drawnTableLocations.contains(table.range.location)
      else {
        return
      }

      drawnTableLocations.insert(table.range.location)
      drawMarkdownTable(table, context: context, textContainerOrigin: textContainerOrigin)
    }
  }

  private func drawMarkdownTable(
    _ table: MarkdownTableBlock,
    context: CGContext,
    textContainerOrigin: CGPoint
  ) {
    let rowLineRanges = [table.headerLineRange] + table.bodyLineRanges
    guard rowLineRanges.count == table.rows.count else {
      return
    }

    let maxWidth = max(0, bounds.width - textContainerInset.left - textContainerInset.right - textContainer.lineFragmentPadding * 2)
    let columnWidths = markdownTableColumnWidths(for: table, maxWidth: maxWidth)
    let tableWidth = columnWidths.reduce(0, +)
    let separatorColor = theme.uiColor(.separator).withAlphaComponent(0.9)
    let rowBackground = theme.uiColor(.editorBackground)
    let headerBackground = theme.uiColor(.surfaceBackground).withAlphaComponent(0.8)

    for (rowIndex, row) in table.rows.enumerated() {
      let lineRange = rowLineRanges[rowIndex]
      let glyphRange = layoutManager.glyphRange(forCharacterRange: lineRange, actualCharacterRange: nil)
      guard glyphRange.length > 0 else {
        continue
      }

      let lineRect = layoutManager.lineFragmentUsedRect(forGlyphAt: glyphRange.location, effectiveRange: nil)
      let rowRect = CGRect(
        x: textContainerOrigin.x + textContainer.lineFragmentPadding,
        y: textContainerOrigin.y + lineRect.minY,
        width: tableWidth,
        height: lineRect.height
      )
      context.setFillColor((row.isHeader ? headerBackground : rowBackground).cgColor)
      context.fill(rowRect)

      var cellX = rowRect.minX
      for columnIndex in 0..<table.columnCount {
        let width = columnWidths[columnIndex]
        let cellRect = CGRect(x: cellX, y: rowRect.minY, width: width, height: rowRect.height)
        context.setStrokeColor(separatorColor.cgColor)
        context.setLineWidth(1 / UIScreen.main.scale)
        context.stroke(cellRect)

        let value = columnIndex < row.cells.count ? row.cells[columnIndex] : ""
        let attributes = markdownTableTextAttributes(isHeader: row.isHeader)
        let textSize = (value as NSString).size(withAttributes: attributes)
        let textRect = CGRect(
          x: cellRect.minX + 10,
          y: cellRect.midY - min(textSize.height, cellRect.height - 8) / 2,
          width: max(0, cellRect.width - 20),
          height: max(0, cellRect.height - 8)
        )
        (value as NSString).draw(in: textRect, withAttributes: attributes)
        cellX += width
      }
    }
  }

  private func markdownTableColumnWidths(for table: MarkdownTableBlock, maxWidth: CGFloat) -> [CGFloat] {
    let minimumWidth: CGFloat = 68
    let padding: CGFloat = 24
    let headerFont = UIFont.systemFont(ofSize: 15, weight: .semibold)
    let bodyFont = UIFont.systemFont(ofSize: 15, weight: .regular)
    var widths = Array(repeating: minimumWidth, count: table.columnCount)

    for row in table.rows {
      let attributes: [NSAttributedString.Key: Any] = [.font: row.isHeader ? headerFont : bodyFont]
      for columnIndex in 0..<table.columnCount {
        let value = columnIndex < row.cells.count ? row.cells[columnIndex] : ""
        widths[columnIndex] = max(widths[columnIndex], (value as NSString).size(withAttributes: attributes).width + padding)
      }
    }

    let totalWidth = widths.reduce(0, +)
    guard totalWidth > maxWidth, maxWidth > 0 else {
      return widths
    }

    let minimumTotal = minimumWidth * CGFloat(table.columnCount)
    if maxWidth <= minimumTotal {
      return Array(repeating: maxWidth / CGFloat(table.columnCount), count: table.columnCount)
    }

    let extraWidth = maxWidth - minimumTotal
    let currentExtra = totalWidth - minimumTotal
    return widths.map { minimumWidth + (($0 - minimumWidth) / currentExtra * extraWidth) }
  }

  private func markdownTableTextAttributes(isHeader: Bool) -> [NSAttributedString.Key: Any] {
    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.lineBreakMode = .byTruncatingTail
    return [
      .font: UIFont.systemFont(ofSize: 15, weight: isHeader ? .semibold : .regular),
      .foregroundColor: theme.uiColor(.primaryText),
      .paragraphStyle: paragraphStyle
    ]
  }

  private func drawUnorderedListMarkers() {
    guard let context = UIGraphicsGetCurrentContext() else {
      return
    }

    let visibleBounds = visibleTextContainerRect
    let textContainerOrigin = textContainerDrawingOrigin
    let visibleGlyphRange = layoutManager.glyphRange(
      forBoundingRect: visibleBounds,
      in: textContainer
    )
    let visibleCharacterRange = layoutManager.characterRange(
      forGlyphRange: visibleGlyphRange,
      actualGlyphRange: nil
    )

    textStorage.enumerateAttribute(.latticeUnorderedListMarker, in: visibleCharacterRange) { value, range, _ in
      guard value as? Bool == true else {
        return
      }

      let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
      guard glyphRange.length > 0 else {
        return
      }

      let lineRect = layoutManager.lineFragmentUsedRect(forGlyphAt: glyphRange.location, effectiveRange: nil)
      let nestingIndent = textStorage.attribute(.latticeUnorderedListIndent, at: range.location, effectiveRange: nil) as? CGFloat ?? 0
      let markerRadius: CGFloat = 3.25
      let markerX = textContainerOrigin.x + textContainer.lineFragmentPadding + 8 + nestingIndent
      let markerY = textContainerOrigin.y + lineRect.midY
      let markerRect = CGRect(
        x: markerX - markerRadius,
        y: markerY - markerRadius,
        width: markerRadius * 2,
        height: markerRadius * 2
      )

      context.setFillColor(theme.uiColor(.accent).cgColor)
      context.fillEllipse(in: markerRect)
    }
  }

  private func drawThematicBreaks() {
    guard let context = UIGraphicsGetCurrentContext() else {
      return
    }

    let visibleBounds = visibleTextContainerRect
    let textContainerOrigin = textContainerDrawingOrigin
    let visibleGlyphRange = layoutManager.glyphRange(
      forBoundingRect: visibleBounds,
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
      let y = textContainerOrigin.y + lineRect.midY
      let startX = textContainerOrigin.x + textContainer.lineFragmentPadding
      let endX = bounds.width - textContainerInset.right - textContainer.lineFragmentPadding
      context.setStrokeColor(theme.uiColor(.separator).withAlphaComponent(0.85).cgColor)
      context.setLineWidth(1 / UIScreen.main.scale)
      context.move(to: CGPoint(x: startX, y: y))
      context.addLine(to: CGPoint(x: endX, y: y))
      context.strokePath()
    }
  }

  private var visibleTextContainerRect: CGRect {
    CGRect(
      x: contentOffset.x - textContainerInset.left,
      y: contentOffset.y - textContainerInset.top,
      width: bounds.width - textContainerInset.left - textContainerInset.right,
      height: bounds.height - textContainerInset.top - textContainerInset.bottom
    )
  }

  private var textContainerDrawingOrigin: CGPoint {
    CGPoint(
      x: textContainerInset.left,
      y: textContainerInset.top
    )
  }
}
#endif

private func clamped(_ range: NSRange, length: Int) -> NSRange {
  let location = max(0, min(range.location, length))
  return NSRange(location: location, length: max(0, min(range.length, length - location)))
}
