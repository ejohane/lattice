import SwiftUI

enum MacSlashCommandPaletteMetrics {
  static let width: CGFloat = 320
  static let height: CGFloat = 54
  static let verticalGap: CGFloat = 14
}

struct MacSlashCommandPalette: View {
  let onSelectToday: @MainActor () -> Void

  var body: some View {
    Button(action: onSelectToday) {
      HStack(spacing: 12) {
        Image(systemName: "calendar")
          .font(.system(size: 15, weight: .semibold))
          .foregroundStyle(.secondary)
          .frame(width: 24, height: 24)

        VStack(alignment: .leading, spacing: 2) {
          Text("Today")
            .font(.body.weight(.medium))

          Text("Insert a link to today's note")
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        Spacer(minLength: 12)
      }
      .padding(.horizontal, 12)
      .frame(
        width: MacSlashCommandPaletteMetrics.width,
        height: MacSlashCommandPaletteMetrics.height
      )
      .background(.quaternary.opacity(0.5))
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .background(
      .regularMaterial,
      in: RoundedRectangle(cornerRadius: 10, style: .continuous)
    )
    .overlay {
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .stroke(.separator.opacity(0.5), lineWidth: 0.5)
    }
    .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
    .accessibilityLabel("Today, insert a link to today's note")
  }
}
