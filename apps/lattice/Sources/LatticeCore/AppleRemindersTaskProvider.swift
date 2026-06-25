import EventKit
import Foundation

@MainActor
public final class AppleRemindersTaskProvider: TaskSyncProvider {
  public let id = "apple-reminders"
  public let displayName = "Apple Reminders"

  private let eventStore: EKEventStore

  public init(eventStore: EKEventStore = EKEventStore()) {
    self.eventStore = eventStore
  }

  public func authorizationStatus() -> TaskProviderAuthorizationStatus {
    switch EKEventStore.authorizationStatus(for: .reminder) {
    case .notDetermined:
      return .notDetermined
    case .restricted:
      return .restricted
    case .denied:
      return .denied
    case .fullAccess, .authorized:
      return .authorized
    case .writeOnly:
      return .denied
    @unknown default:
      return .denied
    }
  }

  public func requestAuthorization() async throws -> TaskProviderAuthorizationStatus {
    switch authorizationStatus() {
    case .authorized:
      return .authorized
    case .denied, .restricted:
      return authorizationStatus()
    case .notDetermined:
      let granted = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
        eventStore.requestFullAccessToReminders { granted, error in
          if let error {
            continuation.resume(throwing: error)
          } else {
            continuation.resume(returning: granted)
          }
        }
      }
      return granted ? .authorized : authorizationStatus()
    }
  }

  public func destinations() async throws -> [TaskDestination] {
    guard authorizationStatus().allowsSync else {
      throw TaskSyncError.notAuthorized
    }
    return eventStore
      .calendars(for: .reminder)
      .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
      .map { TaskDestination(id: $0.calendarIdentifier, title: $0.title) }
  }

  public func defaultDestination() async throws -> TaskDestination? {
    guard authorizationStatus().allowsSync else {
      throw TaskSyncError.notAuthorized
    }
    guard let calendar = eventStore.defaultCalendarForNewReminders() else {
      return try await destinations().first
    }
    return TaskDestination(id: calendar.calendarIdentifier, title: calendar.title)
  }

  public func task(externalID: String) async throws -> TaskProviderTask? {
    guard authorizationStatus().allowsSync else {
      throw TaskSyncError.notAuthorized
    }
    guard let reminder = eventStore.calendarItem(withIdentifier: externalID) as? EKReminder else {
      return nil
    }
    return task(from: reminder)
  }

  public func upsertTask(
    externalID: String?,
    title: String,
    isCompleted: Bool,
    destinationID: String
  ) async throws -> TaskProviderTask {
    guard authorizationStatus().allowsSync else {
      throw TaskSyncError.notAuthorized
    }

    let reminder = externalID
      .flatMap { eventStore.calendarItem(withIdentifier: $0) as? EKReminder }
      ?? EKReminder(eventStore: eventStore)
    reminder.title = title
    reminder.isCompleted = isCompleted
    reminder.calendar = try calendar(for: destinationID)
    try save(reminder)
    return task(from: reminder)
  }

  public func updateCompletion(externalID: String, isCompleted: Bool) async throws -> TaskProviderTask? {
    guard authorizationStatus().allowsSync else {
      throw TaskSyncError.notAuthorized
    }
    guard let reminder = eventStore.calendarItem(withIdentifier: externalID) as? EKReminder else {
      return nil
    }
    reminder.isCompleted = isCompleted
    try save(reminder)
    return task(from: reminder)
  }

  private func calendar(for destinationID: String) throws -> EKCalendar {
    if let calendar = eventStore
      .calendars(for: .reminder)
      .first(where: { $0.calendarIdentifier == destinationID }) {
      return calendar
    }
    if let fallback = eventStore.defaultCalendarForNewReminders() {
      return fallback
    }
    throw TaskSyncError.missingDestination
  }

  private func save(_ reminder: EKReminder) throws {
    try eventStore.save(reminder, commit: true)
  }

  private func task(from reminder: EKReminder) -> TaskProviderTask {
    TaskProviderTask(
      externalID: reminder.calendarItemIdentifier,
      title: reminder.title ?? "",
      isCompleted: reminder.isCompleted,
      destinationID: reminder.calendar?.calendarIdentifier
    )
  }
}
