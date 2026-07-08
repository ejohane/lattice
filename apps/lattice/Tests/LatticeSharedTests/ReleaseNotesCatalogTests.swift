import Foundation
import Testing
@testable import LatticeShared

@Suite("ReleaseNotesCatalog")
struct ReleaseNotesCatalogTests {
  @Test("decodes bundled release note structure")
  func decodesReleaseNoteStructure() throws {
    let data = Data("""
    {
      "schemaVersion": 1,
      "generatedAt": "2026-07-07T14:33:36Z",
      "repository": "ejohane/lattice",
      "entries": [
        {
          "version": "1.34.2",
          "tagName": "v1.34.2",
          "publishedAt": "2026-07-07T14:33:36Z",
          "url": "https://github.com/ejohane/lattice/releases/tag/v1.34.2",
          "sections": [
            {
              "title": "Bug Fixes",
              "items": [
                {
                  "text": "reminders: render markdown task titles",
                  "url": "https://github.com/ejohane/lattice/commit/b1fd7fe"
                }
              ]
            }
          ]
        }
      ]
    }
    """.utf8)

    let catalog = try JSONDecoder().decode(ReleaseNotesCatalog.self, from: data)

    #expect(catalog.schemaVersion == 1)
    #expect(catalog.repository == "ejohane/lattice")
    #expect(catalog.entries.count == 1)
    #expect(catalog.entries[0].version == "1.34.2")
    #expect(catalog.entries[0].displayDate != nil)
    #expect(catalog.entries[0].sections[0].title == "Bug Fixes")
    #expect(catalog.entries[0].sections[0].items[0].text == "reminders: render markdown task titles")
  }

  @Test("loads checked-in bundled catalog")
  func loadsBundledCatalog() {
    #expect(ReleaseNotesCatalog.releaseNotesURL() != nil)

    let catalog = ReleaseNotesCatalog.bundled()

    #expect(catalog.schemaVersion == 1)
    #expect(catalog.repository == "ejohane/lattice")
  }

  @Test("finds release notes inside packaged app resources")
  func findsReleaseNotesInsidePackagedAppResources() throws {
    let rootURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let appURL = rootURL.appendingPathComponent("Lattice.app", isDirectory: true)
    let releaseNotesDirectory = appURL
      .appendingPathComponent("Contents", isDirectory: true)
      .appendingPathComponent("Resources", isDirectory: true)
      .appendingPathComponent(ReleaseNotesCatalog.releaseNotesBundleName, isDirectory: true)
    let releaseNotesURL = releaseNotesDirectory
      .appendingPathComponent(ReleaseNotesCatalog.releaseNotesFileName)

    try FileManager.default.createDirectory(
      at: releaseNotesDirectory,
      withIntermediateDirectories: true
    )
    try Data("{}".utf8).write(to: releaseNotesURL)
    defer {
      try? FileManager.default.removeItem(at: rootURL)
    }

    #expect(ReleaseNotesCatalog.releaseNotesURL(searchBases: [appURL]) == releaseNotesURL)
  }
}
