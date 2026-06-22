import Foundation
import LatticeCore

final class IOSNotesLocationStore {
  private enum Keys {
    static let notesFolderPath = "activeNotesFolderPath"
    static let notesFolderBookmark = "selectedNotesFolderBookmark"
    static let activeNotePath = "activeNotePath"
  }

  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
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
    let didAccess = url.startAccessingSecurityScopedResource()
    defer {
      if didAccess {
        url.stopAccessingSecurityScopedResource()
      }
    }

    try NoteStore.initializeNotesFolder(at: url)
    defaults.set(url.standardizedFileURL.path, forKey: Keys.notesFolderPath)
    if let bookmark = try? url.bookmarkData(
      options: [],
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

  func withActiveNotesFolder<T>(_ work: (URL) throws -> T) rethrows -> T? {
    guard let url = activeNotesFolderURL() else {
      return nil
    }
    let didAccess = url.startAccessingSecurityScopedResource()
    defer {
      if didAccess {
        url.stopAccessingSecurityScopedResource()
      }
    }
    return try work(url)
  }

  private func bookmarkedNotesFolderURL() -> URL? {
    guard let bookmark = defaults.data(forKey: Keys.notesFolderBookmark) else {
      return nil
    }

    var isStale = false
    guard let url = try? URL(
      resolvingBookmarkData: bookmark,
      options: [],
      relativeTo: nil,
      bookmarkDataIsStale: &isStale
    ), !isStale else {
      defaults.removeObject(forKey: Keys.notesFolderBookmark)
      return nil
    }

    return url
  }
}
