import Foundation
import LatticeEditor

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

enum MarkdownAttributedRenderer {
  static func render(_ text: String) -> NSAttributedString {
    let attributed = NSMutableAttributedString(string: text, attributes: baseTypingAttributes())
    applyStyles(to: attributed)
    return attributed
  }

  static func baseTypingAttributes() -> [NSAttributedString.Key: Any] {
    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.lineSpacing = Metrics.lineSpacing
    paragraphStyle.paragraphSpacing = Metrics.paragraphSpacing
    return [
      .font: baseFont(),
      .foregroundColor: labelColor(),
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
      return [.font: headingFont(level: span.level)]
    case .headingMarker:
      return [.foregroundColor: tertiaryLabelColor(), .font: monospacedFont(ofSize: Metrics.markerFontSize)]
    case .listMarker:
      return [.foregroundColor: accentColor(), .font: bodyFont(weight: .semibold)]
    case .blockquote:
      return [.foregroundColor: secondaryLabelColor()]
    case .thematicBreak:
      return [.foregroundColor: tertiaryLabelColor()]
    case .codeBlock:
      return [.font: monospacedFont(ofSize: Metrics.codeFontSize), .backgroundColor: codeBlockBackgroundColor()]
    case .inlineCode:
      return [.font: monospacedFont(ofSize: Metrics.codeFontSize), .foregroundColor: systemPinkColor()]
    case .bold:
      return [.font: bodyFont(weight: .semibold)]
    case .italic:
      return [.font: italicBodyFont()]
    case .link:
      return [.foregroundColor: systemBlueColor(), .underlineStyle: NSUnderlineStyle.single.rawValue]
    }
  }

  private static func headingFont(level: Int?) -> PlatformFont {
    let index = max(0, min((level ?? 1) - 1, Metrics.headingFontSizes.count - 1))
    return bodyFont(ofSize: Metrics.headingFontSizes[index], weight: .bold)
  }

  #if os(macOS)
  private typealias PlatformFont = NSFont
  private typealias PlatformFontWeight = NSFont.Weight
  private typealias PlatformColor = NSColor

  private static func baseFont() -> PlatformFont {
    bodyFont(ofSize: Metrics.bodyFontSize, weight: .regular)
  }

  private static func bodyFont(weight: PlatformFontWeight) -> PlatformFont {
    bodyFont(ofSize: Metrics.bodyFontSize, weight: weight)
  }

  private static func bodyFont(ofSize size: CGFloat, weight: PlatformFontWeight) -> PlatformFont {
    NSFont.systemFont(ofSize: size, weight: weight)
  }

  private static func monospacedFont(ofSize size: CGFloat) -> PlatformFont {
    NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
  }

  private static func italicBodyFont() -> PlatformFont {
    NSFontManager.shared.convert(bodyFont(ofSize: Metrics.bodyFontSize, weight: .regular), toHaveTrait: .italicFontMask)
  }

  private static func labelColor() -> PlatformColor { .labelColor }
  private static func secondaryLabelColor() -> PlatformColor { .secondaryLabelColor }
  private static func tertiaryLabelColor() -> PlatformColor { .tertiaryLabelColor }
  private static func accentColor() -> PlatformColor { .controlAccentColor }
  private static func codeBlockBackgroundColor() -> PlatformColor { .textBackgroundColor }
  private static func systemPinkColor() -> PlatformColor { .systemPink }
  private static func systemBlueColor() -> PlatformColor { .systemBlue }
  #elseif os(iOS)
  private typealias PlatformFont = UIFont
  private typealias PlatformFontWeight = UIFont.Weight
  private typealias PlatformColor = UIColor

  private static func baseFont() -> PlatformFont {
    UIFont.preferredFont(forTextStyle: .title3)
  }

  private static func bodyFont(weight: PlatformFontWeight) -> PlatformFont {
    bodyFont(ofSize: Metrics.bodyFontSize, weight: weight)
  }

  private static func bodyFont(ofSize size: CGFloat, weight: PlatformFontWeight) -> PlatformFont {
    UIFont.systemFont(ofSize: size, weight: weight)
  }

  private static func monospacedFont(ofSize size: CGFloat) -> PlatformFont {
    UIFont.monospacedSystemFont(ofSize: size, weight: .regular)
  }

  private static func italicBodyFont() -> PlatformFont {
    let descriptor = bodyFont(ofSize: Metrics.bodyFontSize, weight: .regular)
      .fontDescriptor
      .withSymbolicTraits(.traitItalic)
      ?? bodyFont(ofSize: Metrics.bodyFontSize, weight: .regular).fontDescriptor
    return UIFont(descriptor: descriptor, size: Metrics.bodyFontSize)
  }

  private static func labelColor() -> PlatformColor { .label }
  private static func secondaryLabelColor() -> PlatformColor { .secondaryLabel }
  private static func tertiaryLabelColor() -> PlatformColor { .tertiaryLabel }
  private static func accentColor() -> PlatformColor { .tintColor }
  private static func codeBlockBackgroundColor() -> PlatformColor { .secondarySystemBackground }
  private static func systemPinkColor() -> PlatformColor { .systemPink }
  private static func systemBlueColor() -> PlatformColor { .systemBlue }
  #endif
}

private enum Metrics {
  static let bodyFontSize: CGFloat = 21
  static let codeFontSize: CGFloat = 18
  static let markerFontSize: CGFloat = 16
  static let lineSpacing: CGFloat = 5
  static let paragraphSpacing: CGFloat = 12
  static let headingFontSizes: [CGFloat] = [34, 30, 26, 23, 21, 20]
}
