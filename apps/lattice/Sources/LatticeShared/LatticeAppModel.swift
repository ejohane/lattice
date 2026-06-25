import Foundation
import LatticeCore
import LatticeEditor
import Observation

@MainActor
@Observable
public final class LatticeAppModel {
  private let folderAccessStore: FolderAccessStore
  public let noteLibrary: NoteLibrary
  private let noteIndex: any NoteIndexing
  private let taskSyncEngine: TaskSyncEngine
  private let taskSyncPollIntervalNanoseconds: UInt64
  private let session: NoteEditingSession
  private var autosaveWorkItem: DispatchWorkItem?
  private var taskSyncPollTask: Task<Void, Never>?
  private var scopedFolderURL: URL?

  public var sections: [NoteSection] = []
  public var noteTitles: [String: String] = [:]
  public var text = ""
  public var selectedRange = NSRange(location: 0, length: 0)
  public var selectedNote: SavedNote?
  public var folderURL: URL?
  public var status = "Choose a notes folder"
  public var errorMessage: String?
  public var isShowingFolderImporter = false
  public var isShowingCommandPalette = false
  public var isShowingSettings = false
  public var commandPaletteQuery = ""
  public var preferredCompactColumn = NavigationColumn.sidebar
  public var editorFocusToken = 0
  public var editorFontSize = 14.0
  public var wikiLinkStates: [WikiLinkRenderState] = []
  public var wikiAutocompleteSuggestions: [WikiAutocompleteSuggestion] = []
  public var ambiguousWikiLink: AmbiguousWikiLinkResolution?
  public var renamingNote: SavedNote?
  public var renameTitle = ""
  public var taskSyncProviderName = "Apple Reminders"
  public var taskSyncAuthorizationStatus = TaskProviderAuthorizationStatus.notDetermined
  public var taskSyncDestinations: [TaskDestination] = []
  public var selectedTaskDestinationID: String?
  public var isTaskSyncEnabled = false
  public var taskSyncStatus = "Task sync is off"
  public var taskSyncErrorMessage: String?
  public var pendingInitialSyncTaskCount: Int?

  public init(
    noteLibrary: NoteLibrary = NoteLibrary(),
    folderAccessStore: FolderAccessStore = FolderAccessStore(),
    noteIndex: any NoteIndexing = NoteIndex(),
    taskSyncEngine: TaskSyncEngine = TaskSyncEngine(),
    taskSyncPollIntervalNanoseconds: UInt64 = 15_000_000_000
  ) {
    self.noteLibrary = noteLibrary
    self.folderAccessStore = folderAccessStore
    self.noteIndex = noteIndex
    self.taskSyncEngine = taskSyncEngine
    self.taskSyncPollIntervalNanoseconds = taskSyncPollIntervalNanoseconds
    self.session = NoteEditingSession(library: noteLibrary)
  }

  public var hasFolder: Bool {
    folderURL != nil
  }

  public var recommendedFolderURL: URL {
    noteLibrary.suggestedNotesFolderURL
  }

  public var canIncreaseEditorFontSize: Bool {
    editorFontSize < Self.maximumEditorFontSize
  }

  public var canDecreaseEditorFontSize: Bool {
    editorFontSize > Self.minimumEditorFontSize
  }

