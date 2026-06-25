import Foundation
import LatticeCore
import Testing

@Suite("MarkdownTaskScanner")
struct MarkdownTaskScannerTests {
  @Test("discovers titled markdown checkbox tasks")
  func discoversTitledMarkdownCheckboxTasks() {
    let body = """
    # Today
    - [ ] Buy milk
    - [x] Pay rent
    - plain list item
    - [ ] 
    """

    let tasks = MarkdownTaskScanner.tasks(in: body, relativePath: "notes/today.md")

    #expect(tasks.count == 2)
    #expect(tasks[0].title == "Buy milk")
    #expect(tasks[0].isCompleted == false)
    #expect(tasks[0].lineNumber == 2)
    #expect(tasks[0].headingContext == "Today")
    #expect(tasks[1].title == "Pay rent")
    #expect(tasks[1].isCompleted == true)
  }

  @Test("replaces only the checkbox marker")
  func replacesOnlyCheckboxMarker() throws {
    let body = "- [ ] Buy milk\nNotes"
    let task = try #require(MarkdownTaskScanner.tasks(in: body, relativePath: "note.md").first)

    #expect(MarkdownTaskScanner.replacingCompletion(in: body, task: task, isCompleted: true) == "- [x] Buy milk\nNotes")
  }
}

@MainActor
@Suite("TaskSyncStore")
struct TaskSyncStoreTests {
  @Test("stores sync data in durable app support task sync database")
  func storesSyncDataInDurableAppSupportTaskSyncDatabase() throws {
    let fixture = try TaskSyncFixture()
    defer { fixture.cleanup() }

    let databaseURL = fixture.store.databaseURL(for: fixture.root)

    #expect(databaseURL.path.hasPrefix(fixture.appSupportURL.path))
    #expect(databaseURL.path.contains("/TaskSync/"))
    #expect(!databaseURL.path.hasPrefix(fixture.root.path))
  }

  @Test("persists settings and provider links")
  func persistsSettingsAndProviderLinks() throws {
    let fixture = try TaskSyncFixture()
    defer { fixture.cleanup() }

    try fixture.store.saveSettings(
      TaskSyncSettings(isEnabled: true, destinationID: "reminders", initialSyncConfirmed: true),
      notesFolderURL: fixture.root
    )
    var record = StoredTaskRecord(
      id: "task-1",
      relativePath: "notes/2026-06-24/note.md",
      lineNumber: 1,
      title: "Buy milk",
      normalizedTitle: "buy milk",
      isCompleted: false,
      fingerprint: "fingerprint"
    )
    record.link = StoredProviderLink(
      taskID: record.id,
      providerID: "apple-reminders",
      externalID: "external-1",
      destinationID: "reminders",
      externalTitle: "Buy milk",
      externalCompleted: false,
      syncedTitle: "Buy milk",
      syncedCompleted: false
    )
    try fixture.store.upsert(record, notesFolderURL: fixture.root)

    let settings = try fixture.store.settings(notesFolderURL: fixture.root)
    let records = try fixture.store.records(notesFolderURL: fixture.root, providerID: "apple-reminders")

    #expect(settings.isEnabled)
    #expect(settings.destinationID == "reminders")
    #expect(records.count == 1)
    #expect(records[0].link?.externalID == "external-1")
  }
}

@MainActor
@Suite("TaskSyncEngine")
struct TaskSyncEngineTests {
  @Test("creates external tasks from markdown")
  func createsExternalTasksFromMarkdown() async throws {
    let fixture = try TaskSyncFixture()
    defer { fixture.cleanup() }
    try fixture.enableSync()
    try fixture.writeNote(body: "- [ ] Buy milk")

    let summary = try await fixture.engine.syncAll(notesFolderURL: fixture.root)

    #expect(summary.createdExternalTasks == 1)
    #expect(fixture.provider.tasks.values.map(\.title) == ["Buy milk"])
  }

  @Test("pushes lattice title changes outward")
  func pushesLatticeTitleChangesOutward() async throws {
    let fixture = try TaskSyncFixture()
    defer { fixture.cleanup() }
    try fixture.enableSync()
    let noteURL = try fixture.writeNote(body: "- [ ] Buy milk")
    _ = try await fixture.engine.syncAll(notesFolderURL: fixture.root)
    let externalID = try #require(fixture.provider.tasks.values.first?.externalID)

    try "- [ ] Buy oat milk\n".write(to: noteURL, atomically: true, encoding: .utf8)
    let summary = try await fixture.engine.syncAll(notesFolderURL: fixture.root)

    #expect(summary.updatedExternalTasks == 1)
    #expect(fixture.provider.tasks[externalID]?.title == "Buy oat milk")
  }

