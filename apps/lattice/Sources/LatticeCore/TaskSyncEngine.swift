import Foundation

@MainActor
public final class TaskSyncEngine {
  private let store: TaskSyncStore
  private let provider: any TaskSyncProvider
  private let fileManager: FileManager

  public init(
    store: TaskSyncStore = TaskSyncStore(),
    provider: any TaskSyncProvider = AppleRemindersTaskProvider(),
    fileManager: FileManager = .default
  ) {
    self.store = store
    self.provider = provider
    self.fileManager = fileManager
  }

  public func settings(notesFolderURL: URL) throws -> TaskSyncSettings {
    try store.settings(notesFolderURL: notesFolderURL)
  }

  public func saveSettings(_ settings: TaskSyncSettings, notesFolderURL: URL) throws {
    try store.saveSettings(settings, notesFolderURL: notesFolderURL)
  }

  public func authorizationStatus() -> TaskProviderAuthorizationStatus {
    provider.authorizationStatus()
  }

  public func requestAuthorization() async throws -> TaskProviderAuthorizationStatus {
    try await provider.requestAuthorization()
  }

  public func destinations() async throws -> [TaskDestination] {
    try await provider.destinations()
  }

  public func defaultDestination() async throws -> TaskDestination? {
    try await provider.defaultDestination()
  }

  public func existingTaskCount(notesFolderURL: URL) throws -> Int {
    try MarkdownTaskScanner.allTasks(
      in: notesFolderURL,
      fileManager: fileManager
    ).count
  }

  public func syncAll(notesFolderURL: URL) async throws -> TaskSyncSummary {
    let noteURLs = try MarkdownTaskScanner.markdownNoteURLs(
      in: notesFolderURL,
      fileManager: fileManager
    )
    var bodies: [String: String] = [:]
    var tasks: [MarkdownTask] = []
    for noteURL in noteURLs {
      guard let relativePath = MarkdownTaskScanner.relativePath(for: noteURL, in: notesFolderURL) else {
        continue
      }
      let body = try String(contentsOf: noteURL, encoding: .utf8)
      bodies[relativePath] = body
      tasks.append(contentsOf: MarkdownTaskScanner.tasks(in: body, relativePath: relativePath))
    }

    return try await reconcile(
      tasks: tasks,
      bodies: bodies,
      scopedRelativePaths: Set(bodies.keys),
      notesFolderURL: notesFolderURL
    )
  }

  public func sync(
    note: SavedNote,
    body: String,
    notesFolderURL: URL
  ) async throws -> TaskSyncSummary {
    guard let relativePath = MarkdownTaskScanner.relativePath(for: note.url, in: notesFolderURL) else {
      throw NoteLibraryError.invalidNotesFolder(note.url.path)
    }
    return try await reconcile(
      tasks: MarkdownTaskScanner.tasks(in: body, relativePath: relativePath),
      bodies: [relativePath: body],
      scopedRelativePaths: [relativePath],
      notesFolderURL: notesFolderURL
    )
  }

