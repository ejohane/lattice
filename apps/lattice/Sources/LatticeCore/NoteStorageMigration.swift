import Foundation

public struct NoteStorageMigrationPreview: Equatable, Sendable {
  public let noteCount: Int

  public init(noteCount: Int) {
    self.noteCount = noteCount
  }
}

public struct NoteStorageMigrationResult: Equatable, Sendable {
  public let migratedNoteCount: Int
  public let renamedNoteCount: Int
  public let collisionCount: Int
  public let ambiguousLinkCount: Int
  public let backupURL: URL

  public init(
    migratedNoteCount: Int,
    renamedNoteCount: Int,
    collisionCount: Int,
    ambiguousLinkCount: Int,
    backupURL: URL
  ) {
    self.migratedNoteCount = migratedNoteCount
    self.renamedNoteCount = renamedNoteCount
    self.collisionCount = collisionCount
    self.ambiguousLinkCount = ambiguousLinkCount
    self.backupURL = backupURL.standardizedFileURL
  }
}

struct NoteStorageMigrator {
  private struct Record {
    let sourceURL: URL
    let rawBody: String
    let body: String
    let noteID: String
    let createdAt: Date
    let title: String
    let oldStem: String
    let destinationURL: URL
    let usedCollisionSuffix: Bool

    var isLegacy: Bool {
      sourceURL.deletingLastPathComponent() != destinationURL.deletingLastPathComponent()
    }
  }

  private struct Replacement {
    let range: NSRange
    let text: String
  }

  let fileManager: FileManager

  func legacyNoteURLs(in notesURL: URL) throws -> [URL] {
    try noteURLs(in: notesURL).filter {
      $0.deletingLastPathComponent().standardizedFileURL != notesURL.standardizedFileURL
    }
  }

  func migrate(
    notesURL: URL,
    activeNoteURL: URL?,
    backupRootURL: URL,
    now: Date
  ) throws -> (result: NoteStorageMigrationResult, activeNoteURL: URL?) {
    let sourceURLs = try noteURLs(in: notesURL)
    let legacyURLs = sourceURLs.filter {
      $0.deletingLastPathComponent().standardizedFileURL != notesURL.standardizedFileURL
    }
    guard !legacyURLs.isEmpty else {
      let backupURL = backupRootURL.appendingPathComponent("unused", isDirectory: true)
      return (
        NoteStorageMigrationResult(
          migratedNoteCount: 0,
          renamedNoteCount: 0,
          collisionCount: 0,
          ambiguousLinkCount: 0,
          backupURL: backupURL
        ),
        activeNoteURL
      )
    }

    try fileManager.createDirectory(at: backupRootURL, withIntermediateDirectories: true)
    let backupURL = backupRootURL
      .appendingPathComponent(Self.backupFolderName(now: now), isDirectory: true)
    let backupNotesURL = backupURL.appendingPathComponent("notes", isDirectory: true)
    try fileManager.createDirectory(at: backupURL, withIntermediateDirectories: true)
    try fileManager.copyItem(at: notesURL, to: backupNotesURL)

    let records = try migrationRecords(sourceURLs: sourceURLs, notesURL: notesURL, now: now)
    let destinationBySource = Dictionary(
      uniqueKeysWithValues: records.map { ($0.sourceURL.standardizedFileURL.path, $0.destinationURL) }
    )
    let recordByID = records.reduce(into: [String: Record]()) { result, record in
      if result[record.noteID] == nil {
        result[record.noteID] = record
      }
    }
    let candidatesByStem = candidateMap(records: records)

    var ambiguousLinkCount = 0
    var outputByDestination: [String: String] = [:]
    for record in records {
      let rewritten = rewriteBody(
        for: record,
        destinationBySource: destinationBySource,
        recordByID: recordByID,
        candidatesByStem: candidatesByStem,
        ambiguousLinkCount: &ambiguousLinkCount
      )
      let rawOutput = MarkdownDocumentMetadata.ensureNoteMetadata(
        in: rewritten,
        id: record.noteID,
        createdAt: record.createdAt
      )
      outputByDestination[record.destinationURL.standardizedFileURL.path] = rawOutput
    }

    for record in records {
      guard let output = outputByDestination[record.destinationURL.standardizedFileURL.path] else {
        continue
      }
      try write(output, to: record.destinationURL)
      let verified = try String(contentsOf: record.destinationURL, encoding: .utf8)
      guard
        MarkdownDocumentMetadata.noteID(in: verified) == record.noteID,
        verified == normalizedFileBody(output)
      else {
        throw NoteLibraryError.invalidNotesFolder(
          "Could not verify migrated note: \(record.destinationURL.lastPathComponent)"
        )
      }
    }

    for record in records where record.sourceURL.standardizedFileURL != record.destinationURL.standardizedFileURL {
      if fileManager.fileExists(atPath: record.sourceURL.path) {
        try fileManager.removeItem(at: record.sourceURL)
      }
    }
    try removeEmptyDirectories(below: notesURL)

    let migratedActiveURL = activeNoteURL.flatMap {
      destinationBySource[$0.standardizedFileURL.path]
    } ?? activeNoteURL
    let renamedCount = records.filter {
      $0.sourceURL.lastPathComponent != $0.destinationURL.lastPathComponent
    }.count
    return (
      NoteStorageMigrationResult(
        migratedNoteCount: legacyURLs.count,
        renamedNoteCount: renamedCount,
        collisionCount: records.filter(\.usedCollisionSuffix).count,
        ambiguousLinkCount: ambiguousLinkCount,
        backupURL: backupURL
      ),
      migratedActiveURL
    )
  }

