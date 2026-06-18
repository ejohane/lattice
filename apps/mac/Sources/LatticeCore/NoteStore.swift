import Foundation

public struct SavedNote: Equatable {
  public let url: URL

  public init(url: URL) {
    self.url = url
  }

  public var title: String {
    url.deletingPathExtension().lastPathComponent
  }
}

public enum NotesFolderValidationResult: Equatable {
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

public enum NoteStoreError: LocalizedError, Equatable {
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

public final class NoteStore {
  public static let activeNotesFolderPathKey = "activeNotesFolderPath"
  public static let activeNotePathKey = "activeNotePath"

  private let defaults: UserDefaults
  private let fileManager: FileManager

  public init(
    defaults: UserDefaults = .standard,
    fileManager: FileManager = .default
  ) {
    self.defaults = defaults
    self.fileManager = fileManager
  }

  public var defaultNotesFolderURL: URL {
    fileManager.homeDirectoryForCurrentUser
      .appendingPathComponent("Documents", isDirectory: true)
      .appendingPathComponent("Lattice", isDirectory: true)
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
    return SavedNote(url: url)
  }

  public func body(for note: SavedNote) throws -> String {
    try String(contentsOf: note.url, encoding: .utf8)
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

  @discardableResult
  public func createNote(body: String, now: Date = Date()) throws -> SavedNote {
    let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedBody.isEmpty else {
      throw NoteStoreError.emptyNote
    }

    guard let folderURL = activeNotesFolderURL() else {
      throw NoteStoreError.noActiveNotesFolder
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
    guard !trimmedBody.isEmpty else {
      throw NoteStoreError.emptyNote
    }
    guard fileManager.fileExists(atPath: note.url.path) else {
      throw NoteStoreError.missingNote(note.url.path)
    }

    try writeNoteBody(trimmedBody, to: note.url)
    defaults.set(note.url.standardizedFileURL.path, forKey: Self.activeNotePathKey)
    return note
  }

  private func notesDirectory(in rootURL: URL) -> URL {
    rootURL.appendingPathComponent("notes", isDirectory: true)
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

    throw NoteStoreError.invalidNotesFolder("Could not create a unique note filename.")
  }

  private func createDirectory(_ url: URL) throws {
    try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
  }

  private func writeNoteBody(_ body: String, to url: URL) throws {
    try createDirectory(url.deletingLastPathComponent())
    let output = body.hasSuffix("\n") ? body : "\(body)\n"
    try output.write(to: url, atomically: true, encoding: .utf8)
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
