import AppKit
import LatticeEditor
import SwiftUI

struct LiveMarkdownEditor: NSViewRepresentable {
  let text: String
  let contentRevision: Int
  let focusRequest: Int
  let isEditable: Bool
  let onEdit: (NSRange, String) -> Void
  let onReplaceAll: (String) -> Void

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

    let textView = LiveMarkdownTextView(usingTextLayoutManager: true)
    textView.delegate = context.coordinator
    textView.onTaskToggle = { [weak coordinator = context.coordinator] location in
      coordinator?.toggleTask(at: location)
    }
    textView.onInsertLink = { [weak coordinator = context.coordinator] in
      coordinator?.insertLink()
    }
    textView.onOpenLink = { url in
      guard NSWorkspace.shared.open(url) else {
        NSSound.beep()
        return
      }
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
    textView.setAccessibilityIdentifier("noteEditor")

    scrollView.documentView = textView
    context.coordinator.attach(textView: textView, scrollView: scrollView)
    context.coordinator.load(text: text, revision: contentRevision)
    return scrollView
  }

  func updateNSView(_ scrollView: NSScrollView, context: Context) {
    context.coordinator.parent = self
    guard let textView = context.coordinator.textView else { return }

    if context.coordinator.loadedRevision != contentRevision {
      context.coordinator.load(text: text, revision: contentRevision)
    }
    textView.isEditable = isEditable
    textView.isSelectable = true

    if context.coordinator.lastFocusRequest != focusRequest {
      context.coordinator.lastFocusRequest = focusRequest
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak textView] in
        guard let textView else { return }
        textView.window?.makeFirstResponder(textView)
      }
    }
  }

  @MainActor
  final class Coordinator: NSObject, NSTextViewDelegate {
    var parent: LiveMarkdownEditor
    fileprivate weak var textView: LiveMarkdownTextView?
    private weak var scrollView: NSScrollView?
    private let presentation = LiveMarkdownPresentationController()
    private var pendingEdits: [LiveMarkdownPresentationController.PendingEdit] = []
    private var isLoading = false
    private var needsPresentationResetAfterMarkedText = false

    fileprivate var loadedRevision = -1
    fileprivate var lastFocusRequest = 0

    init(parent: LiveMarkdownEditor) {
      self.parent = parent
    }

    func attach(textView: LiveMarkdownTextView, scrollView: NSScrollView) {
      self.textView = textView
      self.scrollView = scrollView
    }

    func presentationFocusDidChange(in textView: LiveMarkdownTextView, isFocused: Bool) {
      presentation.focusDidChange(in: textView, isFocused: isFocused)
    }

    func load(text: String, revision: Int) {
      guard let textView else { return }
      isLoading = true
      pendingEdits = []
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
        presentation.reset(
          textView: textView,
          text: textView.string,
          selection: textView.selectedRange()
        )
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
        presentation.reset(
          textView: textView,
          text: textView.string,
          selection: textView.selectedRange()
        )
        return
      }
      presentation.didApplyEdit(
        edit,
        textView: textView,
        selection: textView.selectedRange()
      )
    }

    func textViewDidChangeSelection(_ notification: Notification) {
      guard !isLoading,
            let textView = notification.object as? LiveMarkdownTextView,
            !textView.hasMarkedText()
      else { return }
      presentation.selectionDidChange(in: textView, selection: textView.selectedRange())
    }

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
      guard commandSelector == #selector(NSResponder.insertNewline(_:)) else { return false }
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
      presentation.selectionDidChange(in: textView, selection: selection)
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
      presentation.selectionDidChange(in: textView, selection: result.selection)
    }
  }
}
