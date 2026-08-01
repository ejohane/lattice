import AppKit
import LatticeEditor

enum LiveMarkdownQuoteLayout {
  static let contentIndent: CGFloat = 76
  static let levelSpacing: CGFloat = 76
  static let barIndent: CGFloat = 20
}

enum LiveMarkdownDecorationKind: Equatable {
  case bullet
  case task(isChecked: Bool)
  case thematicBreak
  case blockquote(level: Int)
}

struct LiveMarkdownDecoration: Equatable {
  let kind: LiveMarkdownDecorationKind
  let range: NSRange
  let usesOutline: Bool

  init(
    kind: LiveMarkdownDecorationKind,
    range: NSRange,
    usesOutline: Bool = false
  ) {
    self.kind = kind
    self.range = range
    self.usesOutline = usesOutline
  }
}

struct LiveMarkdownLinkTarget: Equatable {
  enum Destination: Equatable {
    case web(URL)
    case wiki(String)
  }

  let destination: Destination
  let range: NSRange
}

@MainActor
final class LiveMarkdownPresentationController {
  struct PendingEdit {
    let range: NSRange
    let replacement: String
    let dirtyRangeBeforeEdit: NSRange
  }

  private(set) var tokens: [LiveMarkdownToken] = []
  private let usesTitleStyleForEmptyDocument: Bool
  private var lastSelection = NSRange(location: 0, length: 0)
  private var isEditorFocused = false

  init(usesTitleStyleForEmptyDocument: Bool = true) {
    self.usesTitleStyleForEmptyDocument = usesTitleStyleForEmptyDocument
  }

  func pendingEdit(text: NSString, range: NSRange, replacement: String) -> PendingEdit {
    PendingEdit(
      range: range,
      replacement: replacement,
      dirtyRangeBeforeEdit: LiveMarkdownParser.affectedLineRange(
        in: text,
        around: range,
        adjacentLineCount: 1
      )
    )
  }

  func reset(textView: LiveMarkdownTextView, text: String, selection: NSRange) {
    tokens = LiveMarkdownParser.tokens(in: text)
    lastSelection = selection
    isEditorFocused = textView.window?.firstResponder === textView
    applyPresentation(
      to: textView,
      in: NSRange(location: 0, length: (text as NSString).length),
      selection: selection
    )
    updateDecorations(in: textView)
  }

  func focusDidChange(in textView: LiveMarkdownTextView, isFocused: Bool) {
    guard isEditorFocused != isFocused else { return }
    isEditorFocused = isFocused
    let range = LiveMarkdownParser.affectedLineRange(
      in: textView.textStorage?.mutableString ?? (textView.string as NSString),
      around: textView.selectedRange(),
      adjacentLineCount: 0
    )
    applyPresentation(
      to: textView,
      in: range,
      selection: textView.selectedRange()
    )
    updateDecorations(in: textView)
  }

  func didApplyEdit(
    _ edit: PendingEdit,
    textView: LiveMarkdownTextView,
    selection: NSRange
  ) {
    guard let storage = textView.textStorage else { return }
    let text = storage.mutableString
    let replacementLength = (edit.replacement as NSString).length
    let delta = replacementLength - edit.range.length
    let changedRange = NSRange(location: edit.range.location, length: replacementLength)
    let dirtyRangeAfterEdit = LiveMarkdownParser.affectedLineRange(
      in: text,
      around: changedRange,
      adjacentLineCount: 1
    )

    tokens = tokens.compactMap { token in
      if intersects(token.fullRange, edit.dirtyRangeBeforeEdit) {
        return nil
      }
      let adjusted = token.fullRange.location >= NSMaxRange(edit.range)
        ? token.shifted(by: delta)
        : token
      return intersects(adjusted.fullRange, dirtyRangeAfterEdit) ? nil : adjusted
    }
    tokens += LiveMarkdownParser.tokens(in: text, range: dirtyRangeAfterEdit)
    tokens.sort {
      if $0.fullRange.location == $1.fullRange.location {
        return $0.fullRange.length > $1.fullRange.length
      }
      return $0.fullRange.location < $1.fullRange.location
    }

    lastSelection = selection
    applyPresentation(to: textView, in: dirtyRangeAfterEdit, selection: selection)
    updateDecorations(in: textView)
  }

