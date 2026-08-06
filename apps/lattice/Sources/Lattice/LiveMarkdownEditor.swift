import AppKit
import LatticeEditor
import LatticeMacCore
import SwiftUI

struct LiveMarkdownEditor: NSViewRepresentable {
  let text: String
  let contentRevision: Int
  let externalRefreshRequest: Int
  let focusRequest: Int
  let isEditable: Bool
  let treatsEmptyDocumentAsTitle: Bool
  let accessibilityIdentifier: String
  let onEdit: (NSRange, String) -> Void
  let onReplaceAll: (String) -> Void
  let onOpenWikiLink: (String) -> Void
  let onEnsureTodayNote: (Date, Calendar) -> Void
  let tagSummaries: [NoteTagSummary]
  let onOpenTag: (String) -> Void
  let onSubmit: (() -> Void)?
  let onCancel: (() -> Void)?

  init(
    text: String,
    contentRevision: Int,
    externalRefreshRequest: Int,
    focusRequest: Int,
    isEditable: Bool,
    treatsEmptyDocumentAsTitle: Bool = true,
    accessibilityIdentifier: String = "noteEditor",
    onEdit: @escaping (NSRange, String) -> Void,
    onReplaceAll: @escaping (String) -> Void,
    onOpenWikiLink: @escaping (String) -> Void,
    onEnsureTodayNote: @escaping (Date, Calendar) -> Void,
    tagSummaries: [NoteTagSummary] = [],
    onOpenTag: @escaping (String) -> Void = { _ in },
    onSubmit: (() -> Void)? = nil,
    onCancel: (() -> Void)? = nil
  ) {
    self.text = text
    self.contentRevision = contentRevision
    self.externalRefreshRequest = externalRefreshRequest
    self.focusRequest = focusRequest
    self.isEditable = isEditable
    self.treatsEmptyDocumentAsTitle = treatsEmptyDocumentAsTitle
    self.accessibilityIdentifier = accessibilityIdentifier
    self.onEdit = onEdit
    self.onReplaceAll = onReplaceAll
    self.onOpenWikiLink = onOpenWikiLink
    self.onEnsureTodayNote = onEnsureTodayNote
    self.tagSummaries = tagSummaries
    self.onOpenTag = onOpenTag
    self.onSubmit = onSubmit
    self.onCancel = onCancel
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(parent: self)
  }

