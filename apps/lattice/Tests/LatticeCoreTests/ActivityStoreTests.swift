import Foundation
import LatticeCore
import Testing

@Suite("ActivityStore")
struct ActivityStoreTests {
  @Test("appends and reads activity events for a local day")
  func appendsAndReadsActivityEvents() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }

    let later = ActivityEvent(
      id: "later",
      timestamp: fixture.date(hour: 11),
      kind: .noteEdited,
      noteID: "note-1",
      noteRelativePath: "notes/2026-06-26/Project.md",
      noteTitle: "Project",
      beforeExcerpt: "Before",
      afterExcerpt: "After"
    )
    let earlier = ActivityEvent(
      id: "earlier",
      timestamp: fixture.date(hour: 9),
      kind: .captureCreated,
      text: "Quick thought"
    )

    try fixture.store.append(later, notesFolderURL: fixture.root)
    try fixture.store.append(earlier, notesFolderURL: fixture.root)

    let events = try fixture.store.events(on: fixture.date(hour: 12), notesFolderURL: fixture.root)

    #expect(events.map(\.id) == ["earlier", "later"])
    #expect(events[0].text == "Quick thought")
    #expect(events[1].noteRelativePath == "notes/2026-06-26/Project.md")
    #expect(fixture.fileManager.fileExists(
      atPath: fixture.root.appendingPathComponent(".lattice/activity/2026-06-26.jsonl").path
    ))
  }

  @Test("keeps activity files partitioned by day")
  func partitionsActivityByDay() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }

    try fixture.store.append(
      ActivityEvent(id: "first", timestamp: fixture.date(day: 26), kind: .captureCreated, text: "First"),
      notesFolderURL: fixture.root
    )
    try fixture.store.append(
      ActivityEvent(id: "second", timestamp: fixture.date(day: 27), kind: .captureCreated, text: "Second"),
      notesFolderURL: fixture.root
    )

    #expect(try fixture.store.events(on: fixture.date(day: 26), notesFolderURL: fixture.root).map(\.id) == ["first"])
    #expect(try fixture.store.events(on: fixture.date(day: 27), notesFolderURL: fixture.root).map(\.id) == ["second"])
  }
}

private struct Fixture {
  let root: URL
  let store: ActivityStore
  let fileManager = FileManager.default
  private let calendar: Calendar

  init() throws {
    root = fileManager.temporaryDirectory
      .appendingPathComponent("lattice-activity-store-\(UUID().uuidString)", isDirectory: true)
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
    self.calendar = calendar
    store = ActivityStore(fileManager: fileManager, calendar: calendar)
    try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
  }

  func date(day: Int = 26, hour: Int = 10) -> Date {
    var components = DateComponents()
    components.calendar = calendar
    components.timeZone = calendar.timeZone
    components.year = 2026
    components.month = 6
    components.day = day
    components.hour = hour
    components.minute = 30
    components.second = 0
    return components.date ?? Date(timeIntervalSince1970: 0)
  }

  func cleanup() {
    try? fileManager.removeItem(at: root)
  }
}
