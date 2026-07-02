import Foundation
import LatticeCore
import Testing

@Suite("TimelineStore")
struct TimelineStoreTests {
  @Test("parses metadata comments and renders newest-first entries")
  func parsesAndRendersEntries() throws {
    let fixture = Fixture()
    let raw = """
      <!-- lattice-timeline-entry id="new" createdAt="2026-06-30T10:15:00Z" -->
      Newest entry.

      <!-- lattice-timeline-entry id="old" createdAt="2026-06-29T18:40:00Z" -->
      Older entry.

      """

    let document = fixture.store.parse(raw)

    #expect(document.entries.map(\.id) == ["new", "old"])
    #expect(document.entries.map(\.body) == ["Newest entry.", "Older entry."])
    #expect(fixture.store.render(document).contains(#"id="new" createdAt="2026-06-30T10:15:00Z""#))
  }

  @Test("backfills missing metadata and collapses empty paragraphs")
  func backfillsMissingMetadata() throws {
    var ids = ["generated-1", "generated-2"]
    let fixture = Fixture(idProvider: { ids.removeFirst() })
    let raw = """

      First entry.


      Second entry.

      """

    let document = fixture.store.parse(raw)

    #expect(document.entries.map(\.id) == ["generated-1", "generated-2"])
    #expect(document.entries.map(\.createdAt) == [fixture.now, fixture.now])
    #expect(document.entries.map(\.body) == ["First entry.", "Second entry."])
  }

  @Test("saves timeline at folder root")
  func savesTimelineAtFolderRoot() throws {
    let fixture = Fixture()
    defer { fixture.cleanup() }
    try fixture.fileManager.createDirectory(at: fixture.root, withIntermediateDirectories: true)
    let document = TimelineDocument(entries: [
      TimelineEntry(id: "entry", createdAt: fixture.now, body: "Saved entry.")
    ])

    try fixture.store.save(document, notesFolderURL: fixture.root)
    let loaded = try fixture.store.load(notesFolderURL: fixture.root)

    #expect(loaded == document)
    #expect(fixture.fileManager.fileExists(atPath: fixture.root.appendingPathComponent("Timeline.md").path))
    #expect(!fixture.fileManager.fileExists(atPath: fixture.root.appendingPathComponent("notes/Timeline.md").path))
  }
}

private struct Fixture {
  let root: URL
  let now: Date
  let store: TimelineStore
  let fileManager = FileManager.default

  init(idProvider: @escaping () -> String = { "generated" }) {
    root = fileManager.temporaryDirectory
      .appendingPathComponent("lattice-timeline-store-\(UUID().uuidString)", isDirectory: true)
    let now = ISO8601DateFormatter().date(from: "2026-06-30T12:00:00Z") ?? Date(timeIntervalSince1970: 0)
    self.now = now
    store = TimelineStore(fileManager: fileManager, now: { now }, idProvider: idProvider)
  }

  func cleanup() {
    try? fileManager.removeItem(at: root)
  }
}
