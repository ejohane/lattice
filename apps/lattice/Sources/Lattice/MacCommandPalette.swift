import SwiftUI

struct MacMarkdownFocusedAction {
  let isEnabled: Bool
  let perform: @MainActor () -> Void

  init(
    isEnabled: Bool = true,
    perform: @escaping @MainActor () -> Void
  ) {
    self.isEnabled = isEnabled
    self.perform = perform
  }
}

private struct MacMarkdownNewNoteActionKey: FocusedValueKey {
  typealias Value = MacMarkdownFocusedAction
}

private struct MacMarkdownShowCommandPaletteActionKey: FocusedValueKey {
  typealias Value = MacMarkdownFocusedAction
}

extension FocusedValues {
  var macMarkdownNewNoteAction: MacMarkdownFocusedAction? {
    get { self[MacMarkdownNewNoteActionKey.self] }
    set { self[MacMarkdownNewNoteActionKey.self] = newValue }
  }

  var macMarkdownShowCommandPaletteAction: MacMarkdownFocusedAction? {
    get { self[MacMarkdownShowCommandPaletteActionKey.self] }
    set { self[MacMarkdownShowCommandPaletteActionKey.self] = newValue }
  }
}

struct MacCommandPaletteView: View {
  private enum Selection: Hashable {
    case newNote
  }

  let canCreateNote: Bool
  let onCreateNote: @MainActor () -> Void

  @Environment(\.dismiss) private var dismiss
  @FocusState private var isSearchFocused: Bool
  @State private var query = ""
  @State private var selection: Selection? = .newNote

  private var showsNewNote: Bool {
    query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      || "new note".localizedCaseInsensitiveContains(query)
  }

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 10) {
        Image(systemName: "magnifyingglass")
          .foregroundStyle(.secondary)

        TextField("Search commands", text: $query)
          .textFieldStyle(.plain)
          .font(.title3)
          .focused($isSearchFocused)
          .onSubmit(performNewNote)
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 14)

      Divider()

      List(selection: $selection) {
        if showsNewNote {
          Button(action: performNewNote) {
            HStack(spacing: 12) {
              Image(systemName: "square.and.pencil")
                .foregroundStyle(.secondary)
                .frame(width: 20)

              Text("New Note")

              Spacer()

              Text("⌘N")
                .font(.system(.callout, design: .rounded, weight: .medium))
                .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
          }
          .buttonStyle(.plain)
          .disabled(!canCreateNote)
          .tag(Selection.newNote)
          .listRowInsets(EdgeInsets(top: 2, leading: 6, bottom: 2, trailing: 6))
          .listRowSeparator(.hidden)
        } else {
          ContentUnavailableView.search(text: query)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .listRowSeparator(.hidden)
        }
      }
      .listStyle(.plain)
      .scrollContentBackground(.hidden)
    }
    .frame(width: 480, height: 180)
    .task {
      isSearchFocused = true
    }
    .onChange(of: query) {
      selection = showsNewNote ? .newNote : nil
    }
    .onKeyPress(keys: [.upArrow, .downArrow]) { _ in
      if showsNewNote {
        selection = .newNote
      }
      return .handled
    }
    .onExitCommand {
      dismiss()
    }
  }

  private func performNewNote() {
    guard canCreateNote, showsNewNote else { return }
    onCreateNote()
  }
}