  private func reconcile(
    tasks: [MarkdownTask],
    bodies: [String: String],
    scopedRelativePaths: Set<String>,
    notesFolderURL: URL
  ) async throws -> TaskSyncSummary {
    var settings = try store.settings(notesFolderURL: notesFolderURL)
    guard settings.isEnabled else {
      return TaskSyncSummary()
    }
    guard settings.providerID == provider.id else {
      throw TaskSyncError.providerUnavailable
    }
    guard provider.authorizationStatus().allowsSync else {
      throw TaskSyncError.notAuthorized
    }

    let destinationID = try await resolvedDestinationID(settings: &settings, notesFolderURL: notesFolderURL)
    var records = try store.records(notesFolderURL: notesFolderURL, providerID: provider.id)
      .filter { $0.deletedAt == nil }
    var summary = TaskSyncSummary()
    summary.scannedTasks = tasks.count

    var matchedRecordIDs = Set<String>()
    var completionUpdates: [String: [MarkdownTask: Bool]] = [:]

    for task in tasks {
      var record = matchRecord(
        for: task,
        records: records,
        matchedRecordIDs: matchedRecordIDs
      ) ?? StoredTaskRecord(
        relativePath: task.relativePath,
        lineNumber: task.lineNumber,
        title: task.title,
        normalizedTitle: task.normalizedTitle,
        isCompleted: task.isCompleted,
        fingerprint: task.fingerprint
      )

      matchedRecordIDs.insert(record.id)
      var link = record.link
      var effectiveCompleted = task.isCompleted
      var shouldPushTitle = false
      var shouldPushCompletion = false

      if let existingLink = link,
         let external = try await provider.task(externalID: existingLink.externalID) {
        let externalCompletionChanged = external.isCompleted != existingLink.syncedCompleted
        let markdownCompletionChanged = task.isCompleted != existingLink.syncedCompleted

        if externalCompletionChanged && !markdownCompletionChanged {
          effectiveCompleted = external.isCompleted
          completionUpdates[task.relativePath, default: [:]][task] = external.isCompleted
          summary.updatedMarkdownTasks += 1
        } else if markdownCompletionChanged {
          shouldPushCompletion = true
        }

        shouldPushTitle = task.title != existingLink.syncedTitle

        if shouldPushTitle || shouldPushCompletion {
          let updated = try await provider.upsertTask(
            externalID: existingLink.externalID,
            title: task.title,
            isCompleted: effectiveCompleted,
            destinationID: existingLink.destinationID
          )
          link = providerLink(
            from: updated,
            taskID: record.id,
            destinationID: existingLink.destinationID,
            task: task
          )
          summary.updatedExternalTasks += 1
        } else {
          link = StoredProviderLink(
            taskID: record.id,
            providerID: provider.id,
            externalID: existingLink.externalID,
            destinationID: existingLink.destinationID,
            externalTitle: external.title,
            externalCompleted: external.isCompleted,
            syncedTitle: task.title,
            syncedCompleted: effectiveCompleted
          )
        }
      } else {
        let created = try await provider.upsertTask(
          externalID: link?.externalID,
          title: task.title,
          isCompleted: effectiveCompleted,
          destinationID: link?.destinationID ?? destinationID
        )
        link = providerLink(
          from: created,
          taskID: record.id,
          destinationID: link?.destinationID ?? destinationID,
          task: task
        )
        summary.createdExternalTasks += 1
      }

      record.relativePath = task.relativePath
      record.lineNumber = task.lineNumber
      record.title = task.title
      record.normalizedTitle = task.normalizedTitle
      record.isCompleted = effectiveCompleted
      record.fingerprint = task.fingerprint
      record.lastSeenAt = Date()
      record.deletedAt = nil
      record.link = link
      try store.upsert(record, notesFolderURL: notesFolderURL)

      if let index = records.firstIndex(where: { $0.id == record.id }) {
        records[index] = record
      } else {
        records.append(record)
      }
    }

    try applyCompletionUpdates(
      completionUpdates,
      bodies: bodies,
      notesFolderURL: notesFolderURL,
      summary: &summary
    )

    for record in records where scopedRelativePaths.contains(record.relativePath) && !matchedRecordIDs.contains(record.id) {
      if let link = record.link, !link.syncedCompleted {
        _ = try await provider.updateCompletion(externalID: link.externalID, isCompleted: true)
        summary.completedExternalTasks += 1
      }
      try store.markDeleted(taskID: record.id, notesFolderURL: notesFolderURL)
      summary.unlinkedTasks += 1
    }

    return summary
  }

  private func resolvedDestinationID(
    settings: inout TaskSyncSettings,
    notesFolderURL: URL
  ) async throws -> String {
    if let destinationID = settings.destinationID, !destinationID.isEmpty {
      return destinationID
    }
    guard let destination = try await provider.defaultDestination() else {
      throw TaskSyncError.missingDestination
    }
    settings.destinationID = destination.id
    try store.saveSettings(settings, notesFolderURL: notesFolderURL)
    return destination.id
  }

  private func matchRecord(
    for task: MarkdownTask,
    records: [StoredTaskRecord],
    matchedRecordIDs: Set<String>
  ) -> StoredTaskRecord? {
    if let exactPosition = records.first(where: { record in
      !matchedRecordIDs.contains(record.id)
        && record.relativePath == task.relativePath
        && record.lineNumber == task.lineNumber
    }) {
      return exactPosition
    }

    let titleMatches = records.filter { record in
      !matchedRecordIDs.contains(record.id)
        && record.relativePath == task.relativePath
        && record.normalizedTitle == task.normalizedTitle
    }
    if titleMatches.count == 1 {
      return titleMatches[0]
    }

    let fingerprintMatches = records.filter { record in
      !matchedRecordIDs.contains(record.id)
        && record.fingerprint == task.fingerprint
    }
    return fingerprintMatches.count == 1 ? fingerprintMatches[0] : nil
  }

  private func providerLink(
    from providerTask: TaskProviderTask,
    taskID: String,
    destinationID: String,
    task: MarkdownTask
  ) -> StoredProviderLink {
    StoredProviderLink(
      taskID: taskID,
      providerID: provider.id,
      externalID: providerTask.externalID,
      destinationID: providerTask.destinationID ?? destinationID,
      externalTitle: providerTask.title,
      externalCompleted: providerTask.isCompleted,
      syncedTitle: task.title,
      syncedCompleted: providerTask.isCompleted
    )
  }

  private func applyCompletionUpdates(
    _ updates: [String: [MarkdownTask: Bool]],
    bodies: [String: String],
    notesFolderURL: URL,
    summary: inout TaskSyncSummary
  ) throws {
    for (relativePath, taskUpdates) in updates {
      guard var body = bodies[relativePath] else {
        continue
      }
      let sortedUpdates = taskUpdates.sorted { lhs, rhs in
        lhs.key.checkboxRange.location > rhs.key.checkboxRange.location
      }
      for (task, isCompleted) in sortedUpdates {
        body = MarkdownTaskScanner.replacingCompletion(in: body, task: task, isCompleted: isCompleted)
      }
      let noteURL = notesFolderURL.appendingPathComponent(relativePath)
      let output = body.hasSuffix("\n") ? body : "\(body)\n"
      try output.write(to: noteURL, atomically: true, encoding: .utf8)
      summary.updatedNoteRelativePaths.insert(relativePath)
    }
  }
}