  private func migrationRecords(
    sourceURLs: [URL],
    notesURL: URL,
    now: Date
  ) throws -> [Record] {
    let sortedURLs = sourceURLs.sorted { lhs, rhs in
      let lhsIsFlat = lhs.deletingLastPathComponent().standardizedFileURL == notesURL.standardizedFileURL
      let rhsIsFlat = rhs.deletingLastPathComponent().standardizedFileURL == notesURL.standardizedFileURL
      if lhsIsFlat != rhsIsFlat {
        return lhsIsFlat
      }
      return lhs.path.localizedStandardCompare(rhs.path) == .orderedAscending
    }

    var reservedNames: Set<String> = []
    var records: [Record] = []
    for sourceURL in sortedURLs {
      let rawBody = try String(contentsOf: sourceURL, encoding: .utf8)
      let body = MarkdownDocumentMetadata.strippingFrontMatter(from: rawBody)
      let noteID = MarkdownDocumentMetadata.noteID(in: rawBody) ?? UUID().uuidString
      let createdAt = inferredCreatedAt(for: sourceURL, rawBody: rawBody, fallback: now)
      let title = NoteLibrary.firstRenderedLine(in: body) ?? "Untitled"
      let oldStem = sourceURL.deletingPathExtension().lastPathComponent
      let isFlat = sourceURL.deletingLastPathComponent().standardizedFileURL == notesURL.standardizedFileURL

      if let existing = records.first(where: { $0.noteID == noteID }) {
        if existing.body == body {
          records.append(Record(
            sourceURL: sourceURL.standardizedFileURL,
            rawBody: rawBody,
            body: body,
            noteID: noteID,
            createdAt: createdAt,
            title: title,
            oldStem: oldStem,
            destinationURL: existing.destinationURL,
            usedCollisionSuffix: existing.usedCollisionSuffix
          ))
          continue
        }
        throw NoteLibraryError.invalidNotesFolder(
          "Two different notes share the same Lattice ID. Restore or edit one of the files before migrating: "
            + "\(existing.sourceURL.lastPathComponent) and \(sourceURL.lastPathComponent)"
        )
      }

      let baseStem = isFlat ? oldStem : Self.sanitizedNoteStem(title)
      let cleanFilename = "\(baseStem).md"
      let cleanKey = cleanFilename.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
      let useCollisionSuffix = reservedNames.contains(cleanKey)
      let destinationStem = useCollisionSuffix
        ? "\(baseStem)--\(Self.shortIdentifier(noteID: noteID, sourceURL: sourceURL))"
        : baseStem
      var destinationFilename = "\(destinationStem).md"
      var destinationKey = destinationFilename.folding(
        options: [.caseInsensitive, .diacriticInsensitive],
        locale: .current
      )
      if reservedNames.contains(destinationKey) {
        destinationFilename = "\(baseStem)--\(Self.stableHash(noteID + sourceURL.path).prefix(12)).md"
        destinationKey = destinationFilename.lowercased()
      }
      reservedNames.insert(destinationKey)

      records.append(Record(
        sourceURL: sourceURL.standardizedFileURL,
        rawBody: rawBody,
        body: body,
        noteID: noteID,
        createdAt: createdAt,
        title: title,
        oldStem: oldStem,
        destinationURL: notesURL.appendingPathComponent(destinationFilename).standardizedFileURL,
        usedCollisionSuffix: useCollisionSuffix
      ))
    }
    return records
  }

