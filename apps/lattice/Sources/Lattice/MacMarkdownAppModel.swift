import Foundation
import LatticeMacCore
import Observation

struct MacCommandPaletteNote: Identifiable, Hashable {
  let id: MarkdownFile.ID
  let title: String
  let path: String
}

@MainActor
@Observable
final class MacMarkdownAppModel {
  private let bookmarkStore: MarkdownFolderBookmarkStore
  @ObservationIgnored private let fileActions: MacFileActionClient
  private var folder: MarkdownFolder?
  private var selectedFile: MarkdownFile?
  private var selectedDocument: MarkdownDocument?
  private var hasLoadedSelectedFile = false
  private var hasPendingSelectedSave = false
  private var hasStarted = false
  private var isAccessingSecurityScopedFolder = false
  private var loadGeneration = 0
  private var pendingNoteCreations = 0
  private var automaticallyNamedFileIDs: Set<MarkdownFile.ID> = []
  private var namingFileIDs: Set<MarkdownFile.ID> = []
  private var backHistory: [MarkdownFile.ID] = []
  private var forwardHistory: [MarkdownFile.ID] = []

  @ObservationIgnored private var fileLoadTask: Task<Void, Never>?
  @ObservationIgnored private var saveTask: Task<Void, Never>?

  private(set) var folderURL: URL?
  private(set) var files: [MarkdownFile] = []
  private(set) var sidebarPreviews: [MarkdownFile.ID: MarkdownSidebarPreview] = [:]
  private(set) var selectedFileID: MarkdownFile.ID?
  private(set) var text = ""
  private(set) var isLoadingFiles = false
  private(set) var isLoadingFile = false
  private(set) var isCreatingNote = false
  private(set) var editorFocusRequest = 0
  private(set) var editorContentRevision = 0
  private(set) var editorExternalRefreshRequest = 0
  var jotDraft = "" {
    didSet {
      if jotErrorMessage != nil {
        jotErrorMessage = nil
      }
    }
  }
  private(set) var isSubmittingJot = false
  private(set) var jotErrorMessage: String?
  var errorMessage: String?

  var canCreateNote: Bool {
    folder != nil && !isLoadingFiles
  }

