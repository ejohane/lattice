#if os(macOS)
import AppKit
import LatticeCore
import SwiftUI

enum MacNoteSource: Hashable {
  case allNotes
  case tag(String)
}

struct MacNoteSourceSidebar: View {
  @Bindable var model: LatticeAppModel
  @Environment(\.latticeTheme) private var theme

  var body: some View {
    List(selection: sourceSelection) {
      Section("Library") {
        Label("All Notes", systemImage: "tray.full")
          .tag(MacNoteSource.allNotes)
      }

      Section("Tags") {
        if model.tagSummaries.isEmpty {
          Text("Type #tag in a note to create one.")
            .font(.caption)
            .foregroundStyle(.secondary)
        } else {
          ForEach(model.tagSummaries) { tag in
            HStack(spacing: 8) {
              Label("#\(tag.name)", systemImage: "tag")
                .lineLimit(1)
              Spacer(minLength: 8)
              Text(tag.noteCount.formatted())
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
            }
            .tag(MacNoteSource.tag(tag.normalizedName))
            .contextMenu {
              Button {
                model.beginRenamingTag(tag)
              } label: {
                Label("Rename Tag", systemImage: "pencil")
              }
              Button(role: .destructive) {
                model.requestTagDeletion(tag)
              } label: {
                Label("Delete Tag", systemImage: "trash")
              }
            }
          }
        }
      }
    }
    .listStyle(.sidebar)
    .accessibilityIdentifier("sourceSidebar")
    .scrollContentBackground(model.selectedThemeID == .system ? .automatic : .hidden)
    .background {
      if model.selectedThemeID != .system {
        theme.color(.sidebarBackground)
      }
    }
    .navigationTitle("Lattice")
    .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 280)
  }

  private var sourceSelection: Binding<MacNoteSource?> {
    Binding {
      if let selectedTagName = model.selectedTagName {
        return .tag(selectedTagName)
      }
      return .allNotes
    } set: { source in
      switch source {
      case .allNotes:
        model.selectTag(nil)
      case .tag(let normalizedName):
        guard let tag = model.tagSummaries.first(where: { $0.normalizedName == normalizedName }) else {
          return
        }
        model.selectTag(tag)
      case nil:
        break
      }
    }
  }
}

struct MacNoteList: View {
  @Bindable var model: LatticeAppModel
  @Environment(\.latticeTheme) private var theme

  var body: some View {
    Group {
      if visibleNotes.isEmpty {
        emptyState
      } else {
        List(selection: noteSelection) {
          ForEach(visibleNotes) { note in
            MacNoteListRow(
              title: title(for: note),
              excerpt: excerpt(for: note),
              modifiedAt: modifiedAt(for: note),
              isDailyNote: isDailyNote(note),
              isSelected: model.selectedNote?.id == note.id
            )
            .tag(note.id)
            .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
            .listRowSeparator(.hidden)
            .contextMenu {
              Button {
                model.beginRenaming(note)
              } label: {
                Label("Rename", systemImage: "pencil")
              }
              Button(role: .destructive) {
                model.delete(note)
              } label: {
                Label("Delete", systemImage: "trash")
              }
            }
          }
        }
        .listStyle(.plain)
        .accessibilityIdentifier("noteList")
      }
    }
    .scrollContentBackground(model.selectedThemeID == .system ? .automatic : .hidden)
    .background {
      if model.selectedThemeID != .system {
        theme.color(.appBackground)
      }
    }
    .navigationTitle(model.selectedTagName == nil ? "" : sourceTitle)
    .navigationSplitViewColumnWidth(min: 260, ideal: 320, max: 400)
  }

  private var noteSelection: Binding<SavedNote.ID?> {
    Binding {
      model.selectedNote?.id
    } set: { noteID in
      guard
        let noteID,
        noteID != model.selectedNote?.id,
        let note = model.sections.lazy.flatMap(\.notes).first(where: { $0.id == noteID })
      else {
        return
      }
      model.open(note)
    }
  }

