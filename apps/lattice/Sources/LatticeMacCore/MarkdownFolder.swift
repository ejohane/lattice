import Foundation
import LatticeEditor

public struct MarkdownFileSnapshot: Equatable, Sendable {
  public let file: MarkdownFile
  public let preview: MarkdownSidebarPreview
  public let tags: [NoteTagOccurrence]

  public init(
    file: MarkdownFile,
    preview: MarkdownSidebarPreview,
    tags: [NoteTagOccurrence]
  ) {
    self.file = file
    self.preview = preview
    self.tags = tags
  }
}

public struct MarkdownFileOperationFailure: Equatable, Sendable {
  public let relativePath: String
  public let message: String

  public init(relativePath: String, message: String) {
    self.relativePath = relativePath
    self.message = message
  }
}

public struct MarkdownFolderScanResult: Equatable, Sendable {
  public let snapshots: [MarkdownFileSnapshot]
  public let failures: [MarkdownFileOperationFailure]

  public init(
    snapshots: [MarkdownFileSnapshot],
    failures: [MarkdownFileOperationFailure]
  ) {
    self.snapshots = snapshots
    self.failures = failures
  }
}

public struct MarkdownTagRewriteResult: Equatable, Sendable {
  public let changedFiles: [MarkdownFile]
  public let failures: [MarkdownFileOperationFailure]

  public var changedNoteCount: Int { changedFiles.count }
}

public enum MarkdownTagRewriteError: LocalizedError, Equatable {
  case invalidTagName(String)

  public var errorDescription: String? {
    switch self {
    case .invalidTagName(let name):
      "“\(name)” is not a valid tag name. Use letters, numbers, -, _, or /, and include at least one letter."
    }
  }
}

public struct DailyNoteAppendResult: Equatable, Sendable {
  public let file: MarkdownFile
  public let document: MarkdownDocument

  public init(file: MarkdownFile, document: MarkdownDocument) {
    self.file = file
    self.document = document
  }
}

