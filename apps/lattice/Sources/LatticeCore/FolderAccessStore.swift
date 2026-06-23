import Foundation

public final class FolderAccessStore {
  private let defaults: UserDefaults
  private let key: String

  public init(defaults: UserDefaults = .standard, key: String = "selectedNotesFolderBookmark") {
    self.defaults = defaults
    self.key = key
  }

  public func save(folderURL: URL) throws {
    let didAccess = folderURL.startAccessingSecurityScopedResource()
    defer {
      if didAccess {
        folderURL.stopAccessingSecurityScopedResource()
      }
    }
    let data = try folderURL.bookmarkData(
      options: bookmarkCreationOptions,
      includingResourceValuesForKeys: nil,
      relativeTo: nil
    )
    defaults.set(data, forKey: key)
  }

  public func restoreFolderURL() throws -> URL? {
    guard let data = defaults.data(forKey: key) else {
      return nil
    }

    var isStale = false
    let url = try URL(
      resolvingBookmarkData: data,
      options: bookmarkResolutionOptions,
      relativeTo: nil,
      bookmarkDataIsStale: &isStale
    )
    if isStale {
      try save(folderURL: url)
    }
    return url
  }

  public func clear() {
    defaults.removeObject(forKey: key)
  }

  private var bookmarkCreationOptions: URL.BookmarkCreationOptions {
    #if os(macOS)
    return [.withSecurityScope]
    #else
    return []
    #endif
  }

  private var bookmarkResolutionOptions: URL.BookmarkResolutionOptions {
    #if os(macOS)
    return [.withSecurityScope]
    #else
    return []
    #endif
  }
}
