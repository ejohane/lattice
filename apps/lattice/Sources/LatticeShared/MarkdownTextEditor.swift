import LatticeEditor
import LatticeCore
import SwiftUI

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
  let showsTimelineRuler: Bool
  let timelineEntries: [TimelineEntry]
  let dimsInactiveParagraphs: Bool
  let caretAnchorFraction: CGFloat?
  let hasAutocompleteSuggestions: Bool
  let wikiLinkStates: [WikiLinkRenderState]
  let theme: LatticeTheme
  let imagePreviewStates: [MarkdownImageRenderState]
  let onTextChange: () -> Void
  let onSelectionChange: () -> Void
  let onWikiLinkActivated: (Int) -> Void
  let onMarkdownLinkActivated: (Int) -> Void
  let onDismissAutocomplete: () -> Void
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
    showsTimelineRuler: Bool = false,
    timelineEntries: [TimelineEntry] = [],
    dimsInactiveParagraphs: Bool = false,
    caretAnchorFraction: CGFloat? = nil,
    hasAutocompleteSuggestions: Bool,
    wikiLinkStates: [WikiLinkRenderState],
    theme: LatticeTheme,
    imagePreviewStates: [MarkdownImageRenderState],
    onTextChange: @escaping () -> Void,
    onSelectionChange: @escaping () -> Void,
    onWikiLinkActivated: @escaping (Int) -> Void,
    onMarkdownLinkActivated: @escaping (Int) -> Void,
    onDismissAutocomplete: @escaping () -> Void,
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
    self.showsTimelineRuler = showsTimelineRuler
    self.timelineEntries = timelineEntries
    self.dimsInactiveParagraphs = dimsInactiveParagraphs
    self.caretAnchorFraction = caretAnchorFraction
    self.hasAutocompleteSuggestions = hasAutocompleteSuggestions
    self.wikiLinkStates = wikiLinkStates
    self.theme = theme
    self.imagePreviewStates = imagePreviewStates
    self.onTextChange = onTextChange
    self.onSelectionChange = onSelectionChange
    self.onWikiLinkActivated = onWikiLinkActivated
    self.onMarkdownLinkActivated = onMarkdownLinkActivated
    self.onDismissAutocomplete = onDismissAutocomplete
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
    scrollView.hasVerticalScroller = true
    scrollView.autohidesScrollers = true
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
    textView.configureRuler(
      showsRelativeLineNumbers: showsRelativeLineNumbers,
      showsTimelineRuler: showsTimelineRuler
    )
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
      || context.coordinator.lastRenderedTimelineEntries != timelineEntries
      || context.coordinator.lastRenderedDimsInactiveParagraphs != dimsInactiveParagraphs
      || context.coordinator.lastRenderedTheme != theme
      || context.coordinator.lastRenderedImagePreviewStates != imagePreviewStates {
      context.coordinator.render(text, in: textView, preserving: clampedSelectedRange)
    } else if textView.selectedRange() != clampedSelectedRange {
      context.coordinator.render(text, in: textView, preserving: clampedSelectedRange)
    }
    textView.theme = theme
    scrollView.backgroundColor = theme.nsColor(.editorBackground)
    scrollView.contentView.backgroundColor = theme.nsColor(.editorBackground)
    textView.backgroundColor = theme.nsColor(.editorBackground)
    textView.textColor = theme.nsColor(.primaryText)
    textView.insertionPointColor = theme.nsColor(.accent)
    textView.configureRuler(
      showsRelativeLineNumbers: showsRelativeLineNumbers,
      showsTimelineRuler: showsTimelineRuler
    )
    textView.needsDisplay = true
    if context.coordinator.lastFocusToken != focusToken {
      context.coordinator.lastFocusToken = focusToken
      DispatchQueue.main.async {
        textView.window?.makeFirstResponder(textView)
        context.coordinator.scheduleCaretAnchor(selection: clampedSelectedRange, animated: false)
      }
    }
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
    var lastRenderedTimelineEntries: [TimelineEntry] = []
    var lastRenderedDimsInactiveParagraphs = false
    var lastRenderedTheme = LatticeTheme(id: .system)
    var lastRenderedImagePreviewStates: [MarkdownImageRenderState] = []
    private var isRendering = false
    private let defaultTextContainerInset = NSSize(width: 36, height: 34)
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
      render(textView.string, in: textView, preserving: textView.selectedRange())
      scheduleCaretAnchor(animated: true)
    }

    public func textViewDidChangeSelection(_ notification: Notification) {
      guard let textView = notification.object as? NSTextView else {
        return
      }
      let selection = textView.selectedRange()
      parent.selectedRange = selection
      parent.onSelectionChange()
      render(textView.string, in: textView, preserving: selection)
      scheduleCaretAnchor(animated: true)
    }

    @objc private func scrollViewBoundsDidChange(_ notification: Notification) {
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
        if textView.minSize.height != 0 {
          textView.minSize = NSSize(width: 0, height: 0)
        }
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
      isRendering = true
      let activeRanges = parent.dimsInactiveParagraphs
        ? [Self.timelineEntryLineRange(containing: selection, in: text)]
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
      lastRenderedTimelineEntries = parent.timelineEntries
      lastRenderedDimsInactiveParagraphs = parent.dimsInactiveParagraphs
      lastRenderedTheme = parent.theme
      lastRenderedImagePreviewStates = parent.imagePreviewStates
      isRendering = false
      scheduleCaretAnchor(selection: selection, animated: true)
    }

    func scheduleCaretAnchor(selection: NSRange? = nil, animated: Bool) {
      pendingAnchorTask?.cancel()
      pendingAnchorTask = Task { @MainActor [weak self] in
        await Task.yield()
        guard !Task.isCancelled, let self, let textView = self.textView else {
          return
        }
        let targetSelection = selection ?? textView.selectedRange()
        self.scrollCaretToAnchor(in: textView, selection: targetSelection, animated: animated)
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

    private static func timelineEntryLineRange(containing selection: NSRange, in text: String) -> NSRange {
      let nsString = text as NSString
      guard nsString.length > 0 else {
        return NSRange(location: 0, length: 0)
      }
      let location = min(max(selection.location, 0), nsString.length)
      let blocks = TimelineTextRanges.blocks(in: nsString)
      if let block = blocks.first(where: { location >= $0.location && location <= NSMaxRange($0) + 1 }) {
        return block
      }
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

  func configureRuler(showsRelativeLineNumbers: Bool, showsTimelineRuler: Bool) {
    guard let scrollView = enclosingScrollView else {
      return
    }

    if showsTimelineRuler {
      if !(scrollView.verticalRulerView is TimelineRulerView) {
        scrollView.verticalRulerView = TimelineRulerView(textView: self)
      }
      scrollView.hasHorizontalRuler = false
      scrollView.horizontalRulerView = nil
      scrollView.hasVerticalRuler = true
      scrollView.rulersVisible = true
      invalidateLineNumberRuler()
    } else if showsRelativeLineNumbers {
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

  var timelineEntriesForRuler: [TimelineEntry] {
    coordinator?.parent.timelineEntries ?? []
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

private struct TimelineMarker {
  let index: Int
  let entry: TimelineEntry
  let range: NSRange
  let y: CGFloat
  let hitRect: NSRect
}

private final class TimelineRulerView: NSRulerView {
  private weak var textView: MarkdownTextView?
  private let rulerWidth: CGFloat = 132
  private let railX: CGFloat = 96
  private let markerHitSize: CGFloat = 28

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

  override func resetCursorRects() {
    super.resetCursorRects()
    for marker in timelineMarkers() {
      addCursorRect(marker.hitRect, cursor: .pointingHand)
    }
  }

  override func mouseDown(with event: NSEvent) {
    let point = convert(event.locationInWindow, from: nil)
    guard let marker = timelineMarkers().first(where: { $0.hitRect.contains(point) }),
          let textView
    else {
      super.mouseDown(with: event)
      return
    }

    let targetRange = NSRange(location: marker.range.location, length: 0)
    textView.window?.makeFirstResponder(textView)
    textView.setSelectedRange(targetRange)
    textView.coordinator?.parent.selectedRange = targetRange
    textView.coordinator?.parent.onSelectionChange()
    textView.coordinator?.render(textView.string, in: textView, preserving: targetRange)
  }

  override func drawHashMarksAndLabels(in rect: NSRect) {
    guard let textView else { return }

    NSColor.clear.setFill()
    rect.fill()

    let nsString = textView.string as NSString
    let blocks = TimelineTextRanges.blocks(in: nsString)
    let entries = textView.timelineEntriesForRuler
    let activeIndex = blocks.firstIndex { range in
      let location = textView.selectedRange().location
      return location >= range.location && location <= NSMaxRange(range) + 1
    }
    let markers = timelineMarkers(blocks: blocks, entries: entries)

    let visibleRect = textView.visibleRect
    drawRail(for: markers)

    for marker in markers {
      guard marker.y >= visibleRect.minY - 40, marker.y <= visibleRect.maxY + 40 else {
        continue
      }
      drawMarkerAndTimestamp(
        marker.entry.createdAt,
        y: marker.y,
        isActive: marker.index == activeIndex
      )
    }
  }

  private func timelineMarkers(
    blocks: [NSRange]? = nil,
    entries: [TimelineEntry]? = nil
  ) -> [TimelineMarker] {
    guard
      let textView,
      let layoutManager = textView.layoutManager,
      let textContainer = textView.textContainer
    else {
      return []
    }

    let nsString = textView.string as NSString
    let blocks = blocks ?? TimelineTextRanges.blocks(in: nsString)
    let entries = entries ?? textView.timelineEntriesForRuler
    let origin = textView.textContainerOrigin
    layoutManager.ensureLayout(for: textContainer)

    var markers: [TimelineMarker] = []
    for (index, range) in blocks.enumerated() {
      guard let entry = entries.safeElement(at: index) else {
        continue
      }
      let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
      guard glyphRange.length > 0 else {
        continue
      }
      let lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphRange.location, effectiveRange: nil)
      let y = lineRect.minY + origin.y
      guard y.isFinite else {
        continue
      }
      let hitRect = NSRect(
        x: railX - markerHitSize / 2,
        y: y - markerHitSize / 2 + 6,
        width: markerHitSize,
        height: markerHitSize
      )
      markers.append(TimelineMarker(index: index, entry: entry, range: range, y: y, hitRect: hitRect))
    }
    return markers
  }

  private func drawRail(for markers: [TimelineMarker]) {
    guard let firstY = markers.first?.y, let lastY = markers.last?.y else {
      return
    }

    let path = NSBezierPath()
    path.lineWidth = 0.75
    path.move(to: NSPoint(x: railX, y: firstY - 32))
    path.line(to: NSPoint(x: railX, y: lastY + 32))
    NSColor.separatorColor.withAlphaComponent(0.24).setStroke()
    path.stroke()
  }

  private func drawMarkerAndTimestamp(_ date: Date, y: CGFloat, isActive: Bool) {
    let markerSize: CGFloat = isActive ? 15 : 11
    let markerRect = NSRect(
      x: railX - markerSize / 2,
      y: y - 1,
      width: markerSize,
      height: markerSize
    )
    NSColor.textBackgroundColor.setFill()
    NSBezierPath(ovalIn: markerRect.insetBy(dx: -2, dy: -2)).fill()
    let markerPath = NSBezierPath(ovalIn: markerRect)
    markerPath.lineWidth = isActive ? 2 : 1.5
    (isActive ? NSColor.labelColor : NSColor.secondaryLabelColor.withAlphaComponent(0.78)).setStroke()
    markerPath.stroke()
    if isActive {
      NSColor.labelColor.setFill()
      NSBezierPath(ovalIn: markerRect.insetBy(dx: 4.5, dy: 4.5)).fill()
    }

    let label = timestampText(for: date)
    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.alignment = .right
    paragraphStyle.lineSpacing = 3
    let attributes: [NSAttributedString.Key: Any] = [
      .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: isActive ? .semibold : .regular),
      .foregroundColor: isActive ? NSColor.labelColor : NSColor.secondaryLabelColor.withAlphaComponent(0.78),
      .paragraphStyle: paragraphStyle
    ]
    let attributed = NSAttributedString(string: label, attributes: attributes)
    attributed.draw(in: NSRect(x: 4, y: y - 3, width: railX - 18, height: 34))
  }

  private func timestampText(for date: Date) -> String {
    let calendar = Calendar.current
    let day: String
    if calendar.isDateInToday(date) {
      day = "Today"
    } else if calendar.isDateInYesterday(date) {
      day = "Yesterday"
    } else if calendar.component(.year, from: date) == calendar.component(.year, from: Date()) {
      day = Self.monthDayFormatter.string(from: date)
    } else {
      day = Self.monthDayYearFormatter.string(from: date)
    }
    return "\(day)\n\(Self.timeFormatter.string(from: date))"
  }

  private static let monthDayFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "MMM d"
    return formatter
  }()

  private static let monthDayYearFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "MMM d, yyyy"
    return formatter
  }()

  private static let timeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .none
    formatter.timeStyle = .short
    return formatter
  }()
}

private enum TimelineTextRanges {
  static func blocks(in nsString: NSString) -> [NSRange] {
    var ranges: [NSRange] = []
    var searchLocation = 0

    while searchLocation <= nsString.length {
      let separatorRange = nsString.range(
        of: "\n\n",
        options: [],
        range: NSRange(location: searchLocation, length: nsString.length - searchLocation)
      )
      let rawRange: NSRange
      if separatorRange.location == NSNotFound {
        rawRange = NSRange(location: searchLocation, length: nsString.length - searchLocation)
      } else {
        rawRange = NSRange(location: searchLocation, length: separatorRange.location - searchLocation)
      }

      if let range = trimmedContentRange(rawRange, in: nsString) {
        ranges.append(range)
      }

      guard separatorRange.location != NSNotFound else {
        break
      }
      searchLocation = NSMaxRange(separatorRange)
    }

    return ranges
  }

  private static func trimmedContentRange(_ rawRange: NSRange, in nsString: NSString) -> NSRange? {
    var start = rawRange.location
    var end = NSMaxRange(rawRange)
    while start < end, isWhitespace(nsString.character(at: start)) {
      start += 1
    }
    while end > start, isWhitespace(nsString.character(at: end - 1)) {
      end -= 1
    }
    guard end > start else {
      return nil
    }
    return NSRange(location: start, length: end - start)
  }

  private static func isWhitespace(_ character: unichar) -> Bool {
    character == 10 || character == 13 || character == 9 || character == 32
  }
}

private extension Array {
  func safeElement(at index: Int) -> Element? {
    indices.contains(index) ? self[index] : nil
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
  let showsTimelineRuler: Bool
  let timelineEntries: [TimelineEntry]
  let dimsInactiveParagraphs: Bool
  let caretAnchorFraction: CGFloat?
  let hasAutocompleteSuggestions: Bool
  let wikiLinkStates: [WikiLinkRenderState]
  let theme: LatticeTheme
  let imagePreviewStates: [MarkdownImageRenderState]
  let onTextChange: () -> Void
  let onSelectionChange: () -> Void
  let onWikiLinkActivated: (Int) -> Void
  let onMarkdownLinkActivated: (Int) -> Void
  let onDismissAutocomplete: () -> Void
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
    showsTimelineRuler: Bool = false,
    timelineEntries: [TimelineEntry] = [],
    dimsInactiveParagraphs: Bool = false,
    caretAnchorFraction: CGFloat? = nil,
    hasAutocompleteSuggestions: Bool,
    wikiLinkStates: [WikiLinkRenderState],
    theme: LatticeTheme,
    imagePreviewStates: [MarkdownImageRenderState],
    onTextChange: @escaping () -> Void,
    onSelectionChange: @escaping () -> Void,
    onWikiLinkActivated: @escaping (Int) -> Void,
    onMarkdownLinkActivated: @escaping (Int) -> Void,
    onDismissAutocomplete: @escaping () -> Void,
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
    self.showsTimelineRuler = showsTimelineRuler
    self.timelineEntries = timelineEntries
    self.dimsInactiveParagraphs = dimsInactiveParagraphs
    self.caretAnchorFraction = caretAnchorFraction
    self.hasAutocompleteSuggestions = hasAutocompleteSuggestions
    self.wikiLinkStates = wikiLinkStates
    self.theme = theme
    self.imagePreviewStates = imagePreviewStates
    self.onTextChange = onTextChange
    self.onSelectionChange = onSelectionChange
    self.onWikiLinkActivated = onWikiLinkActivated
    self.onMarkdownLinkActivated = onMarkdownLinkActivated
    self.onDismissAutocomplete = onDismissAutocomplete
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
    textView.theme = theme
    textView.backgroundColor = theme.uiColor(.editorBackground)
    textView.textColor = theme.uiColor(.primaryText)
    textView.tintColor = theme.uiColor(.accent)
    textView.isScrollEnabled = true
    textView.alwaysBounceVertical = true
    textView.keyboardDismissMode = .interactive
    textView.textContainerInset = UIEdgeInsets(top: 34, left: 22, bottom: 34, right: 22)
    textView.font = MarkdownAttributedRenderer.bodyFont(fontFamily: fontFamily)
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
    let clampedSelectedRange = clamped(selectedRange, length: (text as NSString).length)
    if textView.text != text
      || context.coordinator.lastRenderedFontFamily != fontFamily
      || context.coordinator.lastRenderedWikiLinkStates != wikiLinkStates
      || context.coordinator.lastRenderedTheme != theme {
      context.coordinator.render(text, in: textView, preserving: clampedSelectedRange)
    } else if textView.selectedRange != clampedSelectedRange {
      context.coordinator.render(text, in: textView, preserving: clampedSelectedRange)
    }
    (textView as? MarkdownUIKitTextView)?.theme = theme
    textView.backgroundColor = theme.uiColor(.editorBackground)
    textView.textColor = theme.uiColor(.primaryText)
    textView.tintColor = theme.uiColor(.accent)
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
    var lastRenderedFontFamily: EditorFontFamily?
    var lastRenderedWikiLinkStates: [WikiLinkRenderState] = []
    var lastRenderedTheme = LatticeTheme(id: .system)
    private var isRendering = false
    private var activeWikiLinkRange: NSRange?

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
      guard !isRendering else {
        return
      }
      parent.selectedRange = textView.selectedRange
      parent.onSelectionChange()
      let clampedSelection = clamped(textView.selectedRange, length: (textView.text as NSString).length)
      let nextActiveWikiLinkRange = WikiLinkParser.link(at: clampedSelection.location, in: textView.text)?.range
      if nextActiveWikiLinkRange != activeWikiLinkRange {
        render(textView.text, in: textView, preserving: clampedSelection)
      }
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
      let clampedSelection = clamped(selection, length: (text as NSString).length)
      activeWikiLinkRange = WikiLinkParser.link(at: clampedSelection.location, in: text)?.range
      textView.attributedText = MarkdownAttributedRenderer.render(
        text,
        fontFamily: parent.fontFamily,
        activeRanges: [clampedSelection],
        wikiLinkStates: parent.wikiLinkStates,
        theme: parent.theme,
        imagePreviewStates: parent.imagePreviewStates
      )
      textView.selectedRange = clampedSelection
      textView.typingAttributes = MarkdownAttributedRenderer.baseTypingAttributes(
        fontFamily: parent.fontFamily,
        theme: parent.theme
      )
      lastRenderedFontFamily = parent.fontFamily
      lastRenderedWikiLinkStates = parent.wikiLinkStates
      lastRenderedTheme = parent.theme
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
  var theme = LatticeTheme(id: .system)

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
      context.setStrokeColor(theme.uiColor(.separator).withAlphaComponent(0.85).cgColor)
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
