import Foundation

public struct TaskDestination: Identifiable, Equatable, Sendable {
  public let id: String
  public let title: String

  public init(id: String, title: String) {
    self.id = id
    self.title = title
  }
}

public struct TaskProviderTask: Equatable, Sendable {
  public let externalID: String
  public let title: String
  public let isCompleted: Bool
  public let destinationID: String?

  public init(
    externalID: String,
    title: String,
    isCompleted: Bool,
    destinationID: String?
  ) {
    self.externalID = externalID
    self.title = title
    self.isCompleted = isCompleted
    self.destinationID = destinationID
  }
}

public enum TaskProviderAuthorizationStatus: Equatable, Sendable {
  case notDetermined
  case authorized
  case denied
  case restricted

  public var allowsSync: Bool {
    self == .authorized
  }
}

public enum TaskSyncError: LocalizedError, Equatable, Sendable {
  case providerUnavailable
  case notAuthorized
  case missingDestination
  case missingNotesFolder
  case database(String)

  public var errorDescription: String? {
    switch self {
    case .providerUnavailable:
      return "Task sync provider is unavailable."
    case .notAuthorized:
      return "Lattice does not have Reminders access."
    case .missingDestination:
      return "Choose a Reminders list before enabling task sync."
    case .missingNotesFolder:
      return "Choose a notes folder before enabling task sync."
    case .database(let message):
      return message
    }
  }
}

@MainActor
public protocol TaskSyncProvider: AnyObject {
  var id: String { get }
  var displayName: String { get }

  func authorizationStatus() -> TaskProviderAuthorizationStatus
  func requestAuthorization() async throws -> TaskProviderAuthorizationStatus
  func destinations() async throws -> [TaskDestination]
  func defaultDestination() async throws -> TaskDestination?
  func task(externalID: String) async throws -> TaskProviderTask?
  func upsertTask(
    externalID: String?,
    title: String,
    isCompleted: Bool,
    destinationID: String
  ) async throws -> TaskProviderTask
  func updateCompletion(externalID: String, isCompleted: Bool) async throws -> TaskProviderTask?
}

public struct TaskSyncSettings: Equatable, Sendable {
  public var isEnabled: Bool
  public var providerID: String
  public var destinationID: String?
  public var initialSyncConfirmed: Bool

  public init(
    isEnabled: Bool = false,
    providerID: String = "apple-reminders",
    destinationID: String? = nil,
    initialSyncConfirmed: Bool = false
  ) {
    self.isEnabled = isEnabled
    self.providerID = providerID
    self.destinationID = destinationID
    self.initialSyncConfirmed = initialSyncConfirmed
  }
}

public struct StoredProviderLink: Equatable, Sendable {
  public let taskID: String
  public let providerID: String
  public var externalID: String
  public var destinationID: String
  public var externalTitle: String
  public var externalCompleted: Bool
  public var syncedTitle: String
  public var syncedCompleted: Bool
  public var updatedAt: Date

  public init(
    taskID: String,
    providerID: String,
    externalID: String,
    destinationID: String,
    externalTitle: String,
    externalCompleted: Bool,
    syncedTitle: String,
    syncedCompleted: Bool,
    updatedAt: Date = Date()
  ) {
    self.taskID = taskID
    self.providerID = providerID
    self.externalID = externalID
    self.destinationID = destinationID
    self.externalTitle = externalTitle
    self.externalCompleted = externalCompleted
    self.syncedTitle = syncedTitle
    self.syncedCompleted = syncedCompleted
    self.updatedAt = updatedAt
  }
}

public struct StoredTaskRecord: Equatable, Sendable {
  public let id: String
  public var relativePath: String
  public var lineNumber: Int
  public var title: String
  public var normalizedTitle: String
  public var isCompleted: Bool
  public var fingerprint: String
  public var lastSeenAt: Date
  public var deletedAt: Date?
  public var link: StoredProviderLink?

  public init(
    id: String = UUID().uuidString,
    relativePath: String,
    lineNumber: Int,
    title: String,
    normalizedTitle: String,
    isCompleted: Bool,
    fingerprint: String,
    lastSeenAt: Date = Date(),
    deletedAt: Date? = nil,
    link: StoredProviderLink? = nil
  ) {
    self.id = id
    self.relativePath = relativePath
    self.lineNumber = lineNumber
    self.title = title
    self.normalizedTitle = normalizedTitle
    self.isCompleted = isCompleted
    self.fingerprint = fingerprint
    self.lastSeenAt = lastSeenAt
    self.deletedAt = deletedAt
    self.link = link
  }
}

public struct TaskSyncSummary: Equatable, Sendable {
  public var createdExternalTasks = 0
  public var updatedExternalTasks = 0
  public var completedExternalTasks = 0
  public var updatedMarkdownTasks = 0
  public var unlinkedTasks = 0
  public var scannedTasks = 0
  public var updatedNoteRelativePaths: Set<String> = []

  public init() {}

  public mutating func merge(_ other: TaskSyncSummary) {
    createdExternalTasks += other.createdExternalTasks
    updatedExternalTasks += other.updatedExternalTasks
    completedExternalTasks += other.completedExternalTasks
    updatedMarkdownTasks += other.updatedMarkdownTasks
    unlinkedTasks += other.unlinkedTasks
    scannedTasks += other.scannedTasks
    updatedNoteRelativePaths.formUnion(other.updatedNoteRelativePaths)
  }
}
