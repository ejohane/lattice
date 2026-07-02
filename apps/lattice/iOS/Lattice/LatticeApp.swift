import LatticeShared
import SwiftUI

@main
struct LatticeIOSApp: App {
  @Environment(\.scenePhase) private var scenePhase
  @State private var model = LatticeAppModel()

  var body: some Scene {
    WindowGroup {
      LatticeRootView(model: model)
        .task {
          model.start()
        }
        .onChange(of: scenePhase) { _, newPhase in
          if newPhase == .active {
            model.appBecameActive()
          }
        }
    }
  }
}