  var canSubmitJot: Bool {
    folder != nil
      && !isSubmittingJot
      && !jotDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  var jotAvailabilityMessage: String? {
    folder == nil ? "Choose a notes folder in Lattice first." : nil
  }

  var canNavigateBack: Bool {
    canNavigate && backHistory.contains(where: hasFile)
  }

  var canNavigateForward: Bool {
    canNavigate && forwardHistory.contains(where: hasFile)
  }

  var selectedNoteTitle: String {
    guard let selectedFile else { return "Lattice" }
    return sidebarPreview(for: selectedFile).title
  }

  func sidebarPreview(for file: MarkdownFile) -> MarkdownSidebarPreview {
    sidebarPreviews[file.id] ?? MarkdownSidebarPreview(file: file, body: "")
  }

  func file(for id: MarkdownFile.ID?) -> MarkdownFile? {
    files.first { $0.id == id }
  }

  @discardableResult
  func performFileAction(
    _ action: MacFileAction,
    for fileID: MarkdownFile.ID
  ) async -> Bool {
    do {
      let url = try await resolvedFileURL(for: fileID)
      switch action {
      case .showInFinder:
        try fileActions.reveal(url)
      case .copyFilePath:
        try fileActions.copyPath(url.path)
      }
      return true
    } catch {
      present(error)
      return false
    }
  }

  func commandPaletteNotes(
    matching query: String,
    limit: Int = 8
  ) -> [MacCommandPaletteNote] {
    let normalizedQuery = query
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()

    let rankedNotes = files.enumerated().compactMap { index, file in
      let preview = sidebarPreview(for: file)
      let note = MacCommandPaletteNote(
        id: file.id,
        title: preview.title,
        path: file.relativePath
      )

      guard !normalizedQuery.isEmpty else {
        return (note: note, rank: 0, recencyIndex: index)
      }

      let candidates = [note.title.lowercased(), note.path.lowercased()]
      guard let rank = candidates.compactMap({ candidate in
        Self.commandPaletteRank(candidate, query: normalizedQuery)
      }).min() else {
        return nil
      }

      return (note: note, rank: rank, recencyIndex: index)
    }
    .sorted { lhs, rhs in
      if lhs.rank != rhs.rank {
        return lhs.rank < rhs.rank
      }
      return lhs.recencyIndex < rhs.recencyIndex
    }

    return Array(rankedNotes.prefix(max(0, limit)).map(\.note))
  }

  func commandPaletteCreationTitle(matching query: String) -> String? {
    guard canCreateNote,
          let title = MarkdownFilename.wikiLinkTitle(from: query),
          let requestedStem = MarkdownFilename.wikiLinkStem(from: query)
    else {
      return nil
    }

    let normalizedTitle = Self.normalizedPaletteIdentity(title)
    let normalizedStem = Self.normalizedPaletteIdentity(requestedStem)
    let hasExactMatch = files.contains { file in
      let renderedTitle = Self.normalizedPaletteIdentity(sidebarPreview(for: file).title)
      let filenameStem = Self.normalizedPaletteIdentity(
        file.url.deletingPathExtension().lastPathComponent
      )
      let relativePathStem = Self.normalizedPaletteIdentity(
        (file.relativePath as NSString).deletingPathExtension
      )
      return renderedTitle == normalizedTitle
        || filenameStem == normalizedStem
        || relativePathStem == normalizedTitle
    }

    return hasExactMatch ? nil : title
  }

  init(
    bookmarkStore: MarkdownFolderBookmarkStore = MarkdownFolderBookmarkStore(),
    fileActions: MacFileActionClient = .live
  ) {
    self.bookmarkStore = bookmarkStore
    self.fileActions = fileActions
  }

  init(
    folderURL: URL,
    bookmarkStore: MarkdownFolderBookmarkStore = MarkdownFolderBookmarkStore(),
    fileActions: MacFileActionClient = .live
  ) {
    self.bookmarkStore = bookmarkStore
    self.fileActions = fileActions
    hasStarted = true
    activateFolder(folderURL)
  }

  func start() {
    guard !hasStarted else { return }
    hasStarted = true

    do {
      if let restoredURL = try bookmarkStore.restoreFolderURL() {
        activateFolder(restoredURL)
      }
    } catch {
      bookmarkStore.clear()
      present(error)
    }
  }

  func chooseFolder(_ url: URL) {
    do {
      try bookmarkStore.save(folderURL: url)
      isLoadingFiles = true
      Task {
        await saveAndFinalizeSelectedNote()
        activateFolder(url)
      }
    } catch {
      present(error)
    }
  }

  func createNote() {
    guard canCreateNote else { return }
    pendingNoteCreations += 1
    startNextNoteCreationIfNeeded()
  }

  func createNote(named title: String) {
    openOrCreateNamedNote(title)
  }

  func navigateBack() {
    guard canNavigate,
          let target = popExistingHistoryTarget(from: &backHistory)
    else { return }

    if let selectedFileID {
      appendHistory(selectedFileID, to: &forwardHistory)
    }
    selectFile(target, recordsHistory: false)
  }

  func navigateForward() {
    guard canNavigate,
          let target = popExistingHistoryTarget(from: &forwardHistory)
    else { return }

    if let selectedFileID {
      appendHistory(selectedFileID, to: &backHistory)
    }
    selectFile(target, recordsHistory: false)
  }

  func openTodayNote(
    now: Date = Date(),
    calendar: Calendar = .current
  ) {
    guard canCreateNote, let activeFolder = folder else { return }

    pendingNoteCreations = 0
    saveTask?.cancel()
    fileLoadTask?.cancel()
    loadGeneration += 1
    let generation = loadGeneration
    isCreatingNote = true

    fileLoadTask = Task {
      defer {
        if generation == loadGeneration {
          isCreatingNote = false
        }
      }
      do {
        try await saveSelectedNote(in: activeFolder)
        do {
          try await finalizeAutomaticNameIfPossible(in: activeFolder)
        } catch {
          present(error)
        }

        let todayFile = try await activeFolder.ensureDailyNote(
          now: now,
          calendar: calendar
        )
        let document = try await activeFolder.read(todayFile)
        let discoveredFiles = try await activeFolder.files()
        let discoveredPreviews = await activeFolder.sidebarPreviews(for: discoveredFiles)
        guard generation == loadGeneration else { return }

        automaticallyNamedFileIDs.remove(todayFile.id)
        replaceDiscoveredFiles(discoveredFiles, previews: discoveredPreviews)
        recordNavigation(to: todayFile.id)
        selectedFileID = todayFile.id
        selectedFile = todayFile
        selectedDocument = document
        hasLoadedSelectedFile = true
        hasPendingSelectedSave = false
        text = document.body
        editorContentRevision += 1
        isLoadingFile = false
        editorFocusRequest += 1
      } catch is CancellationError {
        return
      } catch {
        guard generation == loadGeneration else { return }
        present(error)
      }
    }
  }

  func openWikiLink(_ target: String) {
    openOrCreateNamedNote(target)
  }

  private func openOrCreateNamedNote(_ target: String) {
    guard canCreateNote,
          MarkdownFilename.wikiLinkStem(from: target) != nil,
          let activeFolder = folder
    else { return }

    pendingNoteCreations = 0
    saveTask?.cancel()
    fileLoadTask?.cancel()
    loadGeneration += 1
    let generation = loadGeneration
    isCreatingNote = true

    fileLoadTask = Task {
      defer {
        if generation == loadGeneration {
          isCreatingNote = false
        }
      }
      do {
        try await saveSelectedNote(in: activeFolder)
        do {
          try await finalizeAutomaticNameIfPossible(in: activeFolder)
        } catch {
          present(error)
        }

        guard let linkedFile = try await activeFolder.ensureWikiNote(named: target) else {
          return
        }
        let document = try await activeFolder.read(linkedFile)
        let discoveredFiles = try await activeFolder.files()
        let discoveredPreviews = await activeFolder.sidebarPreviews(for: discoveredFiles)
        guard generation == loadGeneration else { return }

        automaticallyNamedFileIDs.remove(linkedFile.id)
        replaceDiscoveredFiles(discoveredFiles, previews: discoveredPreviews)
        recordNavigation(to: linkedFile.id)
        selectedFileID = linkedFile.id
        selectedFile = linkedFile
        selectedDocument = document
        hasLoadedSelectedFile = true
        hasPendingSelectedSave = false
        text = document.body
        editorContentRevision += 1
        isLoadingFile = false
        editorFocusRequest += 1
      } catch is CancellationError {
        return
      } catch {
        guard generation == loadGeneration else { return }
        present(error)
      }
    }
  }

  func ensureTodayNote(
    now: Date = Date(),
    calendar: Calendar = .current
  ) {
    guard let activeFolder = folder else { return }

    Task {
      do {
        let todayFile = try await activeFolder.ensureDailyNote(
          now: now,
          calendar: calendar
        )
        let discoveredFiles = try await activeFolder.files()
        let discoveredPreviews = await activeFolder.sidebarPreviews(for: discoveredFiles)
        guard folder === activeFolder else { return }

        automaticallyNamedFileIDs.remove(todayFile.id)
        replaceDiscoveredFiles(discoveredFiles, previews: discoveredPreviews)
      } catch {
        guard folder === activeFolder else { return }
        present(error)
      }
    }
  }

  @discardableResult
  func submitJot(
    now: Date = Date(),
    calendar: Calendar = .current
  ) async -> Bool {
    guard !isSubmittingJot else { return false }
    guard !jotDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return false
    }
    guard let activeFolder = folder else {
      jotErrorMessage = "Choose a notes folder in Lattice first."
      return false
    }

    let submittedText = jotDraft
    isSubmittingJot = true
    jotErrorMessage = nil
    saveTask?.cancel()
    defer { isSubmittingJot = false }

    do {
      try await saveSelectedNote(in: activeFolder)
      let result = try await activeFolder.appendToDailyNote(
        submittedText,
        now: now,
        calendar: calendar
      )
      let discoveredFiles = try await activeFolder.files()
      let discoveredPreviews = await activeFolder.sidebarPreviews(for: discoveredFiles)
      guard folder === activeFolder else {
        jotErrorMessage = "The notes folder changed before Jot finished saving."
        return false
      }

      replaceDiscoveredFiles(discoveredFiles, previews: discoveredPreviews)
      automaticallyNamedFileIDs.remove(result.file.id)

      if selectedFileID == result.file.id {
        selectedFile = result.file
        selectedDocument = result.document
        hasLoadedSelectedFile = true
        hasPendingSelectedSave = false
        text = result.document.body
        editorExternalRefreshRequest += 1
      }

      jotDraft = ""
      return true
    } catch {
      jotErrorMessage = error.localizedDescription
      return false
    }
  }

