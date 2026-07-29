import Foundation
import LatticeMacCore
import SwiftUI

struct MacMarkdownSidebarRow: View {
  let preview: MarkdownSidebarPreview

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(preview.title)
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(.primary)
        .lineLimit(1)

      Text(preview.excerpt.isEmpty ? " " : preview.excerpt)
        .font(.system(size: 13))
        .foregroundStyle(.secondary)
        .lineLimit(2)
        .frame(maxWidth: .infinity, minHeight: 32, alignment: .topLeading)

      Text(MacMarkdownSidebarDateLabel.text(for: preview.modifiedAt))
        .font(.system(size: 11))
        .foregroundStyle(.tertiary)
        .lineLimit(1)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.vertical, 5)
    .contentShape(Rectangle())
  }
}

enum MacMarkdownSidebarDateLabel {
  static func text(
    for date: Date?,
    relativeTo now: Date = Date(),
    calendar: Calendar = .current
  ) -> String {
    guard let date else { return "" }

    let seconds = max(0, now.timeIntervalSince(date))
    if seconds < 60 {
      return "Just now"
    }
    if seconds < 3_600 {
      return "\(max(1, Int(seconds / 60))) min ago"
    }
    if seconds < 86_400 {
      let hours = max(1, Int(seconds / 3_600))
      return hours == 1 ? "1 hour ago" : "\(hours) hours ago"
    }

    let formatter = DateFormatter()
    formatter.locale = Locale.current
    formatter.calendar = calendar
    formatter.timeZone = calendar.timeZone
    formatter.setLocalizedDateFormatFromTemplate(
      calendar.component(.year, from: date) == calendar.component(.year, from: now)
        ? "MMMd"
        : "MMMdyyyy"
    )
    return formatter.string(from: date)
  }
}
