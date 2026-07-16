import Foundation
import LatticeCore
import Testing

@Suite("SlashCommands")
struct SlashCommandTests {
  @Test("finds slash command tokens at text boundaries")
  func findsSlashCommandContext() throws {
    let text = "Plan\n/to"
    let context = try #require(SlashCommandParser.autocompleteContext(
      in: text,
      selection: NSRange(location: (text as NSString).length, length: 0)
    ))

    #expect(context.prefix == "to")
    #expect((text as NSString).substring(with: context.replacementRange) == "/to")
  }

  @Test("ignores slashes embedded inside other tokens")
  func ignoresEmbeddedSlashes() {
    let text = "#project/today"
    #expect(SlashCommandParser.autocompleteContext(
      in: text,
      selection: NSRange(location: (text as NSString).length, length: 0)
    ) == nil)
  }
}
