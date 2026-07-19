import Foundation
import LatticeCore
import Testing

@Suite("Context Pack")
struct ContextPackTests {
  private let date = Date(timeIntervalSince1970: 1_768_601_600)

  @Test("renders task ordered sources provenance and stable size")
  func rendersContextPack() {
    let pack = ContextPack(
      task: "Create an onboarding proposal.",
      sources: [
        ContextPackSource(
          noteID: "research",
          title: "Onboarding research",
          body: "# Onboarding research\n\nCustomers need clearer setup guidance."
        ),
        ContextPackSource(
          noteID: "feedback",
          title: "Customer feedback",
          body: "Only this selected paragraph.",
          isExcerpt: true
        )
      ],
      generatedAt: date
    )

    let markdown = ContextPackCompiler.markdown(
      for: pack,
      locale: Locale(identifier: "en_US_POSIX"),
      timeZone: try! #require(TimeZone(secondsFromGMT: 0))
    )

    #expect(markdown == """
    # Task

    Create an onboarding proposal.

    # Context

    ## Onboarding research

    Customers need clearer setup guidance.

    ## Customer feedback (selection)

    Only this selected paragraph.

    ---
    Generated from Lattice on January 16, 2026.
    Sources: Onboarding research, Customer feedback (selection)

    """)
    #expect(ContextPackCompiler.approximateTokenCount(for: markdown) == Int(ceil(Double(markdown.count) / 4)))
  }

  @Test("strips front matter hidden metadata and replaces image references")
  func cleansLatticeMetadataAndImages() {
    let pack = ContextPack(
      task: "",
      sources: [
        ContextPackSource(
          noteID: "project",
          title: "Project plan",
          body: """
          ---
          lattice:
            id: project
          ---

          Project plan

          Talked to @Erik Johansson<!-- lattice:mention=person-1 --> about [[Design]]<!-- lattice:target=design-1 -->.

          <!-- Keep this ordinary HTML comment. -->

          ![Wireframe|720](../attachments/wireframe.png)

          ```markdown
          ![Example](kept-inside-code.png)
          ```
          """
        )
      ],
      generatedAt: date
    )

    let markdown = ContextPackCompiler.markdown(
      for: pack,
      locale: Locale(identifier: "en_US_POSIX"),
      timeZone: try! #require(TimeZone(secondsFromGMT: 0))
    )

    #expect(!markdown.contains("lattice:"))
    #expect(!markdown.contains("lattice:mention"))
    #expect(!markdown.contains("lattice:target"))
    #expect(markdown.contains("<!-- Keep this ordinary HTML comment. -->"))
    #expect(markdown.contains("Talked to @Erik Johansson about [[Design]]."))
    #expect(markdown.contains("[Image omitted: Wireframe]"))
    #expect(markdown.contains("![Example](kept-inside-code.png)"))
  }

  @Test("keeps a selected excerpt title line and supports an empty task")
  func keepsExcerptTitleLine() {
    let pack = ContextPack(
      task: "   ",
      sources: [
        ContextPackSource(
          noteID: "selection",
          title: "Meeting notes",
          body: "Meeting notes\n\nThis phrase was deliberately selected.",
          isExcerpt: true
        )
      ],
      generatedAt: date
    )

    let markdown = ContextPackCompiler.markdown(for: pack)

    #expect(!markdown.contains("# Task"))
    #expect(markdown.contains("## Meeting notes (selection)\n\nMeeting notes\n\nThis phrase was deliberately selected."))
  }
}
