import Foundation

public struct MarkdownSlashCommandContext: Equatable, Sendable {
  public let triggerLocation: Int

  public init(triggerLocation: Int) {
    self.triggerLocation = triggerLocation
  }
}

public enum MarkdownSlashCommandTrigger {
  public static func context(
    in body: String,
    selection: NSRange
  ) -> MarkdownSlashCommandContext? {
    guard selection.length == 0 else { return nil }

    let source = body as NSString
    let location = min(max(selection.location, 0), source.length)
    guard location > 0 else { return nil }

    var tokenStart = location
    while tokenStart > 0 {
      let previous = source.substring(
        with: NSRange(location: tokenStart - 1, length: 1)
      )
      if previous.rangeOfCharacter(from: .whitespacesAndNewlines) != nil {
        break
      }
      tokenStart -= 1
    }

    let tokenRange = NSRange(
      location: tokenStart,
      length: location - tokenStart
    )
    let token = source.substring(with: tokenRange)
    guard token.hasPrefix("/"), !token.dropFirst().contains("/") else {
      return nil
    }

    return MarkdownSlashCommandContext(triggerLocation: tokenStart)
  }
}
