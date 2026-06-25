import LatticeCore
import LatticeEditor
import SwiftUI
import UniformTypeIdentifiers

public struct LatticeRootView: View {
  @Bindable private var model: LatticeAppModel
  private let commandPalettePlatformCommands: @MainActor () -> [CommandPaletteCommand]

  public init(
    model: LatticeAppModel,
    commandPalettePlatformCommands: @escaping @MainActor () -> [CommandPaletteCommand] = { [] }
  ) {
    self.model = model
    self.commandPalettePlatformCommands = commandPalettePlatformCommands
  }

  public var body: some View {
    NavigationSplitView(preferredCompactColumn: preferredColumnBinding) {
      NoteSidebar(model: model)
    } detail: {
      editorPane
    }
    .fileImporter(
      isPresented: $model.isShowingFolderImporter,
      allowedContentTypes: [.folder],
      allowsMultipleSelection: false
    ) { result in
      switch result {
      case .success(let urls):
        if let url = urls.first {
          model.chooseFolder(url)
        }
      case .failure(let error):
        model.errorMessage = error.localizedDescription
      }
    }
    .alert("Lattice", isPresented: Binding(
      get: { model.errorMessage != nil },
      set: { if !$0 { model.errorMessage = nil } }
    )) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(model.errorMessage ?? "")
    }
    .alert("Rename Note", isPresented: Binding(
      get: { model.renamingNote != nil },
      set: { if !$0 { model.cancelRename() } }
    )) {
      TextField("Filename", text: $model.renameTitle)
      Button("Rename") {
        model.commitRename()
      }
      Button("Cancel", role: .cancel) {
        model.cancelRename()
      }
    } message: {
      Text("Wiki links to this note will be updated.")
    }
    .sheet(isPresented: $model.isShowingCommandPalette) {
      CommandPaletteView(
        model: model,
        platformCommands: commandPalettePlatformCommands()
      )
    }
    .sheet(isPresented: $model.isShowingSettings) {
      TaskSyncSettingsView(model: model)
    }
    .confirmationDialog(
      "Choose Note",
      isPresented: Binding(
        get: { model.ambiguousWikiLink != nil },
        set: { if !$0 { model.dismissAmbiguousWikiLinkResolution() } }
      ),
      titleVisibility: .visible
    ) {
      if let pending = model.ambiguousWikiLink {
        ForEach(pending.candidates) { candidate in
          Button(candidate.relativePath) {
            model.chooseAmbiguousWikiLinkTarget(candidate)
          }
        }
      }
      Button("Cancel", role: .cancel) {
        model.dismissAmbiguousWikiLinkResolution()
      }
    } message: {
      Text("Several notes match this link.")
    }
  }

  private var preferredColumnBinding: Binding<NavigationSplitViewColumn> {
    Binding {
      switch model.preferredCompactColumn {
      case .sidebar:
        return .sidebar
      case .detail:
        return .detail
      }
    } set: { column in
      switch column {
      case .detail:
        model.preferredCompactColumn = .detail
      default:
        model.preferredCompactColumn = .sidebar
      }
    }
  }

  @ViewBuilder
  private var editorPane: some View {
    if model.hasFolder {
      NoteEditorPane(model: model)
    } else {
      FolderSetupView(model: model)
    }
  }
}

private struct NoteSidebar: View {
  @Bindable var model: LatticeAppModel

  var body: some View {
    List {
      if model.hasFolder {
        ForEach(model.sections) { section in
          Section(section.dateString) {
            ForEach(section.notes) { note in
              Button {
                model.open(note)
              } label: {
                HStack(spacing: 8) {
                  Text(model.displayTitle(for: note))
                    .lineLimit(1)
                  Spacer()
                  if model.selectedNote == note {
                    Image(systemName: "checkmark")
                      .font(.caption.weight(.semibold))
                      .foregroundStyle(.secondary)
                  }
                }
              }
              .buttonStyle(.plain)
              .contextMenu {
                Button {
                  model.beginRenaming(note)
                } label: {
                  Label("Rename", systemImage: "pencil")
                }
              }
            }
          }
        }
      } else {
        ContentUnavailableView(
          "Choose a Folder",
          systemImage: "folder",
          description: Text("Store plain Markdown notes in a folder you control.")
        )
      }
    }
    .navigationTitle("Lattice")
    #if os(macOS)
    .navigationSplitViewColumnWidth(min: 140, ideal: 180, max: 260)
    #endif
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button {
          model.createNewNote()
        } label: {
          Label("New Note", systemImage: "square.and.pencil")
        }
        .disabled(!model.hasFolder)
      }
      ToolbarItem(placement: .secondaryAction) {
        Button {
          model.showSettings()
        } label: {
          Label("Settings", systemImage: "gearshape")
        }
      }
      ToolbarItem(placement: .secondaryAction) {
        Button {
          model.showFolderImporter()
        } label: {
          Label("Choose Folder", systemImage: "folder")
        }
      }
    }
  }
}

private struct NoteEditorPane: View {
  @Bindable var model: LatticeAppModel

