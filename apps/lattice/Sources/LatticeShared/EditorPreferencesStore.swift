import Foundation

public struct EditorPreferences: Equatable, Sendable {
  public var isVimModeEnabled: Bool
  public var showsRelativeLineNumbers: Bool
  public var showsTimelineRuler: Bool

  public init(
    isVimModeEnabled: Bool = false,
    showsRelativeLineNumbers: Bool = false,
    showsTimelineRuler: Bool = true
  ) {
    self.isVimModeEnabled = isVimModeEnabled
    self.showsRelativeLineNumbers = showsRelativeLineNumbers
    self.showsTimelineRuler = showsTimelineRuler
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
      showsTimelineRuler: defaults.object(forKey: key("showsTimelineRuler")) as? Bool ?? true
    )
  }

  public func save(_ preferences: EditorPreferences) {
    defaults.set(preferences.isVimModeEnabled, forKey: key("isVimModeEnabled"))
    defaults.set(preferences.showsRelativeLineNumbers, forKey: key("showsRelativeLineNumbers"))
    defaults.set(preferences.showsTimelineRuler, forKey: key("showsTimelineRuler"))
  }

  private func key(_ name: String) -> String {
    "\(keyPrefix).\(name)"
  }
}
