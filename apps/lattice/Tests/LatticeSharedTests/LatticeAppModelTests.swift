import Foundation
import LatticeCore
import LatticeShared
import LatticeTestSupport
import Testing

@MainActor
@Suite("LatticeAppModel")
struct LatticeAppModelTests {
  @Test("drives choose folder, autosave, list, and reopen flow")
  func drivesFirstMilestoneNoteFlow() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }
    let model = LatticeAppModel(
      noteLibrary: fixture.library,
      folderAccessStore: fixture.folderAccessStore
    )

    try fixture.fileManager.createDirectory(at: fixture.root, withIntermediateDirectories: true)
    model.chooseFolder(fixture.root)
    #expect(model.hasFolder)
    #expect(model.sections.isEmpty)

    model.text = "**Universal Note**\n\n# Later Heading\n\nBody"
    model.flushAutosave()

    let sections = model.sections
    #expect(sections.count == 1)
    let section = try #require(sections.first)
    #expect(section.notes.count == 1)
    let note = try #require(section.notes.first)
    #expect(note.url.path.contains("/notes/"))
    #expect(note.url.lastPathComponent.hasSuffix(".md"))
    #expect(try fixture.library.body(for: note) == "**Universal Note**\n\n# Later Heading\n\nBody\n")
    #expect(model.displayTitle(for: note) == "Universal Note")

    model.createNewNote()
    #expect(model.text == "")
    model.open(note)
    #expect(model.text == "**Universal Note**\n\n# Later Heading\n\nBody")
  }

  @Test("autosave records note created and edited activity")
  func autosaveRecordsNoteActivity() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }
    var now = fixture.date(hour: 9)
    let model = LatticeAppModel(
      noteLibrary: fixture.library,
      folderAccessStore: fixture.folderAccessStore,
      activityStore: fixture.activityStore,
      dateProvider: { now }
    )

    try fixture.fileManager.createDirectory(at: fixture.root, withIntermediateDirectories: true)
    model.chooseFolder(fixture.root)
    model.text = "Product\n\n# Later Heading\n\nFirst"
    model.flushAutosave()
    now = fixture.date(hour: 10)
    model.text = "Product\n\n# Later Heading\n\nFirst\n\nSecond"
    model.flushAutosave()

    #expect(model.todayActivityEvents.map(\.kind) == [.noteCreated, .noteEdited])
    #expect(model.todayActivityEvents[0].noteTitle == "Product")
    #expect(model.todayActivityEvents[0].noteRelativePath?.hasPrefix("notes/") == true)
    #expect(model.todayActivityEvents[1].beforeExcerpt == "Product # Later Heading First")
    #expect(model.todayActivityEvents[1].afterExcerpt == "Product # Later Heading First Second")
  }

  @Test("autosave preserves trailing editor newline")
  func autosavePreservesTrailingEditorNewline() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }
    let model = LatticeAppModel(
      noteLibrary: fixture.library,
      folderAccessStore: fixture.folderAccessStore,
      noteIndex: NoteIndex(appSupportURL: fixture.appSupportURL)
    )

    try fixture.fileManager.createDirectory(at: fixture.root, withIntermediateDirectories: true)
    model.chooseFolder(fixture.root)
    model.text = "test\n"
    model.selectedRange = NSRange(location: 5, length: 0)

    model.flushAutosave()

    #expect(model.text == "test\n")
    #expect(model.selectedRange.location == 5)
    #expect(try fixture.library.body(for: try #require(model.selectedNote)) == "test\n")
  }

  @Test("records note navigation history and restores cursor positions")
  func recordsNoteNavigationHistory() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }
    let model = LatticeAppModel(
      noteLibrary: fixture.library,
      folderAccessStore: fixture.folderAccessStore,
      noteIndex: NoteIndex(appSupportURL: fixture.appSupportURL)
    )

    try fixture.fileManager.createDirectory(at: fixture.root, withIntermediateDirectories: true)
    try fixture.library.selectNotesFolder(fixture.root)
    let first = try fixture.library.createNote(body: "# First\n\nAlpha")
    let second = try fixture.library.createNote(body: "# Second\n\nBeta")

    model.chooseFolder(fixture.root)
    model.open(first)
    let alphaRange = (model.text as NSString).range(of: "Alpha")
    model.selectedRange = alphaRange

    model.open(second)

    #expect(model.selectedNote == second)
    #expect(model.canNavigateBack)
    #expect(!model.canNavigateForward)

    model.navigateBack()

    #expect(model.selectedNote == first)
    #expect(model.selectedRange == alphaRange)
    #expect(!model.canNavigateBack)
    #expect(model.canNavigateForward)

    model.navigateForward()

    #expect(model.selectedNote == second)
    #expect(model.canNavigateBack)
    #expect(!model.canNavigateForward)
  }

  @Test("records same-note heading navigation history")
  func recordsSameNoteHeadingNavigationHistory() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }
    let model = LatticeAppModel(
      noteLibrary: fixture.library,
      folderAccessStore: fixture.folderAccessStore,
      noteIndex: NoteIndex(appSupportURL: fixture.appSupportURL)
    )

    try fixture.fileManager.createDirectory(at: fixture.root, withIntermediateDirectories: true)
    try fixture.library.selectNotesFolder(fixture.root)
    let note = try fixture.library.createNote(body: "# Source\n\n[[#Target]]\n\nIntro\n\n## Target\n\nBody")

    model.chooseFolder(fixture.root)
    model.open(note)
    let introRange = (model.text as NSString).range(of: "Intro")
    model.selectedRange = introRange
    let linkLocation = (model.text as NSString).range(of: "[[#Target]]").location + 3

    model.activateWikiLink(at: linkLocation)

    #expect(model.selectedRange == (model.text as NSString).range(of: "Target", options: [], range: NSRange(location: 30, length: 9)))
    #expect(model.canNavigateBack)

    model.navigateBack()

    #expect(model.selectedNote == note)
    #expect(model.selectedRange == introRange)
    #expect(model.canNavigateForward)
  }

  @Test("adjusts editor font size with app-style bounds")
  func adjustsEditorFontSize() throws {
    let defaultsSuiteName = "font-size-\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: defaultsSuiteName) else {
      throw FixtureError.defaultsUnavailable
    }
    defer {
      defaults.removePersistentDomain(forName: defaultsSuiteName)
    }

    let model = LatticeAppModel(
      noteLibrary: NoteLibrary(defaults: defaults),
      folderAccessStore: FolderAccessStore(defaults: defaults)
    )

    #expect(model.editorFontSize == 14)

    model.increaseEditorFontSize()
    #expect(model.editorFontSize == 15)

    model.decreaseEditorFontSize()
    #expect(model.editorFontSize == 14)

    model.resetEditorFontSize()
    #expect(model.editorFontSize == 14)

    for _ in 0..<30 {
      model.decreaseEditorFontSize()
    }
    #expect(model.editorFontSize == 10)
    #expect(!model.canDecreaseEditorFontSize)

    for _ in 0..<30 {
      model.increaseEditorFontSize()
    }
    #expect(model.editorFontSize == 28)
    #expect(!model.canIncreaseEditorFontSize)
  }

  @Test("persists per-device editor preferences")
  func persistsEditorPreferences() throws {
    let defaultsSuiteName = "editor-preferences-\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: defaultsSuiteName) else {
      throw FixtureError.defaultsUnavailable
    }
    defer {
      defaults.removePersistentDomain(forName: defaultsSuiteName)
    }
    let model = LatticeAppModel(
      noteLibrary: NoteLibrary(defaults: defaults),
      folderAccessStore: FolderAccessStore(defaults: defaults),
      editorPreferencesStore: EditorPreferencesStore(defaults: defaults)
    )

    #expect(!model.isVimModeEnabled)
    #expect(!model.showsRelativeLineNumbers)
    #expect(model.showsTimelineRuler)
    #expect(model.selectedThemeID == .system)
    #expect(model.editorFontFamily == .system)
    #expect(model.showsStatusBar)
    #expect(model.vimState.mode == .insert)

    model.setVimModeEnabled(true)
    model.setRelativeLineNumbersEnabled(true)
    model.setTimelineRulerEnabled(false)
    model.setTheme(.solarizedDark)
    model.setEditorFontFamily(.monospaced)
    model.setStatusBarVisible(false)

    let restored = LatticeAppModel(
      noteLibrary: NoteLibrary(defaults: defaults),
      folderAccessStore: FolderAccessStore(defaults: defaults),
      editorPreferencesStore: EditorPreferencesStore(defaults: defaults)
    )

    #expect(restored.isVimModeEnabled)
    #expect(restored.showsRelativeLineNumbers)
    #expect(!restored.showsTimelineRuler)
    #expect(restored.selectedThemeID == .solarizedDark)
    #expect(restored.editorFontFamily == .monospaced)
    #expect(!restored.showsStatusBar)
    #expect(restored.vimState.mode == .normal)
  }

  @Test("dismisses wiki autocomplete suggestions")
  func dismissesWikiAutocompleteSuggestions() {
    let model = LatticeAppModel()
    model.wikiAutocompleteSuggestions = [
      WikiAutocompleteSuggestion(
        title: "Daily Note",
        subtitle: "notes/today.md",
        replacement: "[[Daily Note]]",
        replacementRange: NSRange(location: 0, length: 2)
      )
    ]

    model.dismissWikiAutocomplete()

    #expect(model.wikiAutocompleteSuggestions.isEmpty)
  }

  @Test("clears vim status when editing resumes")
  func clearsVimStatusWhenEditingResumes() {
    let model = LatticeAppModel()
    model.setVimStatusMessage("Saved")

    model.noteTextDidChange()

    #expect(model.vimStatusMessage == nil)
  }

  @Test("command palette only exposes update checking without a folder")
  func commandPaletteCommandsWithoutFolder() throws {
    let defaultsSuiteName = "command-palette-setup-\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: defaultsSuiteName) else {
      throw FixtureError.defaultsUnavailable
    }
    defer {
      defaults.removePersistentDomain(forName: defaultsSuiteName)
    }

    let model = LatticeAppModel(
      noteLibrary: NoteLibrary(defaults: defaults),
      folderAccessStore: FolderAccessStore(defaults: defaults)
    )
    let platformCommands = [
      CommandPaletteCommand(
        id: "test.checkForUpdates",
        title: "Check for Updates",
        systemImage: "arrow.triangle.2.circlepath"
      ) {}
    ]

    let titles = model.commandPaletteCommands(platformCommands: platformCommands).map(\.title)
    #expect(titles == ["Check for Updates"])
    #expect(titles.contains("Check for Updates"))
    #expect(!titles.contains("New Note"))
  }

  @Test("command palette shows recent notes and filters note switcher results by title")
  func commandPaletteShowsAndFiltersNotesByTitle() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }
    let model = LatticeAppModel(
      noteLibrary: fixture.library,
      folderAccessStore: fixture.folderAccessStore,
      noteIndex: NoteIndex(appSupportURL: fixture.appSupportURL)
    )

    try fixture.fileManager.createDirectory(at: fixture.root, withIntermediateDirectories: true)
    model.chooseFolder(fixture.root)
    model.text = "**Palette Target**\n\n# Later Heading\n\nBody"
    model.flushAutosave()
    model.createNewNote()
    model.text = "Another Note\n\n# Later Heading\n\nBody"
    model.flushAutosave()

    let recentNotes = model.commandPaletteNotes()
    #expect(recentNotes.count == 2)
    #expect(model.displayTitle(for: try #require(recentNotes.first)) == "Another Note")

    model.commandPaletteQuery = "palette"
    let notes = model.commandPaletteNotes()

    #expect(notes.count == 1)
    let note = try #require(notes.first)
    #expect(model.displayTitle(for: note) == "Palette Target")

    model.commandPaletteQuery = ""
    let commandTitles = model.commandPaletteCommands().map(\.title)
    #expect(commandTitles.contains("Timeline"))
    #expect(commandTitles.contains("New Note"))
    #expect(!commandTitles.contains("Heading"))
    #expect(!commandTitles.contains("Bold"))
    #expect(!commandTitles.contains("Italic"))
    #expect(!commandTitles.contains("List"))
    #expect(!commandTitles.contains("Code"))
    #expect(!commandTitles.contains("Link"))
    #expect(!commandTitles.contains("Increase Font Size"))
  }

  @Test("command palette opens timeline and timeline draft persists at folder root")
  func timelineCommandPersistsDraftAtFolderRoot() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }
    let model = LatticeAppModel(
      noteLibrary: fixture.library,
      folderAccessStore: fixture.folderAccessStore,
      dateProvider: { fixture.date(hour: 14) }
    )

    try fixture.fileManager.createDirectory(at: fixture.root, withIntermediateDirectories: true)
    model.chooseFolder(fixture.root)

    let timelineCommand = try #require(model.commandPaletteCommands().first { $0.title == "Timeline" })
    timelineCommand.perform()

    #expect(model.selectedPage == .timeline)
    #expect(model.activeTimelineEntryID == nil)
    #expect(model.timelineEntries.isEmpty)

    model.timelineText = "Outlined the onboarding flow."
    model.flushTimelineAutosave()

    #expect(model.timelineEntries.map(\.body) == ["Outlined the onboarding flow."])
    #expect(model.activeTimelineEntryID == model.timelineEntries.first?.id)
    #expect(fixture.fileManager.fileExists(atPath: fixture.root.appendingPathComponent("Timeline.md").path))
    #expect(!fixture.fileManager.fileExists(atPath: fixture.root.appendingPathComponent("notes/Timeline.md").path))
  }

  @Test("timeline blank line separates entries in one continuous document")
  func timelineBlankLineSeparatesEntries() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }
    var now = fixture.date(hour: 14)
    let model = LatticeAppModel(
      noteLibrary: fixture.library,
      folderAccessStore: fixture.folderAccessStore,
      dateProvider: { now }
    )

    try fixture.fileManager.createDirectory(at: fixture.root, withIntermediateDirectories: true)
    model.chooseFolder(fixture.root)
    model.showTimeline()
    model.timelineText = "First entry.\n\n"
    model.flushTimelineAutosave()

    #expect(model.timelineEntries.map(\.body) == ["First entry."])
    #expect(model.timelineText == "First entry.\n\n")
    let firstEntry = try #require(model.timelineEntries.first)

    now = fixture.date(hour: 15)
    model.timelineText = "Second entry.\n\nFirst entry."
    model.timelineSelectedRange = NSRange(location: 15, length: 0)
    model.flushTimelineAutosave()

    #expect(model.timelineEntries.map(\.body) == ["Second entry.", "First entry."])
    #expect(model.timelineText == "Second entry.\n\nFirst entry.")
    #expect(model.timelineEntries[0].createdAt == fixture.date(hour: 15))
    #expect(model.timelineEntries[1].id == firstEntry.id)
    #expect(model.timelineEntries[1].createdAt == firstEntry.createdAt)
  }

  @Test("timeline autosave preserves trailing editor newline")
  func timelineAutosavePreservesTrailingEditorNewline() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }
    let model = LatticeAppModel(
      noteLibrary: fixture.library,
      folderAccessStore: fixture.folderAccessStore,
      dateProvider: { fixture.date(hour: 14) }
    )

    try fixture.fileManager.createDirectory(at: fixture.root, withIntermediateDirectories: true)
    model.chooseFolder(fixture.root)
    model.showTimeline()
    model.timelineText = "test\n"
    model.timelineSelectedRange = NSRange(location: 5, length: 0)

    model.flushTimelineAutosave()

    #expect(model.timelineText == "test\n")
    #expect(model.timelineSelectedRange.location == 5)
    #expect(model.timelineEntries.map(\.body) == ["test"])
    #expect(model.activeTimelineEntryID == model.timelineEntries.first?.id)
  }

  @Test("command palette searches indexed note bodies")
  func commandPaletteSearchesIndexedBodies() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }
    let model = LatticeAppModel(
      noteLibrary: fixture.library,
      folderAccessStore: fixture.folderAccessStore,
      noteIndex: NoteIndex(appSupportURL: fixture.appSupportURL)
    )

    try fixture.fileManager.createDirectory(at: fixture.root, withIntermediateDirectories: true)
    model.chooseFolder(fixture.root)
    model.text = "[Indexed Title](https://example.com)\n\n# Later Heading\n\nBody has nebula phrase"
    model.flushAutosave()

    model.commandPaletteQuery = "nebula"
    let notes = model.commandPaletteNotes()

    #expect(notes.count == 1)
    #expect(model.displayTitle(for: try #require(notes.first)) == "Indexed Title")
  }

  @Test("index failure does not block markdown autosave")
  func indexFailureDoesNotBlockAutosave() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }
    let model = LatticeAppModel(
      noteLibrary: fixture.library,
      folderAccessStore: fixture.folderAccessStore,
      noteIndex: FailingNoteIndex()
    )

    try fixture.fileManager.createDirectory(at: fixture.root, withIntermediateDirectories: true)
    model.chooseFolder(fixture.root)
    model.text = "# Still Saves\n\nBody"
    model.flushAutosave()

    let section = try #require(model.sections.first)
    let note = try #require(section.notes.first)
    #expect(try fixture.library.body(for: note) == "# Still Saves\n\nBody\n")

    model.commandPaletteQuery = "still"
    let fallbackNotes = model.commandPaletteNotes()
    #expect(fallbackNotes.count == 1)
  }

  @Test("wiki link click creates a linked note and persists target identity")
  func wikiLinkClickCreatesLinkedNote() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }
    let model = LatticeAppModel(
      noteLibrary: fixture.library,
      folderAccessStore: fixture.folderAccessStore,
      noteIndex: NoteIndex(appSupportURL: fixture.appSupportURL)
    )

    try fixture.fileManager.createDirectory(at: fixture.root, withIntermediateDirectories: true)
    model.chooseFolder(fixture.root)
    model.text = "# Source\n\nSee [[Project Plan]]"
    model.flushAutosave()
    let source = try #require(model.selectedNote)
    let linkLocation = (model.text as NSString).range(of: "[[Project Plan]]").location + 2

    model.activateWikiLink(at: linkLocation)

    let sections = model.sections
    #expect(sections.flatMap(\.notes).contains { $0.filenameTitle == "Project Plan" })
    #expect(model.selectedNote?.filenameTitle == "Project Plan")
    #expect(model.canNavigateBack)
    model.navigateBack()
    #expect(model.selectedNote == source)
    #expect(model.canNavigateForward)
    let sourceBody = try fixture.library.body(for: source)
    #expect(sourceBody.contains("[[Project Plan]]<!-- lattice:target="))
  }

  @Test("renaming a note rewrites wiki links while preserving aliases")
  func renameRewritesWikiLinks() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }
    let model = LatticeAppModel(
      noteLibrary: fixture.library,
      folderAccessStore: fixture.folderAccessStore,
      noteIndex: NoteIndex(appSupportURL: fixture.appSupportURL)
    )

    try fixture.fileManager.createDirectory(at: fixture.root, withIntermediateDirectories: true)
    model.chooseFolder(fixture.root)
    let target = try fixture.library.createLinkedNote(title: "Old Name")
    let targetID = try #require(MarkdownDocumentMetadata.noteID(in: try fixture.library.rawBody(for: target)))
    let source = try fixture.library.createNote(
      body: "# Source\n\nSee [[Old Name|alias]]\(WikiLinkParser.targetComment(noteID: targetID))"
    )

    model.beginRenaming(target)
    model.renameTitle = "New Name"
    model.commitRename()

    #expect(!fixture.fileManager.fileExists(atPath: target.url.path))
    let sourceBody = try fixture.library.body(for: source)
    #expect(sourceBody.contains("[[New Name|alias]]\(WikiLinkParser.targetComment(noteID: targetID))"))
  }

  @Test("deleting the selected note removes it and clears the editor")
  func deletingSelectedNoteClearsEditor() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }
    let model = LatticeAppModel(
      noteLibrary: fixture.library,
      folderAccessStore: fixture.folderAccessStore,
      noteIndex: NoteIndex(appSupportURL: fixture.appSupportURL)
    )

    try fixture.fileManager.createDirectory(at: fixture.root, withIntermediateDirectories: true)
    model.chooseFolder(fixture.root)
    model.text = "# Remove Me\n\nBody"
    model.flushAutosave()
    let note = try #require(model.selectedNote)

    model.delete(note)

    #expect(!fixture.fileManager.fileExists(atPath: note.url.path))
    #expect(model.selectedNote == nil)
    #expect(model.text == "")
    #expect(model.sections.isEmpty)
    #expect(fixture.library.activeNoteURL() == nil)
    #expect(model.commandPaletteNotes().isEmpty)
  }

  @Test("deleting another note keeps the current note open")
  func deletingUnselectedNoteKeepsCurrentNoteOpen() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }
    let model = LatticeAppModel(
      noteLibrary: fixture.library,
      folderAccessStore: fixture.folderAccessStore,
      noteIndex: NoteIndex(appSupportURL: fixture.appSupportURL)
    )

    try fixture.fileManager.createDirectory(at: fixture.root, withIntermediateDirectories: true)
    model.chooseFolder(fixture.root)
    model.text = "# Keep Me\n\nBody"
    model.flushAutosave()
    let keptNote = try #require(model.selectedNote)
    model.createNewNote()
    model.text = "# Delete Me\n\nBody"
    model.flushAutosave()
    let deletedNote = try #require(model.selectedNote)
    model.open(keptNote)

    model.delete(deletedNote)

    #expect(fixture.fileManager.fileExists(atPath: keptNote.url.path))
    #expect(!fixture.fileManager.fileExists(atPath: deletedNote.url.path))
    #expect(model.selectedNote == keptNote)
    #expect(model.text == "# Keep Me\n\nBody")
    #expect(model.sections.flatMap(\.notes) == [keptNote])
    #expect(fixture.library.activeNoteURL()?.path == keptNote.url.path)
  }

  @Test("missing heading links with duplicate note names do not open duplicate chooser")
  func missingHeadingDuplicateLinkDoesNotOpenChooser() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }
    let model = LatticeAppModel(
      noteLibrary: fixture.library,
      folderAccessStore: fixture.folderAccessStore,
      noteIndex: NoteIndex(appSupportURL: fixture.appSupportURL)
    )

    try fixture.fileManager.createDirectory(
      at: fixture.root.appendingPathComponent("notes/2026-06-25", isDirectory: true),
      withIntermediateDirectories: true
    )
    try fixture.fileManager.createDirectory(
      at: fixture.root.appendingPathComponent("notes/2026-06-24", isDirectory: true),
      withIntermediateDirectories: true
    )
    try "# Meeting Notes\n\n## Decisions\n".write(
      to: fixture.root.appendingPathComponent("notes/2026-06-25/Meeting Notes.md"),
      atomically: true,
      encoding: .utf8
    )
    try "# Meeting Notes\n\n## Decisions\n".write(
      to: fixture.root.appendingPathComponent("notes/2026-06-24/Meeting Notes.md"),
      atomically: true,
      encoding: .utf8
    )
    model.chooseFolder(fixture.root)
    model.text = "# Source\n\n[[Meeting Notes#Missing]]"
    model.flushAutosave()
    let source = try #require(model.selectedNote)

    model.activateWikiLink(at: (model.text as NSString).range(of: "[[Meeting Notes#Missing]]").location + 2)

    #expect(model.ambiguousWikiLink == nil)
    #expect(model.selectedNote == source)
  }

  @Test("periodic task sync pulls reminder completion into open note")
  func periodicTaskSyncPullsReminderCompletionIntoOpenNote() async throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }
    let store = TaskSyncStore(appSupportURL: fixture.appSupportURL, fileManager: fixture.fileManager)
    let provider = FakeTaskSyncProvider()
    let engine = TaskSyncEngine(store: store, provider: provider, fileManager: fixture.fileManager)

    try fixture.library.selectNotesFolder(fixture.root)
    let note = try fixture.library.createNote(body: "- [ ] Buy milk\n- [ ] ")
    try store.saveSettings(
      TaskSyncSettings(isEnabled: true, destinationID: "reminders", initialSyncConfirmed: true),
      notesFolderURL: fixture.root
    )

    let model = LatticeAppModel(
      noteLibrary: fixture.library,
      folderAccessStore: fixture.folderAccessStore,
      noteIndex: NoteIndex(appSupportURL: fixture.appSupportURL),
      taskSyncEngine: engine,
      taskSyncPollIntervalNanoseconds: 50_000_000
    )
    model.chooseFolder(fixture.root)
    model.open(note)

    await model.syncTasksNow()
    let externalID = try #require(provider.tasks.values.first?.externalID)
    provider.tasks[externalID] = TaskProviderTask(
      externalID: externalID,
      title: "Buy milk",
      isCompleted: true,
      destinationID: "reminders"
    )

    try await Task.sleep(nanoseconds: 200_000_000)

    #expect(model.text == "- [x] Buy milk\n- [ ] ")
    #expect(try fixture.library.body(for: note) == "- [x] Buy milk\n- [ ] \n")
  }

  @Test("autosave task sync pulls reminder completion without dropping note metadata")
  func autosaveTaskSyncPreservesNoteMetadata() async throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }
    let store = TaskSyncStore(appSupportURL: fixture.appSupportURL, fileManager: fixture.fileManager)
    let provider = FakeTaskSyncProvider()
    let engine = TaskSyncEngine(store: store, provider: provider, fileManager: fixture.fileManager)

    try fixture.library.selectNotesFolder(fixture.root)
    let note = try fixture.library.createNote(body: "- [ ] Buy milk")
    let noteID = try #require(MarkdownDocumentMetadata.noteID(in: try fixture.library.rawBody(for: note)))
    try store.saveSettings(
      TaskSyncSettings(isEnabled: true, destinationID: "reminders", initialSyncConfirmed: true),
      notesFolderURL: fixture.root
    )

    let model = LatticeAppModel(
      noteLibrary: fixture.library,
      folderAccessStore: fixture.folderAccessStore,
      noteIndex: NoteIndex(appSupportURL: fixture.appSupportURL),
      taskSyncEngine: engine,
      taskSyncPollIntervalNanoseconds: 0
    )
    model.chooseFolder(fixture.root)
    model.open(note)
    await model.syncTasksNow()
    let externalID = try #require(provider.tasks.values.first?.externalID)
    provider.tasks[externalID] = TaskProviderTask(
      externalID: externalID,
      title: "Buy milk",
      isCompleted: true,
      destinationID: "reminders"
    )

    model.text = "- [ ] Buy milk\nMore context"
    model.flushAutosave()
    try await Task.sleep(nanoseconds: 200_000_000)

    let rawBody = try fixture.library.rawBody(for: note)
    #expect(MarkdownDocumentMetadata.noteID(in: rawBody) == noteID)
    #expect(model.text == "- [x] Buy milk\nMore context")
    #expect(try fixture.library.body(for: note) == "- [x] Buy milk\nMore context\n")
  }
}