  var body: some View {
    VStack(spacing: 0) {
      MarkdownTextEditor(
        text: $model.text,
        selectedRange: $model.selectedRange,
        fontSize: CGFloat(model.editorFontSize),
        focusToken: model.editorFocusToken,
        wikiLinkStates: model.wikiLinkStates,
        onTextChange: {
          model.noteTextDidChange()
        },
        onSelectionChange: {
          model.noteSelectionDidChange()
        },
        onWikiLinkActivated: { characterIndex in
          model.activateWikiLink(at: characterIndex)
        },
        onMarkdownLinkActivated: { characterIndex in
          model.activateMarkdownLink(at: characterIndex)
        }
      )
      .ignoresSafeArea(.keyboard, edges: .bottom)
      autocompleteBar
      statusBar
    }
    .navigationTitle(model.selectedNote.map { model.displayTitle(for: $0) } ?? "New Note")
    #if os(macOS)
    .navigationSplitViewColumnWidth(min: 260, ideal: 560)
    #endif
    .toolbar {
      #if os(macOS)
      ToolbarItem(placement: .primaryAction) {
        Menu {
          markdownButton(.heading, title: "Heading", systemImage: "textformat.size")
          markdownButton(.bold, title: "Bold", systemImage: "bold")
          markdownButton(.italic, title: "Italic", systemImage: "italic")
          markdownButton(.bulletList, title: "List", systemImage: "list.bullet")
          markdownButton(.taskList, title: "Checkbox", systemImage: "checklist")
          markdownButton(.code, title: "Code", systemImage: "chevron.left.forwardslash.chevron.right")
          markdownButton(.link, title: "Link", systemImage: "link")
        } label: {
          Label("Format", systemImage: "textformat")
        }
        .disabled(!model.hasFolder)
      }
      #else
      ToolbarItemGroup(placement: .primaryAction) {
        markdownButton(.heading, title: "Heading", systemImage: "textformat.size")
        markdownButton(.bold, title: "Bold", systemImage: "bold")
        markdownButton(.italic, title: "Italic", systemImage: "italic")
        markdownButton(.bulletList, title: "List", systemImage: "list.bullet")
        markdownButton(.taskList, title: "Checkbox", systemImage: "checklist")
        markdownButton(.code, title: "Code", systemImage: "chevron.left.forwardslash.chevron.right")
        markdownButton(.link, title: "Link", systemImage: "link")
      }
      #endif
    }
  }

  private var statusBar: some View {
    Text(statusText)
      .font(.footnote.weight(.medium))
      .foregroundStyle(.secondary)
      .frame(maxWidth: .infinity)
      .padding(.vertical, 10)
      .background(.bar)
  }

  @ViewBuilder
  private var autocompleteBar: some View {
    if !model.wikiAutocompleteSuggestions.isEmpty {
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 8) {
          ForEach(model.wikiAutocompleteSuggestions) { suggestion in
            Button {
              model.selectWikiAutocompleteSuggestion(suggestion)
            } label: {
              VStack(alignment: .leading, spacing: 2) {
                Text(suggestion.title)
                  .font(.callout.weight(.medium))
                  .lineLimit(1)
                Text(suggestion.subtitle)
                  .font(.caption)
                  .foregroundStyle(.secondary)
                  .lineLimit(1)
              }
              .frame(minWidth: 120, alignment: .leading)
            }
            .buttonStyle(.bordered)
          }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
      }
      .background(.bar)
    }
  }

  private var statusText: String {
    let count = model.text.count
    let unit = count == 1 ? "character" : "characters"
    return model.status.isEmpty ? "\(count) \(unit)" : "\(model.status) - \(count) \(unit)"
  }

  private func markdownButton(
    _ command: MarkdownCommand,
    title: String,
    systemImage: String
  ) -> some View {
    Button {
      model.apply(command)
    } label: {
      Label(title, systemImage: systemImage)
    }
    .disabled(!model.hasFolder)
  }
}

private struct FolderSetupView: View {
  @Bindable var model: LatticeAppModel

  var body: some View {
    VStack(spacing: 18) {
      Image(systemName: "folder.badge.plus")
        .font(.system(size: 44, weight: .regular))
        .foregroundStyle(.secondary)
      Text("Choose a notes folder")
        .font(.title2.weight(.semibold))
      Text("Lattice writes ordinary Markdown files into a folder you control. Use the recommended location for iCloud Drive sync, or choose another folder.")
        .font(.body)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: 420)
      VStack(spacing: 8) {
        Button {
          model.useRecommendedFolder()
        } label: {
          Label("Use Recommended Folder", systemImage: "icloud.and.arrow.up")
            .frame(minWidth: 240)
        }
        .buttonStyle(.borderedProminent)
        Text(model.recommendedFolderURL.path)
          .font(.caption)
          .foregroundStyle(.tertiary)
          .lineLimit(2)
          .multilineTextAlignment(.center)
        Button {
          model.showFolderImporter()
        } label: {
          Label("Choose Another Folder", systemImage: "folder")
            .frame(minWidth: 240)
        }
        .buttonStyle(.bordered)
      }
    }
    .padding(32)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .navigationTitle("Lattice")
    #if os(macOS)
    .navigationSplitViewColumnWidth(min: 260, ideal: 560)
    #endif
  }
}
