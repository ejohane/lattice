import LatticeMacCore
import LatticeEditor
import SwiftUI
import UniformTypeIdentifiers

struct MacMarkdownRootView: View {
  let model: MacMarkdownAppModel
  @Environment(MacKeyboardShortcutSettings.self) private var shortcutSettings
  @State private var isChoosingFolder = false
  @State private var isShowingCommandPalette = false
  @State private var tagsAreExpanded = true

  var body: some View {
    @Bindable var model = model

    NavigationSplitView {
      sidebar(model: model)
        .navigationSplitViewColumnWidth(min: 210, ideal: 240, max: 280)
    } detail: {
      editor(model: model)
    }
    .navigationTitle(model.selectedNoteTitle)
    .toolbar {
      ToolbarItemGroup(placement: .navigation) {
        Button {
          model.navigateBack()
        } label: {
          Label("Back", systemImage: "chevron.left")
        }
        .disabled(!model.canNavigateBack)
        .help("Back")

        Button {
          model.navigateForward()
        } label: {
          Label("Forward", systemImage: "chevron.right")
        }
        .disabled(!model.canNavigateForward)
        .help("Forward")
      }

      ToolbarItemGroup(placement: .primaryAction) {
        MacFileActionsMenu(
          file: model.file(for: model.selectedFileID),
          noteTitle: model.selectedFileID == nil ? nil : model.selectedNoteTitle,
          action: { action, fileID in
            Task { await model.performFileAction(action, for: fileID) }
          }
        ) {
          Label("File Actions", systemImage: "ellipsis.circle")
        }

        Button {
          model.createNote()
        } label: {
          Label("New Note", systemImage: "square.and.pencil")
        }
        .disabled(!model.canCreateNote)
        .help("New Note")
      }
    }
    .focusedSceneValue(
      \.macMarkdownNewNoteAction,
      MacMarkdownFocusedAction(isEnabled: model.canCreateNote) {
        model.createNote()
      }
    )
    .background {
      MacLocalKeyboardShortcutMonitorView(
        settings: shortcutSettings,
        canOpenTodayNote: model.canCreateNote
      ) {
        model.openTodayNote()
      }
    }
    .focusedSceneValue(
      \.macMarkdownShowCommandPaletteAction,
      MacMarkdownFocusedAction {
        isShowingCommandPalette = true
      }
    )
    .focusedSceneValue(
      \.macMarkdownOpenTodayNoteAction,
      MacMarkdownFocusedAction(isEnabled: model.canCreateNote) {
        model.openTodayNote()
      }
    )
    .sheet(isPresented: $isShowingCommandPalette) {
      MacCommandPaletteView(
        canCreateNote: model.canCreateNote,
        todayNoteShortcut: shortcutSettings.todayNoteShortcut?.description,
        notes: { query in
          model.commandPaletteNotes(matching: query)
        },
        tags: { query in
          model.commandPaletteTags(matching: query)
        },
        creationTitle: { query in
          model.commandPaletteCreationTitle(matching: query)
        },
        onCreateNote: {
          isShowingCommandPalette = false
          Task { @MainActor in
            model.createNote()
          }
        },
        onCreateNamedNote: { title in
          isShowingCommandPalette = false
          Task { @MainActor in
            model.createNote(named: title)
          }
        },
        onOpenTodayNote: {
          isShowingCommandPalette = false
          Task { @MainActor in
            model.openTodayNote()
          }
        },
        onOpenNote: { noteID in
          isShowingCommandPalette = false
          Task { @MainActor in
            model.selectFile(noteID)
          }
        },
        onFilterTag: { tag in
          isShowingCommandPalette = false
          model.selectTag(tag)
        }
      )
    }
    .fileImporter(
      isPresented: $isChoosingFolder,
      allowedContentTypes: [.folder],
      allowsMultipleSelection: false
    ) { result in
      switch result {
      case .success(let urls):
        if let url = urls.first {
          model.chooseFolder(url)
        }
      case .failure(let error):
        model.present(error)
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
    .sheet(item: Binding(
      get: { model.renamingTag },
      set: { if $0 == nil { model.cancelTagRename() } }
    )) { tag in
      MacTagRenameSheet(model: model, tag: tag)
    }
    .alert(
      "Delete #\(model.deletingTag?.name ?? "Tag")?",
      isPresented: Binding(
        get: { model.deletingTag != nil },
        set: { if !$0 { model.cancelTagDeletion() } }
      ),
      presenting: model.deletingTag
    ) { tag in
      Button("Cancel", role: .cancel) { model.cancelTagDeletion() }
      Button("Delete Tag", role: .destructive) {
        Task { _ = await model.confirmTagDeletion(tag) }
      }
    } message: { tag in
      Text("This removes #\(tag.name) from \(tag.noteCount) note\(tag.noteCount == 1 ? "" : "s"). It does not delete any notes.")
    }
    .task {
      model.start()
    }
    .onDisappear {
      model.finishSession()
    }
  }

  private func sidebar(model: MacMarkdownAppModel) -> some View {
    List(selection: Binding(
      get: { model.selectedFileID },
      set: { model.selectFile($0) }
    )) {
      if model.folderURL != nil {
        MacTagSidebarSection(
          tags: model.tagSummaries,
          selectedTagName: model.selectedTagName,
          isExpanded: $tagsAreExpanded,
          onSelect: { model.selectTag($0) },
          onRename: { model.beginRenamingTag($0) },
          onDelete: { model.requestTagDeletion($0) }
        )
      }

      Section {
        if model.folderURL != nil && model.filteredFiles.isEmpty && !model.isLoadingFiles {
          ContentUnavailableView(
            model.selectedTagName == nil ? "No Markdown Files" : "No Tagged Notes",
            systemImage: model.selectedTagName == nil ? "doc.text" : "tag",
            description: Text(emptySidebarDescription(model: model))
          )
          .listRowSeparator(.hidden)
        } else {
          ForEach(model.filteredFiles) { file in
            MacMarkdownSidebarRow(
              file: file,
              preview: model.sidebarPreview(for: file),
              isSelected: model.selectedFileID == file.id,
              action: { action, fileID in
                Task { await model.performFileAction(action, for: fileID) }
              }
            )
              .help(file.relativePath)
              .tag(file.id)
              .listRowInsets(EdgeInsets(top: 2, leading: 12, bottom: 2, trailing: 10))
          }
        }
      }
    }
    .listStyle(.sidebar)
    .overlay {
      if model.isLoadingFiles {
        ProgressView()
      }
    }
    .safeAreaInset(edge: .bottom) {
      Button {
        isChoosingFolder = true
      } label: {
        Label(
          model.folderURL == nil ? "Choose Folder" : "Change Folder",
          systemImage: "folder"
        )
      }
      .buttonStyle(.plain)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 14)
      .padding(.vertical, 12)
      .background(.bar)
    }
  }

  private func emptySidebarDescription(model: MacMarkdownAppModel) -> String {
    guard let selectedTagName = model.selectedTagName else {
      return "This folder does not contain any .md files."
    }
    let displayName = model.tagSummaries.first {
      $0.normalizedName == selectedTagName
    }?.name ?? selectedTagName
    return "No notes currently use #\(displayName)."
  }

  @ViewBuilder
  private func editor(model: MacMarkdownAppModel) -> some View {
    if model.selectedFileID != nil {
      GeometryReader { geometry in
        let horizontalPadding = MacMarkdownSpacing.editorHorizontalPadding(
          for: geometry.size.width
        )
        let topPadding = MacMarkdownSpacing.editorTopPadding(
          for: geometry.size.height
        )

        LiveMarkdownEditor(
          text: model.text,
          contentRevision: model.editorContentRevision,
          externalRefreshRequest: model.editorExternalRefreshRequest,
          focusRequest: model.editorFocusRequest,
          isEditable: !model.isLoadingFile && !model.isCreatingNote,
          onEdit: { range, replacement in
            model.applyEditorEdit(range: range, replacement: replacement)
          },
          onReplaceAll: { replacement in
            model.updateText(replacement)
          },
          onOpenWikiLink: { target in
            model.openWikiLink(target)
          },
          onEnsureTodayNote: { now, calendar in
            model.ensureTodayNote(now: now, calendar: calendar)
          },
          tagSummaries: model.tagSummaries,
          onOpenTag: { normalizedName in
            model.activateTag(normalizedName: normalizedName)
          }
        )
        .frame(
          maxWidth: MacMarkdownSpacing.editorMaximumWidth,
          maxHeight: .infinity
        )
        .padding(.horizontal, horizontalPadding)
        .padding(.top, topPadding)
        .padding(.bottom, MacMarkdownSpacing.editorBottomPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
      }
    } else if model.folderURL == nil {
      ContentUnavailableView {
        Label("Choose a Folder", systemImage: "folder")
      } description: {
        Text("Select a folder containing Markdown files.")
      } actions: {
        Button("Choose Folder") {
          isChoosingFolder = true
        }
      }
    } else if let selectedTagName = model.selectedTagName,
              model.filteredFiles.isEmpty {
      let displayName = model.tagSummaries.first {
        $0.normalizedName == selectedTagName
      }?.name ?? selectedTagName
      ContentUnavailableView(
        "No Notes Tagged #\(displayName)",
        systemImage: "tag",
        description: Text("Choose All Notes or another tag to continue.")
      )
    } else {
      ContentUnavailableView(
        "Select a Markdown File",
        systemImage: "doc.text"
      )
    }
  }
}
