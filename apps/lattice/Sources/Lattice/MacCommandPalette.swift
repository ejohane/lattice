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
  private enum Command: CaseIterable, Hashable {
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

  private enum Item: Hashable {
    case command(Command)
    case createNote(String)
    case note(MacCommandPaletteNote)

    var title: String {
      switch self {
      case .command(let command):
        command.title
      case .createNote(let title):
        "Create “\(title)”"
      case .note(let note):
        note.title
      }
    }

    var subtitle: String? {
      switch self {
      case .command(let command):
        command.subtitle
      case .createNote:
        nil
      case .note(let note):
        note.path
      }
    }

    var systemImage: String {
      switch self {
      case .command(let command):
        command.systemImage
      case .createNote:
        "square.and.pencil"
      case .note:
        "doc.text"
      }
    }

    var shortcut: String? {
      switch self {
      case .command(let command):
        command.shortcut
      case .createNote:
        "⌘↩"
      case .note:
        nil
      }
    }
  }

  let canCreateNote: Bool
  let notes: (String) -> [MacCommandPaletteNote]
  let creationTitle: (String) -> String?
  let onCreateNote: @MainActor () -> Void
  let onCreateNamedNote: @MainActor (String) -> Void
  let onOpenTodayNote: @MainActor () -> Void
  let onOpenNote: @MainActor (MacCommandPaletteNote.ID) -> Void

  @Environment(\.dismiss) private var dismiss
  @FocusState private var isSearchFocused: Bool
  @State private var query = ""
  @State private var selection: Item?

  private var visibleCommands: [Command] {
    let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedQuery.isEmpty else { return Command.allCases }

    return Command.allCases.filter { command in
      [command.title, command.subtitle]
        .compactMap { $0 }
        .joined(separator: " ")
        .localizedCaseInsensitiveContains(trimmedQuery)
    }
  }

  private var visibleNotes: [MacCommandPaletteNote] {
    notes(query)
  }

  private var visibleCommandItems: [Item] {
    let title = creationTitle(query)
    var items = title.map { [Item.createNote($0)] } ?? []
    items += visibleCommands
      .filter { title == nil || $0 != .newNote }
      .map(Item.command)
    return items
  }

  private var visibleItems: [Item] {
    visibleCommandItems + visibleNotes.map(Item.note)
  }

  private var preferredSelection: Item? {
    let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedQuery.isEmpty else {
      return visibleCommandItems.first
    }
    return visibleNotes.first.map(Item.note) ?? visibleCommandItems.first
  }

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 10) {
        Image(systemName: "magnifyingglass")
          .foregroundStyle(.secondary)

        TextField("Search commands and notes", text: $query)
          .textFieldStyle(.plain)
          .font(.title3)
          .focused($isSearchFocused)
          .onKeyPress(keys: [.return]) { press in
            guard press.modifiers.contains(.command) else {
              return .ignored
            }
            performQueryCreation()
            return .handled
          }
          .onSubmit(performSelectedItem)
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 14)

      Divider()

      List(selection: $selection) {
        if visibleItems.isEmpty {
          ContentUnavailableView.search(text: query)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .listRowSeparator(.hidden)
        } else {
          if !visibleCommandItems.isEmpty {
            Section("Commands") {
              ForEach(visibleCommandItems, id: \.self) { item in
                Button {
                  perform(item)
                } label: {
                  itemRow(item)
                }
                .buttonStyle(.plain)
                .disabled(!canCreateNote)
                .tag(item)
                .listRowInsets(EdgeInsets(top: 2, leading: 6, bottom: 2, trailing: 6))
                .listRowSeparator(.hidden)
              }
            }
          }

          if !visibleNotes.isEmpty {
            Section(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Recent Notes" : "Notes") {
              ForEach(visibleNotes) { note in
                Button {
                  perform(.note(note))
                } label: {
                  itemRow(.note(note))
                }
                .buttonStyle(.plain)
                .tag(Item.note(note))
                .listRowInsets(EdgeInsets(top: 2, leading: 6, bottom: 2, trailing: 6))
                .listRowSeparator(.hidden)
              }
            }
          }
        }
      }
      .listStyle(.plain)
      .scrollContentBackground(.hidden)
    }
    .frame(width: 520, height: 420)
    .task {
      isSearchFocused = true
      selection = preferredSelection
    }
    .onChange(of: query) {
      selection = preferredSelection
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

  private func itemRow(_ item: Item) -> some View {
    HStack(spacing: 12) {
      Image(systemName: item.systemImage)
        .foregroundStyle(.secondary)
        .frame(width: 20)

      VStack(alignment: .leading, spacing: 2) {
        Text(item.title)
          .lineLimit(1)

        if let subtitle = item.subtitle {
          Text(subtitle)
            .font(.callout)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
        }
      }

      Spacer()

      if let shortcut = item.shortcut {
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

  private func performSelectedItem() {
    guard let item = selection ?? visibleItems.first else { return }
    perform(item)
  }

  private func performQueryCreation() {
    guard let title = creationTitle(query) else { return }
    onCreateNamedNote(title)
  }

  private func perform(_ item: Item) {
    guard visibleItems.contains(item) else { return }
    switch item {
    case .command(let command):
      guard canCreateNote else { return }
      switch command {
      case .newNote:
        onCreateNote()
      case .todayNote:
        onOpenTodayNote()
      }
    case .createNote(let title):
      onCreateNamedNote(title)
    case .note(let note):
      onOpenNote(note.id)
    }
  }

  private func moveSelection(by offset: Int) {
    guard !visibleItems.isEmpty else {
      selection = nil
      return
    }
    guard let selection,
          let currentIndex = visibleItems.firstIndex(of: selection)
    else {
      self.selection = visibleItems.first
      return
    }

    let nextIndex = min(max(currentIndex + offset, 0), visibleItems.count - 1)
    self.selection = visibleItems[nextIndex]
  }
}
