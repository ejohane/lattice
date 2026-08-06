import AppKit
import Foundation
import LatticeEditor
@testable import Lattice
@testable import LatticeMacCore
import Testing

@Suite("Mac tag storage")
struct MacTagStorageTests {
  @Test("derives disposable per-file tags while scanning Markdown")
  func scansTags() async throws {
    let root = try makeTagTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    try "# Alpha\n\n#Work #work #project/lattice `#ignored`".write(
      to: root.appendingPathComponent("Alpha.md"), atomically: true, encoding: .utf8
    )
    try "# Beta\n\n#Personal".write(
      to: root.appendingPathComponent("Beta.md"), atomically: true, encoding: .utf8
    )

    let result = try await MarkdownFolder(rootURL: root).scan()

    #expect(result.failures.isEmpty)
    #expect(result.snapshots.count == 2)
    let alpha = try #require(result.snapshots.first { $0.file.relativePath == "Alpha.md" })
    #expect(alpha.tags.map(\.name) == ["Work", "work", "project/lattice"])
  }

  @Test("renames and deletes exact tags atomically while preserving raw Markdown")
  func rewritesRawMarkdown() async throws {
    let root = try makeTagTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let firstURL = root.appendingPathComponent("First.md")
    let secondURL = root.appendingPathComponent("Second.md")
    let prefix = "---\nlattice:\n  id: first\naliases: [#Work]\n---\n\n"
    try (prefix + "# First\n\n#Work and #work/project\n`#work`\n").write(
      to: firstURL, atomically: true, encoding: .utf8
    )
    try "# Second\n\n#WORK\n```\n#work\n```\n".write(
      to: secondURL, atomically: true, encoding: .utf8
    )
    let folder = MarkdownFolder(rootURL: root)

    let renamed = try await folder.rewriteTag(normalizedName: "WORK", to: "Career")

    #expect(renamed.changedNoteCount == 2)
    #expect(renamed.failures.isEmpty)
    #expect(try String(contentsOf: firstURL, encoding: .utf8) ==
      prefix + "# First\n\n#Career and #work/project\n`#work`\n")
    #expect(try String(contentsOf: secondURL, encoding: .utf8) ==
      "# Second\n\n#Career\n```\n#work\n```\n")

    let deleted = try await folder.rewriteTag(normalizedName: "career", to: nil)
    #expect(deleted.changedNoteCount == 2)
    #expect(try String(contentsOf: firstURL, encoding: .utf8) ==
      prefix + "# First\n\nand #work/project\n`#work`\n")
    #expect(FileManager.default.fileExists(atPath: firstURL.path))
    #expect(FileManager.default.fileExists(atPath: secondURL.path))
  }

  @Test("continues a tag batch and reports unreadable files")
  func reportsPartialFailure() async throws {
    let root = try makeTagTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let validURL = root.appendingPathComponent("Valid.md")
    let invalidURL = root.appendingPathComponent("Invalid.md")
    try "# Valid\n\n#Work".write(to: validURL, atomically: true, encoding: .utf8)
    try Data([0xFF, 0xFE, 0xFD]).write(to: invalidURL)

    let result = try await MarkdownFolder(rootURL: root).rewriteTag(
      normalizedName: "work",
      to: "career"
    )

    #expect(result.changedNoteCount == 1)
    #expect(result.failures.map(\.relativePath) == ["Invalid.md"])
    #expect(try String(contentsOf: validURL, encoding: .utf8) == "# Valid\n\n#career")
    #expect(try Data(contentsOf: invalidURL) == Data([0xFF, 0xFE, 0xFD]))
  }
}

