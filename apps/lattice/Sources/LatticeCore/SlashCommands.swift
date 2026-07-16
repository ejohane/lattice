import Foundation

public struct SlashCommandAutocompleteContext: Equatable, Sendable {
  public let prefix: String
  public let replacementRange: NSRange

  public init(prefix: String, replacementRange: NSRange) {
    self.prefix = prefix
    self.replacementRange = replacementRange
  }
}

public enum SlashCommandParser {
  public static func autocompleteContext(
    in text: String,
    selection: NSRange
  ) -> SlashCommandAutocompleteContext? {
    guard selection.length == 0 else {
      return nil
    }
    let nsString = text as NSString
    let location = min(max(selection.location, 0), nsString.length)
    var start = location
    while start > 0 {
      let previousRange = NSRange(location: start - 1, length: 1)
      let previous = nsString.substring(with: previousRange)
      if previous.rangeOfCharacter(from: .whitespacesAndNewlines) != nil {
        break
      }
      start -= 1
    }
    guard start < location else {
      return nil
    }
    let tokenRange = NSRange(location: start, length: location - start)
    let token = nsString.substring(with: tokenRange)
    guard token.hasPrefix("/"), !token.dropFirst().contains("/") else {
      return nil
    }
    if start > 0 {
      let preceding = nsString.substring(with: NSRange(location: start - 1, length: 1))
      guard preceding.rangeOfCharacter(from: .whitespacesAndNewlines) != nil else {
        return nil
      }
    }
    return SlashCommandAutocompleteContext(
      prefix: String(token.dropFirst()),
      replacementRange: tokenRange
    )
  }
}
