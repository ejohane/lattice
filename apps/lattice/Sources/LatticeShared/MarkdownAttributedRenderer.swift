import Foundation
import LatticeEditor

#if os(macOS)
import AppKit

enum MarkdownAttributedRenderer {
  static func render(_ text: String, selection: NSRange? = nil) -> NSAttributedString {
    let attributed = NSMutableAttributedString(string: text, attributes: baseTypingAttributes())
    applyStyles(to: attributed, selection: selection)
    return attributed
  }

  static func baseTypingAttributes() -> [NSAttributedString.Key: Any] {
    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.lineSpacing = 5
    paragraphStyle.paragraphSpacing = 12
    return [
      .font: NSFont.systemFont(ofSize: 21, weight: .regular),
      .foregroundColor: NSColor.labelColor,
      .paragraphStyle: paragraphStyle
    ]
  }

  private static func applyStyles(to attributed: NSMutableAttributedString, selection: NSRange?) {
    for span in MarkdownStyler.spans(in: attributed.string) {
      guard NSMaxRange(span.range) <= attributed.length else {
        continue
      }
      attributed.addAttributes(attributes(for: span, selection: selection), range: span.range)
    }
  }

  private static func attributes(for span: MarkdownStyleSpan, selection: NSRange?) -> [NSAttributedString.Key: Any] {
    switch span.kind {
    case .heading:
      let sizes: [CGFloat] = [34, 30, 26, 23, 21, 20]
      let index = max(0, min((span.level ?? 1) - 1, sizes.count - 1))
      return [.font: NSFont.systemFont(ofSize: sizes[index], weight: .bold)]
    case .headingMarker:
      return [.foregroundColor: NSColor.tertiaryLabelColor, .font: NSFont.monospacedSystemFont(ofSize: 16, weight: .regular)]
    case .listMarker:
      return [.foregroundColor: NSColor.controlAccentColor, .font: NSFont.systemFont(ofSize: 21, weight: .semibold)]
    case .blockquote:
      return [.foregroundColor: NSColor.secondaryLabelColor]
    case .thematicBreak:
      return [.foregroundColor: NSColor.tertiaryLabelColor]
    case .codeBlock:
      return [.font: NSFont.monospacedSystemFont(ofSize: 18, weight: .regular), .backgroundColor: NSColor.textBackgroundColor]
    case .inlineCode:
      return [.font: NSFont.monospacedSystemFont(ofSize: 18, weight: .regular), .foregroundColor: NSColor.systemPink]
    case .bold:
      return [.font: NSFont.systemFont(ofSize: 21, weight: .semibold)]
    case .italic:
      return [.font: NSFontManager.shared.convert(NSFont.systemFont(ofSize: 21), toHaveTrait: .italicFontMask)]
    case .link:
      return [.foregroundColor: NSColor.systemBlue, .underlineStyle: NSUnderlineStyle.single.rawValue]
    case .noteLink:
      return [.foregroundColor: NSColor.systemBlue, .underlineStyle: NSUnderlineStyle.single.rawValue]
    case .noteLinkDelimiter:
      if isActiveNoteLink(span, selection: selection) {
        return [
          .foregroundColor: NSColor.tertiaryLabelColor,
          .font: NSFont.monospacedSystemFont(ofSize: 16, weight: .regular)
        ]
      }
      return hiddenDelimiterAttributes()
    }
  }

  private static func hiddenDelimiterAttributes() -> [NSAttributedString.Key: Any] {
    [
      .foregroundColor: NSColor.clear,
      .font: NSFont.systemFont(ofSize: 0.1),
      .kern: -0.1
    ]
  }

  private static func isActiveNoteLink(_ span: MarkdownStyleSpan, selection: NSRange?) -> Bool {
    guard let selection, let containerRange = span.containerRange else {
      return false
    }
    if selection.length == 0 {
      return NSLocationInRange(selection.location, containerRange)
    }
    return NSIntersectionRange(selection, containerRange).length > 0
  }
}

