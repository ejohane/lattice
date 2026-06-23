import Foundation

public struct SavedNote: Identifiable, Hashable, Sendable {
  public let url: URL
  public let dateString: String
  public let modifiedAt: Date?

  public init(url: URL, dateString: String? = nil, modifiedAt: Date? = nil) {
    self.url = url.standardizedFileURL
    self.dateString = dateString ?? url.deletingLastPathComponent().lastPathComponent
    self.modifiedAt = modifiedAt
  }

  public var id: String {
    url.standardizedFileURL.path
  }

  public var filenameTitle: String {
    url.deletingPathExtension().lastPathComponent
  }

  public static func == (lhs: SavedNote, rhs: SavedNote) -> Bool {
    lhs.id == rhs.id
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(id)
  }
}

public struct NoteSection: Identifiable, Equatable, Sendable {
  public let dateString: String
  public let notes: [SavedNote]

  public init(dateString: String, notes: [SavedNote]) {
    self.dateString = dateString
    self.notes = notes
  }

  public var id: String {
    dateString
  }
}

public enum NotesFolderValidationResult: Equatable, Sendable {
  case valid
  case uninitialized
  case invalid(String)

  public var isUsable: Bool {
    if case .valid = self {
      return true
    }
    return false
  }
}

public enum NoteLibraryError: LocalizedError, Equatable, Sendable {
  case noActiveNotesFolder
  case emptyNote
  case missingNote(String)
  case invalidNotesFolder(String)

  public var errorDescription: String? {
    switch self {
    case .noActiveNotesFolder:
      return "No notes folder is selected."
    case .emptyNote:
      return "Cannot save an empty note."
    case .missingNote(let path):
      return "Note file does not exist: \(path)"
    case .invalidNotesFolder(let message):
      return message
    }
  }
}

public enum NoteSaveResult: Equatable, Sendable {
  case unchanged
  case skippedEmptyDraft
  case saved(SavedNote)
}

public struct RestoredNote: Equatable, Sendable {
  public let note: SavedNote
  public let body: String

  public init(note: SavedNote, body: String) {
    self.note = note
    self.body = body
  }
}

public final class NoteEditingSession {
  private let library: NoteLibrary
  private var activeNote: SavedNote?
  private var lastSavedBody = ""

  public init(library: NoteLibrary) {
    self.library = library
  }

  public var currentNote: SavedNote? {
    activeNote
  }

  public var savedBody: String {
    lastSavedBody
  }

  public func restoreActiveNote() throws -> RestoredNote? {
    guard let note = library.restoreActiveNote() else {
      activeNote = nil
      lastSavedBody = ""
      return nil
    }

    do {
      let body = try library.body(for: note)
      activeNote = note
      lastSavedBody = Self.normalizedBody(body)
      return RestoredNote(note: note, body: body)
    } catch {
      library.clearActiveNote()
      activeNote = nil
      lastSavedBody = ""
      throw error
    }
  }

  public func open(_ note: SavedNote) throws -> RestoredNote {
    let opened = try library.openNote(note)
    let body = try library.body(for: opened)
    activeNote = opened
    lastSavedBody = Self.normalizedBody(body)
    return RestoredNote(note: opened, body: body)
  }

  public func resetForNewNote() {
    activeNote = nil
    lastSavedBody = ""
    library.clearActiveNote()
  }

  @discardableResult
  public func save(body: String) throws -> NoteSaveResult {
    let normalizedBody = Self.normalizedBody(body)
    guard activeNote != nil || !normalizedBody.isEmpty else {
      return .skippedEmptyDraft
    }
    guard normalizedBody != lastSavedBody else {
      return .unchanged
    }

    let note: SavedNote
    if let activeNote {
      note = try library.updateNote(activeNote, body: normalizedBody)
    } else {
      note = try library.createNote(body: normalizedBody)
    }
    activeNote = note
    lastSavedBody = normalizedBody
    return .saved(note)
  }

