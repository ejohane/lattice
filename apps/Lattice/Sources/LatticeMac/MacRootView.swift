import LatticeEditor
import SwiftUI

struct MacRootView: View {
  @ObservedObject var model: MacNoteWorkspaceModel

  var body: some View {
    Group {
      if model.needsNotesFolder {
        MacNotesFolderSetupView(model: model)
      } else {
        MacEditorView(model: model)
      }
    }
    .onAppear {
      model.settings.applyAppearance()
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
}

private struct MacNotesFolderSetupView: View {
  @ObservedObject var model: MacNoteWorkspaceModel

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("Choose a notes folder")
        .font(.title2.weight(.semibold))
      Text("Lattice stores portable Markdown notes in a local folder. Choose an existing folder or initialize the default location.")
        .font(.callout)
        .foregroundStyle(.secondary)
      Text(model.defaultNotesFolderURL.path)
        .font(.system(.caption, design: .monospaced))
        .foregroundStyle(.tertiary)
        .lineLimit(1)
        .truncationMode(.middle)

      HStack(spacing: 10) {
        Button("Use ~/Documents/Lattice") {
          model.useDefaultNotesFolder()
        }
        .keyboardShortcut(.defaultAction)

        Button("Choose Folder...") {
          model.chooseNotesFolder()
        }
      }
      .padding(.top, 4)
    }
    .padding(30)
  }
}

private struct MacEditorView: View {
  @ObservedObject var model: MacNoteWorkspaceModel

  var body: some View {
    ZStack(alignment: .bottom) {
      MacMarkdownEditorView(text: $model.text)
        .onChange(of: model.text) { _, _ in
          model.scheduleAutosave()
        }

      Text(model.footerText)
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(.tertiary)
        .padding(.bottom, 18)
    }
    .toolbar {
      ToolbarItemGroup {
        Button {
          model.startNewNote()
        } label: {
          Image(systemName: "square.and.pencil")
        }
        .help("Start a new note")

        Divider()

        EditorToolbarButton(command: .heading, systemImage: "textformat.size", help: "Insert Markdown heading")
        EditorToolbarButton(command: .bold, systemImage: "bold", help: "Wrap selection in bold Markdown")
        EditorToolbarButton(command: .italic, systemImage: "italic", help: "Wrap selection in italic Markdown")
        EditorToolbarButton(command: .bulletList, systemImage: "list.bullet", help: "Start a Markdown bulleted list")
        EditorToolbarButton(command: .code, systemImage: "chevron.left.forwardslash.chevron.right", help: "Wrap selection in inline code Markdown")
        EditorToolbarButton(command: .link, systemImage: "link", help: "Insert a Markdown link")
      }
    }
  }
}

private struct EditorToolbarButton: View {
  let command: MarkdownCommand
  let systemImage: String
  let help: String

  var body: some View {
    Button {
      MacMarkdownTextView.send(command)
    } label: {
      Image(systemName: systemImage)
    }
    .help(help)
  }
}

struct MacSettingsView: View {
  @ObservedObject var settings: MacAppSettings

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Appearance")
        .font(.title3.weight(.semibold))
      Text("Choose whether Lattice follows macOS or always uses a fixed appearance.")
        .font(.callout)
        .foregroundStyle(.secondary)
      Picker("Appearance", selection: Binding(
        get: { settings.appearanceMode },
        set: { settings.appearanceMode = $0 }
      )) {
        ForEach(MacAppearanceMode.allCases) { mode in
          Text(mode.title).tag(mode)
        }
      }
      .pickerStyle(.segmented)
      .labelsHidden()
      .frame(width: 260)
    }
    .padding(24)
  }
}
