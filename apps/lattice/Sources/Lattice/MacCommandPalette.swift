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
  private enum Selection: CaseIterable, Hashable {
    case newNote
    case todayNote

    var title: String {
      switch self {
      case .newNote: "New Note"
      case .todayNote: "Today’s Note"
      }
    }

    var subtitle: String? {
      switch self {
      case .newNote: nil
      case .todayNote: "Create or open today’s daily note"
      }
    }

    var systemImage: String {
      switch self {
      case .newNote: "square.and.pencil"
      case .todayNote: "calendar"
      }
    }

    var shortcut: String? {
      switch self {
      case .newNote: "⌘N"
      case .todayNote: nil
      }
    }
  }

  let canCreateNote: Bool
  let onCreateNote: @MainActor () -> Void
  let onOpenTodayNote: @MainActor () -> Void

  @Environment(\.dismiss) private var dismiss
  @FocusState private var isSearchFocused: Bool
  @State private var query = ""
  @State private var selection: Selection? = .newNote

  private var visibleCommands: [Selection] {
    let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedQuery.isEmpty else { return Selection.allCases }

    return Selection.allCases.filter { command in
      [command.title, command.subtitle]
        .compactMap { $0 }
        .joined(separator: " ")
        .localizedCaseInsensitiveContains(trimmedQuery)
    }
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
          .onSubmit(performSelectedCommand)
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 14)

      Divider()

      List(selection: $selection) {
        if !visibleCommands.isEmpty {
          ForEach(visibleCommands, id: \.self) { command in
            Button {
              perform(command)
            } label: {
              commandRow(command)
            }
            .buttonStyle(.plain)
            .disabled(!canCreateNote)
            .tag(command)
            .listRowInsets(EdgeInsets(top: 2, leading: 6, bottom: 2, trailing: 6))
            .listRowSeparator(.hidden)
          }
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
      selection = visibleCommands.first
    }
    .onKeyPress(.upArrow) {
      moveSelection(by: -1)
      return .handled
    }
    .onKeyPress(.downArrow) {
      moveSelection(by: 1)
      return .handled
    }
    .onExitCommand {
      dismiss()
    }
  }

  private func commandRow(_ command: Selection) -> some View {
    HStack(spacing: 12) {
      Image(systemName: command.systemImage)
        .foregroundStyle(.secondary)
        .frame(width: 20)

      VStack(alignment: .leading, spacing: 2) {
        Text(command.title)

        if let subtitle = command.subtitle {
          Text(subtitle)
            .font(.callout)
            .foregroundStyle(.secondary)
        }
      }

      Spacer()

      if let shortcut = command.shortcut {
        Text(shortcut)
          .font(.system(.callout, design: .rounded, weight: .medium))
          .foregroundStyle(.secondary)
      }
    }
    .contentShape(Rectangle())
    .padding(.horizontal, 8)
    .padding(.vertical, 7)
    .frame(height: 56)
  }

  private func performSelectedCommand() {
    guard let command = selection ?? visibleCommands.first else { return }
    perform(command)
  }

  private func perform(_ command: Selection) {
    guard canCreateNote, visibleCommands.contains(command) else { return }
    switch command {
    case .newNote:
      onCreateNote()
    case .todayNote:
      onOpenTodayNote()
    }
  }

  private func moveSelection(by offset: Int) {
    guard !visibleCommands.isEmpty else {
      selection = nil
      return
    }
    guard let selection,
          let currentIndex = visibleCommands.firstIndex(of: selection)
    else {
      self.selection = visibleCommands.first
      return
    }

    let nextIndex = min(max(currentIndex + offset, 0), visibleCommands.count - 1)
    self.selection = visibleCommands[nextIndex]
  }
}
