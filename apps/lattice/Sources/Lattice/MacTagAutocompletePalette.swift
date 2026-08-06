import SwiftUI

enum MacTagAutocompletePaletteMetrics {
  static let width: CGFloat = 320
  static let rowHeight: CGFloat = 46
  static let maximumVisibleRows = 5
  static let verticalGap: CGFloat = 10
}

struct MacTagAutocompletePalette: View {
  let suggestions: [MacTagAutocompleteSuggestion]
  let selectedIndex: Int
  let onSelect: @MainActor (MacTagAutocompleteSuggestion) -> Void

  var body: some View {
    VStack(spacing: 0) {
      ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, suggestion in
        Button {
          onSelect(suggestion)
        } label: {
          HStack(spacing: 10) {
            Image(systemName: "tag")
              .foregroundStyle(.secondary)
              .frame(width: 18)
            Text("#\(suggestion.name)")
              .lineLimit(1)
            Spacer(minLength: 8)
            Text(suggestion.noteCount.formatted())
              .font(.caption.monospacedDigit())
              .foregroundStyle(.secondary)
          }
          .padding(.horizontal, 12)
          .frame(height: MacTagAutocompletePaletteMetrics.rowHeight)
          .background(index == selectedIndex ? Color.accentColor.opacity(0.16) : .clear)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
          "Tag \(suggestion.name), \(suggestion.noteCount) note\(suggestion.noteCount == 1 ? "" : "s")"
        )
      }
    }
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .stroke(.separator.opacity(0.5), lineWidth: 0.5)
    }
    .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
    .accessibilityIdentifier("tagAutocomplete")
  }
}
