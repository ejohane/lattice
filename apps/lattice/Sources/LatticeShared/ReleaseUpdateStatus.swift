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

  public init(
    availability: Availability,
    version: String? = nil,
    title: String? = nil,
    canCheckForUpdates: Bool = false
  ) {
    self.availability = availability
    self.version = version
    self.title = title
    self.canCheckForUpdates = canCheckForUpdates
  }

  public static let unavailable = ReleaseUpdateStatus(availability: .unavailable)

  public static func idle(canCheckForUpdates: Bool) -> ReleaseUpdateStatus {
    ReleaseUpdateStatus(availability: .idle, canCheckForUpdates: canCheckForUpdates)
  }

  public static func updateAvailable(
    version: String?,
    title: String?,
    canCheckForUpdates: Bool
  ) -> ReleaseUpdateStatus {
    ReleaseUpdateStatus(
      availability: .updateAvailable,
      version: version,
      title: title,
      canCheckForUpdates: canCheckForUpdates
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
        return "Version \(version) available"
      }
      return "Update available"
    }
  }

  public var detailText: String {
    switch availability {
    case .unavailable:
      return "Update checking is available in release builds."
    case .idle:
      return "Check for a newer Lattice build."
    case .updateAvailable:
      if let title, let version, !title.isEmpty, !version.isEmpty {
        return "\(title) \(version) is ready to install."
      }
      if let version, !version.isEmpty {
        return "Lattice \(version) is ready to install."
      }
      return "A newer Lattice build is ready to install."
    }
  }

  public var actionTitle: String {
    availability == .updateAvailable ? "Update Now" : "Check for Updates"
  }

  public var actionSystemImage: String {
    availability == .updateAvailable ? "arrow.down.circle.fill" : "arrow.triangle.2.circlepath"
  }
}
