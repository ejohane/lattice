import Foundation
import LatticeCore
import Testing

@Suite("WikiLinks")
struct WikiLinkTests {
  @Test("parses note aliases headings and current note headings")
  func parsesWikiLinks() throws {
    let text = """
    [[Note]]
    [[Note|Label]]
    [[Note#Heading]]
    [[#Local]]
    ```
    [[Ignored]]
    ```
    """

    let links = WikiLinkParser.links(in: text)

    #expect(links.count == 4)
    #expect(links[0].targetStem == "Note")
    #expect(links[1].alias == "Label")
    #expect(links[2].targetHeading == "Heading")
    #expect(links[3].isCurrentNoteHeadingLink)
  }

  @Test("parses and strips lattice metadata")
  func parsesMetadata() {
    let body = """
    ---
    lattice:
      id: note-1
    ---

    # Title
    """

    #expect(MarkdownDocumentMetadata.noteID(in: body) == "note-1")
    #expect(MarkdownDocumentMetadata.strippingFrontMatter(from: body) == "# Title")
  }

  @Test("creates linked notes with human filenames")
  func createsLinkedNotes() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }

    try fixture.library.selectNotesFolder(fixture.root)
    let note = try fixture.library.createLinkedNote(title: "Project Plan", now: fixture.date)

    #expect(note.url.path.hasSuffix("/notes/2026-06-17/Project Plan.md"))
    #expect(try fixture.library.body(for: note) == "# Project Plan\n")
    #expect(MarkdownDocumentMetadata.noteID(in: try fixture.library.rawBody(for: note)) != nil)
  }

  @Test("indexes wiki links headings backlinks and duplicate filename candidates")
  func indexesWikiData() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }

    let first = try fixture.writeNote(
      relativePath: "notes/2026-06-17/Meeting Notes.md",
      body: "---\nlattice:\n  id: meeting-1\n---\n\n# Meeting Notes\n\n## Decisions\n"
    )
    _ = try fixture.writeNote(
      relativePath: "notes/2026-06-18/Meeting Notes.md",
      body: "# Other Meeting\n"
    )
    let source = try fixture.writeNote(
      relativePath: "notes/2026-06-19/Source.md",
      body: "# Source\n\nSee [[Meeting Notes#Decisions]]<!-- lattice:target=meeting-1 -->."
    )

    try fixture.index.rebuild(notesFolderURL: fixture.root)
    let candidates = try fixture.index.wikiNoteCandidates(
      stem: "Meeting Notes",
      notesFolderURL: fixture.root,
      limit: 10
    )
    let firstIndexed = try #require(try fixture.index.indexedNotes(notesFolderURL: fixture.root)
      .first { $0.url.standardizedFileURL == first.standardizedFileURL })
    let backlinks = try fixture.index.wikiBacklinks(
      to: firstIndexed.noteID,
      notesFolderURL: fixture.root,
      limit: 10
    )
    let states = try fixture.index.wikiLinkRenderStates(
      body: try String(contentsOf: source, encoding: .utf8),
      currentNote: SavedNote(url: source),
      notesFolderURL: fixture.root
    )
    let missingHeadingStates = try fixture.index.wikiLinkRenderStates(
      body: "# Source\n\n[[Meeting Notes#Missing]]",
      currentNote: SavedNote(url: source),
      notesFolderURL: fixture.root
    )

    #expect(candidates.count == 2)
    #expect(backlinks.count == 1)
    #expect(states.map(\.status) == [.resolved])
    #expect(missingHeadingStates.map(\.status) == [.broken])
  }

  @Test("parses standard markdown local note links")
  func parsesMarkdownLinks() throws {
    let links = MarkdownLocalLinkParser.links(in: "[Target](../2026-06-17/Target.md#Part)")

    let link = try #require(links.first)
    #expect(link.label == "Target")
    #expect(link.destination == "../2026-06-17/Target.md#Part")
  }

  @Test("parses image links separately from local note links")
  func parsesImageLinksSeparately() throws {
    let text = "Before\n![Screenshot](../../attachments/2026-06-17/screenshot.png)\n[Target](../2026-06-17/Target.md)"

    let image = try #require(MarkdownImageParser.links(in: text).first)
    let noteLinks = MarkdownLocalLinkParser.links(in: text)

    #expect(image.altText == "Screenshot")
    #expect(image.destination == "../../attachments/2026-06-17/screenshot.png")
    #expect((text as NSString).substring(with: image.lineRange).hasPrefix("![Screenshot]"))
    #expect(noteLinks.count == 1)
    #expect(noteLinks[0].label == "Target")
  }

  @Test("parses obsidian style image widths")
  func parsesObsidianStyleImageWidths() throws {
    let image = try #require(MarkdownImageParser.links(in: "![Screenshot|720](image.png)").first)

    #expect(image.altText == "Screenshot")
    #expect(image.destination == "image.png")
    #expect(image.width == 720)
  }

  @Test("rewrites heading links by target identity")
  func rewritesHeadingLinks() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }

    try fixture.library.selectNotesFolder(fixture.root)
    _ = try fixture.writeNote(
      relativePath: "notes/2026-06-17/Target.md",
      body: "---\nlattice:\n  id: target-1\n---\n\n# Target\n\n## Old Heading\n"
    )
    let source = try fixture.writeNote(
      relativePath: "notes/2026-06-18/Source.md",
      body: "# Source\n\n[[Target#Old Heading|alias]]<!-- lattice:target=target-1 -->"
    )

    try fixture.library.rewriteWikiHeadingLinks(
      targetNoteID: "target-1",
      oldHeading: "Old Heading",
      newHeading: "New Heading"
    )

    let body = try String(contentsOf: source, encoding: .utf8)
    #expect(body.contains("[[Target#New Heading|alias]]<!-- lattice:target=target-1 -->"))
  }
}

private struct Fixture {
  let root: URL
  let appSupportURL: URL
  let library: NoteLibrary
  let index: NoteIndex
  let defaults: UserDefaults
  let suiteName: String
  let fileManager = FileManager.default
  let date: Date

  init() throws {
    root = FileManager.default.temporaryDirectory
      .appendingPathComponent("lattice-wiki-links-\(UUID().uuidString)", isDirectory: true)
    appSupportURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("lattice-wiki-links-index-\(UUID().uuidString)", isDirectory: true)
    suiteName = "lattice-wiki-links-\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
      throw FixtureError.defaultsUnavailable
    }
    self.defaults = defaults
    library = NoteLibrary(defaults: defaults, fileManager: fileManager)
    index = NoteIndex(appSupportURL: appSupportURL, fileManager: fileManager)
    var components = DateComponents()
    components.calendar = Calendar(identifier: .gregorian)
    components.timeZone = TimeZone.current
    components.year = 2026
    components.month = 6
    components.day = 17
    components.hour = 14
    components.minute = 32
    components.second = 10
    date = try #require(components.date)
    try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
  }

  @discardableResult
  func writeNote(relativePath: String, body: String) throws -> URL {
    let url = root.appendingPathComponent(relativePath)
    try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try body.write(to: url, atomically: true, encoding: .utf8)
    return url
  }

  func cleanup() {
    try? fileManager.removeItem(at: root)
    try? fileManager.removeItem(at: appSupportURL)
    defaults.removePersistentDomain(forName: suiteName)
  }
}

private enum FixtureError: Error {
  case defaultsUnavailable
}