  private func candidateMap(records: [Record]) -> [String: [Record]] {
    var result: [String: [Record]] = [:]
    for record in records {
      for key in Set([record.oldStem.lowercased(), record.title.lowercased()]) {
        if result[key, default: []].contains(where: { $0.noteID == record.noteID }) == false {
          result[key, default: []].append(record)
        }
      }
    }
    return result
  }

  private func rewriteBody(
    for record: Record,
    destinationBySource: [String: URL],
    recordByID: [String: Record],
    candidatesByStem: [String: [Record]],
    ambiguousLinkCount: inout Int
  ) -> String {
    var replacements: [Replacement] = []

    for link in WikiLinkParser.links(in: record.body) where !link.isCurrentNoteHeadingLink {
      let target: Record?
      if let targetNoteID = link.targetNoteID {
        target = recordByID[targetNoteID]
      } else if let targetStem = link.targetStem {
        let candidates = candidatesByStem[targetStem.lowercased()] ?? []
        if candidates.count > 1 {
          ambiguousLinkCount += 1
          target = nil
        } else {
          target = candidates.first
        }
      } else {
        target = nil
      }
      guard let target else {
        continue
      }
      let newStem = target.destinationURL.deletingPathExtension().lastPathComponent
      let alias = link.alias ?? (link.targetStem == newStem ? nil : link.visibleText)
      var targetText = newStem
      if let heading = link.targetHeading {
        targetText += "#\(heading)"
      }
      if let alias, !alias.isEmpty {
        targetText += "|\(alias)"
      }
      let replacement = "[[\(targetText)]]" + WikiLinkParser.targetComment(
        noteID: target.noteID,
        headingID: link.targetHeadingID
      )
      replacements.append(Replacement(range: link.totalRange, text: replacement))
    }

    for link in MarkdownLocalLinkParser.links(in: record.body) {
      let parts = link.destination.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
      let oldPath = String(parts[0])
      guard !oldPath.isEmpty, URL(string: oldPath)?.scheme == nil else {
        continue
      }
      let oldTarget = URL(
        fileURLWithPath: oldPath,
        relativeTo: record.sourceURL.deletingLastPathComponent()
      ).standardizedFileURL
      guard let newTarget = destinationBySource[oldTarget.path] else {
        continue
      }
      var newPath = NoteLibrary.relativePath(
        from: record.destinationURL.deletingLastPathComponent(),
        to: newTarget
      )
      if parts.count > 1 {
        newPath += "#\(parts[1])"
      }
      replacements.append(Replacement(
        range: link.range,
        text: "[\(link.label)](\(newPath))"
      ))
    }

    for image in MarkdownImageParser.links(in: record.body) {
      guard !image.destination.isEmpty, URL(string: image.destination)?.scheme == nil else {
        continue
      }
      let target = URL(
        fileURLWithPath: image.destination,
        relativeTo: record.sourceURL.deletingLastPathComponent()
      ).standardizedFileURL
      let newPath = NoteLibrary.relativePath(
        from: record.destinationURL.deletingLastPathComponent(),
        to: target
      )
      let alt = image.width.map { "\(image.altText)|\(Int($0))" } ?? image.altText
      replacements.append(Replacement(
        range: image.range,
        text: "![\(alt)](\(newPath))"
      ))
    }

    return replacements
      .sorted { $0.range.location > $1.range.location }
      .reduce(record.body) { body, replacement in
        (body as NSString).replacingCharacters(in: replacement.range, with: replacement.text)
      }
  }