@MainActor
@Suite("Active Mac tag model")
struct MacTagModelTests {
  @Test("counts case-insensitive tags once per note and filters with stable selection")
  func derivesAndFiltersTags() async throws {
    let root = try makeTagTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let newest = root.appendingPathComponent("Newest.md")
    let older = root.appendingPathComponent("Older.md")
    let personal = root.appendingPathComponent("Personal.md")
    try "# Newest\n\n#Work #work".write(to: newest, atomically: true, encoding: .utf8)
    try "# Older\n\n#WORK".write(to: older, atomically: true, encoding: .utf8)
    try "# Personal\n\n#personal".write(to: personal, atomically: true, encoding: .utf8)
    try setTagModificationDate(3_000, for: newest)
    try setTagModificationDate(2_000, for: older)
    try setTagModificationDate(1_000, for: personal)
    let model = MacMarkdownAppModel(folderURL: root)
    #expect(await tagEventually { !model.isLoadingFiles && !model.isLoadingFile })

    #expect(model.tagSummaries.map { "\($0.name):\($0.noteCount)" } == [
      "personal:1", "Work:2"
    ])
    let work = try #require(model.tagSummaries.first { $0.normalizedName == "work" })
    model.selectTag(work)
    #expect(model.selectedFileID == newest.standardizedFileURL)
    #expect(model.filteredFiles.map(\.id) == [newest.standardizedFileURL, older.standardizedFileURL])

    let personalTag = try #require(model.tagSummaries.first { $0.normalizedName == "personal" })
    model.selectTag(personalTag)
    #expect(await tagEventually { model.selectedFileID == personal.standardizedFileURL })
    model.selectTag(nil)
    #expect(model.selectedFileID == personal.standardizedFileURL)
  }

  @Test("save updates summaries and moves a now-nonmatching filtered selection")
  func updatesAfterSave() async throws {
    let root = try makeTagTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let first = root.appendingPathComponent("First.md")
    let second = root.appendingPathComponent("Second.md")
    try "# First\n\n#work".write(to: first, atomically: true, encoding: .utf8)
    try "# Second\n\n#work".write(to: second, atomically: true, encoding: .utf8)
    try setTagModificationDate(2_000, for: first)
    try setTagModificationDate(1_000, for: second)
    let model = MacMarkdownAppModel(folderURL: root)
    #expect(await tagEventually { !model.isLoadingFiles && !model.isLoadingFile })
    let work = try #require(model.tagSummaries.first)
    model.selectTag(work)

    model.updateText("# First\n\nNo tag")

    #expect(await tagEventually { model.selectedFileID == second.standardizedFileURL })
    #expect(model.tagSummaries.first?.noteCount == 1)
    #expect(try String(contentsOf: first, encoding: .utf8) == "# First\n\nNo tag")
  }

  @Test("empty filters show no selection and clearing restores the prior note")
  func handlesEmptyFilterSelection() async throws {
    let root = try makeTagTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let noteURL = root.appendingPathComponent("Note.md")
    try "# Note\n\n#work".write(to: noteURL, atomically: true, encoding: .utf8)
    let model = MacMarkdownAppModel(folderURL: root)
    #expect(await tagEventually { !model.isLoadingFiles && !model.isLoadingFile })

    model.selectTag(NoteTagSummary(name: "missing", noteCount: 0))
    #expect(model.filteredFiles.isEmpty)
    #expect(model.selectedFileID == nil)

    model.selectTag(nil)
    #expect(await tagEventually { model.selectedFileID == noteURL.standardizedFileURL })
  }

  @Test("reopening reconciles tag summaries from disk")
  func reloadsTagsFromDisk() async throws {
    let root = try makeTagTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let noteURL = root.appendingPathComponent("Note.md")
    try "# Note\n\n#work".write(to: noteURL, atomically: true, encoding: .utf8)
    let firstModel = MacMarkdownAppModel(folderURL: root)
    #expect(await tagEventually { !firstModel.isLoadingFiles && !firstModel.isLoadingFile })
    #expect(firstModel.tagSummaries.map(\.normalizedName) == ["work"])

    try "# Note\n\n#career".write(to: noteURL, atomically: true, encoding: .utf8)
    let reloadedModel = MacMarkdownAppModel(folderURL: root)
    #expect(await tagEventually { !reloadedModel.isLoadingFiles && !reloadedModel.isLoadingFile })
    #expect(reloadedModel.tagSummaries.map(\.normalizedName) == ["career"])
  }

  @Test("inline activation and confirmed rename-delete keep filters and files coherent")
  func activatesRenamesAndDeletes() async throws {
    let root = try makeTagTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let noteURL = root.appendingPathComponent("Note.md")
    try "# Note\n\nPlan #Work now".write(to: noteURL, atomically: true, encoding: .utf8)
    let model = MacMarkdownAppModel(folderURL: root)
    #expect(await tagEventually { !model.isLoadingFiles && !model.isLoadingFile })

    let occurrence = try #require(NoteTagParser.tags(in: model.text).first)
    model.activateTag(at: occurrence.range.location + 1)
    #expect(model.selectedTagName == "work")
    #expect(model.selectedFileID == noteURL.standardizedFileURL)

    let work = try #require(model.tagSummaries.first)
    model.beginRenamingTag(work)
    #expect(model.renamingTag?.noteCount == 1)
    model.renameTagName = "Career"
    #expect(await model.confirmTagRename())
    #expect(model.selectedTagName == "career")
    #expect(try String(contentsOf: noteURL, encoding: .utf8).contains("#Career"))

    let career = try #require(model.tagSummaries.first)
    model.requestTagDeletion(career)
    #expect(model.deletingTag?.noteCount == 1)
    // SwiftUI dismisses an alert before its asynchronous button task runs.
    // Carrying the presented value keeps confirmation routing deterministic.
    model.cancelTagDeletion()
    #expect(await model.confirmTagDeletion(career))
    #expect(model.selectedTagName == nil)
    #expect(model.selectedFileID == noteURL.standardizedFileURL)
    #expect(try String(contentsOf: noteURL, encoding: .utf8) == "# Note\n\nPlan now")
  }

  @Test("partial batch failures clear the filter and use existing error presentation")
  func reportsPartialBatchFailure() async throws {
    let root = try makeTagTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let validURL = root.appendingPathComponent("Valid.md")
    let invalidURL = root.appendingPathComponent("Invalid.md")
    try "# Valid\n\n#work".write(to: validURL, atomically: true, encoding: .utf8)
    try Data([0xFF]).write(to: invalidURL)
    try setTagModificationDate(2_000, for: validURL)
    try setTagModificationDate(1_000, for: invalidURL)
    let model = MacMarkdownAppModel(folderURL: root)
    #expect(await tagEventually { !model.isLoadingFiles && !model.isLoadingFile })
    let work = try #require(model.tagSummaries.first)
    model.selectTag(work)
    model.errorMessage = nil
    model.beginRenamingTag(work)
    model.renameTagName = "career"

    #expect(!(await model.confirmTagRename()))
    #expect(model.selectedTagName == nil)
    #expect(model.errorMessage?.contains("Updated 1 note") == true)
    #expect(model.errorMessage?.contains("Invalid.md") == true)
    #expect(try String(contentsOf: validURL, encoding: .utf8) == "# Valid\n\n#career")
  }

  @Test("tag queries expose filter commands and recency-ranked tagged notes without regressing creation")
  func commandPaletteTagResults() async throws {
    let root = try makeTagTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let work = root.appendingPathComponent("Work.md")
    let other = root.appendingPathComponent("Other.md")
    try "# Roadmap\n\n#Work".write(to: work, atomically: true, encoding: .utf8)
    try "# Other\n\n#personal".write(to: other, atomically: true, encoding: .utf8)
    let model = MacMarkdownAppModel(folderURL: root)
    #expect(await tagEventually { !model.isLoadingFiles && !model.isLoadingFile })

    #expect(model.commandPaletteTags(matching: "#wor").map(\.normalizedName) == ["work"])
    #expect(model.commandPaletteNotes(matching: "#work").map(\.id) == [work.standardizedFileURL])
    #expect(model.commandPaletteCreationTitle(matching: "#work") == nil)
    #expect(model.commandPaletteNotes(matching: "road").map(\.title) == ["Roadmap"])
    #expect(model.commandPaletteCreationTitle(matching: "Fresh Note") == "Fresh Note")
  }
}

