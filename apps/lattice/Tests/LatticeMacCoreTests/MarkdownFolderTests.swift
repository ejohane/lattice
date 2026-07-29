import AppKit
import Foundation
import KeyboardShortcuts
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

  @Test("creates and reuses one local-date daily note without overwriting it")
  func createsAndReusesDailyNote() async throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "America/Chicago"))
    let date = try #require(calendar.date(from: DateComponents(
      year: 2026,
      month: 7,
      day: 28,
      hour: 9
    )))

    let folder = MarkdownFolder(rootURL: root)
    let first = try await folder.ensureDailyNote(now: date, calendar: calendar)

    #expect(first.relativePath == "2026-07-28.md")
    #expect(try String(contentsOf: first.url, encoding: .utf8) == "# Tuesday, July 28, 2026\n\n")

    let updatedBody = "# Tuesday, July 28, 2026\n\nJournal entry\n"
    try updatedBody.write(to: first.url, atomically: true, encoding: .utf8)
    let second = try await folder.ensureDailyNote(
      now: date.addingTimeInterval(60),
      calendar: calendar
    )

    #expect(second == first)
    #expect(try String(contentsOf: second.url, encoding: .utf8) == updatedBody)
    #expect(try await folder.files().filter { $0.relativePath == "2026-07-28.md" }.count == 1)
  }

  @Test("separates appended Jots with a Markdown horizontal rule")
  func appendsToDailyNote() async throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "America/Chicago"))
    let date = try #require(calendar.date(from: DateComponents(
      year: 2026,
      month: 7,
      day: 28,
      hour: 21
    )))
    let folder = MarkdownFolder(rootURL: root)

    let first = try await folder.appendToDailyNote(
      "A quick **thought**.",
      now: date,
      calendar: calendar
    )
    #expect(first.file.relativePath == "2026-07-28.md")
    #expect(first.document.body == "# Tuesday, July 28, 2026\n\nA quick **thought**.")

    let second = try await folder.appendToDailyNote(
      "- [ ] Follow up\n  - Keep the indentation",
      now: date.addingTimeInterval(60),
      calendar: calendar
    )
    #expect(second.file == first.file)
    #expect(second.document.body == """
      # Tuesday, July 28, 2026

      A quick **thought**.

      ---

      - [ ] Follow up
        - Keep the indentation
      """)
  }

  @Test("preserves hidden frontmatter while appending to today's note")
  func appendsToDailyNotePreservingFrontMatter() async throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "America/Chicago"))
    let date = try #require(calendar.date(from: DateComponents(
      year: 2026,
      month: 7,
      day: 28,
      hour: 21
    )))
    let prefix = "---\nlattice:\n  id: today\n---\n\n"
    let originalBody = "# Tuesday, July 28, 2026\n\nExisting entry"
    let url = root.appendingPathComponent("2026-07-28.md")
    try (prefix + originalBody).write(to: url, atomically: true, encoding: .utf8)
    let folder = MarkdownFolder(rootURL: root)

    let result = try await folder.appendToDailyNote(
      "New entry",
      now: date,
      calendar: calendar
    )

    #expect(result.document.hiddenPrefix == prefix)
    #expect(try String(contentsOf: url, encoding: .utf8) == prefix + originalBody + "\n\n---\n\nNew entry")
  }

  @Test("serializes consecutive Today appends without losing a capture")
  func serializesDailyNoteAppends() async throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "America/Chicago"))
    let date = try #require(calendar.date(from: DateComponents(
      year: 2026,
      month: 7,
      day: 28,
      hour: 21
    )))
    let folder = MarkdownFolder(rootURL: root)
    let firstCalendar = calendar
    let secondCalendar = calendar

    async let first = folder.appendToDailyNote(
      "First capture",
      now: date,
      calendar: firstCalendar
    )
    async let second = folder.appendToDailyNote(
      "Second capture",
      now: date,
      calendar: secondCalendar
    )
    _ = try await (first, second)

    let contents = try String(
      contentsOf: root.appendingPathComponent("2026-07-28.md"),
      encoding: .utf8
    )
    #expect(contents.components(separatedBy: "First capture").count == 2)
    #expect(contents.components(separatedBy: "Second capture").count == 2)
    #expect(contents.components(separatedBy: "\n\n---\n\n").count == 2)
  }

  @Test("creates and resolves wiki notes by case-insensitive filename")
  func createsAndResolvesWikiNotes() async throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let folder = MarkdownFolder(rootURL: root)

    let created = try #require(await folder.ensureWikiNote(named: "my note"))
    #expect(created.relativePath == "my note.md")
    #expect(try String(contentsOf: created.url, encoding: .utf8) == "# my note\n\n")

    let existing = try #require(await folder.ensureWikiNote(named: "MY NOTE.md"))
    #expect(existing == created)
    #expect(try await folder.files().filter {
      $0.url.deletingPathExtension().lastPathComponent.lowercased() == "my note"
    }.count == 1)

    #expect(try await folder.ensureWikiNote(named: "   ") == nil)
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

@Suite("Markdown sidebar preview")
struct MarkdownSidebarPreviewTests {
  @Test("renders note titles and excerpts instead of Markdown filenames")
  func rendersTitleAndExcerpt() {
    let file = MarkdownFile(
      url: URL(fileURLWithPath: "/tmp/Friday notes.md"),
      relativePath: "notes/Friday notes.md"
    )
    let preview = MarkdownSidebarPreview(
      file: file,
      body: "# **Friday notes**\n\nKeep the writing surface quiet.\n- [ ] Ship it"
    )

    #expect(preview.title == "Friday notes")
    #expect(preview.excerpt == "Keep the writing surface quiet. Ship it")
  }

  @Test("falls back to the filename for an empty note")
  func fallsBackToFilename() {
    let file = MarkdownFile(
      url: URL(fileURLWithPath: "/tmp/Untitled.md"),
      relativePath: "Untitled.md"
    )

    #expect(MarkdownSidebarPreview(file: file, body: "").title == "Untitled")
  }

  @Test("formats recent modification dates like Bear")
  func formatsRecentDates() {
    let now = Date(timeIntervalSince1970: 10_000)
    #expect(MacMarkdownSidebarDateLabel.text(
      for: now.addingTimeInterval(-30),
      relativeTo: now
    ) == "Just now")
    #expect(MacMarkdownSidebarDateLabel.text(
      for: now.addingTimeInterval(-15 * 60),
      relativeTo: now
    ) == "15 min ago")
    #expect(MacMarkdownSidebarDateLabel.text(
      for: now.addingTimeInterval(-2 * 3_600),
      relativeTo: now
    ) == "2 hours ago")
  }
}

@MainActor
@Suite("Mac Markdown app model")
struct MacMarkdownAppModelTests {
  @Test("applies incremental native editor changes to the Markdown source")
  func appliesIncrementalEditorChanges() async throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let url = root.appendingPathComponent("Existing.md")
    try "Hello world".write(to: url, atomically: true, encoding: .utf8)
    let model = MacMarkdownAppModel(folderURL: root)
    #expect(await eventually { !model.isLoadingFiles && !model.isLoadingFile })

    model.applyEditorEdit(range: NSRange(location: 6, length: 5), replacement: "**world**")
    #expect(model.text == "Hello **world**")
    try await Task.sleep(for: .milliseconds(400))
    #expect(try String(contentsOf: url, encoding: .utf8) == "Hello **world**")
  }

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

    model.navigateBack()
    #expect(await eventually {
      model.selectedFileID?.lastPathComponent == "Call the dentist.md" && !model.isLoadingFile
    })
    #expect(model.text == "Call the dentist")
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

    #expect(Set(model.files.map(\.relativePath)) == ["Untitled 2.md", "Untitled 3.md", "Untitled.md"])
  }

  @Test("navigates backward and forward through note selection history")
  func navigatesSelectionHistory() async throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let alphaURL = root.appendingPathComponent("Alpha.md")
    let betaURL = root.appendingPathComponent("Beta.md")
    let gammaURL = root.appendingPathComponent("Gamma.md")
    try "Alpha".write(to: alphaURL, atomically: true, encoding: .utf8)
    try "Beta".write(to: betaURL, atomically: true, encoding: .utf8)
    try "Gamma".write(to: gammaURL, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes(
      [.modificationDate: Date(timeIntervalSince1970: 3_000)],
      ofItemAtPath: alphaURL.path
    )
    try FileManager.default.setAttributes(
      [.modificationDate: Date(timeIntervalSince1970: 2_000)],
      ofItemAtPath: betaURL.path
    )
    try FileManager.default.setAttributes(
      [.modificationDate: Date(timeIntervalSince1970: 1_000)],
      ofItemAtPath: gammaURL.path
    )
    let model = MacMarkdownAppModel(folderURL: root)
    #expect(await eventually {
      model.selectedFileID == alphaURL.standardizedFileURL && !model.isLoadingFile
    })
    #expect(!model.canNavigateBack)
    #expect(!model.canNavigateForward)

    model.selectFile(betaURL.standardizedFileURL)
    #expect(await eventually {
      model.selectedFileID == betaURL.standardizedFileURL && !model.isLoadingFile
    })
    model.selectFile(gammaURL.standardizedFileURL)
    #expect(await eventually {
      model.selectedFileID == gammaURL.standardizedFileURL && !model.isLoadingFile
    })

    model.navigateBack()
    #expect(await eventually {
      model.selectedFileID == betaURL.standardizedFileURL && !model.isLoadingFile
    })
    #expect(model.canNavigateBack)
    #expect(model.canNavigateForward)

    model.navigateBack()
    #expect(await eventually {
      model.selectedFileID == alphaURL.standardizedFileURL && !model.isLoadingFile
    })
    #expect(!model.canNavigateBack)
    #expect(model.canNavigateForward)

    model.navigateForward()
    #expect(await eventually {
      model.selectedFileID == betaURL.standardizedFileURL && !model.isLoadingFile
    })
    model.selectFile(gammaURL.standardizedFileURL)
    #expect(await eventually {
      model.selectedFileID == gammaURL.standardizedFileURL && !model.isLoadingFile
    })
    #expect(model.canNavigateBack)
    #expect(!model.canNavigateForward)
  }

  @Test("orders sidebar notes by most recent modification")
  func ordersSidebarByRecency() async throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let olderURL = root.appendingPathComponent("Alpha.md")
    let newerURL = root.appendingPathComponent("Beta.md")
    try "# Alpha".write(to: olderURL, atomically: true, encoding: .utf8)
    try "# Beta".write(to: newerURL, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes(
      [.modificationDate: Date(timeIntervalSince1970: 1_000)],
      ofItemAtPath: olderURL.path
    )
    try FileManager.default.setAttributes(
      [.modificationDate: Date(timeIntervalSince1970: 2_000)],
      ofItemAtPath: newerURL.path
    )

    let model = MacMarkdownAppModel(folderURL: root)
    #expect(await eventually { !model.isLoadingFiles && !model.isLoadingFile })

    #expect(model.files.map(\.relativePath) == ["Beta.md", "Alpha.md"])
    #expect(model.selectedFileID == newerURL.standardizedFileURL)
  }

  @Test("opens and reuses today's canonical note from the app model")
  func opensAndReusesTodayNote() async throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let existingURL = root.appendingPathComponent("Existing.md")
    try "Existing".write(to: existingURL, atomically: true, encoding: .utf8)
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "America/Chicago"))
    let date = try #require(calendar.date(from: DateComponents(
      year: 2026,
      month: 7,
      day: 28,
      hour: 9
    )))
    let model = MacMarkdownAppModel(folderURL: root)
    #expect(await eventually { !model.isLoadingFiles && !model.isLoadingFile })

    model.openTodayNote(now: date, calendar: calendar)
    #expect(await eventually { model.selectedFileID?.lastPathComponent == "2026-07-28.md" })
    #expect(model.text == "# Tuesday, July 28, 2026\n\n")
    #expect(model.editorFocusRequest == 1)

    let updatedBody = "# Tuesday, July 28, 2026\n\nJournal entry\n"
    model.updateText(updatedBody)
    try await Task.sleep(for: .milliseconds(400))
    model.selectFile(existingURL.standardizedFileURL)
    #expect(await eventually {
      model.selectedFileID == existingURL.standardizedFileURL && !model.isLoadingFile
    })

    model.openTodayNote(now: date.addingTimeInterval(60), calendar: calendar)
    #expect(await eventually {
      model.selectedFileID?.lastPathComponent == "2026-07-28.md" && !model.isCreatingNote
    })
    #expect(model.text == updatedBody)
    #expect(model.editorFocusRequest == 2)
    #expect(model.files.filter { $0.relativePath == "2026-07-28.md" }.count == 1)
    #expect(!FileManager.default.fileExists(
      atPath: root.appendingPathComponent("Tuesday, July 28, 2026.md").path
    ))
  }

  @Test("ensures today's note without navigating away from the source note")
  func ensuresTodayNoteWithoutNavigating() async throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let sourceURL = root.appendingPathComponent("Source.md")
    let sourceBody = "# Source\n\nDecision [[2026-07-28]]\n"
    try sourceBody.write(to: sourceURL, atomically: true, encoding: .utf8)
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "America/Chicago"))
    let date = try #require(calendar.date(from: DateComponents(
      year: 2026,
      month: 7,
      day: 28,
      hour: 9
    )))
    let model = MacMarkdownAppModel(folderURL: root)
    #expect(await eventually {
      model.selectedFileID == sourceURL.standardizedFileURL && !model.isLoadingFile
    })

    model.ensureTodayNote(now: date, calendar: calendar)

    #expect(await eventually {
      model.files.contains { $0.relativePath == "2026-07-28.md" }
    })
    #expect(model.selectedFileID == sourceURL.standardizedFileURL)
    #expect(model.text == sourceBody)
    #expect(try String(
      contentsOf: root.appendingPathComponent("2026-07-28.md"),
      encoding: .utf8
    ) == "# Tuesday, July 28, 2026\n\n")
  }

  @Test("opens or creates wiki links while preserving the source note")
  func opensOrCreatesWikiLinks() async throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let sourceURL = root.appendingPathComponent("Source.md")
    try "# Source\n".write(to: sourceURL, atomically: true, encoding: .utf8)
    let model = MacMarkdownAppModel(folderURL: root)
    #expect(await eventually {
      model.selectedFileID == sourceURL.standardizedFileURL && !model.isLoadingFile
    })

    let sourceBody = "# Source\n\nOpen [[my note]]\n"
    model.updateText(sourceBody)
    model.openWikiLink("my note")

    #expect(await eventually {
      model.selectedFileID?.lastPathComponent == "my note.md" && !model.isCreatingNote
    })
    #expect(model.text == "# my note\n\n")
    #expect(model.editorFocusRequest == 1)
    #expect(try String(contentsOf: sourceURL, encoding: .utf8) == sourceBody)

    #expect(model.canNavigateBack)
    model.navigateBack()
    #expect(await eventually {
      model.selectedFileID == sourceURL.standardizedFileURL && !model.isLoadingFile
    })
    #expect(model.canNavigateForward)

    model.openWikiLink("MY NOTE.md")
    #expect(await eventually {
      model.selectedFileID?.lastPathComponent == "my note.md" && !model.isCreatingNote
    })
    #expect(model.files.filter {
      $0.url.deletingPathExtension().lastPathComponent.lowercased() == "my note"
    }.count == 1)
    #expect(model.editorFocusRequest == 2)
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

  @Test("Jot appends without navigating away and clears only after success")
  func submitsJotWithoutNavigating() async throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let sourceURL = root.appendingPathComponent("Source.md")
    try "# Source\n".write(to: sourceURL, atomically: true, encoding: .utf8)
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "America/Chicago"))
    let date = try #require(calendar.date(from: DateComponents(
      year: 2026,
      month: 7,
      day: 28,
      hour: 21
    )))
    let model = MacMarkdownAppModel(folderURL: root)
    #expect(await eventually {
      model.selectedFileID == sourceURL.standardizedFileURL && !model.isLoadingFile
    })

    model.jotDraft = "Remember [[Project Plan]]"
    #expect(await model.submitJot(now: date, calendar: calendar))

    #expect(model.selectedFileID == sourceURL.standardizedFileURL)
    #expect(model.text == "# Source\n")
    #expect(model.jotDraft.isEmpty)
    #expect(model.jotErrorMessage == nil)
    #expect(model.files.contains { $0.relativePath == "2026-07-28.md" })
    #expect(try String(
      contentsOf: root.appendingPathComponent("2026-07-28.md"),
      encoding: .utf8
    ) == "# Tuesday, July 28, 2026\n\nRemember [[Project Plan]]")
  }

  @Test("applies incremental Jot edits against the latest draft")
  func appliesIncrementalJotEdits() async throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let model = MacMarkdownAppModel(folderURL: root)
    #expect(await eventually { !model.isLoadingFiles })
    model.jotDraft = "Fast typng"

    model.applyJotEdit(range: NSRange(location: 8, length: 0), replacement: "i")
    model.applyJotEdit(range: NSRange(location: 11, length: 0), replacement: " **works**")

    #expect(model.jotDraft == "Fast typing **works**")
  }

  @Test("Jot preserves unsaved edits when Today is open")
  func submitsJotIntoOpenTodayNote() async throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "America/Chicago"))
    let date = try #require(calendar.date(from: DateComponents(
      year: 2026,
      month: 7,
      day: 28,
      hour: 21
    )))
    let model = MacMarkdownAppModel(folderURL: root)
    #expect(await eventually { !model.isLoadingFiles })
    model.openTodayNote(now: date, calendar: calendar)
    #expect(await eventually {
      model.selectedFileID?.lastPathComponent == "2026-07-28.md" && !model.isCreatingNote
    })

    let unsavedBody = "# Tuesday, July 28, 2026\n\nStill being edited"
    model.updateText(unsavedBody)
    model.jotDraft = "Captured from Jot"
    let refreshRequest = model.editorExternalRefreshRequest

    #expect(await model.submitJot(now: date, calendar: calendar))

    let expected = unsavedBody + "\n\n---\n\nCaptured from Jot"
    #expect(model.text == expected)
    #expect(model.editorExternalRefreshRequest == refreshRequest + 1)
    #expect(try String(
      contentsOf: root.appendingPathComponent("2026-07-28.md"),
      encoding: .utf8
    ) == expected)
  }

  @Test("Jot retains its draft after a write failure")
  func retainsJotAfterWriteFailure() async throws {
    let root = try temporaryDirectory()
    let model = MacMarkdownAppModel(folderURL: root)
    #expect(await eventually { !model.isLoadingFiles })
    try FileManager.default.removeItem(at: root)
    model.jotDraft = "Do not lose this"

    #expect(!(await model.submitJot()))
    #expect(model.jotDraft == "Do not lose this")
    #expect(model.jotErrorMessage != nil)
    #expect(!model.isSubmittingJot)
  }

  @Test("Jot ignores empty and duplicate submissions")
  func ignoresInvalidJotSubmissions() async throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let model = MacMarkdownAppModel(folderURL: root)
    #expect(await eventually { !model.isLoadingFiles })

    model.jotDraft = "  \n"
    #expect(!(await model.submitJot()))
    model.jotDraft = "Exactly once"
    async let first = model.submitJot()
    async let second = model.submitJot()
    let results = await [first, second]

    #expect(results.filter { $0 }.count == 1)
    let dailyFile = try #require(model.files.first { $0.relativePath.hasSuffix(".md") })
    let contents = try String(contentsOf: dailyFile.url, encoding: .utf8)
    #expect(contents.components(separatedBy: "Exactly once").count == 2)
  }
}

@MainActor
@Suite("Mac Jot shortcut")
struct MacJotShortcutTests {
  @Test("uses a collision-resistant default global shortcut")
  func usesDefaultGlobalShortcut() throws {
    let shortcut = try #require(KeyboardShortcuts.Name.showJot.defaultShortcut)

    #expect(shortcut.key == .j)
    #expect(shortcut.modifiers == [.command, .option, .control])
  }
}

@MainActor
@Suite("Live Markdown presentation")
struct LiveMarkdownPresentationTests {
  @Test("uses TextKit 1 for live presentation")
  func usesStableTextLayoutEngine() {
    let textView = LiveMarkdownTextView.makeForEditing()

    #expect(textView.textLayoutManager == nil)
    #expect(textView.layoutManager != nil)
  }

  @Test("Jot starts with body typing attributes and does not seed a title")
  func startsJotAsBodyText() throws {
    let textView = LiveMarkdownTextView.makeForEditing()
    textView.seedsTitleOnFirstInsertion = false
    let presentation = LiveMarkdownPresentationController(
      usesTitleStyleForEmptyDocument: false
    )
    presentation.reset(
      textView: textView,
      text: "",
      selection: NSRange(location: 0, length: 0)
    )

    let font = try #require(textView.typingAttributes[.font] as? NSFont)
    #expect(font.pointSize == 16)
    textView.insertText("Capture this", replacementRange: NSRange(location: 0, length: 0))
    #expect(textView.string == "Capture this")
  }

  @Test("Jot handles Command-Return submit and Escape cancellation")
  func handlesJotWindowCommands() throws {
    let textView = LiveMarkdownTextView.makeForEditing()
    var submitCount = 0
    var cancelCount = 0
    textView.onSubmit = { submitCount += 1 }
    textView.onCancel = { cancelCount += 1 }
    let commandReturn = try #require(NSEvent.keyEvent(
      with: .keyDown,
      location: .zero,
      modifierFlags: .command,
      timestamp: 0,
      windowNumber: 0,
      context: nil,
      characters: "\r",
      charactersIgnoringModifiers: "\r",
      isARepeat: false,
      keyCode: 36
    ))

    #expect(textView.performKeyEquivalent(with: commandReturn))
    textView.cancelOperation(nil)
    #expect(submitCount == 1)
    #expect(cancelCount == 1)
  }

  @Test("Tab and Shift-Tab indent and outdent rendered list items")
  func indentsAndOutdentsListItems() {
    let textView = LiveMarkdownTextView.makeForEditing()
    textView.string = "- Parent\n- Child"
    textView.setSelectedRange(NSRange(location: 16, length: 0))

    textView.insertTab(nil)

    #expect(textView.string == "- Parent\n    - Child")
    #expect(textView.selectedRange() == NSRange(location: 20, length: 0))

    textView.insertBacktab(nil)

    #expect(textView.string == "- Parent\n- Child")
    #expect(textView.selectedRange() == NSRange(location: 16, length: 0))
  }

  @Test("typing after outdenting an empty continued item preserves order")
  func typesAfterOutdentingEmptyContinuedItem() {
    let textView = LiveMarkdownTextView.makeForEditing()
    textView.string = "- Parent\n    - Child\n    - "
    textView.setSelectedRange(NSRange(location: (textView.string as NSString).length, length: 0))

    textView.insertBacktab(nil)

    #expect(textView.string == "- Parent\n    - Child\n- ")
    let staleReplacementRange = textView.selectedRange()
    for character in "[ ] Checklist" {
      textView.insertText(String(character), replacementRange: staleReplacementRange)
    }

    #expect(textView.string == "- Parent\n    - Child\n- [ ] Checklist")
  }

  @Test("Escape dismisses an active slash command palette")
  func escapeDismissesSlashCommandPalette() {
    let textView = LiveMarkdownTextView.makeForEditing()
    var dismissalCount = 0
    textView.onCancelSlashCommandPalette = {
      dismissalCount += 1
      return true
    }

    textView.cancelOperation(nil)

    #expect(dismissalCount == 1)
  }

  @Test("activates wiki links through the native text view")
  func activatesWikiLinks() {
    let textView = LiveMarkdownTextView.makeForEditing()
    textView.string = "Open [[Project Plan]]"
    textView.presentationLinks = [LiveMarkdownLinkTarget(
      destination: .wiki("Project Plan"),
      range: NSRange(location: 7, length: 12)
    )]
    var openedTarget: String?
    textView.onOpenLink = { destination in
      guard case .wiki(let target) = destination else { return }
      openedTarget = target
    }

    #expect(textView.activateLink(at: 8))
    #expect(openedTarget == "Project Plan")
    #expect(!textView.activateLink(at: 0))
  }

  @Test("Return commits the Today slash command as a wiki link")
  func commitsTodaySlashCommand() throws {
    var ensuredDate: Date?
    var ensuredCalendar: Calendar?
    let editor = LiveMarkdownEditor(
      text: "Decision /tod",
      contentRevision: 0,
      externalRefreshRequest: 0,
      focusRequest: 0,
      isEditable: true,
      onEdit: { _, _ in },
      onReplaceAll: { _ in },
      onOpenWikiLink: { _ in },
      onEnsureTodayNote: { date, calendar in
        ensuredDate = date
        ensuredCalendar = calendar
      }
    )
    let coordinator = editor.makeCoordinator()
    let textView = LiveMarkdownTextView.makeForEditing()
    textView.string = editor.text
    textView.setSelectedRange(NSRange(
      location: (textView.string as NSString).length,
      length: 0
    ))
    coordinator.attach(textView: textView, scrollView: NSScrollView())

    #expect(coordinator.textView(
      textView,
      doCommandBy: #selector(NSResponder.insertNewline(_:))
    ))

    let date = try #require(ensuredDate)
    let calendar = try #require(ensuredCalendar)
    let stem = MarkdownFilename.dailyNoteStem(for: date, calendar: calendar)
    #expect(textView.string == "Decision [[\(stem)]]")
    #expect(textView.selectedRange() == NSRange(
      location: (textView.string as NSString).length,
      length: 0
    ))
  }

  @Test("starts an empty note with title-sized typing attributes")
  func startsEmptyNoteAsTitle() throws {
    let textView = LiveMarkdownTextView.makeForEditing()
    let presentation = LiveMarkdownPresentationController()
    presentation.reset(
      textView: textView,
      text: "",
      selection: NSRange(location: 0, length: 0)
    )

    let font = try #require(textView.typingAttributes[.font] as? NSFont)
    #expect(font.pointSize == 28)
    #expect(font.fontDescriptor.symbolicTraits.contains(.bold))
  }

  @Test("reveals only syntax touched by the selection")
  func revealsOnlySyntaxTouchedBySelection() throws {
    let text = "# Title\n\n**bold** and _italic_"
    let textView = LiveMarkdownTextView.makeForEditing()
    textView.string = text
    let presentation = LiveMarkdownPresentationController()
    presentation.reset(
      textView: textView,
      text: text,
      selection: NSRange(location: 2, length: 0)
    )

    let bold = try #require(presentation.tokens.first { $0.kind == .bold })
    let italic = try #require(presentation.tokens.first { $0.kind == .italic })
    let hiddenFont = try #require(textView.textStorage?.attribute(
      .font,
      at: bold.syntaxRanges[0].location,
      effectiveRange: nil
    ) as? NSFont)
    #expect(hiddenFont.pointSize < 1)

    presentation.focusDidChange(in: textView, isFocused: true)
    presentation.selectionDidChange(
      in: textView,
      selection: NSRange(location: bold.contentRange.location, length: 0)
    )
    let revealedFont = try #require(textView.textStorage?.attribute(
      .font,
      at: bold.syntaxRanges[0].location,
      effectiveRange: nil
    ) as? NSFont)
    #expect(revealedFont.pointSize > 10)

    let inactiveItalicFont = try #require(textView.textStorage?.attribute(
      .font,
      at: italic.syntaxRanges[0].location,
      effectiveRange: nil
    ) as? NSFont)
    #expect(inactiveItalicFont.pointSize < 1)

    presentation.selectionDidChange(
      in: textView,
      selection: NSRange(location: italic.contentRange.location, length: 0)
    )
    let hiddenBoldFont = try #require(textView.textStorage?.attribute(
      .font,
      at: bold.syntaxRanges[0].location,
      effectiveRange: nil
    ) as? NSFont)
    let revealedItalicFont = try #require(textView.textStorage?.attribute(
      .font,
      at: italic.syntaxRanges[0].location,
      effectiveRange: nil
    ) as? NSFont)
    #expect(hiddenBoldFont.pointSize < 1)
    #expect(revealedItalicFont.pointSize > 10)
  }

  @Test("collapses inline syntax as soon as typing moves beyond the token")
  func collapsesSyntaxAfterTrailingSpace() throws {
    let text = "_italic_"
    let textView = LiveMarkdownTextView.makeForEditing()
    textView.string = text
    let presentation = LiveMarkdownPresentationController()
    presentation.reset(
      textView: textView,
      text: text,
      selection: NSRange(location: (text as NSString).length, length: 0)
    )
    presentation.focusDidChange(in: textView, isFocused: true)

    let italic = try #require(presentation.tokens.first { $0.kind == .italic })
    let visibleAtBoundary = try #require(textView.textStorage?.attribute(
      .font,
      at: italic.syntaxRanges[0].location,
      effectiveRange: nil
    ) as? NSFont)
    #expect(visibleAtBoundary.pointSize > 10)

    let insertion = NSRange(location: (text as NSString).length, length: 0)
    let edit = presentation.pendingEdit(
      text: text as NSString,
      range: insertion,
      replacement: " "
    )
    textView.textStorage?.replaceCharacters(in: insertion, with: " ")
    presentation.didApplyEdit(
      edit,
      textView: textView,
      selection: NSRange(location: insertion.location + 1, length: 0)
    )

    let collapsedItalic = try #require(presentation.tokens.first { $0.kind == .italic })
    let hiddenAfterSpace = try #require(textView.textStorage?.attribute(
      .font,
      at: collapsedItalic.syntaxRanges[0].location,
      effectiveRange: nil
    ) as? NSFont)
    #expect(hiddenAfterSpace.pointSize < 1)
  }

  @Test("renders web and wiki link targets")
  func rendersLinks() throws {
    let text = "[Lattice](https://example.com), https://openai.com, and [[Project Plan]]"
    let textView = LiveMarkdownTextView.makeForEditing()
    textView.string = text
    let presentation = LiveMarkdownPresentationController()
    presentation.reset(
      textView: textView,
      text: text,
      selection: NSRange(location: (text as NSString).length, length: 0)
    )

    let markdownLink = try #require(presentation.tokens.first {
      if case .markdownLink = $0.kind { return true }
      return false
    })
    let bareLink = try #require(presentation.tokens.first {
      if case .bareLink = $0.kind { return true }
      return false
    })
    let wikiLink = try #require(presentation.tokens.first {
      if case .wikiLink = $0.kind { return true }
      return false
    })
    let hiddenSyntaxFont = try #require(textView.textStorage?.attribute(
      .font,
      at: markdownLink.syntaxRanges[0].location,
      effectiveRange: nil
    ) as? NSFont)
    let markdownLabelColor = try #require(textView.textStorage?.attribute(
      .foregroundColor,
      at: markdownLink.contentRange.location,
      effectiveRange: nil
    ) as? NSColor)
    let bareLinkColor = try #require(textView.textStorage?.attribute(
      .foregroundColor,
      at: bareLink.contentRange.location,
      effectiveRange: nil
    ) as? NSColor)
    let wikiLinkColor = try #require(textView.textStorage?.attribute(
      .foregroundColor,
      at: wikiLink.contentRange.location,
      effectiveRange: nil
    ) as? NSColor)
    let exampleURL = try #require(URL(string: "https://example.com"))
    let openAIURL = try #require(URL(string: "https://openai.com"))

    #expect(hiddenSyntaxFont.pointSize < 1)
    #expect(markdownLabelColor.isEqual(NSColor.linkColor))
    #expect(bareLinkColor.isEqual(NSColor.linkColor))
    #expect(wikiLinkColor.isEqual(NSColor.linkColor))
    #expect(textView.presentationLinks.map(\.destination) == [
      .web(exampleURL),
      .web(openAIURL),
      .wiki("Project Plan")
    ])
    #expect(textView.presentationLinks.map(\.range) == [
      markdownLink.contentRange,
      bareLink.contentRange,
      wikiLink.contentRange
    ])

    presentation.focusDidChange(in: textView, isFocused: true)
    presentation.selectionDidChange(
      in: textView,
      selection: NSRange(location: markdownLink.contentRange.location, length: 0)
    )
    let revealedSyntaxFont = try #require(textView.textStorage?.attribute(
      .font,
      at: markdownLink.syntaxRanges[0].location,
      effectiveRange: nil
    ) as? NSFont)
    #expect(revealedSyntaxFont.pointSize > 10)
  }

  @Test("keeps later token ranges stable after an incremental edit")
  func shiftsTokensAfterIncrementalEdit() throws {
    let text = "# Title\n\n**bold**"
    let textView = LiveMarkdownTextView.makeForEditing()
    textView.string = text
    let presentation = LiveMarkdownPresentationController()
    presentation.reset(
      textView: textView,
      text: text,
      selection: NSRange(location: 2, length: 0)
    )
    let originalBold = try #require(presentation.tokens.first { $0.kind == .bold })
    let insertion = NSRange(location: 2, length: 0)
    let edit = presentation.pendingEdit(
      text: text as NSString,
      range: insertion,
      replacement: "New "
    )

    textView.textStorage?.replaceCharacters(in: insertion, with: "New ")
    presentation.didApplyEdit(
      edit,
      textView: textView,
      selection: NSRange(location: 6, length: 0)
    )

    let shiftedBold = try #require(presentation.tokens.first { $0.kind == .bold })
    #expect(shiftedBold.fullRange.location == originalBold.fullRange.location + 4)
    #expect((textView.string as NSString).substring(with: shiftedBold.contentRange) == "bold")
  }

  @Test("creates presentation-only bullet and task decorations")
  func createsListDecorations() {
    let text = "- bullet\n- [ ] open\n- [x] done"
    let textView = LiveMarkdownTextView.makeForEditing()
    textView.string = text
    let presentation = LiveMarkdownPresentationController()
    presentation.reset(
      textView: textView,
      text: text,
      selection: NSRange(location: (text as NSString).length, length: 0)
    )

    #expect(textView.presentationDecorations.map(\.kind) == [
      .bullet,
      .task(isChecked: false),
      .task(isChecked: true)
    ])
    #expect(textView.string == text)
  }

  @Test("renders an inactive thematic break and reveals its Markdown source when active")
  func rendersThematicBreak() throws {
    let text = "Before\n---\nAfter"
    let ruleRange = (text as NSString).range(of: "---")
    let textView = LiveMarkdownTextView.makeForEditing()
    textView.string = text
    textView.setSelectedRange(NSRange(location: ruleRange.location, length: 0))
    let presentation = LiveMarkdownPresentationController()
    presentation.reset(
      textView: textView,
      text: text,
      selection: textView.selectedRange()
    )

    #expect(presentation.tokens.contains { $0.kind == .thematicBreak })
    #expect(textView.presentationDecorations.map(\.kind) == [.thematicBreak])
    let hiddenColor = textView.textStorage?.attribute(
      .foregroundColor,
      at: ruleRange.location,
      effectiveRange: nil
    ) as? NSColor
    let hiddenFont = try #require(textView.textStorage?.attribute(
      .font,
      at: ruleRange.location,
      effectiveRange: nil
    ) as? NSFont)
    #expect(hiddenColor == NSColor.clear)
    #expect(hiddenFont.pointSize == 16)

    presentation.focusDidChange(in: textView, isFocused: true)

    #expect(textView.presentationDecorations.isEmpty)
    let revealedColor = textView.textStorage?.attribute(
      .foregroundColor,
      at: ruleRange.location,
      effectiveRange: nil
    ) as? NSColor
    #expect(revealedColor == NSColor.tertiaryLabelColor)
    #expect(textView.string == text)
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
