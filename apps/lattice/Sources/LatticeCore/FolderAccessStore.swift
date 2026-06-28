import Foundation

public enum FolderAccessStoreError: LocalizedError, Equatable, Sendable {
  case bookmarkCreationFailed(path: String, reason: String)
  case bookmarkResolutionFailed(reason: String)

  public var errorDescription: String? {
    switch self {
    case .bookmarkCreationFailed(let path, let reason):
      return "Could not create a bookmark for \(path): \(reason)"
    case .bookmarkResolutionFailed(let reason):
      return "Could not restore the selected notes folder: \(reason)"
    }
  }
}

public final class FolderAccessStore {
  private let defaults: UserDefaults
  private let key: String

  public init(defaults: UserDefaults = .standard, key: String = "selectedNotesFolderBookmark") {
    self.defaults = defaults
    self.key = key
  }

  public func save(folderURL: URL) throws(FolderAccessStoreError) {
    let didAccess = folderURL.startAccessingSecurityScopedResource()
    defer {
      if didAccess {
        folderURL.stopAccessingSecurityScopedResource()
      }
    }
    let data = try createBookmarkData(for: folderURL)
    defaults.set(data, forKey: key)
  }

  public func restoreFolderURL() throws(FolderAccessStoreError) -> URL? {
    guard let data = defaults.data(forKey: key) else {
      return nil
    }

    var isStale = false
    let url = try resolveBookmarkData(data, isStale: &isStale)
    if isStale {
      try save(folderURL: url)
    }
    return url
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

  private func createBookmarkData(for folderURL: URL) throws(FolderAccessStoreError) -> Data {
    do {
      return try folderURL.bookmarkData(
        options: bookmarkCreationOptions,
        includingResourceValuesForKeys: nil,
        relativeTo: nil
      )
    } catch {
      throw FolderAccessStoreError.bookmarkCreationFailed(
        path: folderURL.path,
        reason: error.localizedDescription
      )
    }
  }

  private func resolveBookmarkData(
    _ data: Data,
    isStale: inout Bool
  ) throws(FolderAccessStoreError) -> URL {
    do {
      return try URL(
        resolvingBookmarkData: data,
        options: bookmarkResolutionOptions,
        relativeTo: nil,
        bookmarkDataIsStale: &isStale
      )
    } catch {
      throw FolderAccessStoreError.bookmarkResolutionFailed(reason: error.localizedDescription)
    }
  }
}