  func selectionDidChange(in textView: LiveMarkdownTextView, selection: NSRange) {
    guard selection != lastSelection else { return }
    guard let storage = textView.textStorage else { return }
    let text = storage.mutableString
    let previousRange = LiveMarkdownParser.affectedLineRange(
      in: text,
      around: lastSelection,
      adjacentLineCount: 0
    )
    let currentRange = LiveMarkdownParser.affectedLineRange(
      in: text,
      around: selection,
      adjacentLineCount: 0
    )
    lastSelection = selection
    applyPresentation(
      to: textView,
      in: NSUnionRange(previousRange, currentRange),
      selection: selection
    )
    updateDecorations(in: textView)
  }

  func refresh(in textView: LiveMarkdownTextView) {
    applyPresentation(
      to: textView,
      in: NSRange(location: 0, length: (textView.string as NSString).length),
      selection: textView.selectedRange()
    )
    updateDecorations(in: textView)
  }

  private func applyPresentation(
    to textView: LiveMarkdownTextView,
    in requestedRange: NSRange,
    selection: NSRange
  ) {
    guard !textView.hasMarkedText(), let storage = textView.textStorage else { return }
    let range = clamped(requestedRange, length: storage.length)
    guard range.length > 0 else {
      textView.typingAttributes = storage.length == 0 && usesTitleStyleForEmptyDocument
        ? Self.titleTypingAttributes
        : Self.baseAttributes
      return
    }

    storage.beginEditing()
    storage.setAttributes(Self.baseAttributes, range: range)
    for token in tokens where intersects(token.fullRange, range) {
      apply(token, to: storage, selection: selection)
    }
    storage.endEditing()

    textView.typingAttributes = Self.baseAttributes
  }

