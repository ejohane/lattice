import LatticeEditor
import SwiftUI

struct MacTagSidebarSection: View {
  let tags: [NoteTagSummary]
  let selectedTagName: String?
  @Binding var isExpanded: Bool
  let onSelect: @MainActor (NoteTagSummary?) -> Void
  let onRename: @MainActor (NoteTagSummary) -> Void
  let onDelete: @MainActor (NoteTagSummary) -> Void

  var body: some View {
    DisclosureGroup(isExpanded: $isExpanded) {
      filterButton(
        title: "All Notes",
        systemImage: "tray.full",
        count: nil,
        isSelected: selectedTagName == nil,
        identifier: "tagFilter-all"
      ) {
        onSelect(nil)
      }

      if tags.isEmpty {
        Text("Type #tag in a note to create one.")
          .font(.caption)
          .foregroundStyle(.secondary)
          .padding(.vertical, 4)
          .accessibilityIdentifier("tagFilter-empty")
      } else {
        ForEach(tags) { tag in
          filterButton(
            title: "#\(tag.name)",
            systemImage: "tag",
            count: tag.noteCount,
            isSelected: selectedTagName == tag.normalizedName,
            identifier: "tagFilter-\(tag.normalizedName)"
          ) {
            onSelect(tag)
          }
          .accessibilityLabel(
            "Tag \(tag.name), \(tag.noteCount) note\(tag.noteCount == 1 ? "" : "s")"
          )
          .contextMenu {
            Button("Rename Tag…") { onRename(tag) }
            Button("Delete Tag…", role: .destructive) { onDelete(tag) }
          }
        }
      }
    } label: {
      Label("Tags", systemImage: "tag")
        .font(.headline)
        .accessibilityIdentifier("tagsSection")
    }
  }

  private func filterButton(
    title: String,
    systemImage: String,
    count: Int?,
    isSelected: Bool,
    identifier: String,
    action: @escaping @MainActor () -> Void
  ) -> some View {
    Button(action: action) {
      HStack(spacing: 8) {
        Label(title, systemImage: systemImage)
          .lineLimit(1)
        Spacer(minLength: 8)
        if let count {
          Text(count.formatted())
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
      }
      .padding(.horizontal, 6)
      .frame(height: 28)
      .background(
        isSelected ? Color.accentColor.opacity(0.16) : .clear,
        in: RoundedRectangle(cornerRadius: 6, style: .continuous)
      )
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier(identifier)
  }
}

struct MacTagRenameSheet: View {
  @Bindable var model: MacMarkdownAppModel
  let tag: NoteTagSummary
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Rename #\(tag.name)")
        .font(.title2.weight(.semibold))
      Text("This updates \(tag.noteCount) note\(tag.noteCount == 1 ? "" : "s"). Markdown filenames and note identity stay unchanged.")
        .foregroundStyle(.secondary)
      TextField("Tag name", text: $model.renameTagName)
        .textFieldStyle(.roundedBorder)
        .accessibilityIdentifier("renameTagField")
      HStack {
        Spacer()
        Button("Cancel") {
          model.cancelTagRename()
          dismiss()
        }
        .keyboardShortcut(.cancelAction)
        Button("Rename") {
          Task {
            if await model.confirmTagRename() { dismiss() }
          }
        }
        .keyboardShortcut(.defaultAction)
        .disabled(
          model.isMutatingTags
            || !NoteTagParser.isValidName(
              model.renameTagName.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        )
      }
    }
    .padding(24)
    .frame(width: 420)
    .accessibilityIdentifier("renameTagConfirmation")
  }
}
