import Testing
@testable import LatticeShared

@Suite("ReleaseUpdateStatus")
struct ReleaseUpdateStatusTests {
  @Test("detected update is available but not ready to install")
  func detectedUpdateIsAvailable() {
    let status = ReleaseUpdateStatus.updateAvailable(
      version: "1.36.2",
      title: "1.36.2",
      canCheckForUpdates: true
    )

    #expect(status.statusText == "Version 1.36.2 available")
    #expect(status.detailText == "Lattice 1.36.2 is available.")
    #expect(status.actionTitle == "Show Update")
    #expect(status.canPerformAction)
  }

  @Test("ready update can be installed immediately")
  func readyUpdateCanInstall() {
    let status = ReleaseUpdateStatus.updateAvailable(
      version: "1.36.2",
      title: "1.36.2",
      canCheckForUpdates: false,
      canInstallUpdate: true
    )

    #expect(status.statusText == "Version 1.36.2 ready")
    #expect(status.detailText == "Lattice 1.36.2 is ready to install.")
    #expect(status.actionTitle == "Update Now")
    #expect(status.canPerformAction)
  }
}