  private func startNextNoteCreationIfNeeded() {
    guard !isCreatingNote,
          pendingNoteCreations > 0,
          let activeFolder = folder
    else { return }

    pendingNoteCreations -= 1
    saveTask?.cancel()
    fileLoadTask?.cancel()
    loadGeneration += 1
    let generation = loadGeneration
    isCreatingNote = true

    fileLoadTask = Task {
      defer {
        if generation == loadGeneration {
          isCreatingNote = false
          startNextNoteCreationIfNeeded()
        }
      }
      do {
        try await saveSelectedNote(in: activeFolder)
        do {
          try await finalizeAutomaticNameIfPossible(in: activeFolder)
        } catch {
          present(error)
        }

        let createdFile = try await activeFolder.createNote()
        let discoveredFiles = try await activeFolder.files()
        let discoveredPreviews = await activeFolder.sidebarPreviews(for: discoveredFiles)
        guard generation == loadGeneration else { return }

        automaticallyNamedFileIDs.insert(createdFile.id)
        replaceDiscoveredFiles(discoveredFiles, previews: discoveredPreviews)
        recordNavigation(to: createdFile.id)
        selectedFileID = createdFile.id
        selectedFile = createdFile
        selectedDocument = MarkdownDocument(fileContents: "")
        hasLoadedSelectedFile = true
        hasPendingSelectedSave = false
        text = ""
        editorContentRevision += 1
        isLoadingFile = false
        editorFocusRequest += 1
      } catch is CancellationError {
        return
      } catch {
        guard generation == loadGeneration else { return }
        present(error)
      }
    }
  }