#elseif os(iOS)
import UIKit

enum MarkdownAttributedRenderer {
  static func render(_ text: String, selection: NSRange? = nil) -> NSAttributedString {
    let attributed = NSMutableAttributedString(string: text, attributes: baseTypingAttributes())
    applyStyles(to: attributed, selection: selection)
    return attributed
  }

  static func baseTypingAttributes() -> [NSAttributedString.Key: Any] {
    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.lineSpacing = 5
    paragraphStyle.paragraphSpacing = 12
    return [
      .font: UIFont.preferredFont(forTextStyle: .title3),
      .foregroundColor: UIColor.label,
      .paragraphStyle: paragraphStyle
    ]
  }

  private static func applyStyles(to attributed: NSMutableAttributedString, selection: NSRange?) {
    for span in MarkdownStyler.spans(in: attributed.string) {
      guard NSMaxRange(span.range) <= attributed.length else {
        continue
      }
      attributed.addAttributes(attributes(for: span, selection: selection), range: span.range)
    }
  }

  private static func attributes(for span: MarkdownStyleSpan, selection: NSRange?) -> [NSAttributedString.Key: Any] {
    switch span.kind {
    case .heading:
      let sizes: [CGFloat] = [34, 30, 26, 23, 21, 20]
      let index = max(0, min((span.level ?? 1) - 1, sizes.count - 1))
      return [.font: UIFont.systemFont(ofSize: sizes[index], weight: .bold)]
    case .headingMarker:
      return [.foregroundColor: UIColor.tertiaryLabel, .font: UIFont.monospacedSystemFont(ofSize: 16, weight: .regular)]
    case .listMarker:
      return [.foregroundColor: UIColor.tintColor, .font: UIFont.systemFont(ofSize: 21, weight: .semibold)]
    case .blockquote:
      return [.foregroundColor: UIColor.secondaryLabel]
    case .thematicBreak:
      return [.foregroundColor: UIColor.tertiaryLabel]
    case .codeBlock:
      return [.font: UIFont.monospacedSystemFont(ofSize: 18, weight: .regular), .backgroundColor: UIColor.secondarySystemBackground]
    case .inlineCode:
      return [.font: UIFont.monospacedSystemFont(ofSize: 18, weight: .regular), .foregroundColor: UIColor.systemPink]
    case .bold:
      return [.font: UIFont.systemFont(ofSize: 21, weight: .semibold)]
    case .italic:
      return [.font: italicBodyFont()]
    case .link:
      return [.foregroundColor: UIColor.systemBlue, .underlineStyle: NSUnderlineStyle.single.rawValue]
    case .noteLink:
      return [.foregroundColor: UIColor.systemBlue, .underlineStyle: NSUnderlineStyle.single.rawValue]
    case .noteLinkDelimiter:
      if isActiveNoteLink(span, selection: selection) {
        return [
          .foregroundColor: UIColor.tertiaryLabel,
          .font: UIFont.monospacedSystemFont(ofSize: 16, weight: .regular)
        ]
      }
      return hiddenDelimiterAttributes()
    }
  }

  private static func hiddenDelimiterAttributes() -> [NSAttributedString.Key: Any] {
    [
      .foregroundColor: UIColor.clear,
      .font: UIFont.systemFont(ofSize: 0.1),
      .kern: -0.1
    ]
  }

  private static func isActiveNoteLink(_ span: MarkdownStyleSpan, selection: NSRange?) -> Bool {
    guard let selection, let containerRange = span.containerRange else {
      return false
    }
    if selection.length == 0 {
      return NSLocationInRange(selection.location, containerRange)
    }
    return NSIntersectionRange(selection, containerRange).length > 0
  }

  private static func italicBodyFont() -> UIFont {
    let descriptor = UIFont.systemFont(ofSize: 21).fontDescriptor.withSymbolicTraits(.traitItalic)
      ?? UIFont.systemFont(ofSize: 21).fontDescriptor
    return UIFont(descriptor: descriptor, size: 21)
  }
}
#endif
