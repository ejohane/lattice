import SwiftUI
import Sparkle

@main
struct LatticeMacApp: App {
  @StateObject private var model = MacNoteWorkspaceModel()

  private let updater = SparkleUpdater()

  var body: some Scene {
    WindowGroup {
      MacRootView(model: model)
        .frame(minWidth: 420, minHeight: 520)
    }
    .commands {
      MacAppCommands(model: model, updater: updater)
    }

    Settings {
      MacSettingsView(settings: model.settings)
        .frame(width: 440, height: 180)
    }
  }
}

@MainActor
final class SparkleUpdater {
  private var updaterController: SPUStandardUpdaterController?

  init() {
    guard
      let feedURL = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
      !feedURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
      return
    }

    updaterController = SPUStandardUpdaterController(
      startingUpdater: true,
      updaterDelegate: nil,
      userDriverDelegate: nil
    )
  }

  var canCheckForUpdates: Bool {
    updaterController != nil
  }

  func checkForUpdates() {
    updaterController?.checkForUpdates(nil)
  }
}
