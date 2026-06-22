import AppKit
import Combine

@MainActor
final class MacAppSettings: ObservableObject {
  private enum DefaultsKey {
    static let appearanceMode = "appearanceMode"
  }

  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  var appearanceMode: MacAppearanceMode {
    get {
      guard
        let rawValue = defaults.string(forKey: DefaultsKey.appearanceMode),
        let mode = MacAppearanceMode(rawValue: rawValue)
      else {
        return .system
      }
      return mode
    }
    set {
      defaults.set(newValue.rawValue, forKey: DefaultsKey.appearanceMode)
      objectWillChange.send()
      applyAppearance()
    }
  }

  func applyAppearance() {
    NSApp.appearance = appearanceMode.nsAppearance
  }
}

enum MacAppearanceMode: String, CaseIterable, Identifiable {
  case system
  case light
  case dark

  var id: String {
    rawValue
  }

  var title: String {
    switch self {
    case .system:
      "System"
    case .light:
      "Light"
    case .dark:
      "Dark"
    }
  }

  var nsAppearance: NSAppearance? {
    switch self {
    case .system:
      nil
    case .light:
      NSAppearance(named: .aqua)
    case .dark:
      NSAppearance(named: .darkAqua)
    }
  }
}
