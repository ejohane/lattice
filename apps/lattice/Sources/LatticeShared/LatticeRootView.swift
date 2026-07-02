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
    .background(model.theme.color(.appBackground))
    .environment(\.latticeTheme, model.theme)
    .preferredColorScheme(model.theme.preferredColorScheme)
    .tint(model.theme.color(.accent))
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
  @Environment(\.latticeTheme) private var theme

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
                    .truncationMode(.tail)
                  Spacer()
	                  if model.selectedNote == note {
	                    Image(systemName: "checkmark")
	                      .font(.caption.weight(.semibold))
	                      .foregroundStyle(theme.color(.secondaryText))
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
                Button(role: .destructive) {
                  model.delete(note)
                } label: {
                  Label("Delete", systemImage: "trash")
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
    .scrollContentBackground(.hidden)
    .background(theme.color(.sidebarBackground))
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
  @Environment(\.latticeTheme) private var theme
  private let maximumEditorWidth: CGFloat = 920
  private let editorHorizontalPadding: CGFloat = 18

  var body: some View {
    editorContent
      .frame(maxWidth: maximumEditorWidth, maxHeight: .infinity)
      .padding(.horizontal, editorHorizontalPadding)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(theme.color(.appBackground))
      .navigationTitle(model.selectedNote.map { model.displayTitle(for: $0) } ?? "New Note")
      #if os(macOS)
      .navigationSplitViewColumnWidth(min: 260, ideal: 720)
      #endif
      .toolbar {
        ToolbarItemGroup(placement: .primaryAction) {
          Button {
            model.navigateBack()
          } label: {
            Label("Back", systemImage: "chevron.left")
          }
          .help("Back")
          .disabled(!model.canNavigateBack)

          Button {
            model.navigateForward()
          } label: {
            Label("Forward", systemImage: "chevron.right")
          }
          .help("Forward")
          .disabled(!model.canNavigateForward)
        }

        #if os(macOS)
        ToolbarItem(placement: .primaryAction) {
          Menu {
            markdownButton(.heading, title: "Heading", systemImage: "textformat.size")
            markdownButton(.bold, title: "Bold", systemImage: "bold")
            markdownButton(.italic, title: "Italic", systemImage: "italic")
            markdownButton(.horizontalRule, title: "Horizontal Rule", systemImage: "minus")
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
          markdownButton(.horizontalRule, title: "Horizontal Rule", systemImage: "minus")
          markdownButton(.bulletList, title: "List", systemImage: "list.bullet")
          markdownButton(.taskList, title: "Checkbox", systemImage: "checklist")
          markdownButton(.code, title: "Code", systemImage: "chevron.left.forwardslash.chevron.right")
          markdownButton(.link, title: "Link", systemImage: "link")
        }
        #endif
      }
  }

  private var editorContent: some View {
    VStack(spacing: 0) {
      MarkdownTextEditor(
        text: $model.text,
        selectedRange: $model.selectedRange,
        vimState: $model.vimState,
        fontSize: CGFloat(model.editorFontSize),
        fontFamily: model.editorFontFamily,
        focusToken: model.editorFocusToken,
        isVimModeEnabled: model.isVimModeEnabled,
        showsRelativeLineNumbers: model.showsRelativeLineNumbers,
        hasAutocompleteSuggestions: !model.wikiAutocompleteSuggestions.isEmpty,
        wikiLinkStates: model.wikiLinkStates,
        theme: theme,
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
        },
        onDismissAutocomplete: {
          model.dismissWikiAutocomplete()
        },
        onVimWrite: {
          model.vimWrite()
        },
        onVimStatusChange: { message in
          model.setVimStatusMessage(message)
        }
      )
      .ignoresSafeArea(.keyboard, edges: .bottom)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(theme.color(.editorBackground))
      autocompleteBar
      if model.showsStatusBar {
        statusBar
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var statusBar: some View {
    HStack(spacing: 8) {
      if let modeText {
        Text(modeText)
          .font(.caption2.weight(.bold))
          .foregroundStyle(modeText == "NORMAL" ? theme.color(.highlightedText) : theme.color(.secondaryText))
          .padding(.horizontal, 7)
          .padding(.vertical, 3)
          .background {
            Capsule()
              .fill(modeText == "NORMAL" ? theme.color(.accent) : theme.color(.secondaryText).opacity(0.14))
          }
      }

      Text(statusText)
        .font(.footnote.weight(.medium))
        .foregroundStyle(theme.color(.secondaryText))
    }
      .frame(maxWidth: .infinity)
      .padding(.vertical, 10)
      .background(theme.color(.barBackground))
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
                  .foregroundStyle(theme.color(.secondaryText))
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
      .background(theme.color(.barBackground))
    }
  }

  private var statusText: String {
    let count = model.text.count
    let unit = count == 1 ? "character" : "characters"
    var parts: [String] = []
    if let vimStatusMessage = model.vimStatusMessage, !vimStatusMessage.isEmpty {
      parts.append(vimStatusMessage)
    } else if !model.status.isEmpty {
      parts.append(model.status)
    }
    parts.append("\(count) \(unit)")
    return parts.joined(separator: " - ")
  }

  private var modeText: String? {
    guard model.isVimModeEnabled else {
      return nil
    }

    switch model.vimState.mode {
    case .insert:
      return "INSERT"
    case .normal:
      return "NORMAL"
    case .visual:
      return "VISUAL"
    case .commandLine:
      return ":\(model.vimState.commandText)"
    }
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
  @Environment(\.latticeTheme) private var theme

  var body: some View {
    VStack(spacing: 18) {
      Image(systemName: "folder.badge.plus")
        .font(.system(size: 44, weight: .regular))
        .foregroundStyle(theme.color(.secondaryText))
      Text("Choose a notes folder")
        .font(.title2.weight(.semibold))
      Text("Lattice writes ordinary Markdown files into a folder you control. Use the recommended iCloud Drive location to sync between devices, or choose another folder.")
        .font(.body)
        .foregroundStyle(theme.color(.secondaryText))
        .multilineTextAlignment(.center)
        .frame(maxWidth: 420)
      VStack(spacing: 8) {
        Button {
          model.useRecommendedFolder()
        } label: {
          Label(model.isRecommendedFolderCloudBacked ? "Use iCloud Drive" : "Use Local Folder", systemImage: "icloud.and.arrow.up")
            .frame(minWidth: 240)
        }
        .buttonStyle(.borderedProminent)
        Text(model.recommendedFolderDescription)
          .font(.caption)
          .foregroundStyle(model.isRecommendedFolderCloudBacked ? theme.color(.secondaryText) : theme.color(.warning))
          .multilineTextAlignment(.center)
        Text(model.recommendedFolderURL.path)
          .font(.caption)
          .foregroundStyle(theme.color(.tertiaryText))
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
    .background(theme.color(.appBackground))
    .navigationTitle("Lattice")
    #if os(macOS)
    .navigationSplitViewColumnWidth(min: 260, ideal: 560)
    #endif
  }
}
