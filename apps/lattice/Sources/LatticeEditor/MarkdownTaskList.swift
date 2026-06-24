import Foundation

public struct MarkdownTaskToggleResult: Equatable, Sendable {
  public let body: String
  public let selection: NSRange
  public let replacementRange: NSRange
  public let replacement: String

  public init(body: String, selection: NSRange, replacementRange: NSRange, replacement: String) {
    self.body = body
    self.selection = selection
    self.replacementRange = replacementRange
    self.replacement = replacement
  }
}

public enum MarkdownTaskList {
  public static func toggleTask(at location: Int, in body: String, selection: NSRange) -> MarkdownTaskToggleResult? {
    let nsString = body as NSString
    let safeLocation = max(0, min(location, max(0, nsString.length - 1)))
    guard let task = taskMarker(containing: safeLocation, in: nsString) else {
      return nil
    }

    let replacement = task.isChecked ? "[ ]" : "[x]"
    let nextBody = nsString.replacingCharacters(in: task.checkboxRange, with: replacement)
    let replacementDelta = replacement.utf16.count - task.checkboxRange.length

    return MarkdownTaskToggleResult(
      body: nextBody,
      selection: transformed(selection, afterReplacing: task.checkboxRange, delta: replacementDelta),
      replacementRange: task.checkboxRange,
      replacement: replacement
    )
  }

  private struct TaskMarker {
    let checkboxRange: NSRange
    let isChecked: Bool
  }

  private static func taskMarker(containing location: Int, in nsString: NSString) -> TaskMarker? {
    let lineRange = nsString.lineRange(for: NSRange(location: min(location, nsString.length), length: 0))
    let line = nsString.substring(with: lineRange)
    guard let match = firstRegexMatch("^([ \\t]*[-*+][ \\t]+)(\\[([ xX])\\])([ \\t]+)", in: line) else {
      return nil
    }

    let interactiveRange = NSRange(location: lineRange.location, length: NSMaxRange(match.range(at: 4)))
    guard location >= interactiveRange.location && location < NSMaxRange(interactiveRange) else {
      return nil
    }

    let checkboxRange = NSRange(
      location: lineRange.location + match.range(at: 2).location,
      length: match.range(at: 2).length
    )
    let state = (line as NSString).substring(with: match.range(at: 3))
    return TaskMarker(checkboxRange: checkboxRange, isChecked: state.lowercased() == "x")
  }

  private static func transformed(_ selection: NSRange, afterReplacing replacedRange: NSRange, delta: Int) -> NSRange {
    guard delta != 0 else {
      return selection
    }

    let start = transformedLocation(selection.location, afterReplacing: replacedRange, delta: delta)
    let end = transformedLocation(NSMaxRange(selection), afterReplacing: replacedRange, delta: delta)
    return NSRange(location: start, length: max(0, end - start))
  }

  private static func transformedLocation(_ location: Int, afterReplacing replacedRange: NSRange, delta: Int) -> Int {
    if location <= replacedRange.location {
      return location
    }

    if location >= NSMaxRange(replacedRange) {
      return location + delta
    }

    return replacedRange.location + max(0, delta)
  }

  private static func firstRegexMatch(_ pattern: String, in string: String) -> NSTextCheckingResult? {
    guard let regex = try? NSRegularExpression(pattern: pattern) else {
      return nil
    }

    return regex.firstMatch(in: string, range: NSRange(location: 0, length: (string as NSString).length))
  }
}
