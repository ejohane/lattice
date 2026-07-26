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

  private func relativePath(for url: URL) -> String {
    let rootComponents = rootURL.pathComponents
    let fileComponents = url.standardizedFileURL.pathComponents
    guard fileComponents.starts(with: rootComponents) else {
      return url.lastPathComponent
    }
    return fileComponents.dropFirst(rootComponents.count).joined(separator: "/")
  }
}