@MainActor
@Suite("Active Mac tag editor")
struct MacTagEditorTests {
  @Test("ranks autocomplete, commits replacement, and excludes code")
  func autocompleteBehavior() throws {
    let tags = [
      NoteTagSummary(name: "project/other", noteCount: 9),
      NoteTagSummary(name: "Project/Lattice", noteCount: 4),
      NoteTagSummary(name: "process", noteCount: 2)
    ]
    let text = "Plan #pro"
    let suggestions = MacTagAutocomplete.suggestions(
      in: text,
      selection: NSRange(location: (text as NSString).length, length: 0),
      tags: tags
    )
    #expect(suggestions.map(\.name) == ["project/other", "Project/Lattice", "process"])

    let committed = try #require(MacTagAutocomplete.committing(suggestions[1], in: text))
    #expect(committed.text == "Plan #Project/Lattice")
    #expect(committed.selection.location == (committed.text as NSString).length)
    #expect(MacTagAutocomplete.suggestions(
      in: "`#pro",
      selection: NSRange(location: 5, length: 0),
      tags: tags
    ).isEmpty)
  }

  @Test("styles and activates literal inline tags")
  func stylesAndActivatesTags() throws {
    let text = "Plan #Work and `#ignored`"
    let textView = LiveMarkdownTextView.makeForEditing()
    textView.string = text
    let presentation = LiveMarkdownPresentationController()
    presentation.reset(
      textView: textView,
      text: text,
      selection: NSRange(location: 0, length: 0)
    )
    let tagRange = try #require(NoteTagParser.tags(in: text).first?.range)
    let color = try #require(textView.textStorage?.attribute(
      .foregroundColor, at: tagRange.location, effectiveRange: nil
    ) as? NSColor)
    #expect(color.isEqual(NSColor.controlAccentColor))
    #expect(textView.presentationLinks.map(\.destination) == [.tag("work")])

    var activated: String?
    textView.onOpenLink = { destination in
      if case .tag(let normalizedName) = destination { activated = normalizedName }
    }
    #expect(textView.activateLink(at: tagRange.location + 1))
    #expect(activated == "work")
  }

  @Test("routes completion keyboard navigation commit and dismissal")
  func keyboardRouting() {
    let textView = LiveMarkdownTextView.makeForEditing()
    var movement: [Int] = []
    var commits = 0
    var dismissals = 0
    textView.onMoveEditorCompletion = { movement.append($0); return true }
    textView.onCommitEditorCompletion = { commits += 1; return true }
    textView.onCancelEditorCompletion = { dismissals += 1; return true }

    textView.moveDown(nil)
    textView.moveUp(nil)
    textView.insertTab(nil)
    textView.cancelOperation(nil)

    #expect(movement == [1, -1])
    #expect(commits == 1)
    #expect(dismissals == 1)
  }
}

private func makeTagTemporaryDirectory() throws -> URL {
  let url = FileManager.default.temporaryDirectory
    .appendingPathComponent("lattice-tags-\(UUID().uuidString)", isDirectory: true)
  try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  return url
}

private func setTagModificationDate(_ value: TimeInterval, for url: URL) throws {
  try FileManager.default.setAttributes(
    [.modificationDate: Date(timeIntervalSince1970: value)],
    ofItemAtPath: url.path
  )
}

@MainActor
private func tagEventually(
  timeout: Duration = .seconds(10),
  _ condition: @escaping @MainActor () -> Bool
) async -> Bool {
  let clock = ContinuousClock()
  let deadline = clock.now.advanced(by: timeout)
  while clock.now < deadline {
    if condition() { return true }
    try? await Task.sleep(for: .milliseconds(20))
  }
  return condition()
}
