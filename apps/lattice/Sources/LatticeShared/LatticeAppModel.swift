import Foundation
import LatticeCore
import LatticeEditor
import Observation

@MainActor
@Observable
public final class LatticeAppModel {
  private let folderAccessStore: FolderAccessStore
  public let noteLibrary: NoteLibrary
  private let session: NoteEditingSession
  private var autosaveWorkItem: DispatchWorkItem?
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
  public var commandPaletteQuery = ""
  public var preferredCompactColumn = NavigationColumn.sidebar
  public var editorFocusToken = 0
  public var editorFontSize = 14.0

  public init(
    noteLibrary: NoteLibrary = NoteLibrary(),
    folderAccessStore: FolderAccessStore = FolderAccessStore()
  ) {
    self.noteLibrary = noteLibrary
    self.folderAccessStore = folderAccessStore
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

  public func dismissCommandPalette() {
    isShowingCommandPalette = false
    commandPaletteQuery = ""
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
    status = "New note"
    preferredCompactColumn = .detail
    editorFocusToken += 1
    reloadNotes()
  }

  public func open(_ note: SavedNote) {
    flushAutosave()
    do {
      let restored = try session.open(note)
      selectedNote = restored.note
      text = restored.body
      selectedRange = NSRange(location: (restored.body as NSString).length, length: 0)
      status = "Opened \(displayTitle(for: restored.note))"
      preferredCompactColumn = .detail
      reloadNotes(selecting: restored.note)
      editorFocusToken += 1
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  public func apply(_ command: MarkdownCommand) {
    let result = MarkdownTextEditing.apply(command, to: text, selection: selectedRange)
    text = result.body
    selectedRange = result.selection
    scheduleAutosave()
    editorFocusToken += 1
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
    autosaveWorkItem?.cancel()
    autosaveWorkItem = nil
    autosave(showStatus: false)
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
  }

  private func restoreActiveNote() {
    do {
      if let restored = try session.restoreActiveNote() {
        selectedNote = restored.note
        text = restored.body
        selectedRange = NSRange(location: (restored.body as NSString).length, length: 0)
        status = "Opened \(displayTitle(for: restored.note))"
        preferredCompactColumn = .detail
      }
      reloadNotes(selecting: selectedNote)
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func autosave(showStatus: Bool) {
    autosaveWorkItem?.cancel()
    autosaveWorkItem = nil
    do {
      switch try session.save(body: text) {
      case .skippedEmptyDraft, .unchanged:
        return
      case .saved(let note):
        selectedNote = note
        reloadNotes(selecting: note)
        if showStatus {
          status = "Autosaved \(displayTitle(for: note))"
        }
      }
    } catch {
      errorMessage = error.localizedDescription
    }
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

private extension LatticeAppModel {
  static let defaultEditorFontSize = 14.0
  static let minimumEditorFontSize = 10.0
  static let maximumEditorFontSize = 28.0
}
