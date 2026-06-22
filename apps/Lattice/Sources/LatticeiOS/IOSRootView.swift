import LatticeEditor
import SwiftUI
import UniformTypeIdentifiers

struct IOSRootView: View {
  @StateObject var model: IOSNoteWorkspaceModel
  @State private var isChoosingFolder = false

  var body: some View {
    NavigationStack {
      Group {
        if model.needsNotesFolder {
          folderSetupView
        } else {
          editorView
        }
      }
      .navigationTitle("Lattice")
      .toolbar {
        ToolbarItemGroup(placement: .topBarLeading) {
          if !model.needsNotesFolder {
            Button("New") {
              model.startNewNote()
            }
          }
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
          if !model.needsNotesFolder {
            Button("Save") {
              model.save()
            }
          }
        }
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
          model.selectNotesFolder(url)
        }
      case .failure(let error):
        model.errorMessage = error.localizedDescription
      }
    }
    .alert(
      "Lattice",
      isPresented: Binding(
        get: { model.errorMessage != nil },
        set: { if !$0 { model.errorMessage = nil } }
      )
    ) {
      Button("OK") {
        model.errorMessage = nil
      }
    } message: {
      Text(model.errorMessage ?? "")
    }
  }

  private var folderSetupView: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("Choose a notes folder")
        .font(.title2.weight(.semibold))
      Text("Lattice stores portable Markdown notes in a folder you choose from Files.")
        .font(.callout)
        .foregroundStyle(.secondary)
      Button("Choose Folder") {
        isChoosingFolder = true
      }
      .buttonStyle(.borderedProminent)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .padding(24)
  }

  private var editorView: some View {
    VStack(spacing: 0) {
      IOSMarkdownEditorView(text: $model.text, command: $model.pendingCommand)
        .onChange(of: model.text) { _, _ in
          model.save()
        }

      VStack(spacing: 8) {
        Text(model.footerText)
          .font(.footnote)
          .foregroundStyle(.secondary)
        formatToolbar
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, 8)
      .background(.bar)
    }
  }

  private var formatToolbar: some View {
    HStack(spacing: 18) {
      Button("H") { model.apply(.heading) }
      Button("B") { model.apply(.bold) }
        .fontWeight(.bold)
      Button("I") { model.apply(.italic) }
        .italic()
      Button("List") { model.apply(.bulletList) }
      Button("Code") { model.apply(.code) }
      Button("Link") { model.apply(.link) }
    }
    .font(.caption)
    .buttonStyle(.borderless)
  }
}
