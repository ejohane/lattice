import Foundation

public struct MarkdownDocument: Equatable, Sendable {
  public let hiddenPrefix: String
  public var body: String

  public init(fileContents: String) {
    guard let hiddenPrefixEnd = Self.latticeFrontMatterEnd(in: fileContents) else {
      hiddenPrefix = ""
      body = fileContents
      return
    }

    hiddenPrefix = String(fileContents[..<hiddenPrefixEnd])
    body = String(fileContents[hiddenPrefixEnd...])
  }

  public var fileContents: String {
    hiddenPrefix + body
  }

  private static func latticeFrontMatterEnd(in contents: String) -> String.Index? {
    guard let firstLine = nextLine(in: contents, from: contents.startIndex),
          firstLine.text == "---"
    else {
      return nil
    }

    var cursor = firstLine.end
    var containsLatticeMetadata = false

    while let line = nextLine(in: contents, from: cursor) {
      if line.text == "lattice:" {
        containsLatticeMetadata = true
      }

      if line.text == "---" {
        guard containsLatticeMetadata else { return nil }

        var prefixEnd = line.end
        if let separatorLine = nextLine(in: contents, from: prefixEnd),
           separatorLine.text.isEmpty {
          prefixEnd = separatorLine.end
        }
        return prefixEnd
      }

      cursor = line.end
    }

    return nil
  }

  private static func nextLine(
    in contents: String,
    from start: String.Index
  ) -> (text: Substring, end: String.Index)? {
    guard start < contents.endIndex else { return nil }

    if let newline = contents[start...].firstIndex(where: \.isNewline) {
      return (contents[start..<newline], contents.index(after: newline))
    }

    return (contents[start..<contents.endIndex], contents.endIndex)
  }
}