  private var visibleNotes: [SavedNote] {
    let notes = model.sections.flatMap(\.notes)
    return notes.sorted { lhs, rhs in
      switch (modifiedAt(for: lhs), modifiedAt(for: rhs)) {
      case let (lhsDate?, rhsDate?) where lhsDate != rhsDate:
        return lhsDate > rhsDate
      case (_?, nil):
        return true
      case (nil, _?):
        return false
      default:
        return lhs.id > rhs.id
      }
    }
  }

  private func title(for note: SavedNote) -> String {
    model.notePreviews[note.id]?.title ?? model.displayTitle(for: note)
  }

  private func excerpt(for note: SavedNote) -> String {
    let source = model.notePreviews[note.id]?.excerpt ?? ""
    let rendered = (try? AttributedString(
      markdown: source,
      options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
    )).map { String($0.characters) } ?? source
    let excerpt = rendered.trimmingCharacters(in: .whitespacesAndNewlines)
    return excerpt.compare(title(for: note), options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
      ? ""
      : excerpt
  }

  private func modifiedAt(for note: SavedNote) -> Date? {
    model.notePreviews[note.id]?.modifiedAt ?? note.modifiedAt
  }

  private func isDailyNote(_ note: SavedNote) -> Bool {
    note.filenameTitle.range(
      of: #"^\d{4}-\d{2}-\d{2}$"#,
      options: .regularExpression
    ) != nil
  }

  private var sourceTitle: String {
    guard let selectedTagName = model.selectedTagName else {
      return "All Notes"
    }
    let displayName = model.tagSummaries
      .first(where: { $0.normalizedName == selectedTagName })?
      .name ?? selectedTagName
    return "#\(displayName)"
  }

  @ViewBuilder
  private var emptyState: some View {
    ContentUnavailableView(
      model.selectedTagName == nil ? "No Notes" : "No Tagged Notes",
      systemImage: model.selectedTagName == nil ? "note.text" : "tag",
      description: Text(
        model.selectedTagName == nil
          ? "Create a note to start writing."
          : "No notes currently use this tag."
      )
    )
  }
}

@MainActor
private struct MacNoteListRow: View {
  let title: String
  let excerpt: String
  let modifiedAt: Date?
  let isDailyNote: Bool
  let isSelected: Bool

  @Environment(\.latticeTheme) private var theme

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 7) {
        if isDailyNote {
          Image(systemName: "calendar")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(theme.color(.accent))
            .frame(width: 14)
            .accessibilityHidden(true)
        }

        Text(title)
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(theme.color(.primaryText))
          .lineLimit(1)
          .truncationMode(.tail)
      }

      if !excerpt.isEmpty {
        Text(excerpt)
          .font(.system(size: 13))
          .foregroundStyle(theme.color(.secondaryText))
          .lineLimit(2)
          .truncationMode(.tail)
      } else if isDailyNote {
        Text("Daily Note")
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(theme.color(.secondaryText))
      }

      if let modifiedAt {
        Text(modifiedAt, format: noteDateFormat(for: modifiedAt))
          .font(.system(size: 11))
          .foregroundStyle(theme.color(.secondaryText).opacity(0.72))
      }
    }
    .frame(maxWidth: .infinity, minHeight: 66, alignment: .topLeading)
    .padding(.vertical, 8)
    .padding(.horizontal, 10)
    .overlay(alignment: .leading) {
      if isSelected {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
          .fill(theme.color(.accent))
          .frame(width: 3)
          .padding(.vertical, 7)
      }
    }
    .overlay(alignment: .bottom) {
      Rectangle()
        .fill(theme.color(.separator).opacity(0.7))
        .frame(height: 0.5)
        .padding(.leading, 10)
    }
    .contentShape(Rectangle())
  }

  private func noteDateFormat(for date: Date) -> Date.FormatStyle {
    let calendar = Calendar.current
    if calendar.isDateInToday(date) {
      return .dateTime.hour().minute()
    }
    if calendar.component(.year, from: date) == calendar.component(.year, from: Date()) {
      return .dateTime.month(.abbreviated).day()
    }
    return .dateTime.month(.abbreviated).day().year()
  }
}

#endif