  private func apply(
    _ token: LiveMarkdownToken,
    to storage: NSTextStorage,
    selection: NSRange
  ) {
    switch token.kind {
    case .codeBlock(let isFence):
      storage.addAttributes([
        .font: NSFont.monospacedSystemFont(ofSize: 15, weight: .regular),
        .backgroundColor: NSColor.tertiaryLabelColor.withAlphaComponent(0.16),
        .paragraphStyle: Self.codeParagraphStyle
      ], range: token.fullRange)
      if isFence {
        applySyntax(token, to: storage, selection: selection, collapsesWhenInactive: true)
      }

    case .blockquote(let level):
      storage.addAttribute(
        .paragraphStyle,
        value: Self.quoteParagraphStyle(level: level),
        range: token.fullRange
      )
      applySyntax(token, to: storage, selection: selection, collapsesWhenInactive: true)

    case .heading(let level):
      storage.addAttribute(
        .paragraphStyle,
        value: Self.headingParagraphStyle(level: level),
        range: token.fullRange
      )
      storage.addAttribute(.font, value: Self.headingFont(level: level), range: token.contentRange)
      applySyntax(token, to: storage, selection: selection, collapsesWhenInactive: true)

    case .thematicBreak:
      let isActive = isEditorFocused && token.isActive(selection: selection)
      storage.addAttribute(
        .foregroundColor,
        value: isActive ? NSColor.tertiaryLabelColor : NSColor.clear,
        range: token.fullRange
      )

    case .bold:
      addFontTrait(.boldFontMask, to: token.contentRange, storage: storage)
      applySyntax(token, to: storage, selection: selection, collapsesWhenInactive: true)

    case .boldItalic:
      addFontTrait(.boldFontMask, to: token.contentRange, storage: storage)
      addFontTrait(.italicFontMask, to: token.contentRange, storage: storage)
      applySyntax(token, to: storage, selection: selection, collapsesWhenInactive: true)

    case .italic:
      addFontTrait(.italicFontMask, to: token.contentRange, storage: storage)
      applySyntax(token, to: storage, selection: selection, collapsesWhenInactive: true)

    case .strikethrough:
      storage.addAttribute(
        .strikethroughStyle,
        value: NSUnderlineStyle.single.rawValue,
        range: token.contentRange
      )
      applySyntax(token, to: storage, selection: selection, collapsesWhenInactive: true)

    case .escapedCharacter:
      applySyntax(token, to: storage, selection: selection, collapsesWhenInactive: true)

    case .inlineCode:
      storage.addAttributes([
        .font: NSFont.monospacedSystemFont(ofSize: 14.5, weight: .regular),
        .backgroundColor: NSColor.tertiaryLabelColor.withAlphaComponent(0.16)
      ], range: token.contentRange)
      applySyntax(token, to: storage, selection: selection, collapsesWhenInactive: true)

    case .markdownLink, .referenceLink, .autolink, .footnoteReference:
      applyLinkStyle(to: token.contentRange, storage: storage)
      applySyntax(token, to: storage, selection: selection, collapsesWhenInactive: true)

    case .footnoteDefinition:
      storage.addAttributes([
        .foregroundColor: NSColor.linkColor,
        .underlineStyle: NSUnderlineStyle.single.rawValue
      ], range: token.contentRange)
      applySyntax(token, to: storage, selection: selection, collapsesWhenInactive: true)

    case .wikiLink:
      applyLinkStyle(to: token.contentRange, storage: storage)
      applySyntax(token, to: storage, selection: selection, collapsesWhenInactive: true)

    case .bareLink:
      applyLinkStyle(to: token.contentRange, storage: storage)

    case .bullet:
      applyListSyntax(token, to: storage)

    case .orderedList:
      storage.addAttribute(.paragraphStyle, value: Self.orderedListParagraphStyle, range: token.fullRange)
      if let markerRange = token.decorationRange {
        storage.addAttributes([
          .foregroundColor: NSColor.controlAccentColor,
          .font: NSFont.systemFont(ofSize: 16, weight: .semibold)
        ], range: markerRange)
      }

    case .task(let isChecked):
      applyListSyntax(token, to: storage)
      if isChecked, token.contentRange.length > 0 {
        storage.addAttributes([
          .strikethroughStyle: NSUnderlineStyle.single.rawValue,
          .foregroundColor: NSColor.secondaryLabelColor
        ], range: token.contentRange)
      }
    }
  }

  private func applySyntax(
    _ token: LiveMarkdownToken,
    to storage: NSTextStorage,
    selection: NSRange,
    collapsesWhenInactive: Bool
  ) {
    let isActive = isEditorFocused && token.isActive(selection: selection)
    for syntaxRange in token.syntaxRanges {
      if isActive {
        storage.addAttributes([
          .font: Self.bodyFont,
          .foregroundColor: NSColor.tertiaryLabelColor
        ], range: syntaxRange)
      } else if collapsesWhenInactive {
        storage.addAttributes([
          .font: NSFont.systemFont(ofSize: 0.01),
          .foregroundColor: NSColor.clear
        ], range: syntaxRange)
      }
    }
  }

  private func applyListSyntax(_ token: LiveMarkdownToken, to storage: NSTextStorage) {
    for syntaxRange in token.syntaxRanges {
      storage.addAttribute(.foregroundColor, value: NSColor.clear, range: syntaxRange)
    }
  }

  private func applyLinkStyle(to range: NSRange, storage: NSTextStorage) {
    storage.addAttributes([
      .foregroundColor: NSColor.linkColor,
      .underlineStyle: NSUnderlineStyle.single.rawValue
    ], range: range)
  }

