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
  case emptyNote
  case missingNote(String)
  case invalidNotesFolder(String)

  public var errorDescription: String? {
    switch self {
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
  public let rootURL: URL

  private let fileManager: FileManager

  public init(
    rootURL: URL,
    fileManager: FileManager = .default
  ) {
    self.rootURL = rootURL.standardizedFileURL
    self.fileManager = fileManager
  }

  public var notesDirectoryURL: URL {
    Self.notesDirectory(in: rootURL)
  }

  public func validateNotesFolder() -> NotesFolderValidationResult {
    Self.validateNotesFolder(at: rootURL, fileManager: fileManager)
  }

  public func initializeNotesFolder() throws {
    try Self.initializeNotesFolder(at: rootURL, fileManager: fileManager)
  }

  public func body(for note: SavedNote) throws -> String {
    try String(contentsOf: note.url, encoding: .utf8)
  }

  @discardableResult
  public func createNote(body: String, now: Date = Date()) throws -> SavedNote {
    let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedBody.isEmpty else {
      throw NoteStoreError.emptyNote
    }

    try initializeNotesFolder()

    let dateDirectory = notesDirectoryURL
      .appendingPathComponent(Self.localDateString(from: now), isDirectory: true)
    try Self.createDirectory(dateDirectory, fileManager: fileManager)

    let noteURL = try availableNoteURL(in: dateDirectory, now: now)
    try Self.writeNoteBody(trimmedBody, to: noteURL, fileManager: fileManager)
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

    try Self.writeNoteBody(trimmedBody, to: note.url, fileManager: fileManager)
    return note
  }

  public static func validateNotesFolder(
    at url: URL,
    fileManager: FileManager = .default
  ) -> NotesFolderValidationResult {
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

  public static func initializeNotesFolder(
    at url: URL,
    fileManager: FileManager = .default
  ) throws {
    try createDirectory(url, fileManager: fileManager)
    try createDirectory(notesDirectory(in: url), fileManager: fileManager)
  }

  public static func notesDirectory(in rootURL: URL) -> URL {
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

  private static func createDirectory(
    _ url: URL,
    fileManager: FileManager
  ) throws {
    try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
  }

  private static func writeNoteBody(
    _ body: String,
    to url: URL,
    fileManager: FileManager
  ) throws {
    try createDirectory(url.deletingLastPathComponent(), fileManager: fileManager)
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
