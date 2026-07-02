import Foundation

public struct SavedNote: Identifiable, Hashable, Sendable {
  public let url: URL
  public let dateString: String
  public let modifiedAt: Date?

  public init(url: URL, dateString: String? = nil, modifiedAt: Date? = nil) {
    self.url = url.standardizedFileURL
    self.dateString = dateString ?? url.deletingLastPathComponent().lastPathComponent
    self.modifiedAt = modifiedAt
  }

  public var id: String {
    url.standardizedFileURL.path
  }

  public var filenameTitle: String {
    url.deletingPathExtension().lastPathComponent
  }

  public static func == (lhs: SavedNote, rhs: SavedNote) -> Bool {
    lhs.id == rhs.id
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(id)
  }
}

public struct NoteSection: Identifiable, Equatable, Sendable {
  public let dateString: String
  public let notes: [SavedNote]

  public init(dateString: String, notes: [SavedNote]) {
    self.dateString = dateString
    self.notes = notes
  }

  public var id: String {
    dateString
  }
}

public enum NotesFolderValidationResult: Equatable, Sendable {
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

public enum NoteLibraryError: LocalizedError, Equatable, Sendable {
  case noActiveNotesFolder
  case emptyNote
  case missingNote(String)
  case invalidNotesFolder(String)

  public var errorDescription: String? {
    switch self {
    case .noActiveNotesFolder:
      return "No notes folder is selected."
    case .emptyNote:
      return "Cannot save an empty note."
    case .missingNote(let path):
      return "Note file does not exist: \(path)"
    case .invalidNotesFolder(let message):
      return message
    }
  }
}

public enum NoteSaveResult: Equatable, Sendable {
  case unchanged
  case skippedEmptyDraft
  case saved(SavedNote)
}

public enum RecommendedNotesFolder: Equatable, Sendable {
  case iCloud(URL)
  case localFallback(URL)

  public var url: URL {
    switch self {
    case .iCloud(let url), .localFallback(let url):
      return url
    }
  }

  public var isCloudBacked: Bool {
    if case .iCloud = self {
      return true
    }
    return false
  }
}

public struct RestoredNote: Equatable, Sendable {
  public let note: SavedNote
  public let body: String

  public init(note: SavedNote, body: String) {
    self.note = note
    self.body = body
  }
}

public final class NoteEditingSession {
  private let library: NoteLibrary
  private var activeNote: SavedNote?
  private var lastSavedBody = ""

  public init(library: NoteLibrary) {
    self.library = library
  }

  public var currentNote: SavedNote? {
    activeNote
  }

  public var savedBody: String {
    lastSavedBody
  }

  public func restoreActiveNote() throws -> RestoredNote? {
    guard let note = library.restoreActiveNote() else {
      activeNote = nil
      lastSavedBody = ""
      return nil
    }

    do {
      let body = try library.body(for: note)
      activeNote = note
      lastSavedBody = Self.normalizedBody(body)
      return RestoredNote(note: note, body: body)
    } catch {
      library.clearActiveNote()
      activeNote = nil
      lastSavedBody = ""
      throw error
    }
  }

  public func open(_ note: SavedNote) throws -> RestoredNote {
    let opened = try library.openNote(note)
    let body = try library.body(for: opened)
    activeNote = opened
    lastSavedBody = Self.normalizedBody(body)
    return RestoredNote(note: opened, body: body)
  }

  public func resetForNewNote() {
    activeNote = nil
    lastSavedBody = ""
    library.clearActiveNote()
  }

  public func updateSavedBody(_ body: String, for note: SavedNote) {
    guard activeNote == note else {
      return
    }
    lastSavedBody = Self.normalizedBody(body)
  }

  @discardableResult
  public func save(body: String) throws -> NoteSaveResult {
    let normalizedBody = Self.normalizedBody(body)
    guard activeNote != nil || !normalizedBody.isEmpty else {
      return .skippedEmptyDraft
    }
    guard normalizedBody != lastSavedBody else {
      return .unchanged
    }

    let note: SavedNote
    if let activeNote {
      note = try library.updateNote(activeNote, body: normalizedBody)
    } else {
      note = try library.createNote(body: normalizedBody)
    }
    activeNote = note
    lastSavedBody = normalizedBody
    return .saved(note)
  }