  public func start() {
    guard folderURL == nil else {
      return
    }

    do {
      if let restoredURL = try folderAccessStore.restoreFolderURL() {
        try activateFolder(restoredURL, saveBookmark: false)
        restoreActiveNote()
      } else if let activeURL = noteLibrary.activeNotesFolderURL(),
                noteLibrary.validateNotesFolder(at: activeURL).isUsable {
        try activateFolder(activeURL, saveBookmark: false)
        restoreActiveNote()
      } else {
        status = "Choose a notes folder"
      }
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  public func showFolderImporter() {
    isShowingFolderImporter = true
  }

  public func showCommandPalette() {
    commandPaletteQuery = ""
    isShowingCommandPalette = true
  }

  public func showSettings() {
    isShowingSettings = true
  }

  public func dismissCommandPalette() {
    isShowingCommandPalette = false
    commandPaletteQuery = ""
  }

  public func refreshTaskSyncProviderState() async {
    loadTaskSyncSettings()
    taskSyncAuthorizationStatus = taskSyncEngine.authorizationStatus()
    guard taskSyncAuthorizationStatus.allowsSync else {
      taskSyncDestinations = []
      if isTaskSyncEnabled {
        taskSyncStatus = "Reminders access is required for task sync"
      }
      return
    }

    do {
      taskSyncDestinations = try await taskSyncEngine.destinations()
      if selectedTaskDestinationID == nil {
        selectedTaskDestinationID = try await taskSyncEngine.defaultDestination()?.id
        saveTaskSyncSettings(isEnabled: isTaskSyncEnabled, initialSyncConfirmed: false)
      }
    } catch {
      taskSyncErrorMessage = error.localizedDescription
      taskSyncStatus = "Could not load Reminders lists"
    }
  }

  public func selectTaskSyncDestination(_ destinationID: String) {
    selectedTaskDestinationID = destinationID.isEmpty ? nil : destinationID
    saveTaskSyncSettings(isEnabled: isTaskSyncEnabled, initialSyncConfirmed: false)
  }

  public func requestEnableTaskSync() async {
    guard let folderURL else {
      taskSyncErrorMessage = TaskSyncError.missingNotesFolder.localizedDescription
      return
    }

    do {
      let authorization = try await taskSyncEngine.requestAuthorization()
      taskSyncAuthorizationStatus = authorization
      guard authorization.allowsSync else {
        taskSyncStatus = "Reminders access was not granted"
        return
      }

      try await ensureTaskSyncDestination()
      let taskCount = try taskSyncEngine.existingTaskCount(notesFolderURL: folderURL)
      if taskCount > 0 {
        pendingInitialSyncTaskCount = taskCount
      } else {
        await enableTaskSync(syncExistingTasks: false)
      }
    } catch {
      taskSyncErrorMessage = error.localizedDescription
      taskSyncStatus = "Could not enable task sync"
    }
  }

  public func confirmInitialTaskSync() async {
    pendingInitialSyncTaskCount = nil
    await enableTaskSync(syncExistingTasks: true)
  }

  public func cancelInitialTaskSync() {
    pendingInitialSyncTaskCount = nil
  }

  public func disableTaskSync() {
    pendingInitialSyncTaskCount = nil
    isTaskSyncEnabled = false
    saveTaskSyncSettings(isEnabled: false, initialSyncConfirmed: false)
    taskSyncStatus = "Task sync is off"
  }

  public func syncTasksNow() async {
    flushAutosave(syncSavedNote: false)
    await syncAllTasks()
  }

  public func useRecommendedFolder() {
    do {
      try activateFolder(recommendedFolderURL, saveBookmark: false)
      restoreActiveNote()
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  public func chooseFolder(_ url: URL) {
    do {
      try activateFolder(url, saveBookmark: true)
      restoreActiveNote()
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  public func createNewNote() {
    flushAutosave()
    session.resetForNewNote()
    selectedNote = nil
    text = ""
    selectedRange = NSRange(location: 0, length: 0)
    wikiLinkStates = []
    wikiAutocompleteSuggestions = []
    ambiguousWikiLink = nil
    status = "New note"
    preferredCompactColumn = .detail
    editorFocusToken += 1
    reloadNotes()
  }

  public func open(_ note: SavedNote) {
    open(note, heading: nil)
  }

  private func open(_ note: SavedNote, heading: String?) {
    flushAutosave()
    do {
      let restored = try session.open(note)
      selectedNote = restored.note
      text = restored.body
      selectedRange = headingRange(for: heading, in: restored.body)
        ?? NSRange(location: (restored.body as NSString).length, length: 0)
      status = "Opened \(displayTitle(for: restored.note))"
      preferredCompactColumn = .detail
      reloadNotes(selecting: restored.note)
      refreshWikiLinkStates()
      updateWikiAutocomplete()
      editorFocusToken += 1
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  public func activateWikiLink(at characterIndex: Int) {
    guard
      let folderURL,
      let link = WikiLinkParser.link(at: characterIndex, in: text)
    else {
      return
    }

    do {
      if let targetNoteID = link.targetNoteID,
         let target = try indexedNote(noteID: targetNoteID, notesFolderURL: folderURL) {
        if let heading = link.targetHeading, !targetHasHeading(noteID: targetNoteID, heading: heading, notesFolderURL: folderURL) {
          return
        }
        open(target.savedNote, heading: link.targetHeading)
        return
      }

      if link.isCurrentNoteHeadingLink {
        selectHeading(link.targetHeading, in: text)
        return
      }

      guard let targetStem = link.targetStem else {
        return
      }

      let candidates = try noteIndex.wikiNoteCandidates(stem: targetStem, notesFolderURL: folderURL, limit: 20)
      let headingFilteredCandidates: [WikiNoteCandidate]
      if let heading = link.targetHeading {
        headingFilteredCandidates = candidates.filter {
          targetHasHeading(noteID: $0.noteID, heading: heading, notesFolderURL: folderURL)
        }
      } else {
        headingFilteredCandidates = candidates
      }

      if candidates.isEmpty {
        let created = try noteLibrary.createLinkedNote(title: targetStem)
        refreshNoteIndex(for: created)
        let target = try indexedNote(for: created, notesFolderURL: folderURL)
        persistTarget(target.noteID, for: link)
        open(created, heading: nil)
      } else if headingFilteredCandidates.isEmpty {
        return
      } else if headingFilteredCandidates.count == 1 {
        let candidate = headingFilteredCandidates[0]
        persistTarget(candidate.noteID, for: link)
        open(candidate.note, heading: link.targetHeading)
      } else {
        ambiguousWikiLink = AmbiguousWikiLinkResolution(link: link, candidates: headingFilteredCandidates)
      }
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  public func activateMarkdownLink(at characterIndex: Int) {
    guard
      let folderURL,
      let selectedNote,
      let link = MarkdownLocalLinkParser.link(at: characterIndex, in: text)
    else {
      return
    }
    let destinationParts = link.destination.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
    let path = String(destinationParts[0])
    let heading = destinationParts.count > 1 ? String(destinationParts[1]) : nil
    let baseURL = selectedNote.url.deletingLastPathComponent()
    let targetURL = URL(fileURLWithPath: path, relativeTo: baseURL).standardizedFileURL
    let folderPath = folderURL.standardizedFileURL.path
    let targetPath = targetURL.path
    guard
      targetURL.pathExtension.lowercased() == "md",
      (targetPath == folderPath || targetPath.hasPrefix("\(folderPath)/")),
      FileManager.default.fileExists(atPath: targetPath)
    else {
      return
    }
    open(SavedNote(url: targetURL), heading: heading)
  }

  public func chooseAmbiguousWikiLinkTarget(_ candidate: WikiNoteCandidate) {
    guard let pending = ambiguousWikiLink else {
      return
    }
    if let folderURL, let heading = pending.link.targetHeading,
       !targetHasHeading(noteID: candidate.noteID, heading: heading, notesFolderURL: folderURL) {
      ambiguousWikiLink = nil
      return
    }
    persistTarget(candidate.noteID, for: pending.link)
    ambiguousWikiLink = nil
    open(candidate.note, heading: pending.link.targetHeading)
  }

  public func dismissAmbiguousWikiLinkResolution() {
    ambiguousWikiLink = nil
  }

  public func beginRenaming(_ note: SavedNote) {
    renamingNote = note
    renameTitle = note.filenameTitle
  }

  public func cancelRename() {
    renamingNote = nil
    renameTitle = ""
  }

  public func commitRename() {
    guard let folderURL, let note = renamingNote else {
      return
    }
    let title = renameTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !title.isEmpty else {
      return
    }
    do {
      flushAutosave()
      let indexed = try indexedNote(for: note, notesFolderURL: folderURL)
      let oldStem = note.filenameTitle
      let renamed = try noteLibrary.renameNote(note, to: title)
      try noteLibrary.rewriteWikiLinks(
        targetNoteID: indexed.noteID,
        oldStem: oldStem,
        newStem: renamed.filenameTitle
      )
      try noteIndex.rebuild(notesFolderURL: folderURL)
      renamingNote = nil
      renameTitle = ""
      if selectedNote == note {
        open(renamed)
      } else {
        reloadNotes(selecting: selectedNote)
        refreshWikiLinkStates()
      }
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  public func selectWikiAutocompleteSuggestion(_ suggestion: WikiAutocompleteSuggestion) {
    let nsString = text as NSString
    guard NSMaxRange(suggestion.replacementRange) <= nsString.length else {
      return
    }
    text = nsString.replacingCharacters(in: suggestion.replacementRange, with: suggestion.replacement)
    selectedRange = NSRange(location: suggestion.replacementRange.location + (suggestion.replacement as NSString).length, length: 0)
    wikiAutocompleteSuggestions = []
    scheduleAutosave()
    refreshWikiLinkStates()
    editorFocusToken += 1
  }

  public func updateWikiAutocomplete() {
    guard let folderURL, let context = WikiLinkParser.autocompleteContext(in: text, selection: selectedRange) else {
      wikiAutocompleteSuggestions = []
      return
    }

    do {
      switch context {
      case .note(let prefix, let replacementRange):
        let notes = try noteIndex.indexedNotes(notesFolderURL: folderURL, limit: 500)
          .filter { prefix.isEmpty || $0.url.deletingPathExtension().lastPathComponent.localizedCaseInsensitiveContains(prefix) }
          .prefix(8)
        wikiAutocompleteSuggestions = notes.map { note in
          let stem = note.url.deletingPathExtension().lastPathComponent
          return WikiAutocompleteSuggestion(
            title: stem,
            subtitle: note.relativePath,
            replacement: "[[\(stem)]]\(WikiLinkParser.targetComment(noteID: note.noteID))",
            replacementRange: replacementRange
          )
        }
      case .noteHeading(let stem, let prefix, let replacementRange):
        let note = try noteIndex.wikiNoteCandidates(stem: stem, notesFolderURL: folderURL, limit: 1).first
        let headings = try noteIndex.wikiHeadingCandidates(
          noteID: note?.noteID,
          stem: stem,
          prefix: prefix,
          currentNote: nil,
          notesFolderURL: folderURL,
          limit: 8
        )
        wikiAutocompleteSuggestions = headings.map { heading in
          WikiAutocompleteSuggestion(
            title: heading.title,
            subtitle: stem,
            replacement: "[[\(stem)#\(heading.title)]]\(WikiLinkParser.targetComment(noteID: heading.noteID, headingID: heading.headingID))",
            replacementRange: replacementRange
          )
        }
      case .currentNoteHeading(let prefix, let replacementRange):
        let headings = MarkdownHeadingScanner.headings(in: text)
          .filter { prefix.isEmpty || $0.title.localizedCaseInsensitiveContains(prefix) }
          .prefix(8)
        wikiAutocompleteSuggestions = headings.map { heading in
          WikiAutocompleteSuggestion(
            title: heading.title,
            subtitle: "Current note",
            replacement: "[[#\(heading.title)]]",
            replacementRange: replacementRange
          )
        }
      }
    } catch {
      wikiAutocompleteSuggestions = []
    }
  }

  public func apply(_ command: MarkdownCommand) {
    let result = MarkdownTextEditing.apply(command, to: text, selection: selectedRange)
    text = result.body
    selectedRange = result.selection
    scheduleAutosave()
    refreshWikiLinkStates()
    updateWikiAutocomplete()
    editorFocusToken += 1
  }

  public func noteTextDidChange() {
    scheduleAutosave()
    refreshWikiLinkStates()
    updateWikiAutocomplete()
  }

  public func noteSelectionDidChange() {
    updateWikiAutocomplete()
  }

  public func increaseEditorFontSize() {
    setEditorFontSize(editorFontSize + 1)
  }

  public func decreaseEditorFontSize() {
    setEditorFontSize(editorFontSize - 1)
  }

  public func resetEditorFontSize() {
    setEditorFontSize(Self.defaultEditorFontSize)
  }

  public func scheduleAutosave() {
    autosaveWorkItem?.cancel()
    let workItem = DispatchWorkItem { [weak self] in
      Task { @MainActor in
        self?.autosave(showStatus: true)
      }
    }
    autosaveWorkItem = workItem
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: workItem)
  }

  public func flushAutosave() {
    flushAutosave(syncSavedNote: true)
  }

  private func flushAutosave(syncSavedNote: Bool) {
    autosaveWorkItem?.cancel()
    autosaveWorkItem = nil
    autosave(showStatus: false, syncSavedNote: syncSavedNote)
  }

  public func displayTitle(for note: SavedNote) -> String {
    noteTitles[note.id] ?? noteLibrary.displayTitle(for: note)
  }

  public func commandPaletteCommands(
    platformCommands: [CommandPaletteCommand] = []
  ) -> [CommandPaletteCommand] {
    (sharedCommandPaletteCommands + platformCommands)
      .filter(\.isEnabled)
      .filter { command in
        Self.matchesPaletteQuery(command.searchableText, query: commandPaletteQuery)
      }
      .sorted { lhs, rhs in
        Self.paletteRank(for: lhs.searchableText, query: commandPaletteQuery)
          < Self.paletteRank(for: rhs.searchableText, query: commandPaletteQuery)
      }
  }

  public func commandPaletteNotes(limit: Int = 24) -> [SavedNote] {
    guard hasFolder else {
      return []
    }

    if let indexedNotes = commandPaletteIndexedNotes(limit: limit) {
      return indexedNotes
    }

    let notes = sections.flatMap(\.notes)
    let filtered = notes
      .filter { note in
        Self.matchesPaletteQuery(
          "\(displayTitle(for: note)) \(note.dateString) \(note.filenameTitle)",
          query: commandPaletteQuery
        )
      }
      .sorted { lhs, rhs in
        let lhsRank = Self.paletteRank(
          for: "\(displayTitle(for: lhs)) \(lhs.dateString) \(lhs.filenameTitle)",
          query: commandPaletteQuery
        )
        let rhsRank = Self.paletteRank(
          for: "\(displayTitle(for: rhs)) \(rhs.dateString) \(rhs.filenameTitle)",
          query: commandPaletteQuery
        )
        if lhsRank != rhsRank {
          return lhsRank < rhsRank
        }
        return lhs.filenameTitle > rhs.filenameTitle
      }

    return Array(filtered.prefix(limit))
  }

  private func activateFolder(_ url: URL, saveBookmark: Bool) throws {
    scopedFolderURL?.stopAccessingSecurityScopedResource()
    _ = url.startAccessingSecurityScopedResource()
    scopedFolderURL = url
    if saveBookmark {
      try folderAccessStore.save(folderURL: url)
    }
    try noteLibrary.selectNotesFolder(url)
    folderURL = url
    status = url.lastPathComponent
    reloadNotes()
    rebuildNoteIndex()
    loadTaskSyncSettings()
    updateTaskSyncPolling()
    Task { @MainActor in
      await refreshTaskSyncProviderState()
      await syncAllTasks()
    }
  }

  private func restoreActiveNote() {
    do {
      if let restored = try session.restoreActiveNote() {
        selectedNote = restored.note
        text = restored.body
        selectedRange = NSRange(location: (restored.body as NSString).length, length: 0)
        status = "Opened \(displayTitle(for: restored.note))"
        preferredCompactColumn = .detail
        refreshWikiLinkStates()
        updateWikiAutocomplete()
      }
      reloadNotes(selecting: selectedNote)
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func autosave(showStatus: Bool, syncSavedNote: Bool = true) {
    autosaveWorkItem?.cancel()
    autosaveWorkItem = nil
    do {
      let previousBody = session.savedBody
      switch try session.save(body: text) {
      case .skippedEmptyDraft, .unchanged:
        return
      case .saved(let note):
        selectedNote = note
        refreshNoteIndex(for: note)
        rewriteHeadingLinksIfNeeded(for: note, previousBody: previousBody, nextBody: text)
        reloadNotes(selecting: note)
        refreshWikiLinkStates()
        updateWikiAutocomplete()
        if syncSavedNote {
          syncTasks(for: note, body: try noteLibrary.rawBody(for: note))
        }
        if showStatus {
          status = "Autosaved \(displayTitle(for: note))"
        }
      }
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func commandPaletteIndexedNotes(limit: Int) -> [SavedNote]? {
    guard let folderURL else {
      return nil
    }

    do {
      let query = commandPaletteQuery.trimmingCharacters(in: .whitespacesAndNewlines)
      if query.isEmpty {
        return try noteIndex.recentNotes(notesFolderURL: folderURL, limit: limit)
      }
      return try noteIndex.searchNotes(query: query, notesFolderURL: folderURL, limit: limit)
    } catch {
      return nil
    }
  }

  private func rebuildNoteIndex() {
    guard let folderURL else {
      return
    }
    do {
      try noteIndex.rebuild(notesFolderURL: folderURL)
    } catch {
      // The index is disposable; note files remain the source of truth.
    }
  }

  private func refreshNoteIndex(for note: SavedNote) {
    guard let folderURL else {
      return
    }
    do {
      try noteIndex.refresh(note: note, notesFolderURL: folderURL)
    } catch {
      // Autosave should not fail because the derived index could not refresh.
    }
  }

  private func refreshWikiLinkStates() {
    guard let folderURL else {
      wikiLinkStates = []
      return
    }
    do {
      wikiLinkStates = try noteIndex.wikiLinkRenderStates(
        body: text,
        currentNote: selectedNote,
        notesFolderURL: folderURL
      )
    } catch {
      wikiLinkStates = []
    }
  }

  private func rewriteHeadingLinksIfNeeded(for note: SavedNote, previousBody: String, nextBody: String) {
    guard
      let folderURL,
      !previousBody.isEmpty,
      previousBody != nextBody,
      let indexed = try? indexedNote(for: note, notesFolderURL: folderURL)
    else {
      return
    }

    let previousHeadings = MarkdownHeadingScanner.headings(in: previousBody)
    let nextHeadings = MarkdownHeadingScanner.headings(in: nextBody)
    guard previousHeadings.count == nextHeadings.count else {
      return
    }

    for (previous, next) in zip(previousHeadings, nextHeadings)
      where previous.level == next.level && previous.title != next.title {
      try? noteLibrary.rewriteWikiHeadingLinks(
        targetNoteID: indexed.noteID,
        oldHeading: previous.title,
        newHeading: next.title
      )
    }
    try? noteIndex.rebuild(notesFolderURL: folderURL)
    if let updatedBody = try? noteLibrary.body(for: note), updatedBody != text {
      text = updatedBody
      selectedRange = NSRange(location: min(selectedRange.location, (updatedBody as NSString).length), length: 0)
      session.updateSavedBody(updatedBody, for: note)
    }
  }

  private func indexedNote(noteID: String, notesFolderURL: URL) throws -> IndexedNote? {
    try noteIndex.indexedNotes(notesFolderURL: notesFolderURL, limit: 2_000)
      .first { $0.noteID == noteID }
  }

  private func indexedNote(for note: SavedNote, notesFolderURL: URL) throws -> IndexedNote {
    try noteIndex.refresh(note: note, notesFolderURL: notesFolderURL)
    if let indexed = try noteIndex.indexedNotes(notesFolderURL: notesFolderURL, limit: 2_000)
      .first(where: { $0.savedNote == note || $0.url.standardizedFileURL == note.url.standardizedFileURL }) {
      return indexed
    }
    throw NoteIndexError.unreadableNote(note.url.path)
  }

  private func persistTarget(_ noteID: String, for link: WikiLinkOccurrence) {
    text = WikiLinkParser.replacingTargetComment(in: text, for: link, noteID: noteID)
    selectedRange = NSRange(location: min(NSMaxRange(link.range), (text as NSString).length), length: 0)
    flushAutosave()
    refreshWikiLinkStates()
  }

  private func selectHeading(_ heading: String?, in body: String) {
    guard let range = headingRange(for: heading, in: body) else {
      return
    }
    selectedRange = range
    editorFocusToken += 1
  }

  private func headingRange(for heading: String?, in body: String) -> NSRange? {
    guard let heading, !heading.isEmpty else {
      return nil
    }
    let targetAnchor = WikiLinkParser.obsidianAnchor(for: heading)
    return MarkdownHeadingScanner.headings(in: body)
      .first { $0.anchor == targetAnchor || $0.title == heading }?
      .range
  }

  private func targetHasHeading(noteID: String, heading: String, notesFolderURL: URL) -> Bool {
    do {
      let targetAnchor = WikiLinkParser.obsidianAnchor(for: heading)
      return try noteIndex.wikiHeadingCandidates(
        noteID: noteID,
        stem: nil,
        prefix: heading,
        currentNote: nil,
        notesFolderURL: notesFolderURL,
        limit: 20
      )
      .contains { $0.anchor == targetAnchor || $0.title == heading }
    } catch {
      return false
    }
  }

  private func loadTaskSyncSettings() {
    guard let folderURL else {
      isTaskSyncEnabled = false
      selectedTaskDestinationID = nil
      taskSyncStatus = "Choose a notes folder"
      return
    }

    do {
      let settings = try taskSyncEngine.settings(notesFolderURL: folderURL)
      isTaskSyncEnabled = settings.isEnabled
      selectedTaskDestinationID = settings.destinationID
      taskSyncStatus = settings.isEnabled ? "Task sync is on" : "Task sync is off"
    } catch {
      taskSyncErrorMessage = error.localizedDescription
      taskSyncStatus = "Could not load task sync settings"
    }
  }

  private func saveTaskSyncSettings(isEnabled: Bool, initialSyncConfirmed: Bool) {
    guard let folderURL else {
      return
    }

    do {
      var settings = try taskSyncEngine.settings(notesFolderURL: folderURL)
      settings.isEnabled = isEnabled
      settings.providerID = "apple-reminders"
      settings.destinationID = selectedTaskDestinationID
      settings.initialSyncConfirmed = initialSyncConfirmed
      try taskSyncEngine.saveSettings(settings, notesFolderURL: folderURL)
      isTaskSyncEnabled = isEnabled
      updateTaskSyncPolling()
    } catch {
      taskSyncErrorMessage = error.localizedDescription
      taskSyncStatus = "Could not save task sync settings"
    }
  }

  private func ensureTaskSyncDestination() async throws {
    taskSyncDestinations = try await taskSyncEngine.destinations()
    if selectedTaskDestinationID == nil {
      selectedTaskDestinationID = try await taskSyncEngine.defaultDestination()?.id
    }
    guard selectedTaskDestinationID != nil else {
      throw TaskSyncError.missingDestination
    }
  }

  private func enableTaskSync(syncExistingTasks: Bool) async {
    guard folderURL != nil else {
      taskSyncErrorMessage = TaskSyncError.missingNotesFolder.localizedDescription
      return
    }

    do {
      try await ensureTaskSyncDestination()
      saveTaskSyncSettings(isEnabled: true, initialSyncConfirmed: syncExistingTasks)
      taskSyncStatus = "Task sync is on"
      await syncAllTasks()
    } catch {
      taskSyncErrorMessage = error.localizedDescription
      taskSyncStatus = "Could not enable task sync"
    }
  }

  private func syncAllTasks() async {
    guard let folderURL, isTaskSyncEnabled else {
      return
    }

    do {
      let summary = try await taskSyncEngine.syncAll(notesFolderURL: folderURL)
      applyTaskSyncSummary(summary)
    } catch {
      taskSyncErrorMessage = error.localizedDescription
      taskSyncStatus = "Task sync needs attention"
    }
  }

  private func updateTaskSyncPolling() {
    taskSyncPollTask?.cancel()
    taskSyncPollTask = nil

    guard folderURL != nil, isTaskSyncEnabled, taskSyncPollIntervalNanoseconds > 0 else {
      return
    }

    taskSyncPollTask = Task { @MainActor [weak self] in
      while !Task.isCancelled {
        guard let interval = self?.taskSyncPollIntervalNanoseconds else {
          return
        }
        do {
          try await Task.sleep(nanoseconds: interval)
        } catch {
          return
        }
        guard let self, !Task.isCancelled else {
          return
        }
        await self.syncTasksNow()
      }
    }
  }

  private func syncTasks(for note: SavedNote, body: String) {
    guard let folderURL, isTaskSyncEnabled else {
      return
    }

    Task { @MainActor in
      do {
        let summary = try await taskSyncEngine.sync(
          note: note,
          body: body,
          notesFolderURL: folderURL
        )
        applyTaskSyncSummary(summary)
      } catch {
        taskSyncErrorMessage = error.localizedDescription
        taskSyncStatus = "Task sync needs attention"
      }
    }
  }

  private func applyTaskSyncSummary(_ summary: TaskSyncSummary) {
    if !summary.updatedNoteRelativePaths.isEmpty {
      reloadSelectedNoteIfNeeded(updatedRelativePaths: summary.updatedNoteRelativePaths)
      for relativePath in summary.updatedNoteRelativePaths {
        refreshNoteIndex(forRelativePath: relativePath)
      }
    }

    guard summary.scannedTasks > 0 || summary.createdExternalTasks > 0 || summary.updatedMarkdownTasks > 0 else {
      taskSyncStatus = isTaskSyncEnabled ? "Task sync is on" : "Task sync is off"
      return
    }

    let changes = summary.createdExternalTasks
      + summary.updatedExternalTasks
      + summary.completedExternalTasks
      + summary.updatedMarkdownTasks
      + summary.unlinkedTasks
    taskSyncStatus = changes == 0
      ? "Task sync is up to date"
      : "Task sync updated \(changes) task\(changes == 1 ? "" : "s")"
  }

  private func reloadSelectedNoteIfNeeded(updatedRelativePaths: Set<String>) {
    guard
      let folderURL,
      let selectedNote,
      let relativePath = MarkdownTaskScanner.relativePath(for: selectedNote.url, in: folderURL),
      updatedRelativePaths.contains(relativePath)
    else {
      return
    }

    do {
      let updatedBody = try noteLibrary.body(for: selectedNote)
      text = updatedBody
      selectedRange = NSRange(location: min(selectedRange.location, (updatedBody as NSString).length), length: 0)
      session.updateSavedBody(updatedBody, for: selectedNote)
    } catch {
      taskSyncErrorMessage = error.localizedDescription
    }
  }

  private func refreshNoteIndex(forRelativePath relativePath: String) {
    guard let folderURL else {
      return
    }
    let note = SavedNote(url: folderURL.appendingPathComponent(relativePath))
    refreshNoteIndex(for: note)
  }

  private func reloadNotes(selecting note: SavedNote? = nil) {
    do {
      sections = try noteLibrary.listNotes()
      noteTitles = Dictionary(uniqueKeysWithValues: sections
        .flatMap(\.notes)
        .map { ($0.id, noteLibrary.displayTitle(for: $0)) })
      selectedNote = note ?? session.currentNote
    } catch NoteLibraryError.noActiveNotesFolder {
      sections = []
      noteTitles = [:]
      selectedNote = nil
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func setEditorFontSize(_ size: Double) {
    editorFontSize = min(Self.maximumEditorFontSize, max(Self.minimumEditorFontSize, size))
  }

  private var sharedCommandPaletteCommands: [CommandPaletteCommand] {
    guard hasFolder else {
      return []
    }

    return [
      CommandPaletteCommand(
        id: "lattice.newNote",
        title: "New Note",
        subtitle: "Start a fresh Markdown note",
        systemImage: "square.and.pencil"
      ) { [weak self] in
        self?.createNewNote()
      }
    ]
  }

  private static func matchesPaletteQuery(_ text: String, query: String) -> Bool {
    let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !normalizedQuery.isEmpty else {
      return true
    }
    return text.lowercased().contains(normalizedQuery)
  }

  private static func paletteRank(for text: String, query: String) -> Int {
    let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !normalizedQuery.isEmpty else {
      return 2
    }

    let normalizedText = text.lowercased()
    if normalizedText == normalizedQuery {
      return 0
    }
    if normalizedText.hasPrefix(normalizedQuery) {
      return 1
    }
    return 2
  }
}

public enum NavigationColumn: Hashable {
  case sidebar
  case detail
}

public struct CommandPaletteCommand: Identifiable {
  public let id: String
  public let title: String
  public let subtitle: String?
  public let systemImage: String
  public let isEnabled: Bool
  public let isSetupSafe: Bool
  private let action: @MainActor () -> Void

  public init(
    id: String,
    title: String,
    subtitle: String? = nil,
    systemImage: String,
    isEnabled: Bool = true,
    isSetupSafe: Bool = false,
    action: @escaping @MainActor () -> Void
  ) {
    self.id = id
    self.title = title
    self.subtitle = subtitle
    self.systemImage = systemImage
    self.isEnabled = isEnabled
    self.isSetupSafe = isSetupSafe
    self.action = action
  }

  public var searchableText: String {
    "\(title) \(subtitle ?? "")"
  }

  @MainActor
  public func perform() {
    action()
  }
}

public struct WikiAutocompleteSuggestion: Identifiable, Equatable {
  public let id = UUID()
  public let title: String
  public let subtitle: String
  public let replacement: String
  public let replacementRange: NSRange

  public init(title: String, subtitle: String, replacement: String, replacementRange: NSRange) {
    self.title = title
    self.subtitle = subtitle
    self.replacement = replacement
    self.replacementRange = replacementRange
  }
}

public struct AmbiguousWikiLinkResolution: Equatable {
  public let link: WikiLinkOccurrence
  public let candidates: [WikiNoteCandidate]

  public init(link: WikiLinkOccurrence, candidates: [WikiNoteCandidate]) {
    self.link = link
    self.candidates = candidates
  }
}

private extension LatticeAppModel {
  static let defaultEditorFontSize = 14.0
  static let minimumEditorFontSize = 10.0
  static let maximumEditorFontSize = 28.0
}
