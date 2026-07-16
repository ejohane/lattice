import Foundation
import LatticeCore
import Testing

@Suite("Person mentions")
struct PersonMentionTests {
  @Test("parses durable mentions with spaces")
  func parsesDurableMentions() throws {
    let text = "Met with @Erik Johansson<!-- lattice:mention=person-1 --> today."
    let mention = try #require(PersonMentionParser.mentions(in: text).first)

    #expect(mention.name == "Erik Johansson")
    #expect(mention.targetNoteID == "person-1")
    #expect((text as NSString).substring(with: mention.range) == "@Erik Johansson")
    #expect(PersonMentionParser.mention(at: mention.range.location + 3, in: text) == mention)
  }

  @Test("offers autocomplete for names with spaces but not email addresses")
  func findsAutocompleteContext() throws {
    let text = "Talk to @Erik Joh"
    let context = try #require(PersonMentionParser.autocompleteContext(
      in: text,
      selection: NSRange(location: (text as NSString).length, length: 0)
    ))

    #expect(context.name == "Erik Joh")
    #expect((text as NSString).substring(with: context.replacementRange) == "@Erik Joh")
    #expect(PersonMentionParser.autocompleteContext(
      in: "email@example.com",
      selection: NSRange(location: 17, length: 0)
    ) == nil)
  }

  @Test("ignores mentions in code")
  func ignoresCodeMentions() {
    let inline = "`@Erik Johansson<!-- lattice:mention=person-1 -->`"
    let fenced = "```\n@Erik Johansson<!-- lattice:mention=person-1 -->\n```"

    #expect(PersonMentionParser.mentions(in: inline).isEmpty)
    #expect(PersonMentionParser.mentions(in: fenced).isEmpty)
  }

  @Test("adds and reads person metadata")
  func personMetadata() {
    let body = MarkdownDocumentMetadata.ensurePersonMetadata(
      in: "# Erik Johansson\n",
      id: "person-1",
      createdAt: nil
    )

    #expect(MarkdownDocumentMetadata.noteID(in: body) == "person-1")
    #expect(MarkdownDocumentMetadata.kind(in: body) == .person)
    #expect(MarkdownDocumentMetadata.strippingFrontMatter(from: body) == "# Erik Johansson\n")
  }
}