  private func inferredCreatedAt(for url: URL, rawBody: String, fallback: Date) -> Date {
    if let createdAt = MarkdownDocumentMetadata.createdAt(in: rawBody) {
      return createdAt
    }
    if let timestamp = Self.timestampDate(from: url.deletingPathExtension().lastPathComponent) {
      return timestamp
    }
    if let folderDate = Self.folderDate(from: url.deletingLastPathComponent().lastPathComponent) {
      return folderDate
    }
    let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
    return values?.creationDate ?? values?.contentModificationDate ?? fallback
  }

  private func noteURLs(in notesURL: URL) throws -> [URL] {
    guard fileManager.fileExists(atPath: notesURL.path) else {
      return []
    }
    let enumerator = fileManager.enumerator(
      at: notesURL,
      includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
      options: [.skipsHiddenFiles]
    )
    var urls: [URL] = []
    while let url = enumerator?.nextObject() as? URL {
      guard url.pathExtension.lowercased() == "md" else {
        continue
      }
      if (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
        urls.append(url.standardizedFileURL)
      }
    }
    return urls
  }

  private func removeEmptyDirectories(below notesURL: URL) throws {
    let childURLs = try fileManager.contentsOfDirectory(
      at: notesURL,
      includingPropertiesForKeys: [.isDirectoryKey],
      options: [.skipsHiddenFiles]
    )
    for childURL in childURLs {
      guard (try? childURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
        continue
      }
      let children = try fileManager.contentsOfDirectory(atPath: childURL.path)
      if children.isEmpty {
        try fileManager.removeItem(at: childURL)
      }
    }
  }

  private func write(_ body: String, to url: URL) throws {
    try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try normalizedFileBody(body).write(to: url, atomically: true, encoding: .utf8)
  }

  private func normalizedFileBody(_ body: String) -> String {
    body.isEmpty || body.hasSuffix("\n") ? body : "\(body)\n"
  }

  static func sanitizedNoteStem(_ title: String) -> String {
    let forbidden = CharacterSet(charactersIn: "/:\u{0}")
    let scalars = title.unicodeScalars.map { scalar in
      forbidden.contains(scalar) || CharacterSet.newlines.contains(scalar) ? Character("-") : Character(scalar)
    }
    var result = String(scalars)
      .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
      .replacingOccurrences(of: #"-{2,}"#, with: "-", options: .regularExpression)
      .trimmingCharacters(in: CharacterSet(charactersIn: " .-"))
    if result.hasPrefix(".") {
      result.removeFirst()
    }
    if result.count > 120 {
      result = String(result.prefix(120)).trimmingCharacters(in: CharacterSet(charactersIn: " .-"))
    }
    return result.isEmpty ? "Untitled" : result
  }

  static func shortIdentifier(noteID: String, sourceURL: URL) -> String {
    let characters = noteID.lowercased().filter { $0.isLetter || $0.isNumber }
    if characters.count >= 6 {
      return String(characters.prefix(8))
    }
    return String(stableHash(noteID + sourceURL.path).prefix(8))
  }

  private static func backupFolderName(now: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss"
    return "flat-notes-v2-\(formatter.string(from: now))-\(UUID().uuidString.prefix(6).lowercased())"
  }

  private static func timestampDate(from stem: String) -> Date? {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss"
    return formatter.date(from: String(stem.prefix(19)))
  }

  private static func folderDate(from name: String) -> Date? {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.date(from: name)
  }

  private static func stableHash(_ input: String) -> String {
    var hash: UInt64 = 14695981039346656037
    for byte in input.utf8 {
      hash ^= UInt64(byte)
      hash &*= 1099511628211
    }
    return String(hash, radix: 16)
  }
}