  @Test("pulls external completion into markdown")
  func pullsExternalCompletionIntoMarkdown() async throws {
    let fixture = try TaskSyncFixture()
    defer { fixture.cleanup() }
    try fixture.enableSync()
    let noteURL = try fixture.writeNote(body: "- [ ] Buy milk")
    _ = try await fixture.engine.syncAll(notesFolderURL: fixture.root)
    let externalID = try #require(fixture.provider.tasks.values.first?.externalID)
    fixture.provider.tasks[externalID] = TaskProviderTask(
      externalID: externalID,
      title: "Buy milk",
      isCompleted: true,
      destinationID: "reminders"
    )

    let summary = try await fixture.engine.syncAll(notesFolderURL: fixture.root)
    let body = try String(contentsOf: noteURL, encoding: .utf8)

    #expect(summary.updatedMarkdownTasks == 1)
    #expect(body == "- [x] Buy milk\n")
  }

  @Test("ignores external title edits")
  func ignoresExternalTitleEdits() async throws {
    let fixture = try TaskSyncFixture()
    defer { fixture.cleanup() }
    try fixture.enableSync()
    let noteURL = try fixture.writeNote(body: "- [ ] Buy milk")
    _ = try await fixture.engine.syncAll(notesFolderURL: fixture.root)
    let externalID = try #require(fixture.provider.tasks.values.first?.externalID)
    fixture.provider.tasks[externalID] = TaskProviderTask(
      externalID: externalID,
      title: "Changed in Reminders",
      isCompleted: false,
      destinationID: "reminders"
    )

    let summary = try await fixture.engine.syncAll(notesFolderURL: fixture.root)
    let body = try String(contentsOf: noteURL, encoding: .utf8)

    #expect(summary.updatedExternalTasks == 0)
    #expect(fixture.provider.tasks[externalID]?.title == "Changed in Reminders")
    #expect(body == "- [ ] Buy milk\n")
  }

  @Test("completes and unlinks externally when markdown task is deleted")
  func completesAndUnlinksExternallyWhenMarkdownTaskIsDeleted() async throws {
    let fixture = try TaskSyncFixture()
    defer { fixture.cleanup() }
    try fixture.enableSync()
    let noteURL = try fixture.writeNote(body: "- [ ] Buy milk")
    _ = try await fixture.engine.syncAll(notesFolderURL: fixture.root)
    let externalID = try #require(fixture.provider.tasks.values.first?.externalID)

    try "No tasks here\n".write(to: noteURL, atomically: true, encoding: .utf8)
    let summary = try await fixture.engine.syncAll(notesFolderURL: fixture.root)
    let records = try fixture.store.records(notesFolderURL: fixture.root, providerID: "apple-reminders")

    #expect(summary.completedExternalTasks == 1)
    #expect(summary.unlinkedTasks == 1)
    #expect(fixture.provider.tasks[externalID]?.isCompleted == true)
    #expect(try #require(records.first).deletedAt != nil)
  }
}

@MainActor
private final class FakeTaskSyncProvider: TaskSyncProvider {
  let id = "apple-reminders"
  let displayName = "Apple Reminders"
  var authorization = TaskProviderAuthorizationStatus.authorized
  var tasks: [String: TaskProviderTask] = [:]
  private var nextID = 1

  func authorizationStatus() -> TaskProviderAuthorizationStatus {
    authorization
  }

  func requestAuthorization() async throws -> TaskProviderAuthorizationStatus {
    authorization
  }

  func destinations() async throws -> [TaskDestination] {
    [TaskDestination(id: "reminders", title: "Reminders")]
  }

  func defaultDestination() async throws -> TaskDestination? {
    TaskDestination(id: "reminders", title: "Reminders")
  }

  func task(externalID: String) async throws -> TaskProviderTask? {
    tasks[externalID]
  }

  func upsertTask(
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

  func updateCompletion(externalID: String, isCompleted: Bool) async throws -> TaskProviderTask? {
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

@MainActor
private struct TaskSyncFixture {
  let root: URL
  let appSupportURL: URL
  let store: TaskSyncStore
  let provider: FakeTaskSyncProvider
  let engine: TaskSyncEngine
  let fileManager = FileManager.default

  init() throws {
    root = FileManager.default.temporaryDirectory
      .appendingPathComponent("lattice-task-sync-\(UUID().uuidString)", isDirectory: true)
    appSupportURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("lattice-task-sync-db-\(UUID().uuidString)", isDirectory: true)
    store = TaskSyncStore(appSupportURL: appSupportURL, fileManager: fileManager)
    provider = FakeTaskSyncProvider()
    engine = TaskSyncEngine(store: store, provider: provider, fileManager: fileManager)
    try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
  }

  func enableSync() throws {
    try store.saveSettings(
      TaskSyncSettings(isEnabled: true, destinationID: "reminders", initialSyncConfirmed: true),
      notesFolderURL: root
    )
  }

  @discardableResult
  func writeNote(body: String) throws -> URL {
    let noteURL = root
      .appendingPathComponent("notes", isDirectory: true)
      .appendingPathComponent("2026-06-24", isDirectory: true)
      .appendingPathComponent("2026-06-24T12-00-00.md")
    try fileManager.createDirectory(at: noteURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    let output = body.hasSuffix("\n") ? body : "\(body)\n"
    try output.write(to: noteURL, atomically: true, encoding: .utf8)
    return noteURL
  }

  func cleanup() {
    try? fileManager.removeItem(at: root)
    try? fileManager.removeItem(at: appSupportURL)
  }
}
