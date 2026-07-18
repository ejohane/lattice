import Foundation
import LatticeCore

public enum LatticeQuickCapture {
  @discardableResult
  public static func save(text: String, now: Date = Date()) throws -> String {
    let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !body.isEmpty else {
      throw LatticeQuickCaptureError.emptyText
    }

    let folderURL = try FolderAccessStore().restoreFolderURL()
    let didAccess = folderURL?.startAccessingSecurityScopedResource() ?? false
    defer {
      if didAccess {
        folderURL?.stopAccessingSecurityScopedResource()
      }
    }

    let note = try NoteLibrary().createNote(body: body, now: now)
    return note.url.lastPathComponent
  }
}

public enum LatticeQuickCaptureError: LocalizedError {
  case emptyText

  public var errorDescription: String? {
    switch self {
    case .emptyText:
      return "Enter some text to capture."
    }
  }
}