  func makeNSView(context: Context) -> NSScrollView {
    let scrollView = NSScrollView()
    scrollView.drawsBackground = false
    scrollView.hasVerticalScroller = true
    scrollView.hasHorizontalScroller = false
    scrollView.autohidesScrollers = true
    scrollView.scrollerStyle = .overlay

    let textView = LiveMarkdownTextView.makeForEditing()
    textView.delegate = context.coordinator
    textView.onTaskToggle = { [weak coordinator = context.coordinator] location in
      coordinator?.toggleTask(at: location)
    }
    textView.onInsertLink = { [weak coordinator = context.coordinator] in
      coordinator?.insertLink()
    }
    textView.onCancelSlashCommandPalette = { [weak coordinator = context.coordinator] in
      coordinator?.cancelSlashCommandPalette() ?? false
    }
    textView.onMoveEditorCompletion = { [weak coordinator = context.coordinator] delta in
      coordinator?.moveEditorCompletion(by: delta) ?? false
    }
    textView.onCommitEditorCompletion = { [weak coordinator = context.coordinator] in
      coordinator?.commitTagAutocomplete() ?? false
    }
    textView.onCancelEditorCompletion = { [weak coordinator = context.coordinator] in
      coordinator?.cancelTagAutocomplete() ?? false
    }
    textView.onSubmit = onSubmit
    textView.onCancel = onCancel
    textView.seedsTitleOnFirstInsertion = treatsEmptyDocumentAsTitle
    textView.onOpenLink = { [weak coordinator = context.coordinator] destination in
      coordinator?.openLink(destination)
    }
    textView.onFocusChange = { [weak coordinator = context.coordinator, weak textView] isFocused in
      guard let coordinator, let textView else { return }
      coordinator.presentationFocusDidChange(in: textView, isFocused: isFocused)
    }
    textView.isRichText = false
    textView.importsGraphics = false
    textView.allowsUndo = true
    textView.usesFindPanel = true
    textView.isAutomaticDashSubstitutionEnabled = false
    textView.isAutomaticQuoteSubstitutionEnabled = false
    textView.isAutomaticTextReplacementEnabled = false
    textView.isAutomaticSpellingCorrectionEnabled = false
    textView.isContinuousSpellCheckingEnabled = true
    textView.drawsBackground = false
    textView.textColor = .labelColor
    textView.insertionPointColor = .controlAccentColor
    textView.textContainerInset = .zero
    textView.minSize = NSSize(width: 0, height: 0)
    textView.maxSize = NSSize(
      width: CGFloat.greatestFiniteMagnitude,
      height: CGFloat.greatestFiniteMagnitude
    )
    textView.isVerticallyResizable = true
    textView.isHorizontallyResizable = false
    textView.autoresizingMask = [.width]
    textView.textContainer?.widthTracksTextView = true
    textView.textContainer?.containerSize = NSSize(
      width: CGFloat.greatestFiniteMagnitude,
      height: CGFloat.greatestFiniteMagnitude
    )
    textView.setAccessibilityIdentifier(accessibilityIdentifier)

    scrollView.documentView = textView
    context.coordinator.attach(textView: textView, scrollView: scrollView)
    context.coordinator.lastExternalRefreshRequest = externalRefreshRequest
    context.coordinator.load(text: text, revision: contentRevision)
    return scrollView
  }