  private func addFontTrait(
    _ trait: NSFontTraitMask,
    to range: NSRange,
    storage: NSTextStorage
  ) {
    var updates: [(NSFont, NSRange)] = []
    storage.enumerateAttribute(.font, in: range) { value, effectiveRange, _ in
      let font = value as? NSFont ?? Self.bodyFont
      updates.append((NSFontManager.shared.convert(font, toHaveTrait: trait), effectiveRange))
    }
    for (font, effectiveRange) in updates {
      storage.addAttribute(.font, value: font, range: effectiveRange)
    }
  }

  private func updateDecorations(in textView: LiveMarkdownTextView) {
    // Prepare TextKit's line fragments before the view enters draw(_:). Doing
    // this from the draw path can invalidate the view while AppKit is already
    // painting it, which makes typing visibly flash.
    textView.prepareForDecorationDrawing()
    let nonQuoteDecorations: [LiveMarkdownDecoration] = tokens.compactMap { token in
      guard let range = token.decorationRange else { return nil }
      switch token.kind {
      case .bullet:
        return LiveMarkdownDecoration(
          kind: .bullet,
          range: range,
          usesOutline: isInsideBlockquote(token)
        )
      case .task(let isChecked):
        return LiveMarkdownDecoration(kind: .task(isChecked: isChecked), range: range)
      case .thematicBreak:
        guard !(isEditorFocused && token.isActive(selection: lastSelection)) else {
          return nil
        }
        return LiveMarkdownDecoration(kind: .thematicBreak, range: range)
      default:
        return nil
      }
    }
    textView.presentationDecorations = nonQuoteDecorations
      + blockquoteDecorations(in: textView.string as NSString)
    textView.presentationLinks = tokens.compactMap { token in
      switch token.kind {
      case .markdownLink(let value), .referenceLink(let value), .autolink(let value), .bareLink(let value):
        guard let url = LiveMarkdownLinkDestination.webURL(for: value) else {
          return nil
        }
        return LiveMarkdownLinkTarget(
          destination: .web(url),
          range: token.contentRange
        )
      case .wikiLink(let target):
        return LiveMarkdownLinkTarget(
          destination: .wiki(target),
          range: token.contentRange
        )
      default:
        return nil
      }
    }
  }

  private func blockquoteDecorations(in source: NSString) -> [LiveMarkdownDecoration] {
    let quoteTokens = tokens.compactMap { token -> (token: LiveMarkdownToken, level: Int)? in
      guard case .blockquote(let level) = token.kind else { return nil }
      return (token, level)
    }
    guard let maximumLevel = quoteTokens.map(\.level).max() else { return [] }

    var decorations: [LiveMarkdownDecoration] = []
    for level in 1...maximumLevel {
      var group: [LiveMarkdownToken] = []
      for entry in quoteTokens where entry.level >= level {
        if let previous = group.last,
           !isAdjacentQuoteLine(previous, entry.token, in: source) {
          appendBlockquoteDecoration(
            for: group,
            level: level,
            to: &decorations
          )
          group.removeAll(keepingCapacity: true)
        }
        group.append(entry.token)
      }
      appendBlockquoteDecoration(for: group, level: level, to: &decorations)
    }

    return decorations.sorted {
      if $0.range.location == $1.range.location {
        return blockquoteLevel($0) < blockquoteLevel($1)
      }
      return $0.range.location < $1.range.location
    }
  }

  private func isInsideBlockquote(_ token: LiveMarkdownToken) -> Bool {
    tokens.contains { candidate in
      guard case .blockquote = candidate.kind else { return false }
      return NSIntersectionRange(candidate.fullRange, token.fullRange) == token.fullRange
    }
  }

  private func appendBlockquoteDecoration(
    for group: [LiveMarkdownToken],
    level: Int,
    to decorations: inout [LiveMarkdownDecoration]
  ) {
    guard let first = group.first, let last = group.last else { return }
    decorations.append(LiveMarkdownDecoration(
      kind: .blockquote(level: level),
      range: NSRange(
        location: first.fullRange.location,
        length: NSMaxRange(last.fullRange) - first.fullRange.location
      )
    ))
  }

