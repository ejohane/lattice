import Foundation
@testable import Lattice
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

  @Test("creates unique empty notes without overwriting existing files")
  func createsUniqueEmptyNotes() async throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    try "existing".write(
      to: root.appendingPathComponent("Untitled.md"),
      atomically: true,
      encoding: .utf8
    )

    let folder = MarkdownFolder(rootURL: root)
    let second = try await folder.createNote()
    let third = try await folder.createNote()

    #expect(second.relativePath == "Untitled 2.md")
    #expect(third.relativePath == "Untitled 3.md")
    #expect(try String(contentsOf: second.url, encoding: .utf8).isEmpty)
    #expect(try String(contentsOf: third.url, encoding: .utf8).isEmpty)
    #expect(try String(contentsOf: root.appendingPathComponent("Untitled.md"), encoding: .utf8) == "existing")
  }

  @Test("renames from content without changing bytes and resolves collisions")
  func renamesFromContentWithoutChangingBytes() async throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    try "existing".write(
      to: root.appendingPathComponent("Grocery List.md"),
      atomically: true,
      encoding: .utf8
    )

    let folder = MarkdownFolder(rootURL: root)
    let created = try await folder.createNote()
    let body = "# Grocery List\n\n- Milk 🥛\n"
    try body.write(to: created.url, atomically: true, encoding: .utf8)

    let renamed = try #require(await folder.renameUsingFirstMeaningfulLine(created, body: body))

    #expect(renamed.relativePath == "Grocery List 2.md")
    #expect(!FileManager.default.fileExists(atPath: created.url.path))
    #expect(try String(contentsOf: renamed.url, encoding: .utf8) == body)
    #expect(try String(contentsOf: root.appendingPathComponent("Grocery List.md"), encoding: .utf8) == "existing")
  }
}

@Suite("Markdown filename")
struct MarkdownFilenameTests {
  @Test("derives names from headings, plain text, and leading blank lines", arguments: [
    ("# Grocery List", "Grocery List"),
    ("Meeting with Sarah", "Meeting with Sarah"),
    ("\n\n## Project ideas", "Project ideas")
  ])
  func derivesNames(body: String, expected: String) {
    #expect(MarkdownFilename.suggestedStem(from: body) == expected)
  }

  @Test("sanitizes portable filenames", arguments: [
    ("Trip: Oslo / Bergen", "Trip - Oslo - Bergen"),
    ("README.md", "README"),
    (".private", "private"),
    ("Ideas 🚀", "Ideas 🚀")
  ])
  func sanitizesFilenames(body: String, expected: String) {
    #expect(MarkdownFilename.suggestedStem(from: body) == expected)
  }

  @Test("skips blank and punctuation-only lines")
  func skipsNonMeaningfulLines() {
    #expect(MarkdownFilename.suggestedStem(from: "\n---\n***\nUseful title") == "Useful title")
    #expect(MarkdownFilename.suggestedStem(from: "\n---\n***") == nil)
  }

  @Test("waits until the meaningful line is terminated")
  func detectsTerminatedMeaningfulLine() {
    #expect(!MarkdownFilename.hasTerminatedMeaningfulLine(in: "\n\nTitle"))
    #expect(MarkdownFilename.hasTerminatedMeaningfulLine(in: "\n\nTitle\n"))
  }

  @Test("limits long Unicode names without splitting characters")
  func limitsLongUnicodeNames() {
    let stem = MarkdownFilename.suggestedStem(from: String(repeating: "🚀", count: 100))
    #expect(stem?.count == 60)
    #expect(stem?.utf8.count == 240)
  }

  @Test("reserves room for numeric collision suffixes")
  func reservesRoomForSuffixes() {
    let base = String(repeating: "a", count: 80)
    let numbered = MarkdownFilename.numberedStem(base, number: 12)
    #expect(numbered.count == 80)
    #expect(numbered.hasSuffix(" 12"))
  }
}