  func updateNSView(_ scrollView: NSScrollView, context: Context) {
    context.coordinator.parent = self
    guard let textView = context.coordinator.textView else { return }
    textView.onSubmit = onSubmit
    textView.onCancel = onCancel
    textView.seedsTitleOnFirstInsertion = treatsEmptyDocumentAsTitle

    if context.coordinator.lastExternalRefreshRequest != externalRefreshRequest {
      context.coordinator.lastExternalRefreshRequest = externalRefreshRequest
      context.coordinator.refreshPreservingViewState(text: text)
    } else if context.coordinator.loadedRevision != contentRevision {
      context.coordinator.load(text: text, revision: contentRevision)
    }
    textView.isEditable = isEditable
    textView.isSelectable = true

    if context.coordinator.lastFocusRequest != focusRequest {
      context.coordinator.lastFocusRequest = focusRequest
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak textView] in
        guard let textView else { return }
        textView.setSelectedRange(NSRange(
          location: (textView.string as NSString).length,
          length: 0
        ))
        textView.window?.makeFirstResponder(textView)
      }
    }
  }

  @MainActor
  final class Coordinator: NSObject, NSTextViewDelegate {
    var parent: LiveMarkdownEditor
    fileprivate weak var textView: LiveMarkdownTextView?
    private weak var scrollView: NSScrollView?
    private let presentation: LiveMarkdownPresentationController
    private var pendingEdits: [LiveMarkdownPresentationController.PendingEdit] = []
    private var pendingPresentationEdits: [LiveMarkdownPresentationController.PendingEdit] = []
    private var isLoading = false
    private var needsPresentationResetAfterMarkedText = false
    private var needsFullPresentationReset = false
    private var pendingPresentationFocus: Bool?
    private var slashCommandPaletteView: NSHostingView<MacSlashCommandPalette>?
    private var tagAutocompletePaletteView: NSHostingView<MacTagAutocompletePalette>?
    private var tagAutocompleteSuggestions: [MacTagAutocompleteSuggestion] = []
    private var tagAutocompleteSelectionIndex = 0
    private var activeTagTriggerLocation: Int?
    private var dismissedTagTriggerLocation: Int?
    private var activeSlashTriggerLocation: Int?
    private var dismissedSlashTriggerLocation: Int?
    private var presentationRefreshGeneration = 0

    private struct SlashCommandAnchor {
      let slashRect: NSRect
      let lineRect: NSRect
    }

    fileprivate var loadedRevision = -1
    fileprivate var lastExternalRefreshRequest = 0
    fileprivate var lastFocusRequest = 0

    init(parent: LiveMarkdownEditor) {
      self.parent = parent
      presentation = LiveMarkdownPresentationController(
        usesTitleStyleForEmptyDocument: parent.treatsEmptyDocumentAsTitle
      )
    }

    func attach(textView: LiveMarkdownTextView, scrollView: NSScrollView) {
      self.textView = textView
      self.scrollView = scrollView
    }

    func presentationFocusDidChange(in textView: LiveMarkdownTextView, isFocused: Bool) {
      pendingPresentationFocus = isFocused
      schedulePresentationUpdate(in: textView)
    }

    func load(text: String, revision: Int) {
      guard let textView else { return }
      isLoading = true
      pendingEdits = []
      cancelPendingPresentationWork()
      closeSlashCommandPalette(suppressCurrentTrigger: false)
      closeTagAutocomplete(suppressCurrentTrigger: false)
      dismissedSlashTriggerLocation = nil
      textView.string = text
      textView.setSelectedRange(NSRange(location: 0, length: 0))
      loadedRevision = revision
      presentation.reset(
        textView: textView,
        text: text,
        selection: textView.selectedRange()
      )
      needsPresentationResetAfterMarkedText = false
      isLoading = false
      if let scrollView {
        scrollView.contentView.scroll(to: .zero)
        scrollView.reflectScrolledClipView(scrollView.contentView)
      }
    }

    func refreshPreservingViewState(text: String) {
      guard let textView else { return }
      let selection = textView.selectedRange()
      let visibleOrigin = scrollView?.contentView.bounds.origin
      isLoading = true
      pendingEdits = []
      cancelPendingPresentationWork()
      closeSlashCommandPalette(suppressCurrentTrigger: false)
      closeTagAutocomplete(suppressCurrentTrigger: false)
      dismissedSlashTriggerLocation = nil
      textView.string = text
      let length = (text as NSString).length
      textView.setSelectedRange(NSRange(
        location: min(selection.location, length),
        length: min(selection.length, max(0, length - min(selection.location, length)))
      ))
      presentation.reset(
        textView: textView,
        text: text,
        selection: textView.selectedRange()
      )
      needsPresentationResetAfterMarkedText = false
      isLoading = false
      if let scrollView, let visibleOrigin {
        scrollView.contentView.scroll(to: visibleOrigin)
        scrollView.reflectScrolledClipView(scrollView.contentView)
      }
    }

    func textView(
      _ textView: NSTextView,
      shouldChangeTextIn affectedCharRange: NSRange,
      replacementString: String?
    ) -> Bool {
      guard !isLoading else { return true }
      let source: NSString = textView.textStorage?.mutableString ?? (textView.string as NSString)
      pendingEdits.append(presentation.pendingEdit(
        text: source,
        range: affectedCharRange,
        replacement: replacementString ?? ""
      ))
      return true
    }

    func textDidChange(_ notification: Notification) {
      guard !isLoading, let textView = notification.object as? LiveMarkdownTextView else { return }
      guard !pendingEdits.isEmpty else {
        parent.onReplaceAll(textView.string)
        schedulePresentationUpdate(in: textView, requiresFullReset: true)
        return
      }

      let edit = pendingEdits.removeFirst()
      parent.onEdit(edit.range, edit.replacement)
      if textView.hasMarkedText() {
        needsPresentationResetAfterMarkedText = true
        return
      }
      if needsPresentationResetAfterMarkedText {
        needsPresentationResetAfterMarkedText = false
        pendingPresentationEdits.removeAll(keepingCapacity: true)
        schedulePresentationUpdate(in: textView, requiresFullReset: true)
        return
      }
      pendingPresentationEdits.append(edit)
      schedulePresentationUpdate(in: textView)
    }

    func textViewDidChangeSelection(_ notification: Notification) {
      guard !isLoading,
            let textView = notification.object as? LiveMarkdownTextView,
            !textView.hasMarkedText()
      else { return }
      schedulePresentationUpdate(in: textView)
    }

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
      guard commandSelector == #selector(NSResponder.insertNewline(_:)) else { return false }
      if commitTagAutocomplete() {
        return true
      }
      if commitTodaySlashCommand() {
        return true
      }
      guard let result = MarkdownListContinuation.applyReturn(
        to: textView.string,
        selection: textView.selectedRange()
      ) else { return false }

      textView.insertText(result.replacement, replacementRange: result.replacementRange)
      return true
    }

    func toggleTask(at location: Int) {
      guard let textView,
            let result = MarkdownTaskList.toggleTask(
              at: location,
              in: textView.string,
              selection: textView.selectedRange()
            )
      else { return }

      let selection = textView.selectedRange()
      textView.insertText(result.replacement, replacementRange: result.replacementRange)
      textView.setSelectedRange(selection)
    }

    func insertLink() {
      guard let textView,
            let result = LiveMarkdownEditing.linkInsertion(
              currentText: textView.string,
              selection: textView.selectedRange()
            )
      else {
        NSSound.beep()
        return
      }

      textView.insertText(result.replacement, replacementRange: result.replacementRange)
      textView.setSelectedRange(result.selection)
    }

    func openLink(_ destination: LiveMarkdownLinkTarget.Destination) {
      switch destination {
      case .web(let url):
        guard NSWorkspace.shared.open(url) else {
          NSSound.beep()
          return
        }
      case .wiki(let target):
        parent.onOpenWikiLink(target)
      case .tag(let normalizedName):
        parent.onOpenTag(normalizedName)
      }
    }

    func moveEditorCompletion(by delta: Int) -> Bool {
      guard !tagAutocompleteSuggestions.isEmpty else { return false }
      let count = tagAutocompleteSuggestions.count
      tagAutocompleteSelectionIndex = (tagAutocompleteSelectionIndex + delta + count) % count
      updateTagPaletteView()
      return true
    }

    func cancelTagAutocomplete() -> Bool {
      guard !tagAutocompleteSuggestions.isEmpty || tagAutocompletePaletteView != nil else {
        return false
      }
      closeTagAutocomplete(suppressCurrentTrigger: true)
      return true
    }

    @discardableResult
    func commitTagAutocomplete(
      _ selectedSuggestion: MacTagAutocompleteSuggestion? = nil
    ) -> Bool {
      guard let textView else { return false }
      let suggestion: MacTagAutocompleteSuggestion
      if let selectedSuggestion {
        suggestion = selectedSuggestion
      } else {
        guard tagAutocompleteSuggestions.indices.contains(tagAutocompleteSelectionIndex) else {
          return false
        }
        suggestion = tagAutocompleteSuggestions[tagAutocompleteSelectionIndex]
      }
      guard let commit = MacTagAutocomplete.committing(suggestion, in: textView.string)
      else { return false }

      closeTagAutocomplete(suppressCurrentTrigger: false)
      textView.window?.makeFirstResponder(textView)
      textView.insertText(
        "#\(suggestion.name)",
        replacementRange: suggestion.replacementRange
      )
      textView.setSelectedRange(commit.selection)
      return true
    }

    func cancelSlashCommandPalette() -> Bool {
      guard slashCommandPaletteView != nil else { return false }
      closeSlashCommandPalette(suppressCurrentTrigger: true)
      if let textView {
        textView.window?.makeFirstResponder(textView)
      }
      return true
    }

    @discardableResult
    func commitTodaySlashCommand() -> Bool {
      guard let textView,
            let context = MarkdownSlashCommandTrigger.context(
              in: textView.string,
              selection: textView.selectedRange()
            ),
            dismissedSlashTriggerLocation != context.triggerLocation,
            Self.matchesTodayCommand(context.query)
      else { return false }

      let now = Date()
      let calendar = Calendar.current
      let target = MarkdownFilename.dailyNoteStem(for: now, calendar: calendar)
      let replacement = "[[\(target)]]"
      closeSlashCommandPalette(suppressCurrentTrigger: false)
      textView.window?.makeFirstResponder(textView)
      textView.insertText(replacement, replacementRange: context.replacementRange)
      let selection = NSRange(
        location: context.replacementRange.location + (replacement as NSString).length,
        length: 0
      )
      textView.setSelectedRange(selection)
      parent.onEnsureTodayNote(now, calendar)
      return true
    }

    private func schedulePresentationUpdate(
      in textView: LiveMarkdownTextView,
      requiresFullReset: Bool = false
    ) {
      if requiresFullReset {
        needsFullPresentationReset = true
      }

      // NSTextView can be laying out while its delegate callbacks run. Defer
      // attribute rewrites until the event finishes, but apply queued edits
      // incrementally so an ordinary keystroke does not rebuild the whole
      // document and invalidate unrelated markup.
      presentationRefreshGeneration += 1
      let generation = presentationRefreshGeneration
      DispatchQueue.main.async { [weak self, weak textView] in
        guard let self,
              let textView,
              self.presentationRefreshGeneration == generation,
              !textView.hasMarkedText()
        else { return }

        if self.needsFullPresentationReset {
          self.needsFullPresentationReset = false
          self.pendingPresentationEdits.removeAll(keepingCapacity: true)
          self.presentation.reset(
            textView: textView,
            text: textView.string,
            selection: textView.selectedRange()
          )
        } else {
          let edits = self.pendingPresentationEdits
          self.pendingPresentationEdits.removeAll(keepingCapacity: true)
          for edit in edits {
            self.presentation.didApplyEdit(
              edit,
              textView: textView,
              selection: textView.selectedRange()
            )
          }
          if let isFocused = self.pendingPresentationFocus {
            self.pendingPresentationFocus = nil
            self.presentation.focusDidChange(
              in: textView,
              isFocused: isFocused
            )
          } else {
            self.presentation.selectionDidChange(
              in: textView,
              selection: textView.selectedRange()
            )
          }
        }
        self.updateEditorCompletions(in: textView)
      }
    }

    private func updateEditorCompletions(in textView: LiveMarkdownTextView) {
      updateSlashCommandPalette(in: textView)
      if slashCommandPaletteView != nil {
        closeTagAutocomplete(suppressCurrentTrigger: false)
      } else {
        updateTagAutocomplete(in: textView)
      }
    }

    private func updateTagAutocomplete(in textView: LiveMarkdownTextView) {
      guard !textView.hasMarkedText(),
            let context = NoteTagParser.autocompleteContext(
              in: textView.string,
              selection: textView.selectedRange()
            )
      else {
        closeTagAutocomplete(suppressCurrentTrigger: false)
        dismissedTagTriggerLocation = nil
        return
      }
      guard dismissedTagTriggerLocation != context.replacementRange.location else {
        closeTagAutocomplete(suppressCurrentTrigger: false)
        return
      }

      let suggestions = MacTagAutocomplete.suggestions(
        in: textView.string,
        selection: textView.selectedRange(),
        tags: parent.tagSummaries
      )
      guard !suggestions.isEmpty else {
        closeTagAutocomplete(suppressCurrentTrigger: false)
        return
      }

      tagAutocompleteSuggestions = suggestions
      tagAutocompleteSelectionIndex = min(tagAutocompleteSelectionIndex, suggestions.count - 1)
      activeTagTriggerLocation = context.replacementRange.location
      guard let anchor = slashCommandAnchor(
        in: textView,
        triggerLocation: context.replacementRange.location
      ) else { return }

      if tagAutocompletePaletteView == nil {
        let palette = NSHostingView(rootView: tagPaletteRootView())
        textView.addSubview(palette, positioned: .above, relativeTo: nil)
        tagAutocompletePaletteView = palette
      }
      updateTagPaletteView()
      if let palette = tagAutocompletePaletteView {
        positionTagAutocomplete(palette, below: anchor, in: textView)
      }
    }

    private func tagPaletteRootView() -> MacTagAutocompletePalette {
      let maximumRows = MacTagAutocompletePaletteMetrics.maximumVisibleRows
      let start = min(
        max(0, tagAutocompleteSelectionIndex - maximumRows + 1),
        max(0, tagAutocompleteSuggestions.count - maximumRows)
      )
      let end = min(tagAutocompleteSuggestions.count, start + maximumRows)
      return MacTagAutocompletePalette(
        suggestions: Array(tagAutocompleteSuggestions[start..<end]),
        selectedIndex: tagAutocompleteSelectionIndex - start
      ) { [weak self] suggestion in
        _ = self?.commitTagAutocomplete(suggestion)
      }
    }

    private func updateTagPaletteView() {
      tagAutocompletePaletteView?.rootView = tagPaletteRootView()
    }

    private func positionTagAutocomplete(
      _ paletteView: NSView,
      below anchor: SlashCommandAnchor,
      in textView: LiveMarkdownTextView
    ) {
      let visibleRect = textView.visibleRect
      let width = MacTagAutocompletePaletteMetrics.width
      let rowCount = min(
        tagAutocompleteSuggestions.count,
        MacTagAutocompletePaletteMetrics.maximumVisibleRows
      )
      let height = CGFloat(rowCount) * MacTagAutocompletePaletteMetrics.rowHeight
      let minimumX = visibleRect.minX + 8
      let maximumX = max(minimumX, visibleRect.maxX - width - 8)
      let x = min(max(anchor.slashRect.minX, minimumX), maximumX)
      let preferredY = anchor.lineRect.maxY + MacTagAutocompletePaletteMetrics.verticalGap
      let y = preferredY + height <= visibleRect.maxY - 8
        ? preferredY
        : max(visibleRect.minY + 8, anchor.lineRect.minY - height - 8)
      paletteView.frame = NSRect(x: x, y: y, width: width, height: height)
    }

    private func closeTagAutocomplete(suppressCurrentTrigger: Bool) {
      if suppressCurrentTrigger {
        dismissedTagTriggerLocation = activeTagTriggerLocation
      }
      tagAutocompletePaletteView?.removeFromSuperview()
      tagAutocompletePaletteView = nil
      tagAutocompleteSuggestions = []
      tagAutocompleteSelectionIndex = 0
      activeTagTriggerLocation = nil
    }

    private func cancelPendingPresentationWork() {
      presentationRefreshGeneration += 1
      pendingPresentationEdits.removeAll(keepingCapacity: true)
      pendingPresentationFocus = nil
      needsFullPresentationReset = false
    }

    private func updateSlashCommandPalette(in textView: LiveMarkdownTextView) {
      if textView.hasMarkedText() {
        return
      }

      guard let context = MarkdownSlashCommandTrigger.context(
        in: textView.string,
        selection: textView.selectedRange()
      )
      else {
        closeSlashCommandPalette(suppressCurrentTrigger: false)
        dismissedSlashTriggerLocation = nil
        return
      }

      guard Self.matchesTodayCommand(context.query) else {
        closeSlashCommandPalette(suppressCurrentTrigger: false)
        return
      }

      guard dismissedSlashTriggerLocation != context.triggerLocation else {
        closeSlashCommandPalette(suppressCurrentTrigger: false)
        return
      }

      guard let anchor = slashCommandAnchor(
        in: textView,
        triggerLocation: context.triggerLocation
      ) else { return }
      if activeSlashTriggerLocation == context.triggerLocation,
         let slashCommandPaletteView {
        positionSlashCommandPalette(
          slashCommandPaletteView,
          below: anchor,
          in: textView
        )
        return
      }

      closeSlashCommandPalette(suppressCurrentTrigger: false)
      let paletteView = NSHostingView(
        rootView: MacSlashCommandPalette { [weak self] in
          _ = self?.commitTodaySlashCommand()
        }
      )
      paletteView.frame.size = NSSize(
        width: MacSlashCommandPaletteMetrics.width,
        height: MacSlashCommandPaletteMetrics.height
      )
      textView.addSubview(paletteView, positioned: .above, relativeTo: nil)
      slashCommandPaletteView = paletteView
      activeSlashTriggerLocation = context.triggerLocation
      positionSlashCommandPalette(
        paletteView,
        below: anchor,
        in: textView
      )
    }

    private static func matchesTodayCommand(_ query: String) -> Bool {
      "today".hasPrefix(query.lowercased())
    }

    private func slashCommandAnchor(
      in textView: LiveMarkdownTextView,
      triggerLocation: Int
    ) -> SlashCommandAnchor? {
      guard let window = textView.window else { return nil }
      guard triggerLocation >= 0,
            triggerLocation < (textView.string as NSString).length
      else { return nil }
      let slashRange = NSRange(location: triggerLocation, length: 1)
      var actualRange = NSRange(location: NSNotFound, length: 0)
      let screenRect = textView.firstRect(
        forCharacterRange: slashRange,
        actualRange: &actualRange
      )
      guard !screenRect.isEmpty, actualRange.location != NSNotFound else { return nil }
      let windowRect = window.convertFromScreen(screenRect)
      let slashRect = textView.convert(windowRect, from: nil)
      let lineRect = textKitLineRect(
        in: textView,
        at: triggerLocation
      ) ?? slashRect
      return SlashCommandAnchor(slashRect: slashRect, lineRect: lineRect)
    }

    private func textKitLineRect(
      in textView: LiveMarkdownTextView,
      at characterLocation: Int
    ) -> NSRect? {
      guard let layoutManager = textView.layoutManager,
            characterLocation >= 0,
            characterLocation < (textView.string as NSString).length
      else { return nil }
      let glyphRange = layoutManager.glyphRange(
        forCharacterRange: NSRange(location: characterLocation, length: 1),
        actualCharacterRange: nil
      )
      guard glyphRange.length > 0 else { return nil }
      let lineRect = layoutManager.lineFragmentUsedRect(
        forGlyphAt: glyphRange.location,
        effectiveRange: nil
      )
      let origin = textView.textContainerOrigin
      return lineRect.offsetBy(dx: origin.x, dy: origin.y)
    }

    private func positionSlashCommandPalette(
      _ paletteView: NSView,
      below anchor: SlashCommandAnchor,
      in textView: LiveMarkdownTextView
    ) {
      let visibleRect = textView.visibleRect
      let width = MacSlashCommandPaletteMetrics.width
      let height = MacSlashCommandPaletteMetrics.height
      let minimumX = visibleRect.minX + 8
      let maximumX = max(minimumX, visibleRect.maxX - width - 8)
      let x = min(max(anchor.slashRect.minX, minimumX), maximumX)
      let preferredY = anchor.lineRect.maxY + MacSlashCommandPaletteMetrics.verticalGap
      let y = preferredY + height <= visibleRect.maxY - 8
        ? preferredY
        : max(
          visibleRect.minY + 8,
          anchor.lineRect.minY - height - MacSlashCommandPaletteMetrics.verticalGap
        )
      paletteView.frame = NSRect(x: x, y: y, width: width, height: height)
    }

    private func closeSlashCommandPalette(suppressCurrentTrigger: Bool) {
      if suppressCurrentTrigger {
        dismissedSlashTriggerLocation = activeSlashTriggerLocation
      }
      slashCommandPaletteView?.removeFromSuperview()
      slashCommandPaletteView = nil
      activeSlashTriggerLocation = nil
    }
  }
}
