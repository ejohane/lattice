import Foundation

struct Vault {
  let rootURL: URL
  let config: VaultConfig
}

struct VaultConfig: Codable {
  var protocolVersion: Int
  var vault: VaultInfo
  var capture: CaptureConfig

  enum CodingKeys: String, CodingKey {
    case protocolVersion = "protocol_version"
    case vault
    case capture
  }

  static let `default` = VaultConfig(
    protocolVersion: 1,
    vault: VaultInfo(name: "Lattice"),
    capture: CaptureConfig(screenshotsDefault: true)
  )
}

struct VaultInfo: Codable {
  var name: String
}

struct CaptureConfig: Codable {
  var screenshotsDefault: Bool

  enum CodingKeys: String, CodingKey {
    case screenshotsDefault = "screenshots_default"
  }
}

struct CaptureContext: Codable {
  var activeApp: String?
  var activeWindow: String?
  var screenshotPath: String?
  var metadataErrors: [String]

  enum CodingKeys: String, CodingKey {
    case activeApp = "active_app"
    case activeWindow = "active_window"
    case screenshotPath = "screenshot_path"
    case metadataErrors = "metadata_errors"
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(activeApp, forKey: .activeApp)
    try container.encode(activeWindow, forKey: .activeWindow)
    try container.encode(screenshotPath, forKey: .screenshotPath)
    try container.encode(metadataErrors, forKey: .metadataErrors)
  }
}

struct CaptureRecord: Codable {
  var schemaVersion: Int
  var kind: String
  var id: String
  var createdAt: String
  var localDate: String
  var body: String
  var source: String
  var context: CaptureContext

  enum CodingKeys: String, CodingKey {
    case schemaVersion = "schema_version"
    case kind
    case id
    case createdAt = "created_at"
    case localDate = "local_date"
    case body
    case source
    case context
  }
}

struct QueueEntry: Codable {
  var schemaVersion: Int
  var captureID: String
  var createdAt: String
  var localDate: String
  var source: String
  var rawCapturePath: String
  var screenshotPath: String?

  enum CodingKeys: String, CodingKey {
    case schemaVersion = "schema_version"
    case captureID = "capture_id"
    case createdAt = "created_at"
    case localDate = "local_date"
    case source
    case rawCapturePath = "raw_capture_path"
    case screenshotPath = "screenshot_path"
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(schemaVersion, forKey: .schemaVersion)
    try container.encode(captureID, forKey: .captureID)
    try container.encode(createdAt, forKey: .createdAt)
    try container.encode(localDate, forKey: .localDate)
    try container.encode(source, forKey: .source)
    try container.encode(rawCapturePath, forKey: .rawCapturePath)
    try container.encode(screenshotPath, forKey: .screenshotPath)
  }
}

enum VaultValidationResult: Equatable {
  case valid
  case uninitialized
  case invalid(String)

  var isUsableVault: Bool {
    if case .valid = self {
      return true
    }
    return false
  }
}

enum VaultError: LocalizedError {
  case noActiveVault
  case invalidVault(String)
  case emptyCapture
  case duplicateCapture(String)
  case missingCapture(String)

  var errorDescription: String? {
    switch self {
    case .noActiveVault:
      return "No Lattice vault is selected."
    case .invalidVault(let message):
      return message
    case .emptyCapture:
      return "Cannot save an empty capture."
    case .duplicateCapture(let path):
      return "Raw capture already exists: \(path)"
    case .missingCapture(let path):
      return "Raw capture does not exist: \(path)"
    }
  }
}

final class VaultService {
  static let activeVaultPathKey = "activeVaultPath"

  private let defaults: UserDefaults
  private let fileManager: FileManager

  init(
    defaults: UserDefaults = .standard,
    fileManager: FileManager = .default
  ) {
    self.defaults = defaults
    self.fileManager = fileManager
  }

  var defaultVaultURL: URL {
    fileManager.homeDirectoryForCurrentUser
      .appendingPathComponent("Documents", isDirectory: true)
      .appendingPathComponent("lattice", isDirectory: true)
  }

  func activeVaultURL() -> URL? {
    guard let path = defaults.string(forKey: Self.activeVaultPathKey), !path.isEmpty else {
      return nil
    }
    return URL(fileURLWithPath: path, isDirectory: true)
  }

  func currentVault() throws -> Vault {
    guard let url = activeVaultURL() else {
      throw VaultError.noActiveVault
    }

    guard validateVault(at: url).isUsableVault else {
      throw VaultError.noActiveVault
    }

    return Vault(rootURL: url, config: try loadConfig(at: url))
  }

  func selectVault(_ url: URL) throws -> Vault {
    let standardizedURL = url.standardizedFileURL
    try initializeVault(at: standardizedURL)
    defaults.set(standardizedURL.path, forKey: Self.activeVaultPathKey)
    return try currentVault()
  }

  func clearActiveVault() {
    defaults.removeObject(forKey: Self.activeVaultPathKey)
  }

  func validateVault(at url: URL) -> VaultValidationResult {
    var isDirectory: ObjCBool = false
    guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
      return .uninitialized
    }
    guard isDirectory.boolValue else {
      return .invalid("Selected path is not a folder.")
    }

