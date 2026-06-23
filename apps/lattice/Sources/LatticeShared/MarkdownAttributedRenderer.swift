import Foundation
import LatticeEditor

#if os(macOS)
import AppKit

enum MarkdownAttributedRenderer {
  static let bodyFontSize: CGFloat = 14

  static func render(_ text: String, fontSize: CGFloat = bodyFontSize) -> NSAttributedString {
    let attributed = NSMutableAttributedString(string: text, attributes: baseTypingAttributes(fontSize: fontSize))
    applyStyles(to: attributed, fontSize: fontSize)
    return attributed
  }

  static func bodyFont(size: CGFloat = bodyFontSize, weight: NSFont.Weight = .regular) -> NSFont {
    NSFont.systemFont(ofSize: size, weight: weight)
  }

  private static func monospaceBodyFont(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
    NSFont.monospacedSystemFont(ofSize: size, weight: weight)
  }

  static func baseTypingAttributes(fontSize: CGFloat = bodyFontSize) -> [NSAttributedString.Key: Any] {
    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.lineSpacing = 2
    paragraphStyle.paragraphSpacing = 6
    return [
      .font: bodyFont(size: fontSize),
      .foregroundColor: NSColor.labelColor,
      .paragraphStyle: paragraphStyle
    ]
  }

  private static func applyStyles(to attributed: NSMutableAttributedString, fontSize: CGFloat) {
    for span in MarkdownStyler.spans(in: attributed.string) {
      guard NSMaxRange(span.range) <= attributed.length else {
        continue
      }
      attributed.addAttributes(attributes(for: span, fontSize: fontSize), range: span.range)
    }
  }

  private static func attributes(for span: MarkdownStyleSpan, fontSize: CGFloat) -> [NSAttributedString.Key: Any] {
    switch span.kind {
    case .heading:
      let sizes: [CGFloat] = [34, 30, 26, 23, 21, 20]
      let index = max(0, min((span.level ?? 1) - 1, sizes.count - 1))
      let scaledSize = sizes[index] * fontSize / bodyFontSize
      return [.font: NSFont.systemFont(ofSize: scaledSize, weight: .bold)]
    case .headingMarker:
      return [
        .foregroundColor: NSColor.tertiaryLabelColor,
        .font: NSFont.monospacedSystemFont(ofSize: 16 * fontSize / bodyFontSize, weight: .regular)
      ]
    case .listMarker:
      return [
        .foregroundColor: NSColor.controlAccentColor,
        .font: NSFont.systemFont(ofSize: 21 * fontSize / bodyFontSize, weight: .semibold)
      ]
    case .blockquote:
      return [.foregroundColor: NSColor.secondaryLabelColor]
    case .thematicBreak:
      return [.foregroundColor: NSColor.tertiaryLabelColor]
    case .codeBlock:
      return [.font: monospaceBodyFont(size: fontSize), .backgroundColor: NSColor.textBackgroundColor]
    case .inlineCode:
      return [.font: monospaceBodyFont(size: fontSize), .foregroundColor: NSColor.systemPink]
    case .bold:
      return [.font: bodyFont(size: fontSize, weight: .semibold)]
    case .italic:
      return [.font: NSFontManager.shared.convert(bodyFont(size: fontSize), toHaveTrait: .italicFontMask)]
    case .link:
      return [.foregroundColor: NSColor.systemBlue, .underlineStyle: NSUnderlineStyle.single.rawValue]
    }
  }
}

#elseif os(iOS)
import UIKit

enum MarkdownAttributedRenderer {
  static func render(_ text: String) -> NSAttributedString {
    let attributed = NSMutableAttributedString(string: text, attributes: baseTypingAttributes())
    applyStyles(to: attributed)
    return attributed
  }

  static func baseTypingAttributes() -> [NSAttributedString.Key: Any] {
    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.lineSpacing = 2
    paragraphStyle.paragraphSpacing = 6
    return [
      .font: UIFont.preferredFont(forTextStyle: .title3),
      .foregroundColor: UIColor.label,
      .paragraphStyle: paragraphStyle
    ]
  }

  private static func applyStyles(to attributed: NSMutableAttributedString) {
    for span in MarkdownStyler.spans(in: attributed.string) {
      guard NSMaxRange(span.range) <= attributed.length else {
        continue
      }
      attributed.addAttributes(attributes(for: span), range: span.range)
    }
  }

  private static func attributes(for span: MarkdownStyleSpan) -> [NSAttributedString.Key: Any] {
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
    }
  }

  private static func italicBodyFont() -> UIFont {
    let descriptor = UIFont.systemFont(ofSize: 21).fontDescriptor.withSymbolicTraits(.traitItalic)
      ?? UIFont.systemFont(ofSize: 21).fontDescriptor
    return UIFont(descriptor: descriptor, size: 21)
  }
}
#endif
