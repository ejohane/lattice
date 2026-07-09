public struct ReleaseUpdateStatus: Equatable, Sendable {
  public enum Availability: Equatable, Sendable {
    case unavailable
    case idle
    case updateAvailable
  }

  public var availability: Availability
  public var version: String?
  public var title: String?
  public var canCheckForUpdates: Bool
  public var canInstallUpdate: Bool

  public init(
    availability: Availability,
    version: String? = nil,
    title: String? = nil,
    canCheckForUpdates: Bool = false,
    canInstallUpdate: Bool = false
  ) {
    self.availability = availability
    self.version = version
    self.title = title
    self.canCheckForUpdates = canCheckForUpdates
    self.canInstallUpdate = canInstallUpdate
  }

  public static let unavailable = ReleaseUpdateStatus(availability: .unavailable)

  public static func idle(canCheckForUpdates: Bool) -> ReleaseUpdateStatus {
    ReleaseUpdateStatus(availability: .idle, canCheckForUpdates: canCheckForUpdates)
  }

  public static func updateAvailable(
    version: String?,
    title: String?,
    canCheckForUpdates: Bool,
    canInstallUpdate: Bool = false
  ) -> ReleaseUpdateStatus {
    ReleaseUpdateStatus(
      availability: .updateAvailable,
      version: version,
      title: title,
      canCheckForUpdates: canCheckForUpdates,
      canInstallUpdate: canInstallUpdate
    )
  }

  public var shouldShowInChangelog: Bool {
    availability != .unavailable
  }

  public var statusText: String {
    switch availability {
    case .unavailable:
      return "Release builds only"
    case .idle:
      return "No update available"
    case .updateAvailable:
      if let version, !version.isEmpty {
        return canInstallUpdate ? "Version \(version) ready" : "Version \(version) available"
      }
      return canInstallUpdate ? "Update ready" : "Update available"
    }
  }

  public var detailText: String {
    switch availability {
    case .unavailable:
      return "Update checking is available in release builds."
    case .idle:
      return "Check for a newer Lattice build."
    case .updateAvailable:
      if canInstallUpdate, let title, let version, !title.isEmpty, !version.isEmpty, title != version {
        return "\(title) \(version) is ready to install."
      }
      if canInstallUpdate, let version, !version.isEmpty {
        return "Lattice \(version) is ready to install."
      }
      if canInstallUpdate {
        return "A newer Lattice build is ready to install."
      }
      if let title, let version, !title.isEmpty, !version.isEmpty, title != version {
        return "\(title) \(version) is available."
      }
      if let version, !version.isEmpty {
        return "Lattice \(version) is available."
      }
      return "A newer Lattice build is available."
    }
  }

  public var actionTitle: String {
    if availability == .updateAvailable {
      return canInstallUpdate ? "Update Now" : "Show Update"
    }
    return "Check for Updates"
  }

  public var actionSystemImage: String {
    availability == .updateAvailable ? "arrow.down.circle.fill" : "arrow.triangle.2.circlepath"
  }

  public var canPerformAction: Bool {
    switch availability {
    case .unavailable:
      return false
    case .idle:
      return canCheckForUpdates
    case .updateAvailable:
      return canInstallUpdate || canCheckForUpdates
    }
  }
}
