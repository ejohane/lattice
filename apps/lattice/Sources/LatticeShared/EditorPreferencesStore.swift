import Foundation

public struct EditorPreferences: Equatable, Sendable {
  public var isVimModeEnabled: Bool
  public var showsRelativeLineNumbers: Bool

  public init(
    isVimModeEnabled: Bool = false,
    showsRelativeLineNumbers: Bool = false
  ) {
    self.isVimModeEnabled = isVimModeEnabled
    self.showsRelativeLineNumbers = showsRelativeLineNumbers
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
      showsRelativeLineNumbers: defaults.bool(forKey: key("showsRelativeLineNumbers"))
    )
  }

  public func save(_ preferences: EditorPreferences) {
    defaults.set(preferences.isVimModeEnabled, forKey: key("isVimModeEnabled"))
    defaults.set(preferences.showsRelativeLineNumbers, forKey: key("showsRelativeLineNumbers"))
  }

  private func key(_ name: String) -> String {
    "\(keyPrefix).\(name)"
  }
}
