import Foundation

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
}