  private func isAdjacentQuoteLine(
    _ previous: LiveMarkdownToken,
    _ next: LiveMarkdownToken,
    in source: NSString
  ) -> Bool {
    let gap = NSRange(
      location: NSMaxRange(previous.fullRange),
      length: next.fullRange.location - NSMaxRange(previous.fullRange)
    )
    guard gap.length > 0 else { return true }
    return source.substring(with: gap) == "\n"
      || source.substring(with: gap) == "\r\n"
  }

  private func blockquoteLevel(_ decoration: LiveMarkdownDecoration) -> Int {
    guard case .blockquote(let level) = decoration.kind else { return .max }
    return level
  }

  private static let bodyFont = NSFont.systemFont(ofSize: 16, weight: .regular)

  private static var baseAttributes: [NSAttributedString.Key: Any] {
    [
      .font: bodyFont,
      .foregroundColor: NSColor.labelColor,
      .paragraphStyle: bodyParagraphStyle
    ]
  }

  private static var titleTypingAttributes: [NSAttributedString.Key: Any] {
    [
      .font: headingFont(level: 1),
      .foregroundColor: NSColor.labelColor,
      .paragraphStyle: headingParagraphStyle(level: 1)
    ]
  }

  private static var bodyParagraphStyle: NSParagraphStyle {
    let style = NSMutableParagraphStyle()
    style.lineSpacing = 4
    style.paragraphSpacing = 7
    return style
  }

  private static var codeParagraphStyle: NSParagraphStyle {
    let style = bodyParagraphStyle.mutableCopy() as? NSMutableParagraphStyle
      ?? NSMutableParagraphStyle()
    style.lineSpacing = 1
    style.paragraphSpacing = 0
    return style
  }

  private static var orderedListParagraphStyle: NSParagraphStyle {
    let style = bodyParagraphStyle.mutableCopy() as? NSMutableParagraphStyle
      ?? NSMutableParagraphStyle()
    style.headIndent = 28
    style.firstLineHeadIndent = 0
    style.paragraphSpacing = 2
    return style
  }

  private static func headingFont(level: Int) -> NSFont {
    switch level {
    case 1: NSFont.systemFont(ofSize: 28, weight: .bold)
    case 2: NSFont.systemFont(ofSize: 24, weight: .bold)
    case 3: NSFont.systemFont(ofSize: 20, weight: .semibold)
    default: NSFont.systemFont(ofSize: 18, weight: .semibold)
    }
  }

  private static func headingParagraphStyle(level: Int) -> NSParagraphStyle {
    let style = bodyParagraphStyle.mutableCopy() as? NSMutableParagraphStyle
      ?? NSMutableParagraphStyle()
    style.paragraphSpacingBefore = level == 1 ? 0 : 8
    style.paragraphSpacing = level == 1 ? 18 : 12
    return style
  }

  private static func quoteParagraphStyle(level: Int) -> NSParagraphStyle {
    let style = bodyParagraphStyle.mutableCopy() as? NSMutableParagraphStyle
      ?? NSMutableParagraphStyle()
    let indent = CGFloat(max(1, level)) * LiveMarkdownQuoteLayout.contentIndent
    style.headIndent = indent
    style.firstLineHeadIndent = indent
    return style
  }

  private func clamped(_ range: NSRange, length: Int) -> NSRange {
    let location = max(0, min(range.location, length))
    return NSRange(
      location: location,
      length: max(0, min(range.length, length - location))
    )
  }

  private func intersects(_ lhs: NSRange, _ rhs: NSRange) -> Bool {
    if lhs.length == 0 || rhs.length == 0 {
      return lhs.location >= rhs.location && lhs.location <= NSMaxRange(rhs)
        || rhs.location >= lhs.location && rhs.location <= NSMaxRange(lhs)
    }
    return NSIntersectionRange(lhs, rhs).length > 0
  }
}