  public static func normalizedBody(_ body: String) -> String {
    body.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

public final class NoteLibrary {
  public static let activeNotesFolderPathKey = "activeNotesFolderPath"
  public static let activeNotePathKey = "activeNotePath"

  private let defaults: UserDefaults
  private let fileManager: FileManager

  public init(defaults: UserDefaults = .standard, fileManager: FileManager = .default) {
    self.defaults = defaults
    self.fileManager = fileManager
  }

  public var fallbackNotesFolderURL: URL {
    (fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
      ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Documents", isDirectory: true))
      .appendingPathComponent("Lattice", isDirectory: true)
  }

  public var suggestedNotesFolderURL: URL {
    if let cloudURL = fileManager.url(forUbiquityContainerIdentifier: nil) {
      return cloudURL
        .appendingPathComponent("Documents", isDirectory: true)
        .appendingPathComponent("Lattice", isDirectory: true)
    }
    return fallbackNotesFolderURL
  }

  public func activeNotesFolderURL() -> URL? {
    guard
      let path = defaults.string(forKey: Self.activeNotesFolderPathKey),
      !path.isEmpty
    else {
      return nil
    }
    return URL(fileURLWithPath: path, isDirectory: true)
  }

  public func activeNoteURL() -> URL? {
    guard
      let path = defaults.string(forKey: Self.activeNotePathKey),
      !path.isEmpty
    else {
      return nil
    }
    return URL(fileURLWithPath: path)
  }

  public func restoreActiveNote() -> SavedNote? {
    guard
      let url = activeNoteURL(),
      fileManager.fileExists(atPath: url.path)
    else {
      clearActiveNote()
      return nil
    }
    return note(at: url)
  }

  public func body(for note: SavedNote) throws -> String {
    try String(contentsOf: note.url, encoding: .utf8)
  }

  public func displayTitle(for note: SavedNote) -> String {
    guard
      let body = try? body(for: note),
      let heading = Self.firstHeading(in: body)
    else {
      return note.filenameTitle
    }
    return heading
  }

  @discardableResult
  public func openNote(_ note: SavedNote) throws -> SavedNote {
    guard fileManager.fileExists(atPath: note.url.path) else {
      throw NoteLibraryError.missingNote(note.url.path)
    }
    let opened = self.note(at: note.url)
    defaults.set(opened.url.standardizedFileURL.path, forKey: Self.activeNotePathKey)
    return opened
  }

  public func selectNotesFolder(_ url: URL) throws {
    let standardizedURL = url.standardizedFileURL
    try initializeNotesFolder(at: standardizedURL)
    defaults.set(standardizedURL.path, forKey: Self.activeNotesFolderPathKey)
    clearActiveNote()
  }

  public func clearActiveNotesFolder() {
    defaults.removeObject(forKey: Self.activeNotesFolderPathKey)
    clearActiveNote()
  }

  public func clearActiveNote() {
    defaults.removeObject(forKey: Self.activeNotePathKey)
  }

  public func validateNotesFolder(at url: URL) -> NotesFolderValidationResult {
    var isDirectory: ObjCBool = false
    guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
      return .uninitialized
    }
    guard isDirectory.boolValue else {
      return .invalid("Selected path is not a folder.")
    }

    let notesURL = notesDirectory(in: url)
    guard fileManager.fileExists(atPath: notesURL.path, isDirectory: &isDirectory) else {
      return .uninitialized
    }
    guard isDirectory.boolValue else {
      return .invalid("The notes path exists but is not a folder: \(notesURL.path)")
    }

    return .valid
  }

  public func initializeNotesFolder(at url: URL) throws {
    try createDirectory(url)
    try createDirectory(notesDirectory(in: url))
  }

  public func listNotes() throws -> [NoteSection] {
    guard let folderURL = activeNotesFolderURL() else {
      throw NoteLibraryError.noActiveNotesFolder
    }

    try initializeNotesFolder(at: folderURL)
    let notesURL = notesDirectory(in: folderURL)
    let dateURLs = try fileManager.contentsOfDirectory(
      at: notesURL,
      includingPropertiesForKeys: [.isDirectoryKey],
      options: [.skipsHiddenFiles]
    )

    var sections: [NoteSection] = []
    for dateURL in dateURLs {
      let resourceValues = try dateURL.resourceValues(forKeys: [.isDirectoryKey])
      guard resourceValues.isDirectory == true else {
        continue
      }

      let noteURLs = try fileManager.contentsOfDirectory(
        at: dateURL,
        includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
        options: [.skipsHiddenFiles]
      )

      let notes = noteURLs
        .filter { $0.pathExtension.lowercased() == "md" }
        .compactMap { noteURL -> SavedNote? in
          guard (try? noteURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
            return nil
          }
          return note(at: noteURL, dateString: dateURL.lastPathComponent)
        }
        .sorted(by: compareNotesDescending)

      if !notes.isEmpty {
        sections.append(NoteSection(dateString: dateURL.lastPathComponent, notes: notes))
      }
    }

    return sections.sorted { lhs, rhs in
      lhs.dateString > rhs.dateString
    }
  }

  @discardableResult
  public func createNote(body: String, now: Date = Date()) throws -> SavedNote {
    let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedBody.isEmpty else {
      throw NoteLibraryError.emptyNote
    }

    guard let folderURL = activeNotesFolderURL() else {
      throw NoteLibraryError.noActiveNotesFolder
    }
    try initializeNotesFolder(at: folderURL)

    let dateDirectory = notesDirectory(in: folderURL)
      .appendingPathComponent(Self.localDateString(from: now), isDirectory: true)
    try createDirectory(dateDirectory)

    let noteURL = try availableNoteURL(in: dateDirectory, now: now)
    try writeNoteBody(trimmedBody, to: noteURL)
    defaults.set(noteURL.standardizedFileURL.path, forKey: Self.activeNotePathKey)
    return SavedNote(url: noteURL)
  }

  @discardableResult
  public func updateNote(_ note: SavedNote, body: String) throws -> SavedNote {
    let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
    guard fileManager.fileExists(atPath: note.url.path) else {
      throw NoteLibraryError.missingNote(note.url.path)
    }

    try writeNoteBody(trimmedBody, to: note.url)
    defaults.set(note.url.standardizedFileURL.path, forKey: Self.activeNotePathKey)
    return note
  }

  public func notesDirectory(in rootURL: URL) -> URL {
    rootURL.appendingPathComponent("notes", isDirectory: true)
  }

  private func note(at url: URL, dateString: String? = nil) -> SavedNote {
    let resourceValues = try? url.resourceValues(forKeys: [.contentModificationDateKey])
    return SavedNote(
      url: url,
      dateString: dateString,
      modifiedAt: resourceValues?.contentModificationDate
    )
  }

  private func compareNotesDescending(_ lhs: SavedNote, _ rhs: SavedNote) -> Bool {
    if lhs.filenameTitle != rhs.filenameTitle {
      return lhs.filenameTitle > rhs.filenameTitle
    }
    switch (lhs.modifiedAt, rhs.modifiedAt) {
    case let (lhsDate?, rhsDate?):
      return lhsDate > rhsDate
    case (_?, nil):
      return true
    case (nil, _?):
      return false
    case (nil, nil):
      return lhs.url.path > rhs.url.path
    }
  }

  private func availableNoteURL(in directoryURL: URL, now: Date) throws -> URL {
    let baseName = Self.timestampString(from: now)
    let firstURL = directoryURL.appendingPathComponent("\(baseName).md")
    if !fileManager.fileExists(atPath: firstURL.path) {
      return firstURL
    }

    for _ in 0..<20 {
      let suffix = UUID().uuidString.prefix(4).lowercased()
      let candidate = directoryURL.appendingPathComponent("\(baseName)-\(suffix).md")
      if !fileManager.fileExists(atPath: candidate.path) {
        return candidate
      }
    }

    throw NoteLibraryError.invalidNotesFolder("Could not create a unique note filename.")
  }

  private func createDirectory(_ url: URL) throws {
    try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
  }

  private func writeNoteBody(_ body: String, to url: URL) throws {
    try createDirectory(url.deletingLastPathComponent())
    let output = body.isEmpty || body.hasSuffix("\n") ? body : "\(body)\n"
    try output.write(to: url, atomically: true, encoding: .utf8)
  }

  public static func firstHeading(in body: String) -> String? {
    for line in body.components(separatedBy: .newlines) {
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      guard trimmed.hasPrefix("#") else {
        continue
      }
      let markerCount = trimmed.prefix { $0 == "#" }.count
      guard
        (1...6).contains(markerCount),
        trimmed.dropFirst(markerCount).first == " "
      else {
        continue
      }
      let title = trimmed.dropFirst(markerCount).trimmingCharacters(in: .whitespaces)
      if !title.isEmpty {
        return String(title)
      }
    }
    return nil
  }

  private static func localDateString(from date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: date)
  }

  private static func timestampString(from date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss"
    return formatter.string(from: date)
  }
}
