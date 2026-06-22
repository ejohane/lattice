import Foundation
import LatticeCore

final class MacNotesLocationStore {
  private enum Keys {
    static let notesFolderPath = "activeNotesFolderPath"
    static let notesFolderBookmark = "selectedNotesFolderBookmark"
    static let activeNotePath = "activeNotePath"
  }

  private let defaults: UserDefaults
  private let fileManager: FileManager

  init(
    defaults: UserDefaults = .standard,
    fileManager: FileManager = .default
  ) {
    self.defaults = defaults
    self.fileManager = fileManager
  }

  var defaultNotesFolderURL: URL {
    fileManager.homeDirectoryForCurrentUser
      .appendingPathComponent("Documents", isDirectory: true)
      .appendingPathComponent("Lattice", isDirectory: true)
  }

  func activeNotesFolderURL() -> URL? {
    if let bookmarkURL = bookmarkedNotesFolderURL() {
      return bookmarkURL
    }
    guard
      let path = defaults.string(forKey: Keys.notesFolderPath),
      !path.isEmpty
    else {
      return nil
    }
    return URL(fileURLWithPath: path, isDirectory: true)
  }

  func selectNotesFolder(_ url: URL) throws {
    let standardizedURL = url.standardizedFileURL
    try NoteStore.initializeNotesFolder(at: standardizedURL, fileManager: fileManager)
    defaults.set(standardizedURL.path, forKey: Keys.notesFolderPath)
    if let bookmark = try? standardizedURL.bookmarkData(
      options: [.withSecurityScope],
      includingResourceValuesForKeys: nil,
      relativeTo: nil
    ) {
      defaults.set(bookmark, forKey: Keys.notesFolderBookmark)
    }
    clearActiveNote()
  }

  func activeNoteURL() -> URL? {
    guard
      let path = defaults.string(forKey: Keys.activeNotePath),
      !path.isEmpty
    else {
      return nil
    }
    return URL(fileURLWithPath: path)
  }

  func setActiveNoteURL(_ url: URL) {
    defaults.set(url.standardizedFileURL.path, forKey: Keys.activeNotePath)
  }

  func clearActiveNote() {
    defaults.removeObject(forKey: Keys.activeNotePath)
  }

  private func bookmarkedNotesFolderURL() -> URL? {
    guard let bookmark = defaults.data(forKey: Keys.notesFolderBookmark) else {
      return nil
    }

    var isStale = false
    guard let url = try? URL(
      resolvingBookmarkData: bookmark,
      options: [.withSecurityScope],
      relativeTo: nil,
      bookmarkDataIsStale: &isStale
    ), !isStale else {
      defaults.removeObject(forKey: Keys.notesFolderBookmark)
      return nil
    }

    return url
  }
}