public actor MarkdownFolder {
  public let rootURL: URL

  public init(rootURL: URL) {
    self.rootURL = rootURL.standardizedFileURL
  }

  public func files() throws -> [MarkdownFile] {
    let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey, .isHiddenKey]
    guard let enumerator = FileManager.default.enumerator(
      at: rootURL,
      includingPropertiesForKeys: keys,
      options: [.skipsPackageDescendants],
      errorHandler: { _, _ in true }
    ) else {
      return []
    }

    var files: [MarkdownFile] = []
    while let url = enumerator.nextObject() as? URL {
      let values = try url.resourceValues(forKeys: Set(keys))
      if values.isHidden == true {
        if values.isDirectory == true {
          enumerator.skipDescendants()
        }
        continue
      }
      guard values.isRegularFile == true, url.pathExtension.lowercased() == "md" else {
        continue
      }

      files.append(MarkdownFile(
        url: url.standardizedFileURL,
        relativePath: relativePath(for: url)
      ))
    }

    return files.sorted {
      $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending
    }
  }

  public func read(_ file: MarkdownFile) throws -> MarkdownDocument {
    let contents = try String(contentsOf: file.url, encoding: .utf8)
    return MarkdownDocument(fileContents: contents)
  }

  public func scan() throws -> MarkdownFolderScanResult {
    let discoveredFiles = try files()
    var snapshots: [MarkdownFileSnapshot] = []
    var failures: [MarkdownFileOperationFailure] = []
    snapshots.reserveCapacity(discoveredFiles.count)

    for file in discoveredFiles {
      do {
        snapshots.append(try snapshot(for: file))
      } catch {
        snapshots.append(MarkdownFileSnapshot(
          file: file,
          preview: MarkdownSidebarPreview(file: file, body: ""),
          tags: []
        ))
        failures.append(operationFailure(for: file, error: error))
      }
    }
    return MarkdownFolderScanResult(snapshots: snapshots, failures: failures)
  }

  public func sidebarPreviews(
    for files: [MarkdownFile]
  ) -> [MarkdownFile.ID: MarkdownSidebarPreview] {
    var previews: [MarkdownFile.ID: MarkdownSidebarPreview] = [:]
    previews.reserveCapacity(files.count)

    for file in files {
      let contents = (try? String(contentsOf: file.url, encoding: .utf8)) ?? ""
      let body = MarkdownDocument(fileContents: contents).body
      let modifiedAt = try? file.url.resourceValues(
        forKeys: [.contentModificationDateKey]
      ).contentModificationDate
      previews[file.id] = MarkdownSidebarPreview(
        file: file,
        body: body,
        modifiedAt: modifiedAt
      )
    }

    return previews
  }

  public func rewriteTag(
    normalizedName: String,
    to replacementName: String?
  ) throws -> MarkdownTagRewriteResult {
    if let replacementName, !NoteTagParser.isValidName(replacementName) {
      throw MarkdownTagRewriteError.invalidTagName(replacementName)
    }

    let identity = NoteTagParser.normalizedName(normalizedName)
    var changedFiles: [MarkdownFile] = []
    var failures: [MarkdownFileOperationFailure] = []

    for file in try files() {
      do {
        let original = try String(contentsOf: file.url, encoding: .utf8)
        let rewritten = NoteTagParser.replacingTag(
          normalizedName: identity,
          with: replacementName,
          in: original
        )
        guard rewritten != original else { continue }

        try rewritten.write(to: file.url, atomically: true, encoding: .utf8)
        let verified = try String(contentsOf: file.url, encoding: .utf8)
        guard verified == rewritten else {
          try? original.write(to: file.url, atomically: true, encoding: .utf8)
          throw CocoaError(.fileWriteUnknown)
        }
        changedFiles.append(file)
      } catch {
        failures.append(operationFailure(for: file, error: error))
      }
    }

    return MarkdownTagRewriteResult(changedFiles: changedFiles, failures: failures)
  }

  public func write(_ document: MarkdownDocument, to file: MarkdownFile) throws {
    try document.fileContents.write(to: file.url, atomically: true, encoding: .utf8)
  }

  public func createNote() throws -> MarkdownFile {
    for number in 1...10_000 {
      let stem = MarkdownFilename.numberedStem("Untitled", number: number)
      let url = rootURL.appendingPathComponent("\(stem).md")

      do {
        try Data().write(to: url, options: .withoutOverwriting)
        return MarkdownFile(url: url.standardizedFileURL, relativePath: relativePath(for: url))
      } catch {
        if FileManager.default.fileExists(atPath: url.path) {
          continue
        }
        throw error
      }
    }

    throw CocoaError(.fileWriteUnknown)
  }

  public func ensureDailyNote(
    now: Date = Date(),
    calendar: Calendar = .current
  ) throws -> MarkdownFile {
    let stem = MarkdownFilename.dailyNoteStem(for: now, calendar: calendar)
    let url = rootURL.appendingPathComponent("\(stem).md").standardizedFileURL

    if !FileManager.default.fileExists(atPath: url.path) {
      let heading = MarkdownFilename.dailyNoteHeading(for: now, calendar: calendar)
      let body = "# \(heading)\n\n"
      do {
        try Data(body.utf8).write(to: url, options: .withoutOverwriting)
      } catch {
        guard FileManager.default.fileExists(atPath: url.path) else {
          throw error
        }
      }
    }

    return MarkdownFile(url: url, relativePath: relativePath(for: url))
  }

  public func appendToDailyNote(
    _ text: String,
    now: Date = Date(),
    calendar: Calendar = .current
  ) throws -> DailyNoteAppendResult {
    let file = try ensureDailyNote(now: now, calendar: calendar)
    var document = try read(file)
    document.body = Self.appendingJot(
      text,
      to: document.body,
      dailyHeading: MarkdownFilename.dailyNoteHeading(for: now, calendar: calendar)
    )
    try write(document, to: file)
    return DailyNoteAppendResult(file: file, document: document)
  }

  public func ensureWikiNote(named target: String) throws -> MarkdownFile? {
    guard let title = MarkdownFilename.wikiLinkTitle(from: target),
          let stem = MarkdownFilename.wikiLinkStem(from: target)
    else { return nil }

    if let existing = try existingWikiNote(matching: stem) {
      return existing
    }

    let url = rootURL.appendingPathComponent("\(stem).md").standardizedFileURL
    let body = "# \(title)\n\n"
    do {
      try Data(body.utf8).write(to: url, options: .withoutOverwriting)
    } catch {
      if let existing = try existingWikiNote(matching: stem) {
        return existing
      }
      throw error
    }

    return MarkdownFile(url: url, relativePath: relativePath(for: url))
  }

  public func renameUsingFirstMeaningfulLine(
    _ file: MarkdownFile,
    body: String
  ) throws -> MarkdownFile? {
    guard let suggestedStem = MarkdownFilename.suggestedStem(from: body) else {
      return nil
    }

    let directory = file.url.deletingLastPathComponent()
    for number in 1...10_000 {
      let stem = MarkdownFilename.numberedStem(suggestedStem, number: number)
      let url = directory.appendingPathComponent("\(stem).md").standardizedFileURL

      if url == file.url.standardizedFileURL {
        return file
      }
      if FileManager.default.fileExists(atPath: url.path) {
        continue
      }

      do {
        try FileManager.default.moveItem(at: file.url, to: url)
        return MarkdownFile(url: url, relativePath: relativePath(for: url))
      } catch {
        if FileManager.default.fileExists(atPath: url.path) {
          continue
        }
        throw error
      }
    }

    throw CocoaError(.fileWriteUnknown)
  }

  private func relativePath(for url: URL) -> String {
    let rootComponents = rootURL.pathComponents
    let fileComponents = url.standardizedFileURL.pathComponents
    guard fileComponents.starts(with: rootComponents) else {
      return url.lastPathComponent
    }
    return fileComponents.dropFirst(rootComponents.count).joined(separator: "/")
  }

  private func snapshot(for file: MarkdownFile) throws -> MarkdownFileSnapshot {
    let contents = try String(contentsOf: file.url, encoding: .utf8)
    let body = MarkdownDocument(fileContents: contents).body
    let modifiedAt = try file.url.resourceValues(
      forKeys: [.contentModificationDateKey]
    ).contentModificationDate
    return MarkdownFileSnapshot(
      file: file,
      preview: MarkdownSidebarPreview(file: file, body: body, modifiedAt: modifiedAt),
      tags: NoteTagParser.tags(in: contents)
    )
  }

  private func operationFailure(
    for file: MarkdownFile,
    error: Error
  ) -> MarkdownFileOperationFailure {
    MarkdownFileOperationFailure(
      relativePath: file.relativePath,
      message: error.localizedDescription
    )
  }

  private func existingWikiNote(matching stem: String) throws -> MarkdownFile? {
    let candidates = try files().filter {
      $0.url.deletingPathExtension().lastPathComponent.compare(
        stem,
        options: [.caseInsensitive],
        range: nil,
        locale: Locale(identifier: "en_US_POSIX")
      ) == .orderedSame
    }
    return candidates.first {
      $0.url.deletingPathExtension().lastPathComponent == stem
    } ?? candidates.first
  }

  private static func appending(_ text: String, to body: String) -> String {
    guard !body.isEmpty else { return text }
    if body.hasSuffix("\n\n") || text.hasPrefix("\n\n") {
      return body + text
    }
    if body.hasSuffix("\n") || text.hasPrefix("\n") {
      return body + "\n" + text
    }
    return body + "\n\n" + text
  }

  private static func appendingJot(
    _ text: String,
    to body: String,
    dailyHeading: String
  ) -> String {
    let meaningfulBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
    let isEmptyDailyNote = meaningfulBody.isEmpty || meaningfulBody == "# \(dailyHeading)"
    guard !isEmptyDailyNote else {
      return appending(text, to: body)
    }

    return appending(text, to: appending("---", to: body))
  }

}
