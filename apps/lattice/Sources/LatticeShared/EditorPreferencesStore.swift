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

public struct LatticeKeyboardModifiers: OptionSet, Equatable, Sendable {
  public let rawValue: Int

  public init(rawValue: Int) {
    self.rawValue = rawValue
  }

  public static let command = LatticeKeyboardModifiers(rawValue: 1 << 0)
  public static let shift = LatticeKeyboardModifiers(rawValue: 1 << 1)
  public static let option = LatticeKeyboardModifiers(rawValue: 1 << 2)
  public static let control = LatticeKeyboardModifiers(rawValue: 1 << 3)
}

public struct LatticeKeyboardShortcut: Equatable, Sendable {
  public var key: String
  public var modifiers: LatticeKeyboardModifiers

  public init(key: String, modifiers: LatticeKeyboardModifiers) {
    self.key = key.lowercased()
    self.modifiers = modifiers
  }

  public var displayText: String {
    var parts: [String] = []
    if modifiers.contains(.control) {
      parts.append("Ctrl")
    }
    if modifiers.contains(.option) {
      parts.append("Opt")
    }
    if modifiers.contains(.shift) {
      parts.append("Shift")
    }
    if modifiers.contains(.command) {
      parts.insert("Cmd", at: 0)
    }
    parts.append(key.uppercased())
    return parts.joined(separator: "-")
  }

  public var storageValue: String {
    "\(modifiers.rawValue):\(key)"
  }

  public init?(storageValue: String) {
    let parts = storageValue.split(separator: ":", maxSplits: 1).map(String.init)
    guard parts.count == 2,
          let modifierValue = Int(parts[0]),
          !parts[1].isEmpty
    else {
      return nil
    }
    self.init(
      key: parts[1],
      modifiers: LatticeKeyboardModifiers(rawValue: modifierValue)
    )
  }
}

public enum LatticeKeyboardShortcutID: String, CaseIterable, Identifiable, Sendable {
  case commandPalette
  case zenMode
  case newNote
  case navigateBack
  case navigateForward
  case checkForUpdates

  public var id: String {
    rawValue
  }

  public var displayName: String {
    switch self {
    case .commandPalette:
      return "Command Palette"
    case .zenMode:
      return "Zen Mode"
    case .newNote:
      return "New Note"
    case .navigateBack:
      return "Back"
    case .navigateForward:
      return "Forward"
    case .checkForUpdates:
      return "Check for Updates"
    }
  }

  public var defaultShortcut: LatticeKeyboardShortcut {
    switch self {
    case .commandPalette:
      return LatticeKeyboardShortcut(key: "p", modifiers: [.command, .shift])
    case .zenMode:
      return LatticeKeyboardShortcut(key: "z", modifiers: [.command, .shift])
    case .newNote:
      return LatticeKeyboardShortcut(key: "n", modifiers: [.command])
    case .navigateBack:
      return LatticeKeyboardShortcut(key: "[", modifiers: [.command])
    case .navigateForward:
      return LatticeKeyboardShortcut(key: "]", modifiers: [.command])
    case .checkForUpdates:
      return LatticeKeyboardShortcut(key: "u", modifiers: [.command, .shift])
    }
  }
}

public struct EditorPreferences: Equatable, Sendable {
  public var isVimModeEnabled: Bool
  public var showsRelativeLineNumbers: Bool
  public var themeID: LatticeThemeID
  public var fontFamily: EditorFontFamily
  public var keyboardShortcutOverrides: [LatticeKeyboardShortcutID: LatticeKeyboardShortcut]
  public var disabledKeyboardShortcuts: Set<LatticeKeyboardShortcutID>

  public init(
    isVimModeEnabled: Bool = false,
    showsRelativeLineNumbers: Bool = false,
    themeID: LatticeThemeID = .system,
    fontFamily: EditorFontFamily = .system,
    keyboardShortcutOverrides: [LatticeKeyboardShortcutID: LatticeKeyboardShortcut] = [:],
    disabledKeyboardShortcuts: Set<LatticeKeyboardShortcutID> = []
  ) {
    self.isVimModeEnabled = isVimModeEnabled
    self.showsRelativeLineNumbers = showsRelativeLineNumbers
    self.themeID = themeID
    self.fontFamily = fontFamily
    self.keyboardShortcutOverrides = keyboardShortcutOverrides
    self.disabledKeyboardShortcuts = disabledKeyboardShortcuts
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
      keyboardShortcutOverrides: keyboardShortcutOverrides(),
      disabledKeyboardShortcuts: disabledKeyboardShortcuts()
    )
  }

  public func save(_ preferences: EditorPreferences) {
    defaults.set(preferences.isVimModeEnabled, forKey: key("isVimModeEnabled"))
    defaults.set(preferences.showsRelativeLineNumbers, forKey: key("showsRelativeLineNumbers"))
    defaults.set(preferences.themeID.rawValue, forKey: key("themeID"))
    defaults.set(preferences.fontFamily.rawValue, forKey: key("fontFamily"))
    defaults.set(
      Dictionary(uniqueKeysWithValues: preferences.keyboardShortcutOverrides.map {
        ($0.key.rawValue, $0.value.storageValue)
      }),
      forKey: key("keyboardShortcutOverrides")
    )
    defaults.set(
      preferences.disabledKeyboardShortcuts.map(\.rawValue),
      forKey: key("disabledKeyboardShortcuts")
    )
  }

  private func key(_ name: String) -> String {
    "\(keyPrefix).\(name)"
  }

  private func keyboardShortcutOverrides() -> [LatticeKeyboardShortcutID: LatticeKeyboardShortcut] {
    guard let stored = defaults.dictionary(forKey: key("keyboardShortcutOverrides")) as? [String: String] else {
      return [:]
    }

    return stored.reduce(into: [:]) { result, pair in
      guard let id = LatticeKeyboardShortcutID(rawValue: pair.key),
            let shortcut = LatticeKeyboardShortcut(storageValue: pair.value)
      else {
        return
      }
      result[id] = shortcut
    }
  }

  private func disabledKeyboardShortcuts() -> Set<LatticeKeyboardShortcutID> {
    guard let stored = defaults.stringArray(forKey: key("disabledKeyboardShortcuts")) else {
      return []
    }

    return Set(stored.compactMap(LatticeKeyboardShortcutID.init(rawValue:)))
  }
}
