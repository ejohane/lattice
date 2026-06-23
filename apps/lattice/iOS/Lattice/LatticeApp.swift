import LatticeShared
import SwiftUI

@main
struct LatticeIOSApp: App {
  @State private var model = LatticeAppModel()

  var body: some Scene {
    WindowGroup {
      LatticeRootView(model: model)
        .task {
          model.start()
        }
    }
  }
}