  public static func normalizedBody(_ body: String) -> String {
    guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return ""
    }
    let bodyWithoutTrailingNewlines = body.trimmingCharacters(in: .newlines)
    return bodyWithoutTrailingNewlines
  }
}

public final class NoteLibrary {
  public static let iCloudContainerIdentifier = "iCloud.com.ejohane.lattice.ios"
  public static let activeNotesFolderPathKey = "activeNotesFolderPath"
  public static let activeNotePathKey = "activeNotePath"

  private let defaults: UserDefaults
  private let fileManager: FileManager
  private let fallbackNotesFolderURLProvider: () -> URL
  private let iCloudContainerURLProvider: () -> URL?

  public init(
    defaults: UserDefaults = .standard,
    fileManager: FileManager = .default,
    fallbackNotesFolderURLProvider: (() -> URL)? = nil,
    iCloudContainerURLProvider: (() -> URL?)? = nil
  ) {
    self.defaults = defaults
    self.fileManager = fileManager
    let resolvedFileManager = fileManager
    self.fallbackNotesFolderURLProvider = fallbackNotesFolderURLProvider ?? {
      (resolvedFileManager.urls(for: .documentDirectory, in: .userDomainMask).first
        ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Documents", isDirectory: true))
        .appendingPathComponent("Lattice", isDirectory: true)
    }
    self.iCloudContainerURLProvider = iCloudContainerURLProvider ?? {
      resolvedFileManager.url(forUbiquityContainerIdentifier: Self.iCloudContainerIdentifier)
    }
  }

  public var fallbackNotesFolderURL: URL {
    fallbackNotesFolderURLProvider()
  }

  public var recommendedNotesFolder: RecommendedNotesFolder {
    if let cloudURL = iCloudContainerURLProvider() {
      return .iCloud(
        cloudURL
        .appendingPathComponent("Documents", isDirectory: true)
        .appendingPathComponent("Lattice", isDirectory: true)
      )
    }
    return .localFallback(fallbackNotesFolderURL)
  }

  public var suggestedNotesFolderURL: URL {
    recommendedNotesFolder.url
  }

  public func activeNotesFolderURL() -> URL? {
    guard
      let path = defaults.string(forKey: Self.activeNotesFolderPathKey),
      !path.isEmpty
    else {
      return nil
    }
    return URL(fileURLWithPath: path, isDirectory: true)
  }

  public func activeNoteURL() -> URL? {
    guard
      let path = defaults.string(forKey: Self.activeNotePathKey),
      !path.isEmpty
    else {
      return nil
    }
    return URL(fileURLWithPath: path)
  }

  public func restoreActiveNote() -> SavedNote? {
    guard
      let url = activeNoteURL(),
      fileManager.fileExists(atPath: url.path)
    else {
      clearActiveNote()
      return nil
    }
    return note(at: url)
  }

  public func body(for note: SavedNote) throws -> String {
    let rawBody = try rawBody(for: note)
    return MarkdownDocumentMetadata.strippingFrontMatter(from: rawBody)
  }

  public func rawBody(for note: SavedNote) throws -> String {
    try String(contentsOf: note.url, encoding: .utf8)
  }

  public func displayTitle(for note: SavedNote) -> String {
    guard
      let body = try? body(for: note),
      let title = Self.firstRenderedLine(in: body)
    else {
      return note.filenameTitle
    }
    return title
  }

  @discardableResult
  public func openNote(_ note: SavedNote) throws -> SavedNote {
    guard fileManager.fileExists(atPath: note.url.path) else {
      throw NoteLibraryError.missingNote(note.url.path)
    }
    let opened = self.note(at: note.url)
    defaults.set(opened.url.standardizedFileURL.path, forKey: Self.activeNotePathKey)
    return opened
  }

  public func selectNotesFolder(_ url: URL) throws {
    let standardizedURL = url.standardizedFileURL
    try initializeNotesFolder(at: standardizedURL)
    defaults.set(standardizedURL.path, forKey: Self.activeNotesFolderPathKey)
    clearActiveNote()
  }

  public func clearActiveNotesFolder() {
    defaults.removeObject(forKey: Self.activeNotesFolderPathKey)
    clearActiveNote()
  }

  public func clearActiveNote() {
    defaults.removeObject(forKey: Self.activeNotePathKey)
  }

  public func validateNotesFolder(at url: URL) -> NotesFolderValidationResult {
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

  public func initializeNotesFolder(at url: URL) throws {
    try createDirectory(url)
    try createDirectory(notesDirectory(in: url))
  }

  public func migrateFallbackNotesToICloudIfNeeded(iCloudFolderURL: URL) throws {
    let sourceRootURL = fallbackNotesFolderURL.standardizedFileURL
    let destinationRootURL = iCloudFolderURL.standardizedFileURL
    guard sourceRootURL != destinationRootURL else {
      return
    }

    let sourceNotesURL = notesDirectory(in: sourceRootURL)
    var isDirectory: ObjCBool = false
    guard fileManager.fileExists(atPath: sourceNotesURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
      return
    }

    try initializeNotesFolder(at: destinationRootURL)
    try copyMissingItems(from: sourceNotesURL, to: notesDirectory(in: destinationRootURL))
  }

  public func listNotes() throws -> [NoteSection] {
    guard let folderURL = activeNotesFolderURL() else {
      throw NoteLibraryError.noActiveNotesFolder
    }

    try initializeNotesFolder(at: folderURL)
    let notesURL = notesDirectory(in: folderURL)
    let dateURLs = try fileManager.contentsOfDirectory(
      at: notesURL,
      includingPropertiesForKeys: [.isDirectoryKey],
      options: [.skipsHiddenFiles]
    )

    var sections: [NoteSection] = []
    for dateURL in dateURLs {
      let resourceValues = try dateURL.resourceValues(forKeys: [.isDirectoryKey])
      guard resourceValues.isDirectory == true else {
        continue
      }

      let noteURLs = try fileManager.contentsOfDirectory(
        at: dateURL,
        includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
        options: [.skipsHiddenFiles]
      )

      let notes = noteURLs
        .filter { $0.pathExtension.lowercased() == "md" }
        .compactMap { noteURL -> SavedNote? in
          guard (try? noteURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
            return nil
          }
          return note(at: noteURL, dateString: dateURL.lastPathComponent)
        }
        .sorted(by: compareNotesDescending)

      if !notes.isEmpty {
        sections.append(NoteSection(dateString: dateURL.lastPathComponent, notes: notes))
      }
    }

    return sections.sorted { lhs, rhs in
      lhs.dateString > rhs.dateString
    }
  }

  @discardableResult
  public func createNote(body: String, now: Date = Date()) throws -> SavedNote {
    let normalizedBody = NoteEditingSession.normalizedBody(body)
    guard !normalizedBody.isEmpty else {
      throw NoteLibraryError.emptyNote
    }

    guard let folderURL = activeNotesFolderURL() else {
      throw NoteLibraryError.noActiveNotesFolder
    }
    try initializeNotesFolder(at: folderURL)

    let dateDirectory = notesDirectory(in: folderURL)
      .appendingPathComponent(Self.localDateString(from: now), isDirectory: true)
    try createDirectory(dateDirectory)

    let noteURL = try availableNoteURL(in: dateDirectory, now: now)
    try writeNoteBody(MarkdownDocumentMetadata.ensureNoteID(in: normalizedBody), to: noteURL)
    defaults.set(noteURL.standardizedFileURL.path, forKey: Self.activeNotePathKey)
    return SavedNote(url: noteURL)
  }

  @discardableResult
  public func createLinkedNote(title: String, now: Date = Date()) throws -> SavedNote {
    let trimmedTitle = sanitizedFilenameStem(title)
    guard !trimmedTitle.isEmpty else {
      throw NoteLibraryError.emptyNote
    }

    guard let folderURL = activeNotesFolderURL() else {
      throw NoteLibraryError.noActiveNotesFolder
    }
    try initializeNotesFolder(at: folderURL)

    let dateDirectory = notesDirectory(in: folderURL)
      .appendingPathComponent(Self.localDateString(from: now), isDirectory: true)
    try createDirectory(dateDirectory)

    let noteURL = try availableLinkedNoteURL(title: trimmedTitle, in: dateDirectory)
    let body = MarkdownDocumentMetadata.ensureNoteID(in: "# \(trimmedTitle)\n")
    try writeNoteBody(body, to: noteURL)
    defaults.set(noteURL.standardizedFileURL.path, forKey: Self.activeNotePathKey)
    return SavedNote(url: noteURL)
  }

  @discardableResult
  public func updateNote(_ note: SavedNote, body: String) throws -> SavedNote {
    let normalizedBody = NoteEditingSession.normalizedBody(body)
    guard fileManager.fileExists(atPath: note.url.path) else {
      throw NoteLibraryError.missingNote(note.url.path)
    }

    let existingID = (try? rawBody(for: note)).flatMap { MarkdownDocumentMetadata.noteID(in: $0) }
    let nextBody = normalizedBody.isEmpty
      ? ""
      : MarkdownDocumentMetadata.ensureNoteID(
        in: normalizedBody,
        id: existingID ?? UUID().uuidString
      )
    try writeNoteBody(nextBody, to: note.url)
    defaults.set(note.url.standardizedFileURL.path, forKey: Self.activeNotePathKey)
    return note
  }

  @discardableResult
  public func renameNote(_ note: SavedNote, to title: String) throws -> SavedNote {
    let trimmedTitle = sanitizedFilenameStem(title)
    guard !trimmedTitle.isEmpty else {
      throw NoteLibraryError.emptyNote
    }
    guard fileManager.fileExists(atPath: note.url.path) else {
      throw NoteLibraryError.missingNote(note.url.path)
    }
    let destination = note.url.deletingLastPathComponent().appendingPathComponent("\(trimmedTitle).md")
    guard destination.standardizedFileURL != note.url.standardizedFileURL else {
      return note
    }
    if fileManager.fileExists(atPath: destination.path) {
      throw NoteLibraryError.invalidNotesFolder("A note named \(trimmedTitle).md already exists in this folder.")
    }
    try fileManager.moveItem(at: note.url, to: destination)
    let renamed = SavedNote(url: destination, dateString: note.dateString)
    defaults.set(renamed.url.standardizedFileURL.path, forKey: Self.activeNotePathKey)
    return renamed
  }

  public func deleteNote(_ note: SavedNote) throws {
    guard fileManager.fileExists(atPath: note.url.path) else {
      throw NoteLibraryError.missingNote(note.url.path)
    }
    try fileManager.removeItem(at: note.url)
    if activeNoteURL()?.standardizedFileURL == note.url.standardizedFileURL {
      clearActiveNote()
    }
  }

  public func rewriteWikiLinks(targetNoteID: String, oldStem: String, newStem: String) throws {
    guard let folderURL = activeNotesFolderURL() else {
      throw NoteLibraryError.noActiveNotesFolder
    }
    for section in try listNotes() {
      for note in section.notes {
        let raw = try rawBody(for: note)
        let links = WikiLinkParser.links(in: MarkdownDocumentMetadata.strippingFrontMatter(from: raw))
        guard !links.isEmpty else {
          continue
        }
        var body = MarkdownDocumentMetadata.strippingFrontMatter(from: raw)
        var didChange = false
        for link in links.reversed() {
          let matchesID = link.targetNoteID == targetNoteID
          let matchesUniqueText = link.targetNoteID == nil && link.targetStem == oldStem
          guard matchesID || matchesUniqueText else {
            continue
          }
          let replacement = Self.rewrittenWikiLink(link, newStem: newStem, targetNoteID: targetNoteID)
          body = (body as NSString).replacingCharacters(in: link.totalRange, with: replacement)
          didChange = true
        }
        if didChange {
          let id = MarkdownDocumentMetadata.noteID(in: raw) ?? UUID().uuidString
          try writeNoteBody(MarkdownDocumentMetadata.ensureNoteID(in: body, id: id), to: note.url)
        }
      }
    }
    try initializeNotesFolder(at: folderURL)
  }

  public func rewriteWikiHeadingLinks(
    targetNoteID: String,
    oldHeading: String,
    newHeading: String
  ) throws {
    guard let folderURL = activeNotesFolderURL() else {
      throw NoteLibraryError.noActiveNotesFolder
    }
    let oldAnchor = WikiLinkParser.obsidianAnchor(for: oldHeading)
    for section in try listNotes() {
      for note in section.notes {
        let raw = try rawBody(for: note)
        var body = MarkdownDocumentMetadata.strippingFrontMatter(from: raw)
        let links = WikiLinkParser.links(in: body)
        guard !links.isEmpty else {
          continue
        }
        var didChange = false
        for link in links.reversed() {
          guard
            link.targetNoteID == targetNoteID,
            let linkHeading = link.targetHeading,
            WikiLinkParser.obsidianAnchor(for: linkHeading) == oldAnchor
          else {
            continue
          }
          let replacement = Self.rewrittenWikiLink(
            link,
            newStem: link.targetStem ?? "",
            targetNoteID: targetNoteID,
            newHeading: newHeading
          )
          body = (body as NSString).replacingCharacters(in: link.totalRange, with: replacement)
          didChange = true
        }
        if didChange {
          let id = MarkdownDocumentMetadata.noteID(in: raw) ?? UUID().uuidString
          try writeNoteBody(MarkdownDocumentMetadata.ensureNoteID(in: body, id: id), to: note.url)
        }
      }
    }
    try initializeNotesFolder(at: folderURL)
  }

  public func notesDirectory(in rootURL: URL) -> URL {
    rootURL.appendingPathComponent("notes", isDirectory: true)
  }

  private func note(at url: URL, dateString: String? = nil) -> SavedNote {
    let resourceValues = try? url.resourceValues(forKeys: [.contentModificationDateKey])
    return SavedNote(
      url: url,
      dateString: dateString,
      modifiedAt: resourceValues?.contentModificationDate
    )
  }

  private func compareNotesDescending(_ lhs: SavedNote, _ rhs: SavedNote) -> Bool {
    if lhs.filenameTitle != rhs.filenameTitle {
      return lhs.filenameTitle > rhs.filenameTitle
    }
    switch (lhs.modifiedAt, rhs.modifiedAt) {
    case let (lhsDate?, rhsDate?):
      return lhsDate > rhsDate
    case (_?, nil):
      return true
    case (nil, _?):
      return false
    case (nil, nil):
      return lhs.url.path > rhs.url.path
    }
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

    throw NoteLibraryError.invalidNotesFolder("Could not create a unique note filename.")
  }

  private func availableLinkedNoteURL(title: String, in directoryURL: URL) throws -> URL {
    let firstURL = directoryURL.appendingPathComponent("\(title).md")
    if !fileManager.fileExists(atPath: firstURL.path) {
      return firstURL
    }

    for index in 2..<100 {
      let candidate = directoryURL.appendingPathComponent("\(title) \(index).md")
      if !fileManager.fileExists(atPath: candidate.path) {
        return candidate
      }
    }

    throw NoteLibraryError.invalidNotesFolder("Could not create a unique note filename for \(title).")
  }

  private func sanitizedFilenameStem(_ title: String) -> String {
    title
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: "/", with: "-")
      .replacingOccurrences(of: ":", with: "-")
  }

  private func createDirectory(_ url: URL) throws {
    try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
  }

  private func copyMissingItems(from sourceURL: URL, to destinationURL: URL) throws {
    try createDirectory(destinationURL)
    let childURLs = try fileManager.contentsOfDirectory(
      at: sourceURL,
      includingPropertiesForKeys: [.isDirectoryKey],
      options: [.skipsHiddenFiles]
    )

    for sourceChildURL in childURLs {
      let resourceValues = try sourceChildURL.resourceValues(forKeys: [.isDirectoryKey])
      let destinationChildURL = destinationURL.appendingPathComponent(
        sourceChildURL.lastPathComponent,
        isDirectory: resourceValues.isDirectory == true
      )
      if resourceValues.isDirectory == true {
        try copyMissingItems(from: sourceChildURL, to: destinationChildURL)
      } else if !fileManager.fileExists(atPath: destinationChildURL.path) {
        try fileManager.copyItem(at: sourceChildURL, to: destinationChildURL)
      }
    }
  }

  private func writeNoteBody(_ body: String, to url: URL) throws {
    try createDirectory(url.deletingLastPathComponent())
    let output = body.isEmpty || body.hasSuffix("\n") ? body : "\(body)\n"
    try output.write(to: url, atomically: true, encoding: .utf8)
  }

  public static func firstHeading(in body: String) -> String? {
    for line in body.components(separatedBy: .newlines) {
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      guard trimmed.hasPrefix("#") else {
        continue
      }
      let markerCount = trimmed.prefix { $0 == "#" }.count
      guard
        (1...6).contains(markerCount),
        trimmed.dropFirst(markerCount).first == " "
      else {
        continue
      }
      let title = trimmed.dropFirst(markerCount).trimmingCharacters(in: .whitespaces)
      if !title.isEmpty {
        return String(title)
      }
    }
    return nil
  }

  public static func firstRenderedLine(in body: String) -> String? {
    var isInsideCodeFence = false

    for line in body.components(separatedBy: .newlines) {
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      if isCodeFence(trimmed) {
        isInsideCodeFence.toggle()
        continue
      }

      let rendered = isInsideCodeFence
        ? trimmed
        : renderedMarkdownLineText(from: trimmed)
      if !rendered.isEmpty {
        return rendered
      }
    }

    return nil
  }

  private static func renderedMarkdownLineText(from line: String) -> String {
    var text = line.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else {
      return ""
    }

    if text.matches(#"^([-*_]\s*){3,}$"#) {
      return ""
    }

    text = text.replacingRegex(#"^\s{0,3}(>\s*)+"#, with: "")
    text = text.replacingRegex(#"^\s{0,3}#{1,6}\s+"#, with: "")
    text = text.replacingRegex(#"\s+#{1,}\s*$"#, with: "")
    text = text.replacingRegex(#"^\s{0,3}(?:[-+*]|\d+[.)])\s+"#, with: "")
    text = text.replacingRegex(#"^\[[ xX]\]\s+"#, with: "")
    text = text.replacingRegex(#"\s*<!--.*?-->\s*"#, with: " ")
    text = text.replacingRegex(#"!\[([^\]]*)\]\([^)]+\)"#, with: "$1")
    text = text.replacingRegex(#"\[([^\]]+)\]\([^)]+\)"#, with: "$1")
    text = text.replacingRegex(#"\[\[[^\]|]+(?:#[^\]|]+)?\|([^\]]+)\]\]"#, with: "$1")
    text = text.replacingRegex(#"\[\[([^\]#|]+)(?:#[^\]]+)?\]\]"#, with: "$1")
    text = text.replacingRegex(#"`+([^`]+)`+"#, with: "$1")
    text = text.replacingRegex(#"~~([^~]+)~~"#, with: "$1")
    text = text.replacingRegex(#"\*\*\*([^*]+)\*\*\*"#, with: "$1")
    text = text.replacingRegex(#"\*\*([^*]+)\*\*"#, with: "$1")
    text = text.replacingRegex(#"\*([^*]+)\*"#, with: "$1")
    text = text.replacingRegex(#"___([^_]+)___"#, with: "$1")
    text = text.replacingRegex(#"__([^_]+)__"#, with: "$1")
    text = text.replacingRegex(#"_([^_]+)_"#, with: "$1")
    text = text.replacingRegex(#"\s+"#, with: " ")

    return text.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func isCodeFence(_ line: String) -> Bool {
    line.hasPrefix("```") || line.hasPrefix("~~~")
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

  private static func rewrittenWikiLink(
    _ link: WikiLinkOccurrence,
    newStem: String,
    targetNoteID: String,
    newHeading: String? = nil
  ) -> String {
    var target = newStem
    if let heading = newHeading ?? link.targetHeading, !heading.isEmpty {
      target += "#\(heading)"
    }
    if let alias = link.alias, !alias.isEmpty {
      target += "|\(alias)"
    }
    return "[[\(target)]]\(WikiLinkParser.targetComment(noteID: targetNoteID, headingID: link.targetHeadingID))"
  }
}

private extension String {
  func replacingRegex(_ pattern: String, with replacement: String) -> String {
    replacingOccurrences(
      of: pattern,
      with: replacement,
      options: .regularExpression
    )
  }

  func matches(_ pattern: String) -> Bool {
    range(of: pattern, options: .regularExpression) != nil
  }
}
