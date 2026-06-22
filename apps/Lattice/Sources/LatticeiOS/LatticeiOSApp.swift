import SwiftUI

@main
struct LatticeiOSApp: App {
  var body: some Scene {
    WindowGroup {
      IOSRootView(model: IOSNoteWorkspaceModel())
    }
  }
}
