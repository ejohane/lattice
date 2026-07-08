import Foundation

public struct ReleaseNotesCatalog: Decodable, Equatable, Sendable {
  static let releaseNotesBundleName = "Lattice_LatticeShared.bundle"
  static let releaseNotesFileName = "ReleaseNotes.json"

  public var schemaVersion: Int
  public var generatedAt: String?
  public var repository: String
  public var entries: [ReleaseNoteEntry]

  public init(
    schemaVersion: Int = 1,
    generatedAt: String? = nil,
    repository: String = "ejohane/lattice",
    entries: [ReleaseNoteEntry] = []
  ) {
    self.schemaVersion = schemaVersion
    self.generatedAt = generatedAt
    self.repository = repository
    self.entries = entries
  }

  public static func bundled() -> ReleaseNotesCatalog {
    guard let url = releaseNotesURL() else {
      return ReleaseNotesCatalog()
    }

    do {
      let data = try Data(contentsOf: url)
      return try JSONDecoder().decode(ReleaseNotesCatalog.self, from: data)
    } catch {
      return ReleaseNotesCatalog()
    }
  }

  static func releaseNotesURL(searchBases: [URL] = releaseNotesSearchBases()) -> URL? {
    for baseURL in searchBases.flatMap(expandedSearchBases) {
      let directURL = baseURL
        .appendingPathComponent(releaseNotesBundleName, isDirectory: true)
        .appendingPathComponent(releaseNotesFileName)
      if FileManager.default.fileExists(atPath: directURL.path) {
        return directURL
      }

      let appResourceURL = baseURL
        .appendingPathComponent("Contents", isDirectory: true)
        .appendingPathComponent("Resources", isDirectory: true)
        .appendingPathComponent(releaseNotesBundleName, isDirectory: true)
        .appendingPathComponent(releaseNotesFileName)
      if FileManager.default.fileExists(atPath: appResourceURL.path) {
        return appResourceURL
      }
    }

    return Bundle.main.url(
      forResource: "ReleaseNotes",
      withExtension: "json",
      subdirectory: releaseNotesBundleName
    ) ?? sourceReleaseNotesURL()
  }

  private static func releaseNotesSearchBases() -> [URL] {
    [
      Bundle.main.resourceURL,
      Bundle.main.bundleURL,
      Bundle.main.executableURL?.deletingLastPathComponent(),
      commandLineExecutableDirectory()
    ].compactMap(\.self)
  }

  private static func commandLineExecutableDirectory() -> URL? {
    guard let executablePath = CommandLine.arguments.first,
          !executablePath.isEmpty else {
      return nil
    }

    let executableURL: URL
    if executablePath.hasPrefix("/") {
      executableURL = URL(fileURLWithPath: executablePath)
    } else {
      executableURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent(executablePath)
    }

    return executableURL.deletingLastPathComponent()
  }

  private static func expandedSearchBases(from url: URL) -> [URL] {
    var urls: [URL] = []
    var currentURL = url.standardizedFileURL

    for _ in 0..<6 {
      urls.append(currentURL)

      let parentURL = currentURL.deletingLastPathComponent()
      if parentURL.path == currentURL.path {
        break
      }
      currentURL = parentURL
    }

    return urls
  }

  private static func sourceReleaseNotesURL() -> URL? {
    guard Bundle.main.bundleURL.pathExtension != "app" else {
      return nil
    }

    let url = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .appendingPathComponent("Resources", isDirectory: true)
      .appendingPathComponent(releaseNotesFileName)

    return FileManager.default.fileExists(atPath: url.path) ? url : nil
  }
}

public struct ReleaseNoteEntry: Decodable, Equatable, Identifiable, Sendable {
  public var id: String { tagName }
  public var version: String
  public var tagName: String
  public var publishedAt: String?
  public var url: URL?
  public var sections: [ReleaseNoteSection]

  public init(
    version: String,
    tagName: String,
    publishedAt: String? = nil,
    url: URL? = nil,
    sections: [ReleaseNoteSection] = []
  ) {
    self.version = version
    self.tagName = tagName
    self.publishedAt = publishedAt
    self.url = url
    self.sections = sections
  }

  public var displayDate: String? {
    guard let publishedAt else {
      return nil
    }

    if let date = Self.date(from: publishedAt) {
      return Self.displayDateFormatter.string(from: date)
    }

    return publishedAt
  }

  private static func date(from value: String) -> Date? {
    let isoDateFormatter = ISO8601DateFormatter()
    isoDateFormatter.formatOptions = [.withInternetDateTime]

    let isoDateFormatterWithFractionalSeconds = ISO8601DateFormatter()
    isoDateFormatterWithFractionalSeconds.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

    let shortDateFormatter = DateFormatter()
    shortDateFormatter.locale = Locale(identifier: "en_US_POSIX")
    shortDateFormatter.dateFormat = "yyyy-MM-dd"

    return isoDateFormatter.date(from: value)
      ?? isoDateFormatterWithFractionalSeconds.date(from: value)
      ?? shortDateFormatter.date(from: value)
  }

  private static var displayDateFormatter: DateFormatter {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .none
    return formatter
  }
}

public struct ReleaseNoteSection: Decodable, Equatable, Identifiable, Sendable {
  public var id: String { title }
  public var title: String
  public var items: [ReleaseNoteItem]

  public init(title: String, items: [ReleaseNoteItem]) {
    self.title = title
    self.items = items
  }
}

public struct ReleaseNoteItem: Decodable, Equatable, Identifiable, Sendable {
  public var id: String { "\(text)|\(url?.absoluteString ?? "")" }
  public var text: String
  public var url: URL?

  public init(text: String, url: URL? = nil) {
    self.text = text
    self.url = url
  }
}
