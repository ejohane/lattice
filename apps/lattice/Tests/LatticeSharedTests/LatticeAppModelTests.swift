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
      folderAccessStore: fixture.folderAccessStore,
      editorPreferencesStore: EditorPreferencesStore(defaults: fixture.defaults)
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

  @Test("indexes tags and filters the date-grouped sidebar")
  func filtersNotesByTag() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }
    let model = LatticeAppModel(
      noteLibrary: fixture.library,
      folderAccessStore: fixture.folderAccessStore,
      noteIndex: NoteIndex(appSupportURL: fixture.appSupportURL),
      dateProvider: { fixture.date() }
    )

    try fixture.fileManager.createDirectory(at: fixture.root, withIntermediateDirectories: true)
    model.chooseFolder(fixture.root)
    model.text = "# Work note\n\n#Work"
    model.flushAutosave()
    #expect(model.errorMessage == nil)
    let workNote = try #require(model.selectedNote)
    model.createNewNote()
    model.text = "# Personal note\n\n#personal"
    model.flushAutosave()

    #expect(model.tagSummaries.map(\.normalizedName) == ["personal", "work"])
    let workTag = try #require(model.tagSummaries.first { $0.normalizedName == "work" })
    model.selectTag(workTag)

    #expect(model.selectedTagName == "work")
    #expect(model.sections.flatMap(\.notes) == [workNote])
    #expect(model.selectedNote == workNote)

    model.selectTag(nil)
    #expect(model.sections.flatMap(\.notes).count == 2)
  }

  @Test("fully collapses navigation and restores the previous expanded layout")
  func togglesNavigationVisibility() {
    let model = LatticeAppModel()

    #expect(model.navigationVisibility == .all)
    model.setNavigationVisibility(.notesAndEditor)
    model.toggleNavigationVisibility()
    #expect(model.navigationVisibility == .editorOnly)

    model.toggleNavigationVisibility()
    #expect(model.navigationVisibility == .notesAndEditor)

    model.setNavigationVisibility(.all)
    model.toggleSourceVisibility()
    #expect(model.navigationVisibility == .notesAndEditor)
    model.toggleSourceVisibility()
    #expect(model.navigationVisibility == .all)

    model.toggleNavigationVisibility()
    model.toggleNavigationVisibility()
    #expect(model.navigationVisibility == .all)
  }

  @Test("suggests existing tags and commits autocomplete")
  func autocompletesTags() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }
    let model = LatticeAppModel(
      noteLibrary: fixture.library,
      folderAccessStore: fixture.folderAccessStore,
      noteIndex: NoteIndex(appSupportURL: fixture.appSupportURL),
      dateProvider: { fixture.date() }
    )

    try fixture.fileManager.createDirectory(at: fixture.root, withIntermediateDirectories: true)
    model.chooseFolder(fixture.root)
    model.text = "# Existing\n\n#Project/Lattice"
    model.flushAutosave()
    #expect(model.errorMessage == nil)
    model.text = "Plan #pro"
    model.selectedRange = NSRange(location: (model.text as NSString).length, length: 0)
    model.updateWikiAutocomplete()

    let suggestion = try #require(model.tagAutocompleteSuggestions.first)
    #expect(suggestion.name == "Project/Lattice")
    model.commitSelectedEditorAutocompleteSuggestion()
    #expect(model.text == "Plan #Project/Lattice")
  }

  @Test("creates and opens people through explicit mention autocomplete")
  func createsAndOpensPeopleFromAutocomplete() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }
    let index = NoteIndex(appSupportURL: fixture.appSupportURL)
    let model = LatticeAppModel(
      noteLibrary: fixture.library,
      folderAccessStore: fixture.folderAccessStore,
      noteIndex: index,
      dateProvider: { fixture.date() }
    )

    try fixture.fileManager.createDirectory(at: fixture.root, withIntermediateDirectories: true)
    model.chooseFolder(fixture.root)
    model.text = "Met with @Erik Johansson"
    model.selectedRange = NSRange(location: (model.text as NSString).length, length: 0)
    model.updateWikiAutocomplete()

    let createSuggestion = try #require(model.personAutocompleteSuggestions.first)
    #expect(createSuggestion.name == "Erik Johansson")
    #expect(createSuggestion.targetNoteID == nil)
    model.commitSelectedEditorAutocompleteSuggestion()

    let person = try #require(try index.personCandidates(
      prefix: "Erik",
      notesFolderURL: fixture.root,
      limit: 10
    ).first)
    #expect(model.text == "Met with \(PersonMentionParser.replacement(name: "Erik Johansson", noteID: person.noteID))")
    #expect(MarkdownDocumentMetadata.kind(in: try fixture.library.rawBody(for: person.note)) == .person)
    #expect(model.selectedNote == nil)

    model.flushAutosave()
    let source = try #require(model.selectedNote)
    let sourceID = try #require(MarkdownDocumentMetadata.noteID(in: try fixture.library.rawBody(for: source)))
    #expect(try index.personMentions(from: sourceID, notesFolderURL: fixture.root).count == 1)

    let mention = try #require(PersonMentionParser.mentions(in: model.text).first)
    model.activatePersonMention(at: mention.range.location + 2)
    #expect(model.selectedNote == person.note)
    #expect(model.text == "# Erik Johansson")
  }

  @Test("renames and deletes tags across notes")
  func managesTagsGlobally() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }
    let model = LatticeAppModel(
      noteLibrary: fixture.library,
      folderAccessStore: fixture.folderAccessStore,
      noteIndex: NoteIndex(appSupportURL: fixture.appSupportURL),
      dateProvider: { fixture.date() }
    )

    try fixture.fileManager.createDirectory(at: fixture.root, withIntermediateDirectories: true)
    model.chooseFolder(fixture.root)
    model.text = "# First\n\n#Work"
    model.flushAutosave()
    model.createNewNote()
    model.text = "# Second\n\n#work"
    model.flushAutosave()
    #expect(model.errorMessage == nil)

    let workTag = try #require(model.tagSummaries.first { $0.normalizedName == "work" })
    model.beginRenamingTag(workTag)
    model.renameTagName = "career"
    model.commitTagRename()

    let notes = try fixture.library.listNotes().flatMap(\.notes)
    #expect(model.tagSummaries.map(\.normalizedName) == ["career"])
    #expect(try notes.allSatisfy { try fixture.library.body(for: $0).contains("#career") })

    let careerTag = try #require(model.tagSummaries.first)
    model.requestTagDeletion(careerTag)
    model.confirmTagDeletion()

    #expect(model.tagSummaries.isEmpty)
    #expect(try notes.allSatisfy { try !fixture.library.body(for: $0).contains("#career") })
  }

  @Test("today slash command creates a daily note and inserts a durable fixed-date link")
  func insertsTodaySlashCommand() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }
    let now = fixture.date()
    let model = LatticeAppModel(
      noteLibrary: fixture.library,
      folderAccessStore: fixture.folderAccessStore,
      noteIndex: NoteIndex(appSupportURL: fixture.appSupportURL),
      dateProvider: { now }
    )

    try fixture.fileManager.createDirectory(at: fixture.root, withIntermediateDirectories: true)
    model.chooseFolder(fixture.root)
    model.text = "Decision /to"
    model.selectedRange = NSRange(location: (model.text as NSString).length, length: 0)
    model.updateWikiAutocomplete()

    let suggestion = try #require(model.slashCommandSuggestions.first)
    #expect(suggestion.command == "today")
    #expect(model.selectedNote == nil)
    model.commitSelectedEditorAutocompleteSuggestion()

    let dailyURL = fixture.root.appendingPathComponent("notes/2026-06-26.md")
    let dailyRawBody = try String(contentsOf: dailyURL, encoding: .utf8)
    let dailyID = try #require(MarkdownDocumentMetadata.noteID(in: dailyRawBody))
    #expect(model.text == "Decision [[2026-06-26]]\(WikiLinkParser.targetComment(noteID: dailyID))")
    #expect(model.slashCommandSuggestions.isEmpty)
    #expect(model.selectedNote == nil)
    #expect(MarkdownDocumentMetadata.strippingFrontMatter(from: dailyRawBody).hasPrefix("# Friday, June 26, 2026"))
  }

  @Test("today palette command creates, opens, and reuses the canonical daily note")
  func opensTodayNoteFromCommandPalette() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }
    let now = fixture.date()
    let model = LatticeAppModel(
      noteLibrary: fixture.library,
      folderAccessStore: fixture.folderAccessStore,
      noteIndex: NoteIndex(appSupportURL: fixture.appSupportURL),
      dateProvider: { now }
    )

    try fixture.fileManager.createDirectory(at: fixture.root, withIntermediateDirectories: true)
    model.chooseFolder(fixture.root)
    model.text = "# Source Note\n\nUnsaved context"

    let command = try #require(model.commandPaletteCommands().first { $0.title == "Today’s Note" })
    #expect(command.subtitle == "Create or open today’s daily note")
    #expect(command.keyboardShortcut == nil)
    command.perform()

    let dailyNote = try #require(model.selectedNote)
    #expect(dailyNote.filenameTitle == "2026-06-26")
    #expect(model.text == "# Friday, June 26, 2026")
    #expect(model.selectedRange.location == (model.text as NSString).length)
    #expect(try fixture.library.listNotes().flatMap(\.notes).count == 2)

    model.text += "\n\nJournal entry"
    model.flushAutosave()
    let sourceNote = try #require(
      try fixture.library.listNotes().flatMap(\.notes).first { $0.filenameTitle == "Source Note" }
    )
    model.open(sourceNote)
    command.perform()

    #expect(model.selectedNote?.url == dailyNote.url)
    #expect(model.text.contains("Journal entry"))
    #expect(try fixture.library.listNotes().flatMap(\.notes).count == 2)
  }

  @Test("legacy folders prompt once and migrate through the app model")
  func promptsForAndRunsFlatNoteMigration() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }
    let legacyURL = fixture.root.appendingPathComponent(
      "notes/2026-06-25/2026-06-25T09-00-00.md"
    )
    try fixture.fileManager.createDirectory(
      at: legacyURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try "# Legacy Note\n\nBody".write(to: legacyURL, atomically: true, encoding: .utf8)
    let model = LatticeAppModel(
      noteLibrary: fixture.library,
      folderAccessStore: fixture.folderAccessStore,
      noteIndex: NoteIndex(appSupportURL: fixture.appSupportURL),
      dateProvider: { fixture.date() }
    )

    model.chooseFolder(fixture.root)
    #expect(model.isNoteMigrationRequired)
    #expect(model.isShowingNoteMigrationPrompt)
    #expect(!model.commandPaletteCommands().contains { $0.title == "Today’s Note" })

    model.deferNoteMigration()
    #expect(!model.isShowingNoteMigrationPrompt)
    #expect(fixture.fileManager.fileExists(atPath: legacyURL.path))

    model.showNoteMigrationPrompt()
    model.migrateNotesToFlatLayout()

    #expect(!model.isNoteMigrationRequired)
    #expect(model.noteMigrationSummary != nil)
    #expect(model.commandPaletteCommands().contains { $0.title == "Today’s Note" })
    #expect(fixture.fileManager.fileExists(
      atPath: fixture.root.appendingPathComponent("notes/Legacy Note.md").path
    ))
    #expect(!fixture.fileManager.fileExists(atPath: legacyURL.path))
  }

  @Test("start restores the last active note instead of creating a new draft")
  func startRestoresLastActiveNote() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }
    let now = fixture.date()

    try fixture.library.selectNotesFolder(fixture.root)
    let lastNote = try fixture.library.createNote(body: "# Last Open\n\nContinue here", now: now)

    let model = LatticeAppModel(
      noteLibrary: fixture.library,
      folderAccessStore: fixture.folderAccessStore,
      noteIndex: NoteIndex(appSupportURL: fixture.appSupportURL),
      dateProvider: { now }
    )

    model.start()

    #expect(model.selectedNote == lastNote)
    #expect(model.text == "# Last Open\n\nContinue here")
    #expect(model.sections.flatMap(\.notes) == [lastNote])
    #expect(try fixture.library.listNotes().flatMap(\.notes) == [lastNote])
  }

  @Test("indents and outdents selected list items")
  func indentsAndOutdentsSelectedListItems() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }
    let model = LatticeAppModel(
      noteLibrary: fixture.library,
      folderAccessStore: fixture.folderAccessStore
    )

    model.text = "- Parent\n- Child"
    model.selectedRange = (model.text as NSString).range(of: "Child")

    model.indentSelectedListItems()
    #expect(model.text == "- Parent\n    - Child")
    #expect((model.text as NSString).substring(with: model.selectedRange) == "Child")

    model.outdentSelectedListItems()
    #expect(model.text == "- Parent\n- Child")
    #expect((model.text as NSString).substring(with: model.selectedRange) == "Child")
  }

  @Test("formats markdown table columns when selection leaves the table")
  func formatsMarkdownTablesWhenSelectionLeavesTable() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }
    let model = LatticeAppModel(
      noteLibrary: fixture.library,
      folderAccessStore: fixture.folderAccessStore
    )
    model.setEditorMode(.rendered)

    model.text = """
    | Project | Status |
    | --- | --- |
    | Lattice | Ship |

    After
    """
    model.selectedRange = NSRange(location: (model.text as NSString).range(of: "After").location, length: 0)

    model.noteSelectionDidChange()

    #expect(model.text == """
    | Project | Status |
    | ------- | ------ |
    | Lattice | Ship   |

    After
    """)
    #expect((model.text as NSString).substring(from: model.selectedRange.location).hasPrefix("After"))
  }

  @Test("raw mode does not format markdown tables when selection changes")
  func rawModeLeavesMarkdownTableTextLiteral() {
    let model = LatticeAppModel()
    model.setEditorMode(.raw)
    model.text = """
    | Project | Status |
    | --- | --- |
    | Lattice | Ship |

    After
    """
    let original = model.text
    model.selectedRange = NSRange(location: (model.text as NSString).range(of: "After").location, length: 0)

    model.noteSelectionDidChange()

    #expect(model.text == original)
  }

  @Test("inserts image attachments into a new note and autosaves matching paths")
  func insertsImageAttachmentIntoNewNote() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }
    let now = fixture.date(day: 27, hour: 23)
    let model = LatticeAppModel(
      noteLibrary: fixture.library,
      folderAccessStore: fixture.folderAccessStore,
      dateProvider: { now }
    )

    try fixture.fileManager.createDirectory(at: fixture.root, withIntermediateDirectories: true)
    model.chooseFolder(fixture.root)
    model.insertImageAttachments([
      ImageAttachmentImport(
        data: Data("png-bytes".utf8),
        suggestedFilename: "Screen Shot.png",
        preferredExtension: "png"
      )
    ])

    let note = try #require(model.selectedNote)
    let attachmentDate = fixture.localDateString(from: now)
    let attachmentName = "Screen Shot-\(fixture.timestampString(from: now)).png"
    let expectedMarkdown = "![Screen Shot](../attachments/\(attachmentDate)/\(attachmentName))\n"
    #expect(note.url.path.hasSuffix("/notes/Screen Shot.md"))
    #expect(model.text == expectedMarkdown)
    #expect(model.selectedRange.location == (model.text as NSString).range(of: ")").location + 1)
    #expect(try fixture.library.body(for: note) == model.text)
    #expect(try Data(contentsOf: fixture.root.appendingPathComponent("attachments/\(attachmentDate)/\(attachmentName)")) == Data("png-bytes".utf8))
    #expect(model.imagePreviewStates.count == 1)
  }

  @Test("image attachments replace selected text in existing notes")
  func imageAttachmentsReplaceSelectedText() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }
    let now = fixture.date()
    let model = LatticeAppModel(
      noteLibrary: fixture.library,
      folderAccessStore: fixture.folderAccessStore,
      dateProvider: { now }
    )

    try fixture.fileManager.createDirectory(at: fixture.root, withIntermediateDirectories: true)
    try fixture.library.selectNotesFolder(fixture.root)
    let note = try fixture.library.createNote(body: "Before old after", now: now)
    let existingID = try #require(MarkdownDocumentMetadata.noteID(in: fixture.library.rawBody(for: note)))
    model.chooseFolder(fixture.root)
    model.open(note)
    model.selectedRange = (model.text as NSString).range(of: "old")

    model.insertImageAttachments([
      ImageAttachmentImport(
        data: Data("image".utf8),
        suggestedFilename: "diagram.jpg",
        preferredExtension: "jpg"
      )
    ])

    let attachmentDate = fixture.localDateString(from: now)
    let attachmentName = "diagram-\(fixture.timestampString(from: now)).jpg"
    #expect(model.text == "Before \n\n![diagram](../attachments/\(attachmentDate)/\(attachmentName))\n\n after")
    #expect(try fixture.library.body(for: note) == "\(model.text)\n")
    #expect(MarkdownDocumentMetadata.noteID(in: try fixture.library.rawBody(for: note)) == existingID)
    #expect(model.imagePreviewStates.count == 1)
  }

  @Test("resizing image attachments persists obsidian width syntax")
  func resizingImageAttachmentsPersistsWidthSyntax() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }
    let model = LatticeAppModel(
      noteLibrary: fixture.library,
      folderAccessStore: fixture.folderAccessStore
    )

    try fixture.fileManager.createDirectory(at: fixture.root, withIntermediateDirectories: true)
    try fixture.library.selectNotesFolder(fixture.root)
    let attachmentURL = fixture.root.appendingPathComponent("attachments/2026-06-26/image.png")
    try fixture.fileManager.createDirectory(at: attachmentURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("image".utf8).write(to: attachmentURL)
    let note = try fixture.library.createNote(
      body: "Before\n\n![Screenshot](../attachments/2026-06-26/image.png)\n\nAfter",
      now: fixture.date()
    )

    model.chooseFolder(fixture.root)
    model.open(note)
    let image = try #require(MarkdownImageParser.links(in: model.text).first)
    model.resizeImageAttachment(lineLocation: image.lineRange.location, width: 720)
    model.flushAutosave()

    #expect(model.text.contains("![Screenshot|720](../attachments/2026-06-26/image.png)"))
    #expect(model.imagePreviewStates.first?.link.width == 720)
    #expect(try fixture.library.body(for: note).contains("![Screenshot|720](../attachments/2026-06-26/image.png)"))
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

  @Test("external note creation refreshes the note list")
  func externalNoteCreationRefreshesNoteList() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }
    let model = LatticeAppModel(
      noteLibrary: fixture.library,
      folderAccessStore: fixture.folderAccessStore,
      noteIndex: NoteIndex(appSupportURL: fixture.appSupportURL)
    )

    try fixture.fileManager.createDirectory(at: fixture.root, withIntermediateDirectories: true)
    model.chooseFolder(fixture.root)
    #expect(model.sections.isEmpty)

    _ = try fixture.library.createNote(body: "Remote note", now: fixture.date())

    model.refreshExternalChanges()

    #expect(model.sections.flatMap(\.notes).count == 1)
    #expect(model.status == "Notes updated")
  }

  @Test("external selected note changes reload a clean editor")
  func externalSelectedNoteChangesReloadCleanEditor() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }
    let model = LatticeAppModel(
      noteLibrary: fixture.library,
      folderAccessStore: fixture.folderAccessStore,
      noteIndex: NoteIndex(appSupportURL: fixture.appSupportURL)
    )

    try fixture.fileManager.createDirectory(at: fixture.root, withIntermediateDirectories: true)
    model.chooseFolder(fixture.root)
    model.text = "Original"
    model.flushAutosave()
    let note = try #require(model.selectedNote)

    try fixture.library.updateNote(note, body: "Updated elsewhere")

    model.refreshExternalChanges()

    #expect(model.text == "Updated elsewhere")
    #expect(model.selectedNote == note)
  }

  @Test("external selected note changes do not overwrite a dirty editor")
  func externalSelectedNoteChangesDoNotOverwriteDirtyEditor() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }
    let model = LatticeAppModel(
      noteLibrary: fixture.library,
      folderAccessStore: fixture.folderAccessStore,
      noteIndex: NoteIndex(appSupportURL: fixture.appSupportURL)
    )

    try fixture.fileManager.createDirectory(at: fixture.root, withIntermediateDirectories: true)
    model.chooseFolder(fixture.root)
    model.text = "Original"
    model.flushAutosave()
    let note = try #require(model.selectedNote)

    model.text = "Local unsaved edit"
    try fixture.library.updateNote(note, body: "Updated elsewhere")

    model.refreshExternalChanges()

    #expect(model.text == "Local unsaved edit")
    #expect(model.status == "Changed on another device; local edits are still open")
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
    #expect(model.selectedThemeID == .system)
    #expect(model.editorMode == .raw)
    #expect(model.vimState.mode == .insert)

    model.setEditorMode(.rendered)
    model.setVimModeEnabled(true)
    model.setRelativeLineNumbersEnabled(true)
    model.setTheme(.solarizedDark)
    model.setKeyboardShortcut(
      LatticeKeyboardShortcut(key: "b", modifiers: [.command, .shift]),
      for: .zenMode
    )

    let restored = LatticeAppModel(
      noteLibrary: NoteLibrary(defaults: defaults),
      folderAccessStore: FolderAccessStore(defaults: defaults),
      editorPreferencesStore: EditorPreferencesStore(defaults: defaults)
    )

    #expect(restored.isVimModeEnabled)
    #expect(restored.showsRelativeLineNumbers)
    #expect(restored.selectedThemeID == .solarizedDark)
    #expect(restored.editorMode == .rendered)
    #expect(restored.vimState.mode == .insert)
    #expect(!restored.effectiveIsVimModeEnabled)
    #expect(!restored.effectiveShowsRelativeLineNumbers)
    #expect(restored.keyboardShortcut(for: .zenMode) == LatticeKeyboardShortcut(key: "b", modifiers: [.command, .shift]))
  }

  @Test("editor mode defaults to raw and switches without mutating the draft")
  func editorModeDefaultsAndSwitchesWithoutMutatingDraft() throws {
    let suiteName = "editor-mode-default-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let model = LatticeAppModel(
      noteLibrary: NoteLibrary(defaults: defaults),
      folderAccessStore: FolderAccessStore(defaults: defaults),
      editorPreferencesStore: EditorPreferencesStore(defaults: defaults)
    )
    model.text = "# Heading\n\n- [ ] Task\n[[Note]]<!-- lattice:target=abc -->"
    model.selectedRange = NSRange(location: 4, length: 3)
    let originalText = model.text
    let originalSelection = model.selectedRange
    let originalFocusToken = model.editorFocusToken

    #expect(model.editorMode == .raw)
    model.setEditorMode(.rendered)

    #expect(model.editorMode == .rendered)
    #expect(model.text == originalText)
    #expect(model.selectedRange == originalSelection)
    #expect(model.editorFocusToken == originalFocusToken + 1)

    model.setEditorMode(.raw)
    #expect(model.text == originalText)
    #expect(model.selectedRange == originalSelection)
  }

  @Test("vim and relative line numbers are effective only in raw mode")
  func editorModeGatesRawCapabilities() throws {
    let suiteName = "editor-mode-capabilities-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let model = LatticeAppModel(
      noteLibrary: NoteLibrary(defaults: defaults),
      folderAccessStore: FolderAccessStore(defaults: defaults),
      editorPreferencesStore: EditorPreferencesStore(defaults: defaults)
    )
    model.setVimModeEnabled(true)
    model.setRelativeLineNumbersEnabled(true)

    #expect(model.effectiveIsVimModeEnabled)
    #expect(model.effectiveShowsRelativeLineNumbers)

    model.setEditorMode(.rendered)
    #expect(!model.effectiveIsVimModeEnabled)
    #expect(!model.effectiveShowsRelativeLineNumbers)
    #expect(model.vimState.mode == .insert)

    model.setEditorMode(.raw)
    #expect(model.effectiveIsVimModeEnabled)
    #expect(model.effectiveShowsRelativeLineNumbers)
    #expect(model.vimState.mode == .normal)
  }

  @Test("keyboard shortcuts can override conflicts and reset to defaults")
  func keyboardShortcutOverridesConflictsAndResets() throws {
    let defaultsSuiteName = "keyboard-shortcuts-\(UUID().uuidString)"
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

    let newNoteShortcut = try #require(model.keyboardShortcut(for: .newNote))
    model.setKeyboardShortcut(newNoteShortcut, for: .zenMode)

    #expect(model.keyboardShortcut(for: .zenMode) == newNoteShortcut)
    #expect(model.keyboardShortcut(for: .newNote) == nil)

    let restored = LatticeAppModel(
      noteLibrary: NoteLibrary(defaults: defaults),
      folderAccessStore: FolderAccessStore(defaults: defaults),
      editorPreferencesStore: EditorPreferencesStore(defaults: defaults)
    )

    #expect(restored.keyboardShortcut(for: .zenMode) == newNoteShortcut)
    #expect(restored.keyboardShortcut(for: .newNote) == nil)

    restored.resetKeyboardShortcut(for: .newNote)
    #expect(restored.keyboardShortcut(for: .newNote) == LatticeKeyboardShortcutID.newNote.defaultShortcut)
    #expect(restored.keyboardShortcut(for: .zenMode) == nil)

    restored.resetKeyboardShortcut(for: .zenMode)
    #expect(restored.keyboardShortcut(for: .zenMode) == LatticeKeyboardShortcutID.zenMode.defaultShortcut)
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

  @Test("suggests notes while typing wiki links")
  func suggestsNotesWhileTypingWikiLinks() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }
    let model = LatticeAppModel(
      noteLibrary: fixture.library,
      folderAccessStore: fixture.folderAccessStore,
      noteIndex: NoteIndex(appSupportURL: fixture.appSupportURL)
    )

    try fixture.fileManager.createDirectory(at: fixture.root, withIntermediateDirectories: true)
    try fixture.library.selectNotesFolder(fixture.root)
    let created = try fixture.library.createNote(body: "# Deep Link Notes", now: fixture.date())
    let target = try fixture.library.renameNote(created, to: "Deep Link Notes")
    model.chooseFolder(fixture.root)
    model.text = "See [[deep"
    model.selectedRange = NSRange(location: (model.text as NSString).length, length: 0)

    model.updateWikiAutocomplete()

    #expect(model.wikiAutocompleteSuggestions.map(\.title).contains(target.filenameTitle))
  }

  @Test("suggests notes by rendered sidebar title while typing wiki links")
  func suggestsNotesByRenderedSidebarTitleWhileTypingWikiLinks() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }
    let model = LatticeAppModel(
      noteLibrary: fixture.library,
      folderAccessStore: fixture.folderAccessStore,
      noteIndex: NoteIndex(appSupportURL: fixture.appSupportURL)
    )

    try fixture.fileManager.createDirectory(at: fixture.root, withIntermediateDirectories: true)
    try fixture.library.selectNotesFolder(fixture.root)
    let target = try fixture.library.createNote(body: "Pocket Closet\n\nInventory", now: fixture.date(day: 4))
    let targetID = try #require(MarkdownDocumentMetadata.noteID(in: fixture.library.rawBody(for: target)))
    let expectedReplacement = "[[Pocket Closet]]\(WikiLinkParser.targetComment(noteID: targetID))"
    model.chooseFolder(fixture.root)
    model.text = "See [[pocket"
    model.selectedRange = NSRange(location: (model.text as NSString).length, length: 0)

    model.updateWikiAutocomplete()

    let suggestion = try #require(model.wikiAutocompleteSuggestions.first)
    #expect(suggestion.title == "Pocket Closet")
    #expect(suggestion.subtitle.hasSuffix("/\(target.filenameTitle).md"))
    #expect(suggestion.replacement == expectedReplacement)
  }

  @Test("moves and commits selected wiki autocomplete suggestion")
  func movesAndCommitsSelectedWikiAutocompleteSuggestion() {
    let model = LatticeAppModel()
    model.text = "See [["
    model.selectedRange = NSRange(location: (model.text as NSString).length, length: 0)
    model.wikiAutocompleteSuggestions = [
      WikiAutocompleteSuggestion(
        title: "Alpha",
        subtitle: "notes/Alpha.md",
        replacement: "[[Alpha]]",
        replacementRange: NSRange(location: 4, length: 2)
      ),
      WikiAutocompleteSuggestion(
        title: "Beta",
        subtitle: "notes/Beta.md",
        replacement: "[[Beta]]",
        replacementRange: NSRange(location: 4, length: 2)
      )
    ]

    model.moveWikiAutocompleteSelection(by: 1)
    #expect(model.wikiAutocompleteSelectionIndex == 1)

    model.moveWikiAutocompleteSelection(by: 1)
    #expect(model.wikiAutocompleteSelectionIndex == 0)

    model.moveWikiAutocompleteSelection(by: -1)
    #expect(model.wikiAutocompleteSelectionIndex == 1)

    model.commitSelectedWikiAutocompleteSuggestion()

    #expect(model.text == "See [[Beta]]")
    #expect(model.selectedRange.location == (model.text as NSString).length)
    #expect(model.wikiAutocompleteSuggestions.isEmpty)
    #expect(model.wikiAutocompleteSelectionIndex == 0)
  }

  @Test("skips synchronous editor decoration refresh while typing")
  func skipsSynchronousEditorDecorationRefreshWhileTyping() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }
    let noteIndex = CountingNoteIndex()
    let model = LatticeAppModel(
      noteLibrary: fixture.library,
      folderAccessStore: fixture.folderAccessStore,
      noteIndex: noteIndex
    )

    try fixture.fileManager.createDirectory(at: fixture.root, withIntermediateDirectories: true)
    model.chooseFolder(fixture.root)
    noteIndex.wikiLinkRenderStateCallCount = 0
    model.text = "Draft body"
    model.selectedRange = NSRange(location: (model.text as NSString).length, length: 0)

    model.noteTextDidChange()

    #expect(noteIndex.wikiLinkRenderStateCallCount == 0)
    model.flushAutosave()
    #expect(noteIndex.wikiLinkRenderStateCallCount > 0)
  }

  @Test("zen mode is session-only and suppresses vim while active")
  func zenModeIsSessionOnlyAndSuppressesVimWhileActive() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }
    let model = LatticeAppModel(
      noteLibrary: fixture.library,
      folderAccessStore: fixture.folderAccessStore,
      editorPreferencesStore: EditorPreferencesStore(defaults: fixture.defaults)
    )

    try fixture.fileManager.createDirectory(at: fixture.root, withIntermediateDirectories: true)
    model.chooseFolder(fixture.root)
    model.setVimModeEnabled(true)

    #expect(model.isVimModeEnabled)
    #expect(model.effectiveIsVimModeEnabled)

    model.enterZenMode()

    #expect(model.isZenModeEnabled)
    #expect(model.isVimModeEnabled)
    #expect(!model.effectiveIsVimModeEnabled)

    model.exitZenMode()

    #expect(!model.isZenModeEnabled)
    #expect(model.isVimModeEnabled)
    #expect(model.effectiveIsVimModeEnabled)

    let enterCommand = try #require(model.commandPaletteCommands().first { $0.title == "Enter Zen Mode" })
    enterCommand.perform()
    #expect(model.isZenModeEnabled)

    let exitCommand = try #require(model.commandPaletteCommands().first { $0.title == "Exit Zen Mode" })
    exitCommand.perform()
    #expect(!model.isZenModeEnabled)
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

  @Test("context pack starts from the current selection and flushes autosave")
  func contextPackStartsFromCurrentSelection() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }
    let model = LatticeAppModel(
      noteLibrary: fixture.library,
      folderAccessStore: fixture.folderAccessStore,
      noteIndex: NoteIndex(appSupportURL: fixture.appSupportURL),
      dateProvider: { fixture.date() }
    )

    try fixture.fileManager.createDirectory(at: fixture.root, withIntermediateDirectories: true)
    model.chooseFolder(fixture.root)
    model.text = "Project plan\n\nKeep this paragraph.\n\nLeave this out."
    let selectedText = "Keep this paragraph."
    model.selectedRange = (model.text as NSString).range(of: selectedText)

    model.showContextPack()

    let source = try #require(model.contextPackSources.first)
    #expect(model.selectedNote != nil)
    #expect(model.isShowingContextPack)
    #expect(source.body == selectedText)
    #expect(source.isExcerpt)
    #expect(source.displayTitle == "Project plan (selection)")
    #expect(model.contextPackMarkdown.contains("## Project plan (selection)\n\nKeep this paragraph."))
    #expect(!model.contextPackMarkdown.contains("Leave this out."))
  }

  @Test("context pack adds unique notes reorders them and discards its draft")
  func contextPackAddsReordersAndDiscardsSources() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }
    let model = LatticeAppModel(
      noteLibrary: fixture.library,
      folderAccessStore: fixture.folderAccessStore,
      noteIndex: NoteIndex(appSupportURL: fixture.appSupportURL),
      dateProvider: { fixture.date() }
    )

    try fixture.fileManager.createDirectory(at: fixture.root, withIntermediateDirectories: true)
    model.chooseFolder(fixture.root)
    model.text = "First source\n\nAlpha details"
    model.flushAutosave()
    model.createNewNote()
    model.text = "Second source\n\nBeta details"
    model.flushAutosave()

    model.showContextPack()
    model.contextPackSearchQuery = "first"
    let firstNote = try #require(model.contextPackSearchNotes().first)
    model.addNoteToContextPack(firstNote)
    model.addNoteToContextPack(firstNote)

    #expect(model.contextPackSources.map { $0.title } == ["Second source", "First source"])
    #expect(model.contextPackSources.count == 2)

    model.moveContextPackSource(id: firstNote.id, by: -1)
    #expect(model.contextPackSources.map { $0.title } == ["First source", "Second source"])
    #expect(model.contextPackMarkdown.range(of: "## First source")!.lowerBound
      < model.contextPackMarkdown.range(of: "## Second source")!.lowerBound)

    model.contextPackTask = "Summarize both sources."
    #expect(model.contextPackCharacterCount == model.contextPackMarkdown.count)
    #expect(model.contextPackApproximateTokenCount > 0)

    model.dismissContextPack()
    #expect(!model.isShowingContextPack)
    #expect(model.contextPackTask.isEmpty)
    #expect(model.contextPackSources.isEmpty)
    #expect(model.contextPackGeneratedAt == nil)
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
    #expect(commandTitles.contains("Enter Zen Mode"))
    #expect(commandTitles.contains("Today’s Note"))
    #expect(commandTitles.contains("New Note"))
    #expect(!commandTitles.contains("Heading"))
    #expect(!commandTitles.contains("Bold"))
    #expect(!commandTitles.contains("Italic"))
    #expect(!commandTitles.contains("List"))
    #expect(!commandTitles.contains("Code"))
    #expect(!commandTitles.contains("Link"))
    #expect(!commandTitles.contains("Increase Font Size"))

    let commandShortcuts = Dictionary(uniqueKeysWithValues: model.commandPaletteCommands().map {
      ($0.title, $0.keyboardShortcut)
    })
    #expect(commandShortcuts["Enter Zen Mode"] == "Cmd-Shift-Z")
    #expect(commandShortcuts["New Note"] == "Cmd-N")
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

    let savedNote = try #require(model.selectedNote)
    let preview = try #require(model.notePreviews[savedNote.id])
    #expect(preview.title == "Indexed Title")
    #expect(preview.modifiedAt != nil)

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
    #expect(model.notePreviews.isEmpty)

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
    let migrationBackupRoot = appSupportURL.appendingPathComponent("Migration Backups", isDirectory: true)
    library = NoteLibrary(
      defaults: defaults,
      fileManager: fileManager,
      migrationBackupRootURLProvider: { migrationBackupRoot }
    )
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

  func localDateString(from date: Date) -> String {
    dateString(from: date, format: "yyyy-MM-dd")
  }

  func timestampString(from date: Date) -> String {
    dateString(from: date, format: "yyyy-MM-dd'T'HH-mm-ss")
  }

  private func dateString(from date: Date, format: String) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.dateFormat = format
    return formatter.string(from: date)
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

private final class CountingNoteIndex: NoteIndexing {
  var wikiLinkRenderStateCallCount = 0

  func rebuild(notesFolderURL: URL) throws {}

  func refresh(note: SavedNote, notesFolderURL: URL) throws {}

  func recentNotes(notesFolderURL: URL, limit: Int) throws -> [SavedNote] {
    []
  }

  func searchNotes(query: String, notesFolderURL: URL, limit: Int) throws -> [SavedNote] {
    []
  }

  func indexedNotes(notesFolderURL: URL, limit: Int) throws -> [IndexedNote] {
    []
  }

  func wikiNoteCandidates(stem: String, notesFolderURL: URL, limit: Int) throws -> [WikiNoteCandidate] {
    []
  }

  func wikiHeadingCandidates(
    noteID: String?,
    stem: String?,
    prefix: String,
    currentNote: SavedNote?,
    notesFolderURL: URL,
    limit: Int
  ) throws -> [WikiHeadingCandidate] {
    []
  }

  func wikiBacklinks(to noteID: String, notesFolderURL: URL, limit: Int) throws -> [WikiBacklink] {
    []
  }

  func wikiLinkRenderStates(
    body: String,
    currentNote: SavedNote?,
    notesFolderURL: URL
  ) throws -> [WikiLinkRenderState] {
    wikiLinkRenderStateCallCount += 1
    return []
  }
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
