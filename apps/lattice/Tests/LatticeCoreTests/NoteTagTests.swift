import Foundation
import LatticeCore
import Testing

@Suite("NoteTags")
struct NoteTagTests {
  @Test("parses portable inline tags with case-insensitive identities")
  func parsesInlineTags() {
    let tags = NoteTagParser.tags(in: "#Work #project/lattice (#Mañana) #work")

    #expect(tags.map(\.name) == ["Work", "project/lattice", "Mañana", "work"])
    #expect(tags.map(\.normalizedName) == ["work", "project/lattice", "mañana", "work"])
  }

  @Test("ignores headings escapes code and URL fragments")
  func ignoresNonTags() {
    let text = """
    # Heading
    \\#escaped
    `#inline`
    ```swift
    #fenced
    ```
    https://example.com/#fragment
    Valid #tag
    """

    #expect(NoteTagParser.tags(in: text).map(\.name) == ["tag"])
  }

  @Test("rejects invalid names")
  func rejectsInvalidNames() {
    #expect(NoteTagParser.isValidName("project/lattice"))
    #expect(NoteTagParser.isValidName("mañana-2"))
    #expect(!NoteTagParser.isValidName("1984"))
    #expect(!NoteTagParser.isValidName("two words"))
    #expect(!NoteTagParser.isValidName("/child"))
    #expect(!NoteTagParser.isValidName("parent/"))
    #expect(!NoteTagParser.isValidName("parent//child"))
  }

  @Test("finds autocomplete context outside code")
  func autocompleteContext() throws {
    let text = "Plan #pro"
    let context = try #require(NoteTagParser.autocompleteContext(
      in: text,
      selection: NSRange(location: (text as NSString).length, length: 0)
    ))

    #expect(context.prefix == "pro")
    #expect((text as NSString).substring(with: context.replacementRange) == "#pro")
    #expect(NoteTagParser.autocompleteContext(
      in: "`#pro",
      selection: NSRange(location: 5, length: 0)
    ) == nil)
  }

  @Test("rewrites matching tags without touching code")
  func rewritesTags() {
    let text = "#Work and #work\n`#work`"

    #expect(NoteTagParser.replacingTag(
      normalizedName: "work",
      with: "career",
      in: text
    ) == "#career and #career\n`#work`")
    #expect(NoteTagParser.replacingTag(
      normalizedName: "work",
      with: nil,
      in: text
    ) == "and\n`#work`")
  }
}
