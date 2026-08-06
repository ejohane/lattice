import Foundation
import LatticeEditor

struct MacTagAutocompleteSuggestion: Identifiable, Equatable {
  let name: String
  let normalizedName: String
  let noteCount: Int
  let replacementRange: NSRange

  var id: String { normalizedName }
}

struct MacTagAutocompleteCommit: Equatable {
  let text: String
  let selection: NSRange
}

enum MacTagAutocomplete {
  static func suggestions(
    in text: String,
    selection: NSRange,
    tags: [NoteTagSummary],
    limit: Int = 8
  ) -> [MacTagAutocompleteSuggestion] {
    guard let context = NoteTagParser.autocompleteContext(in: text, selection: selection) else {
      return []
    }
    let prefix = NoteTagParser.normalizedName(context.prefix)
    let ranked = tags.filter {
      prefix.isEmpty || $0.normalizedName.hasPrefix(prefix)
    }.sorted { lhs, rhs in
      let lhsExact = lhs.normalizedName == prefix
      let rhsExact = rhs.normalizedName == prefix
      if lhsExact != rhsExact { return lhsExact }
      if lhs.noteCount != rhs.noteCount { return lhs.noteCount > rhs.noteCount }
      return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }

    return ranked.prefix(max(0, limit)).map {
      MacTagAutocompleteSuggestion(
        name: $0.name,
        normalizedName: $0.normalizedName,
        noteCount: $0.noteCount,
        replacementRange: context.replacementRange
      )
    }
  }

  static func committing(
    _ suggestion: MacTagAutocompleteSuggestion,
    in text: String
  ) -> MacTagAutocompleteCommit? {
    let source = text as NSString
    guard suggestion.replacementRange.location != NSNotFound,
          NSMaxRange(suggestion.replacementRange) <= source.length
    else { return nil }
    let replacement = "#\(suggestion.name)"
    let updated = source.replacingCharacters(
      in: suggestion.replacementRange,
      with: replacement
    )
    return MacTagAutocompleteCommit(
      text: updated,
      selection: NSRange(
        location: suggestion.replacementRange.location + (replacement as NSString).length,
        length: 0
      )
    )
  }
}
