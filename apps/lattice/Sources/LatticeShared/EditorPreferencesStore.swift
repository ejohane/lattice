import Foundation

public struct EditorPreferences: Equatable, Sendable {
  public var isVimModeEnabled: Bool
  public var showsRelativeLineNumbers: Bool
  public var themeID: LatticeThemeID

  public init(
    isVimModeEnabled: Bool = false,
    showsRelativeLineNumbers: Bool = false,
    themeID: LatticeThemeID = .system
  ) {
    self.isVimModeEnabled = isVimModeEnabled
    self.showsRelativeLineNumbers = showsRelativeLineNumbers
    self.themeID = themeID
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
      themeID: LatticeThemeID(rawValue: defaults.string(forKey: key("themeID")) ?? "") ?? .system
    )
  }

  public func save(_ preferences: EditorPreferences) {
    defaults.set(preferences.isVimModeEnabled, forKey: key("isVimModeEnabled"))
    defaults.set(preferences.showsRelativeLineNumbers, forKey: key("showsRelativeLineNumbers"))
    defaults.set(preferences.themeID.rawValue, forKey: key("themeID"))
  }

  private func key(_ name: String) -> String {
    "\(keyPrefix).\(name)"
  }
}
