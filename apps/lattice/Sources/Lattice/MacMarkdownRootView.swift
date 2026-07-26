import LatticeMacCore
import SwiftUI
import UniformTypeIdentifiers

struct MacMarkdownRootView: View {
  @State private var model = MacMarkdownAppModel()
  @State private var isChoosingFolder = false
  @FocusState private var isEditorFocused: Bool

  var body: some View {
    @Bindable var model = model

    NavigationSplitView {
      sidebar(model: model)
        .navigationSplitViewColumnWidth(min: 220, ideal: 280, max: 360)
    } detail: {
      editor(model: model)
    }
    .toolbar {
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
    .onChange(of: model.editorFocusRequest) {
      Task { @MainActor in
        try? await Task.sleep(for: .milliseconds(50))
        isEditorFocused = true
      }
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
        Text(file.relativePath)
          .lineLimit(1)
          .help(file.relativePath)
          .tag(file.id)
          .listRowInsets(EdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 12))
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

        TextEditor(text: Binding(
          get: { model.text },
          set: { model.updateText($0) }
        ))
        .font(.system(.body, design: .monospaced))
        .textEditorStyle(.plain)
        .scrollContentBackground(.hidden)
        .focused($isEditorFocused)
        .onAppear {
          guard model.editorFocusRequest > 0 else { return }
          Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            isEditorFocused = true
          }
        }
        .frame(
          maxWidth: MacMarkdownSpacing.editorMaximumWidth,
          maxHeight: .infinity
        )
        .padding(.horizontal, horizontalPadding)
        .padding(.top, topPadding)
        .padding(.bottom, MacMarkdownSpacing.editorBottomPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .disabled(model.isLoadingFile || model.isCreatingNote)
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