@MainActor
@Suite("Mac Markdown app model")
struct MacMarkdownAppModelTests {
  @Test("creates, selects, focuses, and names a new note once")
  func createsAndNamesNewNoteOnce() async throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    try "Existing".write(
      to: root.appendingPathComponent("Existing.md"),
      atomically: true,
      encoding: .utf8
    )
    let model = MacMarkdownAppModel(folderURL: root)
    #expect(await eventually { !model.isLoadingFiles && !model.isLoadingFile })

    model.createNote()
    #expect(await eventually { model.selectedFileID?.lastPathComponent == "Untitled.md" })
    #expect(model.text.isEmpty)
    #expect(model.editorFocusRequest == 1)
    #expect(try String(contentsOf: root.appendingPathComponent("Untitled.md"), encoding: .utf8).isEmpty)

    let body = "# Grocery List\n\nMilk\n"
    model.updateText(body)
    #expect(await eventually { model.selectedFileID?.lastPathComponent == "Grocery List.md" })
    #expect(try String(contentsOf: root.appendingPathComponent("Grocery List.md"), encoding: .utf8) == body)

    model.updateText("# A Different Title\n")
    try await Task.sleep(for: .milliseconds(450))
    #expect(model.selectedFileID?.lastPathComponent == "Grocery List.md")
    #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("A Different Title.md").path))
  }

  @Test("finalizes a single-line note when leaving it")
  func finalizesSingleLineNoteOnSelection() async throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let existingURL = root.appendingPathComponent("Existing.md")
    try "Existing".write(to: existingURL, atomically: true, encoding: .utf8)
    let model = MacMarkdownAppModel(folderURL: root)
    #expect(await eventually { !model.isLoadingFiles && !model.isLoadingFile })

    model.createNote()
    #expect(await eventually { model.selectedFileID?.lastPathComponent == "Untitled.md" })
    model.updateText("Call the dentist")
    try await Task.sleep(for: .milliseconds(400))
    #expect(model.selectedFileID?.lastPathComponent == "Untitled.md")

    model.selectFile(existingURL.standardizedFileURL)
    #expect(await eventually { model.selectedFileID == existingURL.standardizedFileURL && !model.isLoadingFile })
    #expect(try String(contentsOf: root.appendingPathComponent("Call the dentist.md"), encoding: .utf8) == "Call the dentist")
  }

  @Test("creates numbered notes across rapid consecutive actions")
  func createsNumberedNotes() async throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    try "existing".write(
      to: root.appendingPathComponent("Untitled.md"),
      atomically: true,
      encoding: .utf8
    )
    let model = MacMarkdownAppModel(folderURL: root)
    #expect(await eventually { !model.isLoadingFiles && !model.isLoadingFile })

    model.createNote()
    model.createNote()
    #expect(await eventually { model.selectedFileID?.lastPathComponent == "Untitled 3.md" })

    #expect(model.files.map(\.relativePath) == ["Untitled 2.md", "Untitled 3.md", "Untitled.md"])
  }

  @Test("reports creation failure without adding a phantom note")
  func reportsCreationFailure() async throws {
    let root = try temporaryDirectory()
    let model = MacMarkdownAppModel(folderURL: root)
    #expect(await eventually { !model.isLoadingFiles })
    try FileManager.default.removeItem(at: root)

    model.createNote()
    #expect(await eventually { !model.isCreatingNote })

    #expect(model.files.isEmpty)
    #expect(model.selectedFileID == nil)
    #expect(model.errorMessage != nil)
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

private func temporaryDirectory() throws -> URL {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString, isDirectory: true)
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  return root
}

@MainActor
private func eventually(
  timeout: Duration = .seconds(10),
  condition: @MainActor () -> Bool
) async -> Bool {
  let clock = ContinuousClock()
  let deadline = clock.now.advanced(by: timeout)
  while clock.now < deadline {
    if condition() { return true }
    try? await Task.sleep(for: .milliseconds(20))
  }
  return condition()
}
