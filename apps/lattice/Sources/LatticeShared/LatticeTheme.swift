import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

public enum LatticeThemeID: String, CaseIterable, Identifiable, Sendable {
  case system
  case graphite
  case darkGraphite
  case solarizedLight
  case solarizedDark

  public var id: String { rawValue }

  public var displayName: String {
    switch self {
    case .system:
      return "System"
    case .graphite:
      return "Graphite"
    case .darkGraphite:
      return "Dark Graphite"
    case .solarizedLight:
      return "Solarized Light"
    case .solarizedDark:
      return "Solarized Dark"
    }
  }

  var preferredColorScheme: ColorScheme? {
    switch self {
    case .system:
      return nil
    case .graphite, .solarizedLight:
      return .light
    case .darkGraphite, .solarizedDark:
      return .dark
    }
  }
}

public enum LatticeThemeRole: Hashable, Sendable {
  case appBackground
  case editorBackground
  case sidebarBackground
  case surfaceBackground
  case barBackground
  case primaryText
  case secondaryText
  case tertiaryText
  case accent
  case link
  case codeText
  case codeBackground
  case quoteText
  case warning
  case highlightedText
  case separator
}

public struct LatticeTheme: Equatable, Sendable {
  public let id: LatticeThemeID
  private let palette: [LatticeThemeRole: LatticeThemeRGB]

  public init(id: LatticeThemeID) {
    self.id = id
    self.palette = Self.palette(for: id)
  }

  public var displayName: String {
    id.displayName
  }

  public var preferredColorScheme: ColorScheme? {
    id.preferredColorScheme
  }

  public func color(_ role: LatticeThemeRole) -> Color {
    #if os(macOS)
    Color(nsColor: nsColor(role))
    #else
    Color(uiColor: uiColor(role))
    #endif
  }

  private func fixedColor(_ role: LatticeThemeRole) -> LatticeThemeRGB? {
    palette[role]
  }

  private static func palette(for id: LatticeThemeID) -> [LatticeThemeRole: LatticeThemeRGB] {
    switch id {
    case .system:
      return [:]
    case .graphite:
      return [
        .appBackground: 0xF4F2EF,
        .editorBackground: 0xF4F2EF,
        .sidebarBackground: 0xE8E5E0,
        .surfaceBackground: 0xFFFFFF,
        .barBackground: 0xEEEAE4,
        .primaryText: 0x2F3336,
        .secondaryText: 0x6E7378,
        .tertiaryText: 0x9BA0A5,
        .accent: 0xD65B5B,
        .link: 0x3978B8,
        .codeText: 0xB04F63,
        .codeBackground: 0xEEEAE4,
        .quoteText: 0x697178,
        .warning: 0xC0732B,
        .highlightedText: 0xFFFFFF,
        .separator: 0xD7D2CB
      ]
    case .darkGraphite:
      return [
        .appBackground: 0x151719,
        .editorBackground: 0x151719,
        .sidebarBackground: 0x111315,
        .surfaceBackground: 0x222629,
        .barBackground: 0x181B1D,
        .primaryText: 0xE6E1D9,
        .secondaryText: 0xA9A49C,
        .tertiaryText: 0x706D68,
        .accent: 0x3FA5F5,
        .link: 0x49A8F2,
        .codeText: 0xE07A9B,
        .codeBackground: 0x2A2E31,
        .quoteText: 0xB4ACA1,
        .warning: 0xD99A47,
        .highlightedText: 0xFFFFFF,
        .separator: 0x34383B
      ]
    case .solarizedLight:
      return [
        .appBackground: 0xFDF6E3,
        .editorBackground: 0xFDF6E3,
        .sidebarBackground: 0xEEE8D5,
        .surfaceBackground: 0xFDF6E3,
        .barBackground: 0xEEE8D5,
        .primaryText: 0x334A4D,
        .secondaryText: 0x657B83,
        .tertiaryText: 0x93A1A1,
        .accent: 0xCB4B16,
        .link: 0x268BD2,
        .codeText: 0xD33682,
        .codeBackground: 0xEEE8D5,
        .quoteText: 0x586E75,
        .warning: 0xB58900,
        .highlightedText: 0xFDF6E3,
        .separator: 0xD8CFB5
      ]
    case .solarizedDark:
      return [
        .appBackground: 0x002B36,
        .editorBackground: 0x002B36,
        .sidebarBackground: 0x00212A,
        .surfaceBackground: 0x073642,
        .barBackground: 0x002B36,
        .primaryText: 0xEEE8D5,
        .secondaryText: 0x93A1A1,
        .tertiaryText: 0x657B83,
        .accent: 0x2AA198,
        .link: 0x268BD2,
        .codeText: 0xD33682,
        .codeBackground: 0x002B36,
        .quoteText: 0xB7BDAF,
        .warning: 0xB58900,
        .highlightedText: 0xFDF6E3,
        .separator: 0x174B57
      ]
    }
  }
}

private struct LatticeThemeRGB: Equatable, Sendable, ExpressibleByIntegerLiteral {
  let red: Double
  let green: Double
  let blue: Double
  let alpha: Double

  init(integerLiteral value: UInt32) {
    self.init(hex: value)
  }

  init(hex: UInt32, alpha: Double = 1) {
    self.red = Double((hex >> 16) & 0xFF) / 255
    self.green = Double((hex >> 8) & 0xFF) / 255
    self.blue = Double(hex & 0xFF) / 255
    self.alpha = alpha
  }
}

private struct LatticeThemeEnvironmentKey: EnvironmentKey {
  static let defaultValue = LatticeTheme(id: .system)
}

public extension EnvironmentValues {
  var latticeTheme: LatticeTheme {
    get { self[LatticeThemeEnvironmentKey.self] }
    set { self[LatticeThemeEnvironmentKey.self] = newValue }
  }
}

#if os(macOS)
public extension LatticeTheme {
  func nsColor(_ role: LatticeThemeRole) -> NSColor {
    if let fixedColor = fixedColor(role) {
      return NSColor(
        calibratedRed: fixedColor.red,
        green: fixedColor.green,
        blue: fixedColor.blue,
        alpha: fixedColor.alpha
      )
    }

    switch role {
    case .appBackground, .editorBackground:
      return .textBackgroundColor
    case .sidebarBackground, .surfaceBackground, .barBackground, .codeBackground:
      return .controlBackgroundColor
    case .primaryText, .codeText:
      return .labelColor
    case .secondaryText, .quoteText:
      return .secondaryLabelColor
    case .tertiaryText:
      return .tertiaryLabelColor
    case .accent:
      return .controlAccentColor
    case .link:
      return .systemBlue
    case .warning:
      return .systemOrange
    case .highlightedText:
      return .white
    case .separator:
      return .separatorColor
    }
  }
}
#else
public extension LatticeTheme {
  func uiColor(_ role: LatticeThemeRole) -> UIColor {
    if let fixedColor = fixedColor(role) {
      return UIColor(
        red: fixedColor.red,
        green: fixedColor.green,
        blue: fixedColor.blue,
        alpha: fixedColor.alpha
      )
    }

    switch role {
    case .appBackground, .editorBackground:
      return .systemBackground
    case .sidebarBackground, .surfaceBackground, .barBackground, .codeBackground:
      return .secondarySystemBackground
    case .primaryText, .codeText:
      return .label
    case .secondaryText, .quoteText:
      return .secondaryLabel
    case .tertiaryText:
      return .tertiaryLabel
    case .accent, .link:
      return .tintColor
    case .warning:
      return .systemOrange
    case .highlightedText:
      return .white
    case .separator:
      return .separator
    }
  }
}
#endif