  func selectFile(_ id: MarkdownFile.ID?, recordsHistory: Bool = true) {
    guard id != selectedFileID else { return }

    let previousFile = selectedFile
    var previousDocument = selectedDocument
    previousDocument?.body = text
    let shouldSavePreviousFile = hasLoadedSelectedFile
    let nextFile = files.first { $0.id == id }
    let activeFolder = folder

    if recordsHistory, let nextFile {
      recordNavigation(to: nextFile.id)
    }

    saveTask?.cancel()
    fileLoadTask?.cancel()
    isCreatingNote = false
    pendingNoteCreations = 0
    loadGeneration += 1
    let generation = loadGeneration

    selectedFileID = nextFile?.id
    selectedFile = nextFile
    selectedDocument = nil
    hasLoadedSelectedFile = false
    hasPendingSelectedSave = false
    text = ""
    editorContentRevision += 1
    isLoadingFile = nextFile != nil

    guard let activeFolder, let nextFile else {
      isLoadingFile = false
      if shouldSavePreviousFile,
         let activeFolder,
         let previousFile,
         let previousDocument {
        Task {
          do {
            try await activeFolder.write(previousDocument, to: previousFile)
            try await finalizeAutomaticNameIfPossible(
              file: previousFile,
              document: previousDocument,
              in: activeFolder
            )
          } catch {
            present(error)
          }
        }
      }
      return
    }

    fileLoadTask = Task {
      do {
        if shouldSavePreviousFile, let previousFile, let previousDocument {
          try await activeFolder.write(previousDocument, to: previousFile)
          do {
            try await finalizeAutomaticNameIfPossible(
              file: previousFile,
              document: previousDocument,
              in: activeFolder
            )
          } catch {
            present(error)
          }
        }
        let loadedDocument = try await activeFolder.read(nextFile)
        guard !Task.isCancelled, generation == loadGeneration else { return }
        selectedDocument = loadedDocument
        text = loadedDocument.body
        editorContentRevision += 1
        hasLoadedSelectedFile = true
        hasPendingSelectedSave = false
        isLoadingFile = false
      } catch is CancellationError {
        return
      } catch {
        guard generation == loadGeneration else { return }
        isLoadingFile = false
        present(error)
      }
    }
  }

  func updateText(_ newText: String) {
    guard !isLoadingFile,
          let selectedFile,
          let folder,
          var document = selectedDocument
    else { return }

    text = newText
    document.body = newText
    selectedDocument = document
    hasPendingSelectedSave = true
    updateSidebarPreview(for: selectedFile, body: newText)
    let shouldFinalizeName = automaticallyNamedFileIDs.contains(selectedFile.id)
      && MarkdownFilename.hasTerminatedMeaningfulLine(in: newText)

    saveTask?.cancel()
    saveTask = Task {
      do {
        try await Task.sleep(for: .milliseconds(300))
        try Task.checkCancellation()
        try await folder.write(document, to: selectedFile)
        try Task.checkCancellation()
        if selectedFileID == selectedFile.id, text == document.body {
          hasPendingSelectedSave = false
        }
        updateSidebarPreview(for: selectedFile, body: document.body, modifiedAt: Date())
        if shouldFinalizeName {
          try await finalizeAutomaticNameIfPossible(
            file: selectedFile,
            document: document,
            in: folder
          )
        }
      } catch is CancellationError {
        return
      } catch {
        present(error)
      }
    }
  }

