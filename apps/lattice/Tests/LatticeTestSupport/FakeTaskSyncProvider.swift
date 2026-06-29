import LatticeCore

@MainActor
public final class FakeTaskSyncProvider: TaskSyncProvider {
  public let id = "apple-reminders"
  public let displayName = "Apple Reminders"
  public var authorization = TaskProviderAuthorizationStatus.authorized
  public var tasks: [String: TaskProviderTask] = [:]
  private var nextID = 1

  public init() {}

  public func authorizationStatus() -> TaskProviderAuthorizationStatus {
    authorization
  }

  public func requestAuthorization() async throws -> TaskProviderAuthorizationStatus {
    authorization
  }

  public func destinations() async throws -> [TaskDestination] {
    [TaskDestination(id: "reminders", title: "Reminders")]
  }

  public func defaultDestination() async throws -> TaskDestination? {
    TaskDestination(id: "reminders", title: "Reminders")
  }

  public func task(externalID: String) async throws -> TaskProviderTask? {
    tasks[externalID]
  }

  public func upsertTask(
    externalID: String?,
    title: String,
    isCompleted: Bool,
    destinationID: String
  ) async throws -> TaskProviderTask {
    let id = externalID ?? "external-\(nextID)"
    if externalID == nil {
      nextID += 1
    }
    let task = TaskProviderTask(
      externalID: id,
      title: title,
      isCompleted: isCompleted,
      destinationID: destinationID
    )
    tasks[id] = task
    return task
  }

  public func updateCompletion(externalID: String, isCompleted: Bool) async throws -> TaskProviderTask? {
    guard let task = tasks[externalID] else {
      return nil
    }
    let updated = TaskProviderTask(
      externalID: task.externalID,
      title: task.title,
      isCompleted: isCompleted,
      destinationID: task.destinationID
    )
    tasks[externalID] = updated
    return updated
  }
}
