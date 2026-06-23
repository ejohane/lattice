import LatticeEditor
import SwiftUI

#if os(macOS)
import AppKit

public struct MarkdownTextEditor: NSViewRepresentable {
  @Binding var text: String
  @Binding var selectedRange: NSRange
  let fontSize: CGFloat
  let focusToken: Int
  let onTextChange: () -> Void

  public init(
    text: Binding<String>,
    selectedRange: Binding<NSRange>,
    fontSize: CGFloat,
    focusToken: Int,
    onTextChange: @escaping () -> Void
  ) {
    self._text = text
    self._selectedRange = selectedRange
    self.fontSize = fontSize
    self.focusToken = focusToken
    self.onTextChange = onTextChange
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
    if textView.string != text || context.coordinator.lastRenderedFontSize != fontSize {
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
        activeRanges: [selection]
      )
      textView.textStorage?.setAttributedString(attributed)
      textView.setSelectedRange(clamped(selection, length: (text as NSString).length))
      textView.typingAttributes = MarkdownAttributedRenderer.baseTypingAttributes(fontSize: parent.fontSize)
      lastRenderedFontSize = parent.fontSize
      isRendering = false
    }
  }
}

private final class MarkdownTextView: NSTextView {
  private struct MarkdownListMarker {
    let lineContentRange: NSRange
    let continuationPrefix: String
    let hasContent: Bool
  }

  override func insertNewline(_ sender: Any?) {
    if continueMarkdownList() {
      return
    }

    super.insertNewline(sender)
  }

  private func continueMarkdownList() -> Bool {
    let range = selectedRange()
    guard let marker = markdownListMarker(at: range.location) else {
      return false
    }

    if range.length == 0 && !marker.hasContent {
      guard shouldChangeText(in: marker.lineContentRange, replacementString: "") else {
        return true
      }

      textStorage?.replaceCharacters(in: marker.lineContentRange, with: "")
      setSelectedRange(NSRange(location: marker.lineContentRange.location, length: 0))
      didChangeText()
      return true
    }

    let replacement = "\n" + marker.continuationPrefix
    guard shouldChangeText(in: range, replacementString: replacement) else {
      return true
    }

    textStorage?.replaceCharacters(in: range, with: replacement)
    setSelectedRange(NSRange(location: range.location + replacement.utf16.count, length: 0))
    didChangeText()
    return true
  }

  private func markdownListMarker(at location: Int) -> MarkdownListMarker? {
    let nsString = string as NSString
    let safeLocation = min(location, nsString.length)
    let lineRange = nsString.lineRange(for: NSRange(location: safeLocation, length: 0))
    let lineContentRange = contentRangeWithoutLineEnding(lineRange, in: nsString)
    let line = nsString.substring(with: lineContentRange)

    if let marker = unorderedListMarker(line: line, lineContentRange: lineContentRange) {
      return marker
    }

    return orderedListMarker(line: line, lineContentRange: lineContentRange)
  }

  private func unorderedListMarker(line: String, lineContentRange: NSRange) -> MarkdownListMarker? {
    guard let match = firstRegexMatch("^([ \\t]*)([-*+])([ \\t]+)(?:(\\[[ xX]\\])([ \\t]+))?(.*)$", in: line) else {
      return nil
    }

    let nsLine = line as NSString
    let indent = nsLine.substring(with: match.range(at: 1))
    let bullet = nsLine.substring(with: match.range(at: 2))
    let spacing = nsLine.substring(with: match.range(at: 3))
    let contentRange = match.range(at: 6)
    let content = contentRange.location == NSNotFound ? "" : nsLine.substring(with: contentRange)
    let taskSpacingRange = match.range(at: 5)
    let continuationPrefix: String

    if match.range(at: 4).location == NSNotFound {
      continuationPrefix = indent + bullet + spacing
    } else {
      let taskSpacing = taskSpacingRange.location == NSNotFound ? spacing : nsLine.substring(with: taskSpacingRange)
      continuationPrefix = indent + bullet + spacing + "[ ]" + taskSpacing
    }

    return MarkdownListMarker(
      lineContentRange: lineContentRange,
      continuationPrefix: continuationPrefix,
      hasContent: !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    )
  }

  private func orderedListMarker(line: String, lineContentRange: NSRange) -> MarkdownListMarker? {
    guard let match = firstRegexMatch("^([ \\t]*)(\\d+)([.)])([ \\t]+)(.*)$", in: line) else {
      return nil
    }

    let nsLine = line as NSString
    let indent = nsLine.substring(with: match.range(at: 1))
    let numberText = nsLine.substring(with: match.range(at: 2))
    let delimiter = nsLine.substring(with: match.range(at: 3))
    let spacing = nsLine.substring(with: match.range(at: 4))
    let content = nsLine.substring(with: match.range(at: 5))
    let nextNumber = (Int(numberText) ?? 0) + 1

    return MarkdownListMarker(
      lineContentRange: lineContentRange,
      continuationPrefix: "\(indent)\(nextNumber)\(delimiter)\(spacing)",
      hasContent: !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    )
  }

  private func contentRangeWithoutLineEnding(_ lineRange: NSRange, in nsString: NSString) -> NSRange {
    var end = NSMaxRange(lineRange)
    while end > lineRange.location {
      let character = nsString.character(at: end - 1)
      if character == 10 || character == 13 {
        end -= 1
      } else {
        break
      }
    }

    return NSRange(location: lineRange.location, length: end - lineRange.location)
  }

  private func firstRegexMatch(_ pattern: String, in string: String) -> NSTextCheckingResult? {
    guard let regex = try? NSRegularExpression(pattern: pattern) else {
      return nil
    }

    return regex.firstMatch(in: string, range: NSRange(location: 0, length: (string as NSString).length))
  }
}

#elseif os(iOS)
import UIKit

public struct MarkdownTextEditor: UIViewRepresentable {
  @Binding var text: String
  @Binding var selectedRange: NSRange
  let fontSize: CGFloat
  let focusToken: Int
  let onTextChange: () -> Void

  public init(
    text: Binding<String>,
    selectedRange: Binding<NSRange>,
    fontSize: CGFloat,
    focusToken: Int,
    onTextChange: @escaping () -> Void
  ) {
    self._text = text
    self._selectedRange = selectedRange
    self.fontSize = fontSize
    self.focusToken = focusToken
    self.onTextChange = onTextChange
  }

  public func makeCoordinator() -> Coordinator {
    Coordinator(parent: self)
  }

  public func makeUIView(context: Context) -> UITextView {
    let textView = UITextView()
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
    return textView
  }

  public func updateUIView(_ textView: UITextView, context: Context) {
    context.coordinator.parent = self
    if textView.text != text {
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
  public final class Coordinator: NSObject, UITextViewDelegate {
    var parent: MarkdownTextEditor
    var lastFocusToken = 0
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
    }

    func render(_ text: String, in textView: UITextView, preserving selection: NSRange) {
      guard !isRendering else {
        return
      }
      isRendering = true
      textView.attributedText = MarkdownAttributedRenderer.render(text)
      textView.selectedRange = clamped(selection, length: (text as NSString).length)
      textView.typingAttributes = MarkdownAttributedRenderer.baseTypingAttributes()
      isRendering = false
    }
  }
}
#endif

private func clamped(_ range: NSRange, length: Int) -> NSRange {
  let location = max(0, min(range.location, length))
  return NSRange(location: location, length: max(0, min(range.length, length - location)))
}
