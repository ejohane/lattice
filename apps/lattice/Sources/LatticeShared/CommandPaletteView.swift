import LatticeCore
import SwiftUI

public struct CommandPaletteView: View {
  @Bindable private var model: LatticeAppModel
  private let platformCommands: [CommandPaletteCommand]
  @FocusState private var isSearchFocused: Bool
  @State private var highlightedID: CommandPaletteItem.ID?

  public init(
    model: LatticeAppModel,
    platformCommands: [CommandPaletteCommand] = []
  ) {
    self.model = model
    self.platformCommands = platformCommands
  }

  public var body: some View {
    VStack(spacing: 0) {
      searchField
      Divider()
      resultsList
    }
    #if os(macOS)
    .frame(width: 540, height: 480)
    #else
    .presentationDetents([.medium, .large])
    #endif
    .task {
      highlightedID = items.first?.id
      isSearchFocused = true
    }
    .onChange(of: model.commandPaletteQuery) {
      highlightedID = items.first?.id
    }
    .commandPaletteExitCommand {
      model.dismissCommandPalette()
    }
    .onKeyPress(.return) {
      activateHighlightedItem()
      return .handled
    }
    .onKeyPress(keys: [.upArrow, .downArrow]) { press in
      switch press.key {
      case .upArrow:
        moveHighlight(by: -1)
      case .downArrow:
        moveHighlight(by: 1)
      default:
        return .ignored
      }
      return .handled
    }
  }

  private var searchField: some View {
    HStack(spacing: 10) {
      Image(systemName: "magnifyingglass")
        .foregroundStyle(.secondary)
      TextField("Search commands and notes", text: $model.commandPaletteQuery)
        .textFieldStyle(.plain)
        .focused($isSearchFocused)
        .onSubmit {
          activateHighlightedItem()
        }
    }
    .font(.title3)
    .padding(.horizontal, 16)
    .padding(.vertical, 14)
  }

  private var resultsList: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 2) {
        if items.isEmpty {
          ContentUnavailableView.search
            .frame(maxWidth: .infinity)
            .padding(.vertical, 36)
        } else {
          ForEach(items) { item in
            Button {
              activate(item)
            } label: {
              CommandPaletteRow(
                item: item,
                isHighlighted: item.id == highlightedID
              )
            }
            .buttonStyle(.plain)
            .onHover { isHovering in
              if isHovering {
                highlightedID = item.id
              }
            }
          }
        }
      }
      .padding(8)
    }
  }

  private var items: [CommandPaletteItem] {
    let commands = model.commandPaletteCommands(platformCommands: platformCommands)
      .map(CommandPaletteItem.command)
    let notes = model.commandPaletteNotes()
      .map { note in
        CommandPaletteItem.note(
          note,
          title: model.displayTitle(for: note),
          subtitle: note.dateString
        )
      }
    return commands + notes
  }

  private func activateHighlightedItem() {
    guard let highlightedID,
          let item = items.first(where: { $0.id == highlightedID }) ?? items.first
    else {
      return
    }
    activate(item)
  }

  private func activate(_ item: CommandPaletteItem) {
    model.dismissCommandPalette()
    DispatchQueue.main.async {
      switch item {
      case .command(let command):
        command.perform()
      case .note(let note, _, _):
        model.open(note)
      }
    }
  }

  private func moveHighlight(by offset: Int) {
    let currentItems = items
    guard !currentItems.isEmpty else {
      highlightedID = nil
      return
    }

    let currentIndex = highlightedID
      .flatMap { id in currentItems.firstIndex { $0.id == id } }
      ?? 0
    let nextIndex = min(max(currentIndex + offset, 0), currentItems.count - 1)
    highlightedID = currentItems[nextIndex].id
  }
}

private extension View {
  @ViewBuilder
  func commandPaletteExitCommand(
    _ action: @escaping @MainActor () -> Void
  ) -> some View {
    #if os(macOS)
    self.onExitCommand(perform: action)
    #else
    self
    #endif
  }
}

private enum CommandPaletteItem: Identifiable {
  case command(CommandPaletteCommand)
  case note(SavedNote, title: String, subtitle: String)

  var id: String {
    switch self {
    case .command(let command):
      return "command:\(command.id)"
    case .note(let note, _, _):
      return "note:\(note.id)"
    }
  }

  var title: String {
    switch self {
    case .command(let command):
      return command.title
    case .note(_, let title, _):
      return title
    }
  }

  var subtitle: String? {
    switch self {
    case .command(let command):
      return command.subtitle
    case .note(_, _, let subtitle):
      return subtitle
    }
  }

  var systemImage: String {
    switch self {
    case .command(let command):
      return command.systemImage
    case .note:
      return "doc.text"
    }
  }
}

private struct CommandPaletteRow: View {
  let item: CommandPaletteItem
  let isHighlighted: Bool

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: item.systemImage)
        .font(.system(size: 16, weight: .medium))
        .foregroundStyle(isHighlighted ? .white : .secondary)
        .frame(width: 24, height: 24)
      VStack(alignment: .leading, spacing: 2) {
        Text(item.title)
          .font(.body.weight(.medium))
          .foregroundStyle(isHighlighted ? .white : .primary)
          .lineLimit(1)
          .truncationMode(.tail)
        if let subtitle = item.subtitle, !subtitle.isEmpty {
          Text(subtitle)
            .font(.caption)
            .foregroundStyle(isHighlighted ? .white.opacity(0.82) : .secondary)
            .lineLimit(1)
            .truncationMode(.tail)
        }
      }
      Spacer(minLength: 12)
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 8)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(isHighlighted ? Color.accentColor : Color.clear)
    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
  }
}