  func applyEditorEdit(range: NSRange, replacement: String) {
    let source = text as NSString
    let location = max(0, min(range.location, source.length))
    let clampedRange = NSRange(
      location: location,
      length: max(0, min(range.length, source.length - location))
    )
    updateText(source.replacingCharacters(in: clampedRange, with: replacement))
  }

  func applyJotEdit(range: NSRange, replacement: String) {
    let source = jotDraft as NSString
    let location = max(0, min(range.location, source.length))
    let clampedRange = NSRange(
      location: location,
      length: max(0, min(range.length, source.length - location))
    )
    jotDraft = source.replacingCharacters(in: clampedRange, with: replacement)
  }

  func flushSave() {
    guard hasLoadedSelectedFile,
          let selectedFile,
          var document = selectedDocument
    else { return }

    saveTask?.cancel()
    document.body = text
    selectedDocument = document
    do {
      try document.fileContents.write(to: selectedFile.url, atomically: true, encoding: .utf8)
      hasPendingSelectedSave = false
      updateSidebarPreview(for: selectedFile, body: document.body, modifiedAt: Date())
    } catch {
      present(error)
    }
  }

  func finishSession() {
    flushSave()
    Task {
      await saveAndFinalizeSelectedNote()
    }
  }

  func present(_ error: Error) {
    errorMessage = error.localizedDescription
  }

  private func activateFolder(_ url: URL) {
    flushSave()
    fileLoadTask?.cancel()
    loadGeneration += 1

    if isAccessingSecurityScopedFolder {
      folderURL?.stopAccessingSecurityScopedResource()
    }

    isAccessingSecurityScopedFolder = url.startAccessingSecurityScopedResource()
    folderURL = url
    folder = MarkdownFolder(rootURL: url)
    files = []
    sidebarPreviews = [:]
    pendingNoteCreations = 0
    automaticallyNamedFileIDs = []
    namingFileIDs = []
    backHistory = []
    forwardHistory = []
    selectedFile = nil
    selectedDocument = nil
    hasLoadedSelectedFile = false
    hasPendingSelectedSave = false
    selectedFileID = nil
    text = ""
    editorContentRevision += 1
    isLoadingFile = false
    isLoadingFiles = true
    isCreatingNote = false

    guard let folder else { return }
    let generation = loadGeneration
    Task {
      do {
        let discoveredFiles = try await folder.files()
        let discoveredPreviews = await folder.sidebarPreviews(for: discoveredFiles)
        guard generation == loadGeneration else { return }
        replaceDiscoveredFiles(discoveredFiles, previews: discoveredPreviews)
        isLoadingFiles = false
        selectFile(files.first?.id)
      } catch {
        guard generation == loadGeneration else { return }
        isLoadingFiles = false
        present(error)
      }
    }
  }

  private func saveSelectedNote(in activeFolder: MarkdownFolder) async throws {
    guard hasLoadedSelectedFile,
          let selectedFile,
          var document = selectedDocument
    else { return }

    document.body = text
    selectedDocument = document
    try await activeFolder.write(document, to: selectedFile)
    hasPendingSelectedSave = false
    updateSidebarPreview(for: selectedFile, body: document.body, modifiedAt: Date())
  }

  private func resolvedFileURL(for fileID: MarkdownFile.ID) async throws -> URL {
    guard let targetFile = file(for: fileID) else {
      throw MacFileActionError.fileUnavailable(fileID)
    }
    try ensureFileExists(at: targetFile.url)

    guard fileID == selectedFileID,
          let activeFolder = folder
    else {
      return targetFile.url.standardizedFileURL
    }

    saveTask?.cancel()
    if hasPendingSelectedSave {
      try await saveSelectedNote(in: activeFolder)
    }
    try await finalizeAutomaticNameIfPossible(in: activeFolder)
    guard folder === activeFolder else {
      throw MacFileActionError.folderChanged
    }

    let resolvedFile = selectedFile ?? targetFile
    try ensureFileExists(at: resolvedFile.url)
    return resolvedFile.url.standardizedFileURL
  }

  private func ensureFileExists(at url: URL) throws {
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
          !isDirectory.boolValue
    else {
      throw MacFileActionError.fileUnavailable(url)
    }
  }

