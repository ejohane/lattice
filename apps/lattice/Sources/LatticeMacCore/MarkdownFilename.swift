import Foundation

public enum MarkdownFilename {
  public static let maximumStemLength = 80

  public static func suggestedStem(from body: String) -> String? {
    firstMeaningfulLine(in: body)?.stem
  }

  public static func hasTerminatedMeaningfulLine(in body: String) -> Bool {
    firstMeaningfulLine(in: body)?.isTerminated == true
  }

  public static func numberedStem(_ stem: String, number: Int) -> String {
    guard number > 1 else { return constrained(stem, suffix: "") }
    let suffix = " \(number)"
    return constrained(stem, suffix: suffix) + suffix
  }

  private static func firstMeaningfulLine(
    in body: String
  ) -> (stem: String, isTerminated: Bool)? {
    var start = body.startIndex

    while start < body.endIndex {
      if let newline = body[start...].firstIndex(where: \.isNewline) {
        if let stem = sanitizedStem(String(body[start..<newline])) {
          return (stem, true)
        }
        start = body.index(after: newline)
      } else {
        return sanitizedStem(String(body[start...])).map { ($0, false) }
      }
    }

    return nil
  }

  private static func sanitizedStem(_ line: String) -> String? {
    var candidate = line.trimmingCharacters(in: .whitespacesAndNewlines)
    candidate = removingHeadingMarker(from: candidate)
    candidate = removingMarkdownExtension(from: candidate)

    let separatorMarker = "\u{F000}"
    let forbidden = CharacterSet(charactersIn: "/:\u{0}")
      .union(.controlCharacters)
      .union(.newlines)
    candidate = String(candidate.unicodeScalars.map { scalar in
      forbidden.contains(scalar) ? separatorMarker : String(scalar)
    }.joined())
    candidate = candidate.replacingOccurrences(
      of: "\(separatorMarker)+",
      with: " - ",
      options: .regularExpression
    )
    candidate = candidate.replacingOccurrences(
      of: #"\s+"#,
      with: " ",
      options: .regularExpression
    )
    candidate = candidate.trimmingCharacters(in: CharacterSet(charactersIn: " .-"))
    while candidate.hasPrefix(".") {
      candidate.removeFirst()
    }
    candidate = candidate.trimmingCharacters(in: CharacterSet(charactersIn: " .-"))

    guard containsMeaningfulCharacter(candidate) else { return nil }

    let constrainedCandidate = constrained(candidate, suffix: "")
    return constrainedCandidate.isEmpty ? nil : constrainedCandidate
  }

  private static func removingHeadingMarker(from text: String) -> String {
    var cursor = text.startIndex
    var count = 0
    while cursor < text.endIndex, text[cursor] == "#", count < 6 {
      count += 1
      cursor = text.index(after: cursor)
    }

    guard count > 0,
          cursor < text.endIndex,
          text[cursor].isWhitespace
    else {
      return text
    }

    return String(text[cursor...]).trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func removingMarkdownExtension(from text: String) -> String {
    guard text.lowercased().hasSuffix(".md") else { return text }
    return String(text.dropLast(3))
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func containsMeaningfulCharacter(_ text: String) -> Bool {
    let markdownPunctuation = CharacterSet(charactersIn: "#*_`~->.[](){}!|=+")
    return text.unicodeScalars.contains { scalar in
      !CharacterSet.whitespacesAndNewlines.contains(scalar)
        && !markdownPunctuation.contains(scalar)
    }
  }

  private static func constrained(_ stem: String, suffix: String) -> String {
    let characterLimit = max(1, maximumStemLength - suffix.count)
    var result = String(stem.prefix(characterLimit))
      .trimmingCharacters(in: CharacterSet(charactersIn: " .-"))

    while !result.isEmpty, (result + suffix).utf8.count > 240 {
      result.removeLast()
    }

    return result.trimmingCharacters(in: CharacterSet(charactersIn: " .-"))
  }
}
