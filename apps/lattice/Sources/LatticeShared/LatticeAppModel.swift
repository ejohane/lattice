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
  private let activityStore: any ActivityStoring
  private let taskSyncEngine: TaskSyncEngine
  private let editorPreferencesStore: EditorPreferencesStore
  private let notesFolderChangeMonitor: NotesFolderChangeMonitoring
  private let taskSyncPollIntervalNanoseconds: UInt64
  private let dateProvider: () -> Date
  private let session: NoteEditingSession
  private var autosaveWorkItem: DispatchWorkItem?
  private var editorDecorationWorkItem: DispatchWorkItem?
  private var taskSyncPollTask: Task<Void, Never>?
  private var scopedFolderURL: URL?
  private var backStack: [NavigationHistoryEntry] = []
  private var forwardStack: [NavigationHistoryEntry] = []
  private var allSections: [NoteSection] = []
  private var lastExpandedNavigationVisibility = LatticeNavigationVisibility.all

  private enum ExternalSelectedNoteChange {
    case none
    case reloaded
    case conflict
    case deleted
  }

  public var sections: [NoteSection] = []
  public var noteTitles: [String: String] = [:]
  public var notePreviews: [String: IndexedNote] = [:]
  public var tagSummaries: [NoteTagSummary] = []
  public var selectedTagName: String?
  public var text = ""
  public var selectedRange = NSRange(location: 0, length: 0)
  public var selectedNote: SavedNote?
  public var folderURL: URL?
  public var status = "Choose a notes folder"
  public var errorMessage: String?
  public var isShowingFolderImporter = false
  public var isShowingCommandPalette = false
  public var isShowingContextPack = false
  public var isShowingSettings = false
  public var commandPaletteQuery = ""
  public var contextPackTask = ""
  public var contextPackSearchQuery = ""
  public var contextPackSources: [ContextPackSource] = []
  public var contextPackGeneratedAt: Date?
  public var preferredCompactColumn = NavigationColumn.sidebar
  public var navigationVisibility = LatticeNavigationVisibility.all
  public var editorFocusToken = 0
  public var editorFontSize = 14.0
  public var editorFontFamily = EditorFontFamily.system
  public var isVimModeEnabled = false
  public var showsRelativeLineNumbers = false
  public var isZenModeEnabled = false
  public var selectedThemeID = LatticeThemeID.system
  public var keyboardShortcutOverrides: [LatticeKeyboardShortcutID: LatticeKeyboardShortcut] = [:]
  public var disabledKeyboardShortcuts: Set<LatticeKeyboardShortcutID> = []
  public var vimState = VimEditorState(mode: .insert)
  public var wikiLinkStates: [WikiLinkRenderState] = []
  public var imagePreviewStates: [MarkdownImageRenderState] = []
  public var wikiAutocompleteSuggestions: [WikiAutocompleteSuggestion] = [] {
    didSet {
      clampWikiAutocompleteSelection()
    }
  }
  public var wikiAutocompleteSelectionIndex = 0
  public var tagAutocompleteSuggestions: [TagAutocompleteSuggestion] = [] {
    didSet {
      clampTagAutocompleteSelection()
    }
  }
  public var tagAutocompleteSelectionIndex = 0
  public var personAutocompleteSuggestions: [PersonAutocompleteSuggestion] = [] {
    didSet {
      clampPersonAutocompleteSelection()
    }
  }
  public var personAutocompleteSelectionIndex = 0
  public var slashCommandSuggestions: [SlashCommandSuggestion] = [] {
    didSet {
      clampSlashCommandSelection()
    }
  }
  public var slashCommandSelectionIndex = 0
  public var ambiguousWikiLink: AmbiguousWikiLinkResolution?
  public var renamingNote: SavedNote?
  public var renameTitle = ""
  public var renamingTag: NoteTagSummary?
  public var renameTagName = ""
  public var deletingTag: NoteTagSummary?
  public var taskSyncProviderName = "Apple Reminders"
  public var taskSyncAuthorizationStatus = TaskProviderAuthorizationStatus.notDetermined
  public var taskSyncDestinations: [TaskDestination] = []
  public var selectedTaskDestinationID: String?
  public var isTaskSyncEnabled = false
  public var taskSyncStatus = "Task sync is off"
  public var taskSyncErrorMessage: String?
  public var pendingInitialSyncTaskCount: Int?
  public var todayActivityEvents: [ActivityEvent] = []
  public var noteMigrationPreview: NoteStorageMigrationPreview?
  public var isShowingNoteMigrationPrompt = false
  public var isMigratingNotes = false
  public var noteMigrationSummary: String?
  public init(
    noteLibrary: NoteLibrary = NoteLibrary(),
    folderAccessStore: FolderAccessStore = FolderAccessStore(),
    noteIndex: any NoteIndexing = NoteIndex(),
    activityStore: any ActivityStoring = ActivityStore(),
    taskSyncEngine: TaskSyncEngine = TaskSyncEngine(),
    editorPreferencesStore: EditorPreferencesStore = EditorPreferencesStore(),
    notesFolderChangeMonitor: NotesFolderChangeMonitoring = NotesFolderChangeMonitor(),
    taskSyncPollIntervalNanoseconds: UInt64 = 15_000_000_000,
    dateProvider: @escaping () -> Date = Date.init
  ) {
    self.noteLibrary = noteLibrary
    self.folderAccessStore = folderAccessStore
    self.noteIndex = noteIndex
    self.activityStore = activityStore
    self.taskSyncEngine = taskSyncEngine
    self.editorPreferencesStore = editorPreferencesStore
    self.notesFolderChangeMonitor = notesFolderChangeMonitor
    self.taskSyncPollIntervalNanoseconds = taskSyncPollIntervalNanoseconds
    self.dateProvider = dateProvider
    self.session = NoteEditingSession(library: noteLibrary)
    let editorPreferences = editorPreferencesStore.load()
    self.isVimModeEnabled = editorPreferences.isVimModeEnabled
    self.showsRelativeLineNumbers = editorPreferences.showsRelativeLineNumbers
    self.selectedThemeID = editorPreferences.themeID
    self.editorFontFamily = editorPreferences.fontFamily
    self.keyboardShortcutOverrides = editorPreferences.keyboardShortcutOverrides
    self.disabledKeyboardShortcuts = editorPreferences.disabledKeyboardShortcuts
    self.vimState = VimEditorState(mode: editorPreferences.isVimModeEnabled ? .normal : .insert)
  }

  public var hasFolder: Bool {
    folderURL != nil
  }

  public var hasEditorAutocompleteSuggestions: Bool {
    !slashCommandSuggestions.isEmpty
      || !tagAutocompleteSuggestions.isEmpty
      || !personAutocompleteSuggestions.isEmpty
      || !wikiAutocompleteSuggestions.isEmpty
  }

  public var isNoteMigrationRequired: Bool {
    noteMigrationPreview != nil
  }

  public var canCommitTagRename: Bool {
    NoteTagParser.isValidName(renameTagName.trimmingCharacters(in: .whitespacesAndNewlines))
  }

  public var recommendedFolderURL: URL {
    recommendedNotesFolder.url
  }

  public var recommendedNotesFolder: RecommendedNotesFolder {
    noteLibrary.recommendedNotesFolder
  }

  public var isRecommendedFolderCloudBacked: Bool {
    recommendedNotesFolder.isCloudBacked
  }

  public var recommendedFolderDescription: String {
    isRecommendedFolderCloudBacked
      ? "iCloud Drive"
      : "Local fallback. Sign in to iCloud Drive to sync between devices."
  }

  public var canNavigateBack: Bool {
    !backStack.isEmpty
  }

  public var canNavigateForward: Bool {
    !forwardStack.isEmpty
  }

  public var theme: LatticeTheme {
    LatticeTheme(id: selectedThemeID)
  }

  public var canIncreaseEditorFontSize: Bool {
    editorFontSize < Self.maximumEditorFontSize
  }

  public var canDecreaseEditorFontSize: Bool {
    editorFontSize > Self.minimumEditorFontSize
  }

  public var effectiveIsVimModeEnabled: Bool {
    isVimModeEnabled && !isZenModeEnabled
  }

  public func start() {
    guard folderURL == nil else {
      refreshExternalChanges()
      return
    }

    do {
      if let restoredURL = try folderAccessStore.restoreFolderURL() {
        try activateFolder(restoredURL, saveBookmark: false, preserveActiveNoteForSameFolder: true)
        restoreActiveNote()
      } else if let activeURL = noteLibrary.activeNotesFolderURL(),
                noteLibrary.validateNotesFolder(at: activeURL).isUsable {
        try activateFolder(activeURL, saveBookmark: false, preserveActiveNoteForSameFolder: true)
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

  public func showContextPack() {
    guard hasFolder, !isNoteMigrationRequired else {
      return
    }

    flushAutosave()
    contextPackTask = ""
    contextPackSearchQuery = ""
    contextPackSources = []
    contextPackGeneratedAt = dateProvider()

    if let selectedNote {
      let selection = clampedRange(selectedRange, in: text)
      let isExcerpt = selection.length > 0
      let body = isExcerpt
        ? (text as NSString).substring(with: selection)
        : text
      contextPackSources = [ContextPackSource(
        noteID: selectedNote.id,
        title: displayTitle(for: selectedNote),
        body: body,
        isExcerpt: isExcerpt
      )]
    }

    isShowingContextPack = true
  }

  public func dismissContextPack() {
    isShowingContextPack = false
    discardContextPackDraft()
  }

  public func discardContextPackDraft() {
    contextPackTask = ""
    contextPackSearchQuery = ""
    contextPackSources = []
    contextPackGeneratedAt = nil
  }

  public func contextPackSearchNotes(limit: Int = 50) -> [SavedNote] {
    guard let folderURL else {
      return []
    }

    let query = contextPackSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    do {
      if query.isEmpty {
        return try noteIndex.recentNotes(notesFolderURL: folderURL, limit: limit)
      }
      return try noteIndex.searchNotes(query: query, notesFolderURL: folderURL, limit: limit)
    } catch {
      let notes = sections.flatMap(\.notes)
      let filtered = query.isEmpty
        ? notes
        : notes.filter { note in
          Self.matchesPaletteQuery(
            "\(displayTitle(for: note)) \(note.dateString) \(note.filenameTitle)",
            query: query
          )
        }
      return Array(filtered.prefix(limit))
    }
  }

  public func contextPackContains(_ note: SavedNote) -> Bool {
    contextPackSources.contains { $0.noteID == note.id }
  }

  public func addNoteToContextPack(_ note: SavedNote) {
    guard !contextPackContains(note) else {
      return
    }

    do {
      contextPackSources.append(ContextPackSource(
        noteID: note.id,
        title: displayTitle(for: note),
        body: try noteLibrary.body(for: note)
      ))
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  public func removeContextPackSource(id: String) {
    contextPackSources.removeAll { $0.id == id }
  }

  public func moveContextPackSource(id: String, by offset: Int) {
    guard
      offset != 0,
      let currentIndex = contextPackSources.firstIndex(where: { $0.id == id })
    else {
      return
    }
    let destinationIndex = min(max(currentIndex + offset, 0), contextPackSources.count - 1)
    guard destinationIndex != currentIndex else {
      return
    }
    let source = contextPackSources.remove(at: currentIndex)
    contextPackSources.insert(source, at: destinationIndex)
  }

  public var contextPackMarkdown: String {
    ContextPackCompiler.markdown(for: ContextPack(
      task: contextPackTask,
      sources: contextPackSources,
      generatedAt: contextPackGeneratedAt ?? dateProvider()
    ))
  }

  public var contextPackCharacterCount: Int {
    contextPackMarkdown.count
  }

  public var contextPackApproximateTokenCount: Int {
    ContextPackCompiler.approximateTokenCount(for: contextPackMarkdown)
  }

  public var isContextPackReady: Bool {
    !contextPackSources.isEmpty
  }

  public func showSettings() {
    isShowingSettings = true
  }

  public func showNoteMigrationPrompt() {
    guard isNoteMigrationRequired else {
      return
    }
    isShowingNoteMigrationPrompt = true
  }

  public func deferNoteMigration() {
    isShowingNoteMigrationPrompt = false
  }

  public func dismissNoteMigrationSummary() {
    noteMigrationSummary = nil
  }

  public func migrateNotesToFlatLayout() {
    guard isNoteMigrationRequired, !isMigratingNotes else {
      return
    }
    flushAutosave()
    isShowingNoteMigrationPrompt = false
    isMigratingNotes = true
    notesFolderChangeMonitor.stop()
    do {
      let result = try noteLibrary.migrateNotesToFlatLayout(now: dateProvider())
      noteMigrationPreview = nil
      clearNavigationHistory()
      rebuildNoteIndex()
      restoreActiveNote()
      startNotesFolderChangeMonitor()
      isMigratingNotes = false
      status = "Notes migrated"
      var summary = "Migrated \(result.migratedNoteCount) notes and renamed \(result.renamedNoteCount) files."
      if result.collisionCount > 0 {
        summary += " \(result.collisionCount) filename collisions received stable suffixes."
      }
      if result.ambiguousLinkCount > 0 {
        summary += " \(result.ambiguousLinkCount) ambiguous links were left unchanged."
      }
      summary += " A recovery copy is at \(result.backupURL.path)."
      noteMigrationSummary = summary
    } catch {
      isMigratingNotes = false
      startNotesFolderChangeMonitor()
      errorMessage = error.localizedDescription
      refreshNoteMigrationRequirement(presentPrompt: false)
    }
  }

  public func dismissCommandPalette() {
    isShowingCommandPalette = false
    commandPaletteQuery = ""
  }

  public func toggleZenMode() {
    if isZenModeEnabled {
      exitZenMode()
    } else {
      enterZenMode()
    }
  }

  public func enterZenMode() {
    guard hasFolder else {
      return
    }
    flushAutosave()
    isZenModeEnabled = true
    preferredCompactColumn = .detail
    editorFocusToken += 1
  }

  public func exitZenMode() {
    guard isZenModeEnabled else {
      return
    }
    flushAutosave()
    isZenModeEnabled = false
    editorFocusToken += 1
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

  public func appBecameActive() {
    refreshExternalChanges()
  }

  public func refreshExternalChanges() {
    guard folderURL != nil else {
      return
    }

    let previousNoteListSignature = noteListSignature
    refreshNoteMigrationRequirement(presentPrompt: false)
    let selectedChange = refreshSelectedNoteForExternalChanges()
    reloadNotes(selecting: selectedNote)
    rebuildNoteIndex()
    refreshTodayActivity()
    refreshWikiLinkStates()
    updateWikiAutocomplete()
    updateSelectedNoteChangeMonitor()

    if selectedChange == .none, previousNoteListSignature != noteListSignature {
      status = "Notes updated"
    }
  }

  public func useRecommendedFolder() {
    do {
      let recommendation = recommendedNotesFolder
      if recommendation.isCloudBacked {
        try noteLibrary.migrateFallbackNotesToICloudIfNeeded(iCloudFolderURL: recommendation.url)
      }
      try activateFolder(recommendation.url, saveBookmark: false)
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
    forwardStack.removeAll()
    selectedTagName = nil
    session.resetForNewNote()
    selectedNote = nil
    updateSelectedNoteChangeMonitor()
    text = ""
    selectedRange = NSRange(location: 0, length: 0)
    wikiLinkStates = []
    imagePreviewStates = []
    wikiAutocompleteSuggestions = []
    tagAutocompleteSuggestions = []
    slashCommandSuggestions = []
    ambiguousWikiLink = nil
    status = "New note"
    preferredCompactColumn = .detail
    editorFocusToken += 1
    reloadNotes()
  }

  public func openTodayNote() {
    guard hasFolder, !isNoteMigrationRequired else {
      return
    }

    flushAutosave()
    do {
      let dailyNote = try noteLibrary.ensureDailyNote(now: dateProvider())
      refreshNoteIndex(for: dailyNote)
      open(
        dailyNote,
        heading: nil,
        selection: nil,
        recordHistory: true,
        flushBeforeOpen: false
      )
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  public func open(_ note: SavedNote) {
    open(note, heading: nil, selection: nil, recordHistory: true)
  }

  public func navigateBack() {
    guard let destination = backStack.popLast() else {
      return
    }

    flushAutosave()
    let current = currentHistoryEntry()
    if open(destination.note, heading: nil, selection: destination.selectedRange, recordHistory: false, flushBeforeOpen: false) {
      if let current {
        Self.appendHistoryEntry(current, to: &forwardStack)
      }
    } else {
      Self.appendHistoryEntry(destination, to: &backStack)
    }
  }

  public func navigateForward() {
    guard let destination = forwardStack.popLast() else {
      return
    }

    flushAutosave()
    let current = currentHistoryEntry()
    if open(destination.note, heading: nil, selection: destination.selectedRange, recordHistory: false, flushBeforeOpen: false) {
      if let current {
        Self.appendHistoryEntry(current, to: &backStack)
      }
    } else {
      Self.appendHistoryEntry(destination, to: &forwardStack)
    }
  }

  @discardableResult
  private func open(
    _ note: SavedNote,
    heading: String?,
    selection: NSRange?,
    recordHistory: Bool,
    flushBeforeOpen: Bool = true
  ) -> Bool {
    if flushBeforeOpen {
      flushAutosave()
    }
    let pendingHistoryEntry = recordHistory ? currentHistoryEntry() : nil
    let shouldRecordHistory = pendingHistoryEntry.map {
      self.shouldRecordHistory($0, destination: note, heading: heading)
    } ?? false
    do {
      let restored = try session.open(note)
      if shouldRecordHistory, let pendingHistoryEntry {
        Self.appendHistoryEntry(pendingHistoryEntry, to: &backStack)
        forwardStack.removeAll()
      }
      selectedNote = restored.note
      updateSelectedNoteChangeMonitor()
      let editorBody = Self.editorBody(from: restored.body)
      text = editorBody
      selectedRange = selection.map { clampedRange($0, in: editorBody) }
        ?? headingRange(for: heading, in: editorBody)
        ?? NSRange(location: (editorBody as NSString).length, length: 0)
      status = "Opened \(displayTitle(for: restored.note))"
      preferredCompactColumn = .detail
      reloadNotes(selecting: restored.note)
      refreshWikiLinkStates()
      refreshImagePreviewStates()
      updateWikiAutocomplete()
      editorFocusToken += 1
      return true
    } catch {
      errorMessage = error.localizedDescription
      return false
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
        open(target.savedNote, heading: link.targetHeading, selection: nil, recordHistory: true)
        return
      }

      if link.isCurrentNoteHeadingLink {
        pushCurrentHistoryEntry(destination: selectedNote, heading: link.targetHeading)
        if selectHeading(link.targetHeading, in: text) {
          forwardStack.removeAll()
        }
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
        open(created, heading: nil, selection: nil, recordHistory: true)
      } else if headingFilteredCandidates.isEmpty {
        return
      } else if headingFilteredCandidates.count == 1 {
        let candidate = headingFilteredCandidates[0]
        persistTarget(candidate.noteID, for: link)
        open(candidate.note, heading: link.targetHeading, selection: nil, recordHistory: true)
      } else {
        ambiguousWikiLink = AmbiguousWikiLinkResolution(link: link, candidates: headingFilteredCandidates)
      }
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  public func activatePersonMention(at characterIndex: Int) {
    guard
      let folderURL,
      let mention = PersonMentionParser.mention(at: characterIndex, in: text)
    else {
      return
    }
    do {
      guard let target = try indexedNote(noteID: mention.targetNoteID, notesFolderURL: folderURL) else {
        return
      }
      open(target.savedNote, heading: nil, selection: nil, recordHistory: true)
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
    open(SavedNote(url: targetURL), heading: heading, selection: nil, recordHistory: true)
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
    open(candidate.note, heading: pending.link.targetHeading, selection: nil, recordHistory: true)
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
        _ = open(renamed, heading: nil, selection: selectedRange, recordHistory: false)
      } else {
        reloadNotes(selecting: selectedNote)
        refreshWikiLinkStates()
      }
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  public func delete(_ note: SavedNote) {
    let title = displayTitle(for: note)
    do {
      flushAutosave()
      let isDeletingSelectedNote = selectedNote == note
      try noteLibrary.deleteNote(note)
      refreshNoteIndex(for: note)
      if isDeletingSelectedNote {
        clearEditorAfterDeletingSelectedNote()
      } else {
        reloadNotes(selecting: selectedNote)
        refreshWikiLinkStates()
        updateWikiAutocomplete()
      }
      status = "Deleted \(title)"
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  public func selectTag(_ tag: NoteTagSummary?) {
    selectedTagName = tag?.normalizedName
    reloadNotes(selecting: selectedNote)
    let visibleNotes = sections.flatMap(\.notes)
    if let firstVisibleNote = visibleNotes.first,
       !visibleNotes.contains(where: { $0 == selectedNote }) {
      open(firstVisibleNote)
    }
    status = tag.map { "Showing #\($0.name)" } ?? "All notes"
  }

  public func setNavigationVisibility(_ visibility: LatticeNavigationVisibility) {
    navigationVisibility = visibility
    if visibility != .editorOnly {
      lastExpandedNavigationVisibility = visibility
    }
  }

  public func toggleNavigationVisibility() {
    if navigationVisibility == .editorOnly {
      navigationVisibility = lastExpandedNavigationVisibility
    } else {
      lastExpandedNavigationVisibility = navigationVisibility
      navigationVisibility = .editorOnly
    }
  }

  public func toggleSourceVisibility() {
    switch navigationVisibility {
    case .all:
      setNavigationVisibility(.notesAndEditor)
    case .notesAndEditor, .editorOnly:
      setNavigationVisibility(.all)
    }
  }

  public func activateTag(at characterIndex: Int) {
    guard let occurrence = NoteTagParser.tag(at: characterIndex, in: text) else {
      return
    }
    flushAutosave()
    let summary = tagSummaries.first { $0.normalizedName == occurrence.normalizedName }
      ?? NoteTagSummary(name: occurrence.name, noteCount: 1)
    selectTag(summary)
    setNavigationVisibility(.all)
    preferredCompactColumn = .sidebar
  }

  public func beginRenamingTag(_ tag: NoteTagSummary) {
    renamingTag = tag
    renameTagName = tag.name
  }

  public func cancelTagRename() {
    renamingTag = nil
    renameTagName = ""
  }

  public func commitTagRename() {
    guard let folderURL, let tag = renamingTag else {
      return
    }
    let name = renameTagName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard NoteTagParser.isValidName(name) else {
      errorMessage = "Tag names need a letter and can use numbers, -, _, or /, but not spaces."
      return
    }

    do {
      flushAutosave()
      let selected = selectedNote
      let selection = selectedRange
      try noteLibrary.rewriteTag(normalizedName: tag.normalizedName, to: name)
      try noteIndex.rebuild(notesFolderURL: folderURL)
      selectedTagName = selectedTagName == tag.normalizedName
        ? NoteTagParser.normalizedName(name)
        : selectedTagName
      renamingTag = nil
      renameTagName = ""
      refreshTagSummaries()
      if let selected {
        _ = open(selected, heading: nil, selection: selection, recordHistory: false, flushBeforeOpen: false)
      } else {
        reloadNotes()
      }
      status = "Renamed #\(tag.name) to #\(name)"
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  public func requestTagDeletion(_ tag: NoteTagSummary) {
    deletingTag = tag
  }

  public func cancelTagDeletion() {
    deletingTag = nil
  }

  public func confirmTagDeletion() {
    guard let folderURL, let tag = deletingTag else {
      return
    }

    do {
      flushAutosave()
      let selected = selectedNote
      let selection = selectedRange
      try noteLibrary.rewriteTag(normalizedName: tag.normalizedName, to: nil)
      try noteIndex.rebuild(notesFolderURL: folderURL)
      if selectedTagName == tag.normalizedName {
        selectedTagName = nil
      }
      deletingTag = nil
      refreshTagSummaries()
      if let selected {
        _ = open(selected, heading: nil, selection: selection, recordHistory: false, flushBeforeOpen: false)
      } else {
        reloadNotes()
      }
      status = "Deleted #\(tag.name)"
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
    tagAutocompleteSuggestions = []
    personAutocompleteSuggestions = []
    slashCommandSuggestions = []
    scheduleAutosave()
    refreshWikiLinkStates()
    refreshImagePreviewStates()
    editorFocusToken += 1
  }

  public func moveWikiAutocompleteSelection(by delta: Int) {
    guard !wikiAutocompleteSuggestions.isEmpty else {
      wikiAutocompleteSelectionIndex = 0
      return
    }
    let count = wikiAutocompleteSuggestions.count
    wikiAutocompleteSelectionIndex = (wikiAutocompleteSelectionIndex + delta + count) % count
  }

  public func commitSelectedWikiAutocompleteSuggestion() {
    guard wikiAutocompleteSuggestions.indices.contains(wikiAutocompleteSelectionIndex) else {
      return
    }
    selectWikiAutocompleteSuggestion(wikiAutocompleteSuggestions[wikiAutocompleteSelectionIndex])
  }

  public func dismissWikiAutocomplete() {
    wikiAutocompleteSuggestions = []
    wikiAutocompleteSelectionIndex = 0
    tagAutocompleteSuggestions = []
    tagAutocompleteSelectionIndex = 0
    personAutocompleteSuggestions = []
    personAutocompleteSelectionIndex = 0
    slashCommandSuggestions = []
    slashCommandSelectionIndex = 0
  }

  public func selectTagAutocompleteSuggestion(_ suggestion: TagAutocompleteSuggestion) {
    let nsString = text as NSString
    guard NSMaxRange(suggestion.replacementRange) <= nsString.length else {
      return
    }
    text = nsString.replacingCharacters(in: suggestion.replacementRange, with: suggestion.replacement)
    selectedRange = NSRange(
      location: suggestion.replacementRange.location + (suggestion.replacement as NSString).length,
      length: 0
    )
    tagAutocompleteSuggestions = []
    personAutocompleteSuggestions = []
    wikiAutocompleteSuggestions = []
    slashCommandSuggestions = []
    scheduleAutosave()
    refreshWikiLinkStates()
    refreshImagePreviewStates()
    editorFocusToken += 1
  }

  public func selectPersonAutocompleteSuggestion(_ suggestion: PersonAutocompleteSuggestion) {
    guard let folderURL else {
      return
    }
    let nsString = text as NSString
    guard NSMaxRange(suggestion.replacementRange) <= nsString.length else {
      return
    }

    do {
      let noteID: String
      if let existingNoteID = suggestion.targetNoteID {
        noteID = existingNoteID
      } else {
        let person = try noteLibrary.createPersonNote(name: suggestion.name, now: dateProvider())
        refreshNoteIndex(for: person)
        let indexed = try indexedNote(for: person, notesFolderURL: folderURL)
        noteID = indexed.noteID
        reloadNotes(selecting: selectedNote)
        status = "Created @\(suggestion.name)"
      }

      let replacement = PersonMentionParser.replacement(name: suggestion.name, noteID: noteID)
      text = nsString.replacingCharacters(in: suggestion.replacementRange, with: replacement)
      selectedRange = NSRange(
        location: suggestion.replacementRange.location + (replacement as NSString).length,
        length: 0
      )
      personAutocompleteSuggestions = []
      tagAutocompleteSuggestions = []
      wikiAutocompleteSuggestions = []
      slashCommandSuggestions = []
      scheduleAutosave()
      refreshWikiLinkStates()
      refreshImagePreviewStates()
      editorFocusToken += 1
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  public func selectSlashCommandSuggestion(_ suggestion: SlashCommandSuggestion) {
    guard suggestion.command == "today", folderURL != nil else {
      return
    }
    let nsString = text as NSString
    guard NSMaxRange(suggestion.replacementRange) <= nsString.length else {
      return
    }
    do {
      let dailyNote = try noteLibrary.ensureDailyNote(now: dateProvider())
      refreshNoteIndex(for: dailyNote)
      let rawBody = try noteLibrary.rawBody(for: dailyNote)
      guard let noteID = MarkdownDocumentMetadata.noteID(in: rawBody) else {
        throw NoteLibraryError.invalidNotesFolder("Could not identify today's daily note.")
      }
      let dateStem = dailyNote.filenameTitle
      let replacement = "[[\(dateStem)]]\(WikiLinkParser.targetComment(noteID: noteID))"
      text = nsString.replacingCharacters(in: suggestion.replacementRange, with: replacement)
      selectedRange = NSRange(
        location: suggestion.replacementRange.location + (replacement as NSString).length,
        length: 0
      )
      slashCommandSuggestions = []
      tagAutocompleteSuggestions = []
      personAutocompleteSuggestions = []
      wikiAutocompleteSuggestions = []
      scheduleAutosave()
      refreshWikiLinkStates()
      refreshImagePreviewStates()
      editorFocusToken += 1
      status = "Linked \(dateStem)"
      reloadNotes(selecting: selectedNote)
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  public func moveEditorAutocompleteSelection(by delta: Int) {
    if !slashCommandSuggestions.isEmpty {
      let count = slashCommandSuggestions.count
      slashCommandSelectionIndex = (slashCommandSelectionIndex + delta + count) % count
    } else if !tagAutocompleteSuggestions.isEmpty {
      let count = tagAutocompleteSuggestions.count
      tagAutocompleteSelectionIndex = (tagAutocompleteSelectionIndex + delta + count) % count
    } else if !personAutocompleteSuggestions.isEmpty {
      let count = personAutocompleteSuggestions.count
      personAutocompleteSelectionIndex = (personAutocompleteSelectionIndex + delta + count) % count
    } else {
      moveWikiAutocompleteSelection(by: delta)
    }
  }

  public func commitSelectedEditorAutocompleteSuggestion() {
    if slashCommandSuggestions.indices.contains(slashCommandSelectionIndex) {
      selectSlashCommandSuggestion(slashCommandSuggestions[slashCommandSelectionIndex])
    } else if tagAutocompleteSuggestions.indices.contains(tagAutocompleteSelectionIndex) {
      selectTagAutocompleteSuggestion(tagAutocompleteSuggestions[tagAutocompleteSelectionIndex])
    } else if personAutocompleteSuggestions.indices.contains(personAutocompleteSelectionIndex) {
      selectPersonAutocompleteSuggestion(personAutocompleteSuggestions[personAutocompleteSelectionIndex])
    } else {
      commitSelectedWikiAutocompleteSuggestion()
    }
  }

  public func updateWikiAutocomplete() {
    guard let folderURL else {
      slashCommandSuggestions = []
      tagAutocompleteSuggestions = []
      personAutocompleteSuggestions = []
      wikiAutocompleteSuggestions = []
      return
    }

    if !isNoteMigrationRequired,
       let context = SlashCommandParser.autocompleteContext(in: text, selection: selectedRange) {
      let prefix = context.prefix.lowercased()
      if prefix.isEmpty || "today".hasPrefix(prefix) {
        tagAutocompleteSuggestions = []
        personAutocompleteSuggestions = []
        wikiAutocompleteSuggestions = []
        slashCommandSuggestions = [
          SlashCommandSuggestion(
            command: "today",
            title: "Today's Daily Note",
            subtitle: "Insert a link to today's date",
            replacementRange: context.replacementRange
          )
        ]
        return
      }
    }

    slashCommandSuggestions = []

    if let context = NoteTagParser.autocompleteContext(in: text, selection: selectedRange) {
      wikiAutocompleteSuggestions = []
      personAutocompleteSuggestions = []
      let normalizedPrefix = NoteTagParser.normalizedName(context.prefix)
      tagAutocompleteSuggestions = tagSummaries
        .filter { normalizedPrefix.isEmpty || $0.normalizedName.hasPrefix(normalizedPrefix) }
        .prefix(8)
        .map { tag in
          TagAutocompleteSuggestion(
            name: tag.name,
            noteCount: tag.noteCount,
            replacement: "#\(tag.name)",
            replacementRange: context.replacementRange
          )
        }
      return
    }

    tagAutocompleteSuggestions = []
    if let context = PersonMentionParser.autocompleteContext(in: text, selection: selectedRange) {
      wikiAutocompleteSuggestions = []
      do {
        let trimmedName = context.name.trimmingCharacters(in: .whitespaces)
        let candidates = try noteIndex.personCandidates(
          prefix: trimmedName,
          notesFolderURL: folderURL,
          limit: 8
        )
        var suggestions = candidates.map { candidate in
          PersonAutocompleteSuggestion(
            name: candidate.name,
            subtitle: "Person",
            targetNoteID: candidate.noteID,
            replacementRange: context.replacementRange
          )
        }
        let hasExactMatch = candidates.contains {
          $0.name.compare(trimmedName, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
        if PersonMentionParser.isValidName(trimmedName), !hasExactMatch {
          suggestions.append(PersonAutocompleteSuggestion(
            name: trimmedName,
            subtitle: "Create person",
            targetNoteID: nil,
            replacementRange: context.replacementRange
          ))
        }
        personAutocompleteSuggestions = Array(suggestions.prefix(8))
      } catch {
        personAutocompleteSuggestions = []
      }
      return
    }

    personAutocompleteSuggestions = []
    guard let context = WikiLinkParser.autocompleteContext(in: text, selection: selectedRange) else {
      wikiAutocompleteSuggestions = []
      return
    }

    do {
      switch context {
      case .note(let prefix, let replacementRange):
        let notes = try noteIndex.indexedNotes(notesFolderURL: folderURL, limit: 500)
          .filter {
            let stem = $0.url.deletingPathExtension().lastPathComponent
            return prefix.isEmpty
              || stem.localizedCaseInsensitiveContains(prefix)
              || $0.title.localizedCaseInsensitiveContains(prefix)
          }
          .prefix(8)
        wikiAutocompleteSuggestions = notes.map { note in
          let stem = note.url.deletingPathExtension().lastPathComponent
          let target = stem == note.title ? stem : "\(stem)|\(note.title)"
          return WikiAutocompleteSuggestion(
            title: note.title,
            subtitle: note.relativePath,
            replacement: "[[\(target)]]\(WikiLinkParser.targetComment(noteID: note.noteID))",
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
    refreshImagePreviewStates()
    updateWikiAutocomplete()
    editorFocusToken += 1
  }

  private func clampWikiAutocompleteSelection() {
    guard !wikiAutocompleteSuggestions.isEmpty else {
      wikiAutocompleteSelectionIndex = 0
      return
    }
    wikiAutocompleteSelectionIndex = min(max(wikiAutocompleteSelectionIndex, 0), wikiAutocompleteSuggestions.count - 1)
  }

  private func clampTagAutocompleteSelection() {
    guard !tagAutocompleteSuggestions.isEmpty else {
      tagAutocompleteSelectionIndex = 0
      return
    }
    tagAutocompleteSelectionIndex = min(
      max(tagAutocompleteSelectionIndex, 0),
      tagAutocompleteSuggestions.count - 1
    )
  }

  private func clampPersonAutocompleteSelection() {
    guard !personAutocompleteSuggestions.isEmpty else {
      personAutocompleteSelectionIndex = 0
      return
    }
    personAutocompleteSelectionIndex = min(
      max(personAutocompleteSelectionIndex, 0),
      personAutocompleteSuggestions.count - 1
    )
  }

  private func clampSlashCommandSelection() {
    guard !slashCommandSuggestions.isEmpty else {
      slashCommandSelectionIndex = 0
      return
    }
    slashCommandSelectionIndex = min(
      max(slashCommandSelectionIndex, 0),
      slashCommandSuggestions.count - 1
    )
  }

  public func indentSelectedListItems() {
    applyListIndentation { body, selection in
      MarkdownListIndentation.applyIndent(to: body, selection: selection)
    }
  }

  public func outdentSelectedListItems() {
    applyListIndentation { body, selection in
      MarkdownListIndentation.applyOutdent(to: body, selection: selection)
    }
  }

  private func applyListIndentation(
    _ transform: (String, NSRange) -> MarkdownListIndentationResult?
  ) {
    guard let result = transform(text, selectedRange) else {
      return
    }

    text = result.body
    selectedRange = result.selection
    scheduleAutosave()
    refreshWikiLinkStates()
    refreshImagePreviewStates()
    updateWikiAutocomplete()
    editorFocusToken += 1
  }

  public func noteTextDidChange() {
    scheduleAutosave()
    updateWikiAutocompleteIfNeeded()
    scheduleEditorDecorationRefresh()
  }

  public func insertImageAttachments(_ imports: [ImageAttachmentImport]) {
    guard let folderURL, !imports.isEmpty else {
      return
    }

    let now = dateProvider()
    do {
      let noteDirectory = selectedNote?.url.deletingLastPathComponent()
        ?? noteLibrary.draftNoteDirectory(in: folderURL, now: now)
      for imageImport in imports {
        let attachment = try noteLibrary.saveImageAttachment(
          data: imageImport.data,
          suggestedFilename: imageImport.suggestedFilename,
          preferredExtension: imageImport.preferredExtension,
          now: now,
          relativeTo: noteDirectory
        )
        insertMarkdownImage(attachment)
      }
      refreshWikiLinkStates()
      refreshImagePreviewStates()
      updateWikiAutocomplete()
      editorFocusToken += 1
      autosave(showStatus: true, now: now)
      status = imports.count == 1 ? "Attached image" : "Attached \(imports.count) images"
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  public func insertImageAttachmentFiles(_ urls: [URL]) {
    let imports = urls.compactMap { url in
      let didAccess = url.startAccessingSecurityScopedResource()
      defer {
        if didAccess {
          url.stopAccessingSecurityScopedResource()
        }
      }
      return Self.imageAttachmentImport(fromFileURL: url)
    }
    guard !imports.isEmpty else {
      errorMessage = "Choose a PNG, JPEG, GIF, HEIC, TIFF, or WebP image."
      return
    }
    insertImageAttachments(imports)
  }

  public func resizeImageAttachment(lineLocation: Int, width: Double) {
    let clampedWidth = min(2400, max(96, width.rounded()))
    guard let link = MarkdownImageParser.links(in: text).first(where: { $0.lineRange.location == lineLocation }) else {
      return
    }
    let replacement = "![\(escapedMarkdownImageAltText(link.altText))|\(Int(clampedWidth))](\(link.destination))"
    text = (text as NSString).replacingCharacters(in: link.range, with: replacement)
    selectedRange = clampedRange(selectedRange, in: text)
    scheduleAutosave()
    refreshWikiLinkStates()
    refreshImagePreviewStates()
    updateWikiAutocomplete()
  }

  public func noteSelectionDidChange() {
    formatInactiveMarkdownTables()
    updateWikiAutocompleteIfNeeded()
  }

  public func setVimModeEnabled(_ isEnabled: Bool) {
    isVimModeEnabled = isEnabled
    vimState = VimEditorState(mode: isEnabled ? .normal : .insert)
    saveEditorPreferences()
    editorFocusToken += 1
  }

  public func setRelativeLineNumbersEnabled(_ isEnabled: Bool) {
    showsRelativeLineNumbers = isEnabled
    saveEditorPreferences()
  }

  public func setTheme(_ themeID: LatticeThemeID) {
    selectedThemeID = themeID
    saveEditorPreferences()
  }

  public func setEditorFontFamily(_ fontFamily: EditorFontFamily) {
    editorFontFamily = fontFamily
    saveEditorPreferences()
  }

  public func keyboardShortcut(for id: LatticeKeyboardShortcutID) -> LatticeKeyboardShortcut? {
    guard !disabledKeyboardShortcuts.contains(id) else {
      return nil
    }
    return keyboardShortcutOverrides[id] ?? id.defaultShortcut
  }

  public func setKeyboardShortcut(_ shortcut: LatticeKeyboardShortcut, for id: LatticeKeyboardShortcutID) {
    for otherID in LatticeKeyboardShortcutID.allCases where otherID != id {
      if keyboardShortcut(for: otherID) == shortcut {
        keyboardShortcutOverrides.removeValue(forKey: otherID)
        disabledKeyboardShortcuts.insert(otherID)
      }
    }
    keyboardShortcutOverrides[id] = shortcut
    disabledKeyboardShortcuts.remove(id)
    saveEditorPreferences()
  }

  public func resetKeyboardShortcut(for id: LatticeKeyboardShortcutID) {
    let defaultShortcut = id.defaultShortcut
    for otherID in LatticeKeyboardShortcutID.allCases where otherID != id {
      if keyboardShortcut(for: otherID) == defaultShortcut {
        keyboardShortcutOverrides.removeValue(forKey: otherID)
        disabledKeyboardShortcuts.insert(otherID)
      }
    }
    keyboardShortcutOverrides.removeValue(forKey: id)
    disabledKeyboardShortcuts.remove(id)
    saveEditorPreferences()
  }

  public func vimWrite() {
    flushAutosave()
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

  private func scheduleEditorDecorationRefresh() {
    editorDecorationWorkItem?.cancel()
    let workItem = DispatchWorkItem { [weak self] in
      Task { @MainActor in
        self?.refreshEditorDecorations()
      }
    }
    editorDecorationWorkItem = workItem
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: workItem)
  }

  public func flushAutosave() {
    flushAutosave(syncSavedNote: true)
  }

  private func flushAutosave(syncSavedNote: Bool) {
    autosaveWorkItem?.cancel()
    autosaveWorkItem = nil
    editorDecorationWorkItem?.cancel()
    editorDecorationWorkItem = nil
    refreshEditorDecorations()
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

  private func activateFolder(
    _ url: URL,
    saveBookmark: Bool,
    preserveActiveNoteForSameFolder: Bool = false
  ) throws {
    scopedFolderURL?.stopAccessingSecurityScopedResource()
    _ = url.startAccessingSecurityScopedResource()
    scopedFolderURL = url
    if saveBookmark {
      try folderAccessStore.save(folderURL: url)
    }
    try noteLibrary.selectNotesFolder(url, preserveActiveNoteForSameFolder: preserveActiveNoteForSameFolder)
    clearNavigationHistory()
    folderURL = url
    selectedTagName = nil
    tagSummaries = []
    status = url.lastPathComponent
    refreshNoteMigrationRequirement(presentPrompt: true)
    reloadNotes()
    startNotesFolderChangeMonitor()
    isZenModeEnabled = false
    rebuildNoteIndex()
    refreshTodayActivity()
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
        updateSelectedNoteChangeMonitor()
        let editorBody = Self.editorBody(from: restored.body)
        text = editorBody
        selectedRange = NSRange(location: (editorBody as NSString).length, length: 0)
        status = "Opened \(displayTitle(for: restored.note))"
        preferredCompactColumn = .detail
        refreshWikiLinkStates()
        refreshImagePreviewStates()
        updateWikiAutocomplete()
      }
      reloadNotes(selecting: selectedNote)
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func autosave(showStatus: Bool, syncSavedNote: Bool = true, now: Date? = nil) {
    autosaveWorkItem?.cancel()
    autosaveWorkItem = nil
    do {
      formatInactiveMarkdownTables()
      let saveDate = now ?? dateProvider()
      let previousBody = session.savedBody
      let wasExistingNote = session.currentNote != nil
      switch try session.save(body: text, now: saveDate) {
      case .skippedEmptyDraft, .unchanged:
        return
      case .saved(let note):
        selectedNote = note
        updateSelectedNoteChangeMonitor()
        refreshNoteIndex(for: note)
        rewriteHeadingLinksIfNeeded(for: note, previousBody: previousBody, nextBody: text)
        reloadNotes(selecting: note)
        refreshWikiLinkStates()
        refreshImagePreviewStates()
        updateWikiAutocomplete()
        let rawBody = try noteLibrary.rawBody(for: note)
        recordSavedNoteActivity(
          note: note,
          kind: wasExistingNote ? .noteEdited : .noteCreated,
          previousBody: previousBody,
          nextBody: text,
          rawBody: rawBody
        )
        if syncSavedNote {
          syncTasks(for: note, body: rawBody)
        }
        if showStatus {
          status = "Autosaved \(displayTitle(for: note))"
        }
      }
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func formatInactiveMarkdownTables() {
    guard let result = MarkdownTableFormatter.formatTables(in: text, selection: selectedRange) else {
      return
    }

    text = result.body
    selectedRange = clampedRange(result.selection, in: text)
    refreshWikiLinkStates()
    refreshImagePreviewStates()
    updateWikiAutocomplete()
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
      refreshTagSummaries()
      reloadNotes(selecting: selectedNote)
    } catch {
      // The index is disposable; note files remain the source of truth.
    }
  }

  private func refreshNoteMigrationRequirement(presentPrompt: Bool) {
    do {
      noteMigrationPreview = try noteLibrary.flatNoteMigrationPreview()
      if presentPrompt, noteMigrationPreview != nil {
        isShowingNoteMigrationPrompt = true
      }
    } catch {
      noteMigrationPreview = nil
      if presentPrompt {
        errorMessage = error.localizedDescription
      }
    }
  }

  private func refreshNoteIndex(for note: SavedNote) {
    guard let folderURL else {
      return
    }
    do {
      try noteIndex.refresh(note: note, notesFolderURL: folderURL)
      refreshTagSummaries()
    } catch {
      // Autosave should not fail because the derived index could not refresh.
    }
  }

  private func recordSavedNoteActivity(
    note: SavedNote,
    kind: ActivityEvent.Kind,
    previousBody: String,
    nextBody: String,
    rawBody: String
  ) {
    guard let folderURL else {
      return
    }
    let event = ActivityEvent(
      timestamp: dateProvider(),
      kind: kind,
      noteID: MarkdownDocumentMetadata.noteID(in: rawBody),
      noteRelativePath: Self.relativePath(for: note.url, in: folderURL),
      noteTitle: displayTitle(for: note),
      beforeExcerpt: kind == .noteEdited ? Self.activityExcerpt(from: previousBody) : nil,
      afterExcerpt: Self.activityExcerpt(from: nextBody)
    )
    try? appendActivityEvent(event, notesFolderURL: folderURL, surfaceErrors: false)
  }

  private func appendActivityEvent(
    _ event: ActivityEvent,
    notesFolderURL: URL,
    surfaceErrors: Bool
  ) throws {
    do {
      try activityStore.append(event, notesFolderURL: notesFolderURL)
      refreshTodayActivity()
    } catch {
      if surfaceErrors {
        throw error
      }
    }
  }

  private func refreshTodayActivity() {
    guard let folderURL else {
      todayActivityEvents = []
      return
    }
    do {
      todayActivityEvents = try activityStore.events(on: dateProvider(), notesFolderURL: folderURL)
    } catch {
      todayActivityEvents = []
    }
  }

  private func clearEditorAfterDeletingSelectedNote() {
    session.resetForNewNote()
    selectedNote = nil
    text = ""
    selectedRange = NSRange(location: 0, length: 0)
    wikiLinkStates = []
    wikiAutocompleteSuggestions = []
    tagAutocompleteSuggestions = []
    slashCommandSuggestions = []
    ambiguousWikiLink = nil
    preferredCompactColumn = .sidebar
    reloadNotes(selecting: nil)
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

  private func refreshImagePreviewStates() {
    guard let folderURL else {
      imagePreviewStates = []
      return
    }
    let baseDirectory = selectedNote?.url.deletingLastPathComponent()
      ?? noteLibrary.draftNoteDirectory(in: folderURL, now: dateProvider())
    imagePreviewStates = MarkdownImageParser.links(in: text).compactMap { link in
      guard let url = resolvedLocalImageURL(
        destination: link.destination,
        baseDirectory: baseDirectory,
        notesFolderURL: folderURL
      ) else {
        return nil
      }
      return MarkdownImageRenderState(link: link, url: url)
    }
  }

  private func refreshEditorDecorations() {
    editorDecorationWorkItem?.cancel()
    editorDecorationWorkItem = nil
    refreshWikiLinkStates()
    refreshImagePreviewStates()
    updateWikiAutocompleteIfNeeded()
  }

  private func updateWikiAutocompleteIfNeeded() {
    guard
      (!isNoteMigrationRequired && SlashCommandParser.autocompleteContext(in: text, selection: selectedRange) != nil)
        || NoteTagParser.autocompleteContext(in: text, selection: selectedRange) != nil
        || PersonMentionParser.autocompleteContext(in: text, selection: selectedRange) != nil
        || WikiLinkParser.autocompleteContext(in: text, selection: selectedRange) != nil
    else {
      if !wikiAutocompleteSuggestions.isEmpty {
        wikiAutocompleteSuggestions = []
      }
      if !tagAutocompleteSuggestions.isEmpty {
        tagAutocompleteSuggestions = []
      }
      if !slashCommandSuggestions.isEmpty {
        slashCommandSuggestions = []
      }
      return
    }

    updateWikiAutocomplete()
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

    var didChangeHeading = false
    for (previous, next) in zip(previousHeadings, nextHeadings)
      where previous.level == next.level && previous.title != next.title {
      didChangeHeading = true
      try? noteLibrary.rewriteWikiHeadingLinks(
        targetNoteID: indexed.noteID,
        oldHeading: previous.title,
        newHeading: next.title
      )
    }
    guard didChangeHeading else {
      return
    }
    try? noteIndex.rebuild(notesFolderURL: folderURL)
    if let updatedBody = try? noteLibrary.body(for: note) {
      let editorBody = Self.editorBody(from: updatedBody)
      guard editorBody != text else {
        return
      }
      text = editorBody
      selectedRange = NSRange(location: min(selectedRange.location, (editorBody as NSString).length), length: 0)
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

  @discardableResult
  private func selectHeading(_ heading: String?, in body: String) -> Bool {
    guard let range = headingRange(for: heading, in: body) else {
      return false
    }
    let targetRange = clampedRange(range, in: body)
    guard selectedRange != targetRange else {
      return false
    }
    selectedRange = targetRange
    editorFocusToken += 1
    return true
  }

  private func currentHistoryEntry() -> NavigationHistoryEntry? {
    guard let selectedNote else {
      return nil
    }
    return NavigationHistoryEntry(
      note: selectedNote,
      selectedRange: clampedRange(selectedRange, in: text)
    )
  }

  private func pushCurrentHistoryEntry(destination: SavedNote?, heading: String?) {
    guard let entry = currentHistoryEntry(),
          shouldRecordHistory(entry, destination: destination, heading: heading)
    else {
      return
    }
    Self.appendHistoryEntry(entry, to: &backStack)
    forwardStack.removeAll()
  }

  private func shouldRecordHistory(
    _ entry: NavigationHistoryEntry,
    destination: SavedNote?,
    heading: String?
  ) -> Bool {
    guard let destination else {
      return true
    }
    guard destination == entry.note else {
      return true
    }
    guard let targetRange = headingRange(for: heading, in: text) else {
      return false
    }
    return entry.selectedRange != clampedRange(targetRange, in: text)
  }

  private static func appendHistoryEntry(_ entry: NavigationHistoryEntry, to stack: inout [NavigationHistoryEntry]) {
    guard stack.last != entry else {
      return
    }
    stack.append(entry)
    if stack.count > Self.maximumNavigationHistoryEntries {
      stack.removeFirst(stack.count - Self.maximumNavigationHistoryEntries)
    }
  }

  private func clearNavigationHistory() {
    backStack = []
    forwardStack = []
  }

  private func clampedRange(_ range: NSRange, in body: String) -> NSRange {
    let length = (body as NSString).length
    guard range.location != NSNotFound else {
      return NSRange(location: length, length: 0)
    }
    let location = min(max(range.location, 0), length)
    let rangeLength = min(max(range.length, 0), length - location)
    return NSRange(location: location, length: rangeLength)
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
      let editorBody = Self.editorBody(from: updatedBody)
      text = editorBody
      selectedRange = NSRange(location: min(selectedRange.location, (editorBody as NSString).length), length: 0)
      session.updateSavedBody(updatedBody, for: selectedNote)
      refreshWikiLinkStates()
      refreshImagePreviewStates()
    } catch {
      taskSyncErrorMessage = error.localizedDescription
    }
  }

  private func refreshSelectedNoteForExternalChanges() -> ExternalSelectedNoteChange {
    guard let selectedNote else {
      return .none
    }

    let isDirty = isCurrentEditorDirty
    guard FileManager.default.fileExists(atPath: selectedNote.url.path) else {
      if isDirty {
        status = "Deleted on another device; local edits are still open"
        return .conflict
      }
      clearEditorAfterExternalDelete()
      return .deleted
    }

    do {
      let storedBody = try noteLibrary.body(for: selectedNote)
      let normalizedStoredBody = NoteEditingSession.normalizedBody(storedBody)
      guard normalizedStoredBody != session.savedBody else {
        return .none
      }

      if isDirty {
        status = "Changed on another device; local edits are still open"
        return .conflict
      }

      let editorBody = Self.editorBody(from: storedBody)
      text = editorBody
      selectedRange = NSRange(location: min(selectedRange.location, (editorBody as NSString).length), length: 0)
      session.updateSavedBody(storedBody, for: selectedNote)
      status = "Updated \(displayTitle(for: selectedNote))"
      return .reloaded
    } catch {
      errorMessage = error.localizedDescription
      return .none
    }
  }

  private var isCurrentEditorDirty: Bool {
    autosaveWorkItem != nil || NoteEditingSession.normalizedBody(text) != session.savedBody
  }

  private var noteListSignature: [String] {
    sections.flatMap { section in
      [section.dateString] + section.notes.map { note in
        let modifiedAt = note.modifiedAt?.timeIntervalSinceReferenceDate.description ?? ""
        return "\(note.id)|\(modifiedAt)"
      }
    }
  }

  private func clearEditorAfterExternalDelete() {
    let title = selectedNote.map { displayTitle(for: $0) } ?? "note"
    session.resetForNewNote()
    selectedNote = nil
    text = ""
    selectedRange = NSRange(location: 0, length: 0)
    wikiLinkStates = []
    wikiAutocompleteSuggestions = []
    tagAutocompleteSuggestions = []
    ambiguousWikiLink = nil
    status = "Removed \(title)"
    preferredCompactColumn = .sidebar
    updateSelectedNoteChangeMonitor()
  }

  private func startNotesFolderChangeMonitor() {
    guard let folderURL else {
      notesFolderChangeMonitor.stop()
      return
    }
    notesFolderChangeMonitor.start(
      notesFolderURL: folderURL,
      selectedNoteURL: selectedNote?.url
    ) { [weak self] in
      Task { @MainActor in
        self?.refreshExternalChanges()
      }
    }
  }

  private func updateSelectedNoteChangeMonitor() {
    notesFolderChangeMonitor.updateSelectedNoteURL(selectedNote?.url)
  }

  private static func editorBody(from storedBody: String) -> String {
    var body = storedBody
    while let scalar = body.unicodeScalars.last, CharacterSet.newlines.contains(scalar) {
      body.removeLast()
    }
    return body
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
      allSections = try noteLibrary.listNotes()
      noteTitles = Dictionary(uniqueKeysWithValues: allSections
        .flatMap(\.notes)
        .map { ($0.id, noteLibrary.displayTitle(for: $0)) })
      if let folderURL {
        let indexedNotes = (try? noteIndex.indexedNotes(notesFolderURL: folderURL, limit: 2_000)) ?? []
        notePreviews = Dictionary(uniqueKeysWithValues: indexedNotes.map { ($0.savedNote.id, $0) })
      } else {
        notePreviews = [:]
      }
      if let selectedTagName, let folderURL {
        let taggedNoteIDs = Set(try noteIndex.notes(
          tagged: selectedTagName,
          notesFolderURL: folderURL,
          limit: 2_000
        ).map(\.id))
        sections = allSections.compactMap { section in
          let notes = section.notes.filter { taggedNoteIDs.contains($0.id) }
          return notes.isEmpty ? nil : NoteSection(dateString: section.dateString, notes: notes)
        }
      } else {
        sections = allSections
      }
      selectedNote = note ?? session.currentNote
      updateSelectedNoteChangeMonitor()
    } catch NoteLibraryError.noActiveNotesFolder {
      allSections = []
      sections = []
      noteTitles = [:]
      notePreviews = [:]
      tagSummaries = []
      selectedTagName = nil
      selectedNote = nil
      updateSelectedNoteChangeMonitor()
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func refreshTagSummaries() {
    guard let folderURL else {
      tagSummaries = []
      selectedTagName = nil
      return
    }
    do {
      tagSummaries = try noteIndex.tagSummaries(notesFolderURL: folderURL)
      if let selectedTagName,
         !tagSummaries.contains(where: { $0.normalizedName == selectedTagName }) {
        self.selectedTagName = nil
      }
    } catch {
      tagSummaries = []
      selectedTagName = nil
    }
  }

  private func setEditorFontSize(_ size: Double) {
    editorFontSize = min(Self.maximumEditorFontSize, max(Self.minimumEditorFontSize, size))
  }

  private func saveEditorPreferences() {
    editorPreferencesStore.save(EditorPreferences(
      isVimModeEnabled: isVimModeEnabled,
      showsRelativeLineNumbers: showsRelativeLineNumbers,
      themeID: selectedThemeID,
      fontFamily: editorFontFamily,
      keyboardShortcutOverrides: keyboardShortcutOverrides,
      disabledKeyboardShortcuts: disabledKeyboardShortcuts
    ))
  }

  private var sharedCommandPaletteCommands: [CommandPaletteCommand] {
    guard hasFolder else {
      return []
    }

    return [
      CommandPaletteCommand(
        id: "lattice.toggleZenMode",
        title: isZenModeEnabled ? "Exit Zen Mode" : "Enter Zen Mode",
        subtitle: isZenModeEnabled
          ? "Restore the full notes interface"
          : "Focus the current note",
        systemImage: isZenModeEnabled ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
        keyboardShortcut: keyboardShortcut(for: .zenMode)?.displayText
      ) { [weak self] in
        self?.toggleZenMode()
      },
      CommandPaletteCommand(
        id: "lattice.navigateBack",
        title: "Back",
        subtitle: "Return to the previous note location",
        systemImage: "chevron.left",
        isEnabled: canNavigateBack,
        keyboardShortcut: keyboardShortcut(for: .navigateBack)?.displayText
      ) { [weak self] in
        self?.navigateBack()
      },
      CommandPaletteCommand(
        id: "lattice.navigateForward",
        title: "Forward",
        subtitle: "Go to the next note location",
        systemImage: "chevron.right",
        isEnabled: canNavigateForward,
        keyboardShortcut: keyboardShortcut(for: .navigateForward)?.displayText
      ) { [weak self] in
        self?.navigateForward()
      },
      CommandPaletteCommand(
        id: "lattice.todayNote",
        title: "Today’s Note",
        subtitle: "Create or open today’s daily note",
        systemImage: "calendar",
        isEnabled: !isNoteMigrationRequired
      ) { [weak self] in
        self?.openTodayNote()
      },
      CommandPaletteCommand(
        id: "lattice.newNote",
        title: "New Note",
        subtitle: "Start a fresh Markdown note",
        systemImage: "square.and.pencil",
        keyboardShortcut: keyboardShortcut(for: .newNote)?.displayText
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

  private static func relativePath(for url: URL, in folderURL: URL) -> String? {
    let folderPath = folderURL.standardizedFileURL.path
    let notePath = url.standardizedFileURL.path
    guard notePath == folderPath || notePath.hasPrefix("\(folderPath)/") else {
      return nil
    }
    return String(notePath.dropFirst(folderPath.count + 1))
  }

  private func insertMarkdownImage(_ attachment: SavedAttachment) {
    let nsString = text as NSString
    let range = clampedRange(selectedRange, in: text)
    let markdown = "![\(escapedMarkdownImageAltText(attachment.altText))](\(attachment.markdownPath))"
    let insertion = paddedInsertion(markdown, in: text, replacing: range)
    text = nsString.replacingCharacters(in: range, with: insertion.text)
    selectedRange = NSRange(location: range.location + insertion.cursorOffset, length: 0)
  }

  private func paddedInsertion(
    _ markdown: String,
    in body: String,
    replacing range: NSRange
  ) -> (text: String, cursorOffset: Int) {
    let nsString = body as NSString
    var prefix = ""
    var suffix = ""
    if range.location > 0 {
      let previous = nsString.substring(with: NSRange(location: range.location - 1, length: 1))
      if previous != "\n" {
        prefix = "\n\n"
      }
    }
    let rangeEnd = NSMaxRange(range)
    if rangeEnd < nsString.length {
      let next = nsString.substring(with: NSRange(location: rangeEnd, length: 1))
      if next != "\n" {
        suffix = "\n\n"
      }
    } else {
      suffix = "\n"
    }
    return ("\(prefix)\(markdown)\(suffix)", (prefix + markdown).utf16.count)
  }

  private func escapedMarkdownImageAltText(_ text: String) -> String {
    text
      .replacingOccurrences(of: "[", with: "\\[")
      .replacingOccurrences(of: "]", with: "\\]")
  }

  private static func imageAttachmentImport(fromFileURL url: URL) -> ImageAttachmentImport? {
    let supportedExtensions = Set(["png", "jpg", "jpeg", "gif", "heic", "tif", "tiff", "webp"])
    let fileExtension = url.pathExtension.lowercased()
    guard supportedExtensions.contains(fileExtension),
          let data = try? Data(contentsOf: url) else {
      return nil
    }
    return ImageAttachmentImport(
      data: data,
      suggestedFilename: url.lastPathComponent,
      preferredExtension: fileExtension
    )
  }

  private func resolvedLocalImageURL(
    destination: String,
    baseDirectory: URL,
    notesFolderURL: URL
  ) -> URL? {
    let trimmedDestination = destination.trimmingCharacters(in: .whitespacesAndNewlines)
    guard
      !trimmedDestination.isEmpty,
      URL(string: trimmedDestination)?.scheme == nil,
      !trimmedDestination.hasPrefix("/")
    else {
      return nil
    }

    let candidate = URL(fileURLWithPath: trimmedDestination, relativeTo: baseDirectory).standardizedFileURL
    let rootPath = notesFolderURL.standardizedFileURL.path
    let candidatePath = candidate.path
    guard
      (candidatePath == rootPath || candidatePath.hasPrefix("\(rootPath)/")),
      FileManager.default.fileExists(atPath: candidatePath)
    else {
      return nil
    }
    return candidate
  }

  private static func activityExcerpt(from body: String, limit: Int = 240) -> String? {
    let collapsed = body
      .split(whereSeparator: { $0.isNewline })
      .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
      .joined(separator: " ")
    guard !collapsed.isEmpty else {
      return nil
    }
    if collapsed.count <= limit {
      return collapsed
    }
    let endIndex = collapsed.index(collapsed.startIndex, offsetBy: limit)
    return "\(collapsed[..<endIndex])..."
  }
}

public enum NavigationColumn: Hashable {
  case sidebar
  case detail
}

public enum LatticeNavigationVisibility: Hashable, Sendable {
  case all
  case notesAndEditor
  case editorOnly
}

public struct CommandPaletteCommand: Identifiable {
  public let id: String
  public let title: String
  public let subtitle: String?
  public let systemImage: String
  public let isEnabled: Bool
  public let isSetupSafe: Bool
  public let keyboardShortcut: String?
  private let action: @MainActor () -> Void

  public init(
    id: String,
    title: String,
    subtitle: String? = nil,
    systemImage: String,
    isEnabled: Bool = true,
    isSetupSafe: Bool = false,
    keyboardShortcut: String? = nil,
    action: @escaping @MainActor () -> Void
  ) {
    self.id = id
    self.title = title
    self.subtitle = subtitle
    self.systemImage = systemImage
    self.isEnabled = isEnabled
    self.isSetupSafe = isSetupSafe
    self.keyboardShortcut = keyboardShortcut
    self.action = action
  }

  public var searchableText: String {
    "\(title) \(subtitle ?? "") \(keyboardShortcut ?? "")"
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

public struct TagAutocompleteSuggestion: Identifiable, Equatable {
  public let id = UUID()
  public let name: String
  public let noteCount: Int
  public let replacement: String
  public let replacementRange: NSRange

  public init(name: String, noteCount: Int, replacement: String, replacementRange: NSRange) {
    self.name = name
    self.noteCount = noteCount
    self.replacement = replacement
    self.replacementRange = replacementRange
  }
}

public struct PersonAutocompleteSuggestion: Identifiable, Equatable {
  public let id = UUID()
  public let name: String
  public let subtitle: String
  public let targetNoteID: String?
  public let replacementRange: NSRange

  public init(
    name: String,
    subtitle: String,
    targetNoteID: String?,
    replacementRange: NSRange
  ) {
    self.name = name
    self.subtitle = subtitle
    self.targetNoteID = targetNoteID
    self.replacementRange = replacementRange
  }
}

public struct SlashCommandSuggestion: Identifiable, Equatable {
  public let id = UUID()
  public let command: String
  public let title: String
  public let subtitle: String
  public let replacementRange: NSRange

  public init(
    command: String,
    title: String,
    subtitle: String,
    replacementRange: NSRange
  ) {
    self.command = command
    self.title = title
    self.subtitle = subtitle
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

private struct NavigationHistoryEntry: Equatable {
  let note: SavedNote
  let selectedRange: NSRange
}

private extension LatticeAppModel {
  static let defaultEditorFontSize = 14.0
  static let minimumEditorFontSize = 10.0
  static let maximumEditorFontSize = 28.0
  static let maximumNavigationHistoryEntries = 100
}
