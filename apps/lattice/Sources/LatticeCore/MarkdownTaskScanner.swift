import Foundation

public struct MarkdownTask: Equatable, Hashable, Sendable {
  public let relativePath: String
  public let lineNumber: Int
  public let checkboxRange: NSRange
  public let titleRange: NSRange
  public let title: String
  public let isCompleted: Bool
  public let headingContext: String?

  public init(
    relativePath: String,
    lineNumber: Int,
    checkboxRange: NSRange,
    titleRange: NSRange,
    title: String,
    isCompleted: Bool,
    headingContext: String?
  ) {
    self.relativePath = relativePath
    self.lineNumber = lineNumber
    self.checkboxRange = checkboxRange
    self.titleRange = titleRange
    self.title = title
    self.isCompleted = isCompleted
    self.headingContext = headingContext
  }

  public var normalizedTitle: String {
    Self.normalizedTitle(title)
  }

  public var fingerprint: String {
    [
      relativePath,
      String(lineNumber),
      normalizedTitle,
      headingContext.map(Self.normalizedTitle) ?? ""
    ].joined(separator: "\u{1f}")
  }

  public static func normalizedTitle(_ value: String) -> String {
    value
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .split { $0.isWhitespace }
      .joined(separator: " ")
      .lowercased()
  }
}

public enum MarkdownTaskScanner {
  public static func tasks(in body: String, relativePath: String) -> [MarkdownTask] {
    let nsString = body as NSString
    let length = nsString.length
    guard length > 0 else {
      return []
    }

    var tasks: [MarkdownTask] = []
    var location = 0
    var lineNumber = 1
    var headingContext: String?
    let regex = taskRegex()

    while location < length {
      let lineRange = nsString.lineRange(for: NSRange(location: location, length: 0))
      let contentRange = lineContentRange(lineRange, in: nsString)
      let line = nsString.substring(with: contentRange)

      if let heading = heading(in: line) {
        headingContext = heading
      }

      if let match = regex.firstMatch(
        in: line,
        range: NSRange(location: 0, length: (line as NSString).length)
      ) {
        let titleRangeInLine = match.range(at: 4)
        let rawTitle = titleRangeInLine.location == NSNotFound
          ? ""
          : (line as NSString).substring(with: titleRangeInLine)
        let title = rawTitle.trimmingCharacters(in: .whitespaces)

        if !title.isEmpty {
          let checkboxRange = NSRange(
            location: contentRange.location + match.range(at: 2).location,
            length: match.range(at: 2).length
          )
          let titleRange = NSRange(
            location: contentRange.location + titleRangeInLine.location,
            length: titleRangeInLine.length
          )
          let state = (line as NSString).substring(with: match.range(at: 3))
          tasks.append(MarkdownTask(
            relativePath: relativePath,
            lineNumber: lineNumber,
            checkboxRange: checkboxRange,
            titleRange: titleRange,
            title: title,
            isCompleted: state.lowercased() == "x",
            headingContext: headingContext
          ))
        }
      }

      let nextLocation = NSMaxRange(lineRange)
      guard nextLocation > location else {
        break
      }
      location = nextLocation
      lineNumber += 1
    }

    return tasks
  }

  public static func allTasks(
    in notesFolderURL: URL,
    fileManager: FileManager = .default
  ) throws -> [MarkdownTask] {
    let noteURLs = try markdownNoteURLs(in: notesFolderURL, fileManager: fileManager)
    var output: [MarkdownTask] = []
    for noteURL in noteURLs {
      guard let relativePath = relativePath(for: noteURL, in: notesFolderURL) else {
        continue
      }
      let body = try String(contentsOf: noteURL, encoding: .utf8)
      output.append(contentsOf: tasks(in: body, relativePath: relativePath))
    }
    return output
  }

  public static func markdownNoteURLs(
    in notesFolderURL: URL,
    fileManager: FileManager = .default
  ) throws -> [URL] {
    let notesURL = notesFolderURL.appendingPathComponent("notes", isDirectory: true)
    var isDirectory: ObjCBool = false
    guard fileManager.fileExists(atPath: notesURL.path, isDirectory: &isDirectory) else {
      return []
    }
    guard isDirectory.boolValue else {
      throw NoteLibraryError.invalidNotesFolder("The notes path exists but is not a folder: \(notesURL.path)")
    }

    let childURLs = try fileManager.contentsOfDirectory(
      at: notesURL,
      includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
      options: [.skipsHiddenFiles]
    )

    var noteURLs: [URL] = []
    for childURL in childURLs {
      let values = try childURL.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
      if values.isRegularFile == true, childURL.pathExtension.lowercased() == "md" {
        noteURLs.append(childURL)
        continue
      }

      guard values.isDirectory == true else {
        continue
      }
      let legacyNoteURLs = try fileManager.contentsOfDirectory(
        at: childURL,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles]
      )
      noteURLs.append(contentsOf: legacyNoteURLs.filter { url in
        url.pathExtension.lowercased() == "md"
          && ((try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true)
      })
    }

    return noteURLs.sorted { $0.path < $1.path }
  }

  public static func relativePath(for noteURL: URL, in notesFolderURL: URL) -> String? {
    let basePath = notesFolderURL.standardizedFileURL.path
    let notePath = noteURL.standardizedFileURL.path
    guard notePath == basePath || notePath.hasPrefix("\(basePath)/") else {
      return nil
    }
    let startIndex = notePath.index(notePath.startIndex, offsetBy: basePath.count)
    let suffix = notePath[startIndex...].trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    return suffix.isEmpty ? nil : suffix
  }

  public static func replacingCompletion(
    in body: String,
    task: MarkdownTask,
    isCompleted: Bool
  ) -> String {
    let replacement = isCompleted ? "[x]" : "[ ]"
    return (body as NSString).replacingCharacters(in: task.checkboxRange, with: replacement)
  }

  private static func lineContentRange(_ lineRange: NSRange, in nsString: NSString) -> NSRange {
    var length = lineRange.length
    while length > 0 {
      let character = nsString.character(at: lineRange.location + length - 1)
      if character == 10 || character == 13 {
        length -= 1
      } else {
        break
      }
    }
    return NSRange(location: lineRange.location, length: length)
  }

  private static func heading(in line: String) -> String? {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    guard trimmed.hasPrefix("#") else {
      return nil
    }
    let markerCount = trimmed.prefix { $0 == "#" }.count
    guard
      (1...6).contains(markerCount),
      trimmed.dropFirst(markerCount).first == " "
    else {
      return nil
    }
    let title = trimmed.dropFirst(markerCount).trimmingCharacters(in: .whitespaces)
    return title.isEmpty ? nil : String(title)
  }

  private static func taskRegex() -> NSRegularExpression {
    // CommonMark-style task list item: "- [ ] Title", "* [x] Title", or "+ [X] Title".
    try! NSRegularExpression(pattern: #"^([ \t]*[-*+][ \t]+)(\[([ xX])\])(?:[ \t]+(.*))?$"#)
  }
}