    let configURL = url.appendingPathComponent("config.json")
    guard fileManager.fileExists(atPath: configURL.path) else {
      return .uninitialized
    }

    do {
      let config = try loadConfig(at: url)
      guard config.protocolVersion == 1 else {
        return .invalid("Unsupported vault protocol version: \(config.protocolVersion).")
      }
      return .valid
    } catch {
      return .invalid(error.localizedDescription)
    }
  }

  func initializeVault(at url: URL, name: String? = nil) throws {
    try createDirectory(url)

    let rawURL = url.appendingPathComponent("raw", isDirectory: true)
    let capturesURL = rawURL.appendingPathComponent("captures", isDirectory: true)
    let screenshotsURL = rawURL.appendingPathComponent("screenshots", isDirectory: true)
    let queueURL = url.appendingPathComponent("queue", isDirectory: true)
    let wikiURL = url.appendingPathComponent("wiki", isDirectory: true)
    let wikiPagesURL = wikiURL.appendingPathComponent("pages", isDirectory: true)
    let skillsURL = url.appendingPathComponent("skills", isDirectory: true)
    let exportsURL = url.appendingPathComponent("exports", isDirectory: true)
    let packsURL = exportsURL.appendingPathComponent("packs", isDirectory: true)

    for directory in [
      rawURL,
      capturesURL,
      screenshotsURL,
      queueURL,
      wikiURL,
      wikiPagesURL,
      skillsURL,
      exportsURL,
      packsURL
    ] {
      try createDirectory(directory)
    }

    let configURL = url.appendingPathComponent("config.json")
    if !fileManager.fileExists(atPath: configURL.path) {
      var config = VaultConfig.default
      if let name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        config.vault.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
      }
      try writeJSON(config, to: configURL, prettyPrinted: true)
    }

    let config = (try? loadConfig(at: url)) ?? .default
    try writeTextIfMissing(
      [
        "# Lattice Vault",
        "",
        "This is a Lattice vault: immutable raw captures plus an agent-maintained markdown wiki.",
        "",
        "Core rules:",
        "",
        "- Do not edit, move, or delete files under `raw/`.",
        "- Do not edit `queue/` by hand.",
        "- Wiki maintenance belongs under `wiki/`.",
        "- Cite capture IDs for claims added from raw captures."
      ].joined(separator: "\n"),
      to: url.appendingPathComponent("AGENTS.md")
    )
    try writeTextIfMissing(
      [
        "# \(config.vault.name) Wiki",
        "",
        "Use `wiki/pages/` for durable pages and `wiki/log.md` for the running maintenance log."
      ].joined(separator: "\n"),
      to: wikiURL.appendingPathComponent("index.md")
    )
    try writeTextIfMissing(
      [
        "# Wiki Maintenance Log",
        "",
        "Append dated notes here when captures are ingested or pages change."
      ].joined(separator: "\n"),
      to: wikiURL.appendingPathComponent("log.md")
    )
    try writeTextIfMissing(
      [
        "# Lattice Vault Agent Guide",
        "",
        "Maintain the wiki from raw captures without editing immutable source material."
      ].joined(separator: "\n"),
      to: skillsURL.appendingPathComponent("AGENTS.md")
    )
    try writeTextIfMissing("", to: rawURL.appendingPathComponent("log.jsonl"))
    try writeTextIfMissing("", to: queueURL.appendingPathComponent("pending.jsonl"))
    try writeTextIfMissing("", to: queueURL.appendingPathComponent("ingested.jsonl"))
  }

  @discardableResult
  func saveCapture(body: String, source: String = "macos", now: Date = Date()) throws -> CaptureRecord {
    let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedBody.isEmpty else {
      throw VaultError.emptyCapture
    }

    let vault = try currentVault()
    let createdAt = Self.isoString(from: now)
    let localDate = Self.localDateString(from: now)
    let captureID = "cap_\(Self.captureIDDateString(from: now))_\(UUID().uuidString.prefix(8).lowercased())"

    let record = CaptureRecord(
      schemaVersion: 1,
      kind: "capture",
      id: captureID,
      createdAt: createdAt,
      localDate: localDate,
      body: trimmedBody,
      source: source,
      context: CaptureContext(
        activeApp: nil,
        activeWindow: nil,
        screenshotPath: nil,
        metadataErrors: []
      )
    )

    let captureDirectory = vault.rootURL
      .appendingPathComponent("raw", isDirectory: true)
      .appendingPathComponent("captures", isDirectory: true)
      .appendingPathComponent(localDate, isDirectory: true)
    try createDirectory(captureDirectory)

    let captureURL = captureDirectory.appendingPathComponent("\(captureID).json")
    if fileManager.fileExists(atPath: captureURL.path) {
      throw VaultError.duplicateCapture(relativePath(from: vault.rootURL, to: captureURL))
    }

    try writeJSON(record, to: captureURL, prettyPrinted: true)
    try appendJSONLine(
      record,
      to: vault.rootURL
        .appendingPathComponent("raw", isDirectory: true)
        .appendingPathComponent("log.jsonl")
    )

    let entry = QueueEntry(
      schemaVersion: 1,
      captureID: captureID,
      createdAt: createdAt,
      localDate: localDate,
      source: source,
      rawCapturePath: relativePath(from: vault.rootURL, to: captureURL),
      screenshotPath: nil
    )
    try appendJSONLine(
      entry,
      to: vault.rootURL
        .appendingPathComponent("queue", isDirectory: true)
        .appendingPathComponent("pending.jsonl")
    )

    return record
  }

  func updateCapture(_ capture: CaptureRecord, body: String) throws -> CaptureRecord {
    let vault = try currentVault()
    let captureURL = captureURL(for: capture, in: vault)
    if !fileManager.fileExists(atPath: captureURL.path) {
      throw VaultError.missingCapture(relativePath(from: vault.rootURL, to: captureURL))
    }

    var updatedRecord = capture
    updatedRecord.body = body.trimmingCharacters(in: .whitespacesAndNewlines)

    try writeJSON(updatedRecord, to: captureURL, prettyPrinted: true)
    try replaceCaptureInRawLog(
      updatedRecord,
      at: vault.rootURL
        .appendingPathComponent("raw", isDirectory: true)
        .appendingPathComponent("log.jsonl")
    )
    return updatedRecord
  }

  private func loadConfig(at url: URL) throws -> VaultConfig {
    let data = try Data(contentsOf: url.appendingPathComponent("config.json"))
    return try JSONDecoder().decode(VaultConfig.self, from: data)
  }

  private func createDirectory(_ url: URL) throws {
    try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
  }

  private func writeTextIfMissing(_ text: String, to url: URL) throws {
    guard !fileManager.fileExists(atPath: url.path) else {
      return
    }
    try createDirectory(url.deletingLastPathComponent())
    let output = text.isEmpty || text.hasSuffix("\n") ? text : "\(text)\n"
    try output.write(to: url, atomically: true, encoding: .utf8)
  }

  private func writeJSON<T: Encodable>(_ value: T, to url: URL, prettyPrinted: Bool) throws {
    try createDirectory(url.deletingLastPathComponent())
    let encoder = JSONEncoder()
    encoder.outputFormatting = prettyPrinted ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
    let data = try encoder.encode(value)
    var output = data
    output.append(0x0A)
    try output.write(to: url, options: .atomic)
  }

  private func captureURL(for capture: CaptureRecord, in vault: Vault) -> URL {
    vault.rootURL
      .appendingPathComponent("raw", isDirectory: true)
      .appendingPathComponent("captures", isDirectory: true)
      .appendingPathComponent(capture.localDate, isDirectory: true)
      .appendingPathComponent("\(capture.id).json")
  }

  private func jsonLine<T: Encodable>(for value: T) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(value)
    return String(data: data, encoding: .utf8) ?? "{}"
  }

  private func appendJSONLine<T: Encodable>(_ value: T, to url: URL) throws {
    try createDirectory(url.deletingLastPathComponent())
    let line = try jsonLine(for: value)
    if !fileManager.fileExists(atPath: url.path) {
      try Data().write(to: url, options: .atomic)
    }
    let handle = try FileHandle(forWritingTo: url)
    defer {
      try? handle.close()
    }
    try handle.seekToEnd()
    try handle.write(contentsOf: Data("\(line)\n".utf8))
  }

  private func replaceCaptureInRawLog(_ capture: CaptureRecord, at url: URL) throws {
    try createDirectory(url.deletingLastPathComponent())
    let replacementLine = try jsonLine(for: capture)
    guard fileManager.fileExists(atPath: url.path) else {
      try "\(replacementLine)\n".write(to: url, atomically: true, encoding: .utf8)
      return
    }

    let existing = try String(contentsOf: url, encoding: .utf8)
    var replaced = false
    var outputLines: [String] = []
    let decoder = JSONDecoder()

    for line in existing.split(separator: "\n", omittingEmptySubsequences: true) {
      let lineString = String(line)
      if
        let data = lineString.data(using: .utf8),
        let decoded = try? decoder.decode(CaptureRecord.self, from: data),
        decoded.id == capture.id
      {
        outputLines.append(replacementLine)
        replaced = true
      } else {
        outputLines.append(lineString)
      }
    }

    if !replaced {
      outputLines.append(replacementLine)
    }

    try "\(outputLines.joined(separator: "\n"))\n".write(to: url, atomically: true, encoding: .utf8)
  }

  private func relativePath(from rootURL: URL, to fileURL: URL) -> String {
    let rootComponents = rootURL.standardizedFileURL.pathComponents
    let fileComponents = fileURL.standardizedFileURL.pathComponents
    let commonCount = zip(rootComponents, fileComponents).prefix { $0 == $1 }.count
    return fileComponents.dropFirst(commonCount).joined(separator: "/")
  }

  private static func isoString(from date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
  }

  private static func localDateString(from date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: date)
  }

  private static func captureIDDateString(from date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss"
    return formatter.string(from: date)
  }
}
