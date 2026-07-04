import Foundation

public enum EditorFontFamily: String, CaseIterable, Identifiable, Sendable {
  case system
  case monospaced

  public var id: String {
    rawValue
  }

  public var displayName: String {
    switch self {
    case .system:
      return "System"
    case .monospaced:
      return "Monospaced"
    }
  }
}

public struct EditorPreferences: Equatable, Sendable {
  public var isVimModeEnabled: Bool
  public var showsRelativeLineNumbers: Bool
  public var themeID: LatticeThemeID
  public var fontFamily: EditorFontFamily
  public var showsStatusBar: Bool

  public init(
    isVimModeEnabled: Bool = false,
    showsRelativeLineNumbers: Bool = false,
    themeID: LatticeThemeID = .system,
    fontFamily: EditorFontFamily = .system,
    showsStatusBar: Bool = true
  ) {
    self.isVimModeEnabled = isVimModeEnabled
    self.showsRelativeLineNumbers = showsRelativeLineNumbers
    self.themeID = themeID
    self.fontFamily = fontFamily
    self.showsStatusBar = showsStatusBar
  }
}

public final class EditorPreferencesStore {
  private let defaults: UserDefaults
  private let keyPrefix: String

  public init(
    defaults: UserDefaults = .standard,
    keyPrefix: String = "editor"
  ) {
    self.defaults = defaults
    self.keyPrefix = keyPrefix
  }

  public func load() -> EditorPreferences {
    EditorPreferences(
      isVimModeEnabled: defaults.bool(forKey: key("isVimModeEnabled")),
      showsRelativeLineNumbers: defaults.bool(forKey: key("showsRelativeLineNumbers")),
      themeID: LatticeThemeID(rawValue: defaults.string(forKey: key("themeID")) ?? "") ?? .system,
      fontFamily: EditorFontFamily(rawValue: defaults.string(forKey: key("fontFamily")) ?? "") ?? .system,
      showsStatusBar: bool(forKey: key("showsStatusBar"), defaultValue: true)
    )
  }

  public func save(_ preferences: EditorPreferences) {
    defaults.set(preferences.isVimModeEnabled, forKey: key("isVimModeEnabled"))
    defaults.set(preferences.showsRelativeLineNumbers, forKey: key("showsRelativeLineNumbers"))
    defaults.set(preferences.themeID.rawValue, forKey: key("themeID"))
    defaults.set(preferences.fontFamily.rawValue, forKey: key("fontFamily"))
    defaults.set(preferences.showsStatusBar, forKey: key("showsStatusBar"))
  }

  private func key(_ name: String) -> String {
    "\(keyPrefix).\(name)"
  }

  private func bool(forKey key: String, defaultValue: Bool) -> Bool {
    guard defaults.object(forKey: key) != nil else {
      return defaultValue
    }

    return defaults.bool(forKey: key)
  }
}