  private func saveAndFinalizeSelectedNote() async {
    guard let activeFolder = folder else { return }

    saveTask?.cancel()
    do {
      try await saveSelectedNote(in: activeFolder)
      try await finalizeAutomaticNameIfPossible(in: activeFolder)
    } catch {
      present(error)
    }
  }

  private func finalizeAutomaticNameIfPossible(
    in activeFolder: MarkdownFolder
  ) async throws {
    guard let selectedFile,
          var document = selectedDocument
    else { return }

    document.body = text
    selectedDocument = document
    try await finalizeAutomaticNameIfPossible(
      file: selectedFile,
      document: document,
      in: activeFolder
    )
  }

  private func finalizeAutomaticNameIfPossible(
    file: MarkdownFile,
    document: MarkdownDocument,
    in activeFolder: MarkdownFolder
  ) async throws {
    guard automaticallyNamedFileIDs.contains(file.id),
          MarkdownFilename.suggestedStem(from: document.body) != nil,
          namingFileIDs.insert(file.id).inserted
    else { return }

    defer { namingFileIDs.remove(file.id) }
    guard let renamedFile = try await activeFolder.renameUsingFirstMeaningfulLine(
      file,
      body: document.body
    ) else { return }

    automaticallyNamedFileIDs.remove(file.id)
    replaceFile(file, with: renamedFile)
    replaceHistoryFileID(file.id, with: renamedFile.id)

    if selectedFileID == file.id {
      selectedFileID = renamedFile.id
      selectedFile = renamedFile
    }
  }

  private func replaceFile(_ oldFile: MarkdownFile, with newFile: MarkdownFile) {
    if let preview = sidebarPreviews.removeValue(forKey: oldFile.id) {
      sidebarPreviews[newFile.id] = preview
    }
    files.removeAll { $0.id == oldFile.id }
    files.append(newFile)
    sortFilesByRecency()
  }

  private var canNavigate: Bool {
    !isLoadingFiles && !isLoadingFile && !isCreatingNote
  }

  private func hasFile(_ id: MarkdownFile.ID) -> Bool {
    files.contains { $0.id == id }
  }

  private func recordNavigation(to nextID: MarkdownFile.ID) {
    guard let selectedFileID, selectedFileID != nextID else { return }
    appendHistory(selectedFileID, to: &backHistory)
    forwardHistory = []
  }

  private func appendHistory(_ id: MarkdownFile.ID, to history: inout [MarkdownFile.ID]) {
    guard history.last != id else { return }
    history.append(id)
  }

  private func popExistingHistoryTarget(
    from history: inout [MarkdownFile.ID]
  ) -> MarkdownFile.ID? {
    while let candidate = history.popLast() {
      if hasFile(candidate), candidate != selectedFileID {
        return candidate
      }
    }
    return nil
  }

  private func replaceHistoryFileID(
    _ oldID: MarkdownFile.ID,
    with newID: MarkdownFile.ID
  ) {
    backHistory = backHistory.map { $0 == oldID ? newID : $0 }
    forwardHistory = forwardHistory.map { $0 == oldID ? newID : $0 }
  }

  private func updateSidebarPreview(
    for file: MarkdownFile,
    body: String,
    modifiedAt: Date? = nil
  ) {
    let date = modifiedAt ?? sidebarPreviews[file.id]?.modifiedAt
    sidebarPreviews[file.id] = MarkdownSidebarPreview(
      file: file,
      body: body,
      modifiedAt: date
    )
    if modifiedAt != nil {
      sortFilesByRecency()
    }
  }

  private func replaceDiscoveredFiles(
    _ discoveredFiles: [MarkdownFile],
    previews: [MarkdownFile.ID: MarkdownSidebarPreview]
  ) {
    sidebarPreviews = previews
    files = discoveredFiles
    sortFilesByRecency()
  }

  private func sortFilesByRecency() {
    files.sort { lhs, rhs in
      let lhsDate = sidebarPreviews[lhs.id]?.modifiedAt ?? .distantPast
      let rhsDate = sidebarPreviews[rhs.id]?.modifiedAt ?? .distantPast
      if lhsDate != rhsDate {
        return lhsDate > rhsDate
      }
      return lhs.relativePath.localizedStandardCompare(rhs.relativePath) == .orderedAscending
    }
  }

  private static func commandPaletteRank(_ candidate: String, query: String) -> Int? {
    if candidate == query {
      return 0
    }
    if candidate.hasPrefix(query) {
      return 1
    }
    if candidate.contains(query) {
      return 2
    }
    return nil
  }

  private static func normalizedPaletteIdentity(_ value: String) -> String {
    value
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
  }
}
