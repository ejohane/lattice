import Foundation

enum MarkdownTextRange {
  static func clamped(_ range: NSRange, length: Int) -> NSRange {
    let location = max(0, min(range.location, length))
    let maxLength = length - location
    return NSRange(location: location, length: max(0, min(range.length, maxLength)))
  }

  static func contentRangeWithoutLineEnding(_ lineRange: NSRange, in nsString: NSString) -> NSRange {
    var end = NSMaxRange(lineRange)
    while end > lineRange.location {
      let character = nsString.character(at: end - 1)
      if character == 10 || character == 13 {
        end -= 1
      } else {
        break
      }
    }

    return NSRange(location: lineRange.location, length: end - lineRange.location)
  }

  static func firstRegexMatch(_ pattern: String, in string: String) -> NSTextCheckingResult? {
    guard let regex = try? NSRegularExpression(pattern: pattern) else {
      return nil
    }

    return regex.firstMatch(
      in: string,
      range: NSRange(location: 0, length: (string as NSString).length)
    )
  }
}