private struct Fixture {
  let root: URL
  let appSupportURL: URL
  let library: NoteLibrary
  let folderAccessStore: FolderAccessStore
  let activityStore: ActivityStore
  let defaults: UserDefaults
  let suiteName: String
  let fileManager = FileManager.default
  let calendar: Calendar

  init() throws {
    root = FileManager.default.temporaryDirectory
      .appendingPathComponent("lattice-app-model-\(UUID().uuidString)", isDirectory: true)
    appSupportURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("lattice-app-model-index-\(UUID().uuidString)", isDirectory: true)
    suiteName = "lattice-app-model-\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
      throw FixtureError.defaultsUnavailable
    }
    self.defaults = defaults
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
    self.calendar = calendar
    library = NoteLibrary(defaults: defaults, fileManager: fileManager)
    folderAccessStore = FolderAccessStore(defaults: defaults)
    activityStore = ActivityStore(fileManager: fileManager, calendar: calendar)
  }

  func date(day: Int = 26, hour: Int = 10) -> Date {
    var components = DateComponents()
    components.calendar = calendar
    components.timeZone = calendar.timeZone
    components.year = 2026
    components.month = 6
    components.day = day
    components.hour = hour
    components.minute = 15
    components.second = 0
    return components.date ?? Date(timeIntervalSince1970: 0)
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

private final class FailingNoteIndex: NoteIndexing {
  func rebuild(notesFolderURL: URL) throws {
    throw FixtureError.defaultsUnavailable
  }

  func refresh(note: SavedNote, notesFolderURL: URL) throws {
    throw FixtureError.defaultsUnavailable
  }

  func recentNotes(notesFolderURL: URL, limit: Int) throws -> [SavedNote] {
    throw FixtureError.defaultsUnavailable
  }

  func searchNotes(query: String, notesFolderURL: URL, limit: Int) throws -> [SavedNote] {
    throw FixtureError.defaultsUnavailable
  }

  func indexedNotes(notesFolderURL: URL, limit: Int) throws -> [IndexedNote] {
    throw FixtureError.defaultsUnavailable
  }

  func wikiNoteCandidates(stem: String, notesFolderURL: URL, limit: Int) throws -> [WikiNoteCandidate] {
    throw FixtureError.defaultsUnavailable
  }

  func wikiHeadingCandidates(
    noteID: String?,
    stem: String?,
    prefix: String,
    currentNote: SavedNote?,
    notesFolderURL: URL,
    limit: Int
  ) throws -> [WikiHeadingCandidate] {
    throw FixtureError.defaultsUnavailable
  }

  func wikiBacklinks(to noteID: String, notesFolderURL: URL, limit: Int) throws -> [WikiBacklink] {
    throw FixtureError.defaultsUnavailable
  }

  func wikiLinkRenderStates(
    body: String,
    currentNote: SavedNote?,
    notesFolderURL: URL
  ) throws -> [WikiLinkRenderState] {
    throw FixtureError.defaultsUnavailable
  }
}
