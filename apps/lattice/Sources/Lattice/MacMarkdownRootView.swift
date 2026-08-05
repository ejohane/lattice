import LatticeMacCore
import SwiftUI
import UniformTypeIdentifiers

struct MacMarkdownRootView: View {
  let model: MacMarkdownAppModel
  @Environment(MacKeyboardShortcutSettings.self) private var shortcutSettings
  @State private var isChoosingFolder = false
  @State private var isShowingCommandPalette = false

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

      ToolbarItem(placement: .primaryAction) {
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
      ForEach(model.files) { file in
        MacMarkdownSidebarRow(preview: model.sidebarPreview(for: file))
          .help(file.relativePath)
          .tag(file.id)
          .listRowInsets(EdgeInsets(top: 2, leading: 12, bottom: 2, trailing: 10))
      }
    }
    .listStyle(.sidebar)
    .overlay {
      if model.isLoadingFiles {
        ProgressView()
      } else if model.folderURL != nil && model.files.isEmpty {
        ContentUnavailableView(
          "No Markdown Files",
          systemImage: "doc.text",
          description: Text("This folder does not contain any .md files.")
        )
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
    } else {
      ContentUnavailableView(
        "Select a Markdown File",
        systemImage: "doc.text"
      )
    }
  }
}
