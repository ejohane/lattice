import Foundation
@testable import LatticeMacCore
import Testing

@Suite("Markdown folder")
struct MarkdownFolderTests {
  @Test("discovers visible Markdown files recursively in path order")
  func discoversMarkdownFiles() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let nested = root.appendingPathComponent("Projects", isDirectory: true)
    let hidden = root.appendingPathComponent(".private", isDirectory: true)
    try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: hidden, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    try "# Zebra".write(
      to: root.appendingPathComponent("Zebra.md"),
      atomically: true,
      encoding: .utf8
    )
    try "# Alpha".write(
      to: nested.appendingPathComponent("Alpha.MD"),
      atomically: true,
      encoding: .utf8
    )
    try "ignore".write(
      to: root.appendingPathComponent("notes.txt"),
      atomically: true,
      encoding: .utf8
    )
    try "hidden".write(
      to: hidden.appendingPathComponent("Hidden.md"),
      atomically: true,
      encoding: .utf8
    )

    let folder = MarkdownFolder(rootURL: root)
    let files = try await folder.files()

    #expect(files.map(\.relativePath) == ["Projects/Alpha.MD", "Zebra.md"])
  }

  @Test("reads and writes a file without Lattice metadata verbatim")
  func readsAndWritesWithoutMetadataVerbatim() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let url = root.appendingPathComponent("Note.md")
    let original = "# Heading\n\n- [ ] literal **Markdown**\n"
    try original.write(to: url, atomically: true, encoding: .utf8)

    let folder = MarkdownFolder(rootURL: root)
    let file = try #require(await folder.files().first)
    var document = try await folder.read(file)
    #expect(document.hiddenPrefix.isEmpty)
    #expect(document.body == original)

    let replacement = "Raw <text> & symbols\n"
    document.body = replacement
    try await folder.write(document, to: file)
    #expect(try String(contentsOf: url, encoding: .utf8) == replacement)
  }
}

@Suite("Markdown document")
struct MarkdownDocumentTests {
  @Test("hides Lattice frontmatter and preserves it unchanged")
  func hidesAndPreservesLatticeFrontMatter() {
    let prefix = "---\nlattice:\n  id: note-1\n  created_at: 2026-07-25T12:00:00Z\n---\n\n"
    var document = MarkdownDocument(fileContents: prefix + "# Original\n")

    #expect(document.hiddenPrefix == prefix)
    #expect(document.body == "# Original\n")

    document.body = "# Edited\n\nRaw **Markdown**\n"
    #expect(document.fileContents == prefix + "# Edited\n\nRaw **Markdown**\n")
  }

  @Test("keeps user frontmatter visible")
  func keepsUserFrontMatterVisible() {
    let contents = "---\ntitle: Personal metadata\n---\n\n# Note\n"
    let document = MarkdownDocument(fileContents: contents)

    #expect(document.hiddenPrefix.isEmpty)
    #expect(document.body == contents)
  }

  @Test("keeps malformed Lattice frontmatter visible")
  func keepsMalformedLatticeFrontMatterVisible() {
    let contents = "---\nlattice:\n  id: unfinished\n# Still source\n"
    let document = MarkdownDocument(fileContents: contents)

    #expect(document.hiddenPrefix.isEmpty)
    #expect(document.body == contents)
  }

  @Test("preserves CRLF frontmatter")
  func preservesCRLFFrontMatter() {
    let prefix = "---\r\nlattice:\r\n  id: note-1\r\n---\r\n\r\n"
    let document = MarkdownDocument(fileContents: prefix + "Body\r\n")

    #expect(document.hiddenPrefix == prefix)
    #expect(document.body == "Body\r\n")
    #expect(document.fileContents == prefix + "Body\r\n")
  }
}

@Suite("Mac Markdown spacing")
struct MacMarkdownSpacingTests {
  @Test("horizontal editor padding grows and clamps with pane width")
  func horizontalPadding() {
    #expect(MacMarkdownSpacing.editorHorizontalPadding(for: 280) == 32)
    #expect(MacMarkdownSpacing.editorHorizontalPadding(for: 560) == 56)
    #expect(MacMarkdownSpacing.editorHorizontalPadding(for: 1_400) == 72)
  }

  @Test("top editor padding grows and clamps with pane height")
  func topPadding() {
    #expect(MacMarkdownSpacing.editorTopPadding(for: 300) == 32)
    #expect(MacMarkdownSpacing.editorTopPadding(for: 600) == 48)
    #expect(MacMarkdownSpacing.editorTopPadding(for: 1_000) == 64)
  }
}
