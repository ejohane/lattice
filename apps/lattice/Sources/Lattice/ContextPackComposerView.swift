import AppKit
import LatticeShared
import SwiftUI
import UniformTypeIdentifiers

struct ContextPackComposerView: View {
  @Bindable private var model: LatticeAppModel
  @FocusState private var isTaskFocused: Bool
  @State private var actionMessage: String?
  @State private var actionError: String?

  init(model: LatticeAppModel) {
    self.model = model
  }

  var body: some View {
    VStack(spacing: 0) {
      HSplitView {
        composerPane
          .frame(minWidth: 360, idealWidth: 400, maxWidth: 480)
        previewPane
          .frame(minWidth: 440, maxWidth: .infinity)
      }
      Divider()
      footer
    }
    .frame(minWidth: 900, idealWidth: 980, minHeight: 650, idealHeight: 720)
    .task {
      isTaskFocused = true
    }
    .onChange(of: model.contextPackTask) {
      actionMessage = nil
    }
    .onExitCommand {
      model.dismissContextPack()
    }
    .alert("Context Pack", isPresented: Binding(
      get: { actionError != nil },
      set: { if !$0 { actionError = nil } }
    )) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(actionError ?? "")
    }
  }

  private var composerPane: some View {
    VStack(alignment: .leading, spacing: 0) {
      VStack(alignment: .leading, spacing: 8) {
        Text("Context Pack")
          .font(.title2.weight(.semibold))
        Text("Assemble portable Markdown for any AI chat.")
          .foregroundStyle(.secondary)

        Text("Task")
          .font(.headline)
          .padding(.top, 8)
        TextEditor(text: $model.contextPackTask)
          .font(.body)
          .frame(height: 92)
          .padding(6)
          .background(.background, in: RoundedRectangle(cornerRadius: 6))
          .overlay {
            RoundedRectangle(cornerRadius: 6)
              .stroke(.separator)
          }
          .focused($isTaskFocused)
          .accessibilityLabel("Task")

        Text("Add notes")
          .font(.headline)
          .padding(.top, 8)
        TextField("Search notes", text: $model.contextPackSearchQuery)
          .textFieldStyle(.roundedBorder)
      }
      .padding(16)

      availableNotes
        .frame(height: 150)

      Divider()

      HStack {
        Text("Included context")
          .font(.headline)
        Spacer()
        Text(model.contextPackSources.count.formatted())
          .foregroundStyle(.secondary)
      }
      .padding(.horizontal, 16)
      .padding(.top, 14)
      .padding(.bottom, 8)

      includedSources
    }
  }

  private var availableNotes: some View {
    let notes = model.contextPackSearchNotes()
      .filter { !model.contextPackContains($0) }

    return Group {
      if notes.isEmpty {
        ContentUnavailableView(
          model.contextPackSearchQuery.isEmpty ? "No Other Notes" : "No Matching Notes",
          systemImage: "doc.text.magnifyingglass"
        )
      } else {
        ScrollView {
          LazyVStack(spacing: 0) {
            ForEach(notes) { note in
              Button {
                model.addNoteToContextPack(note)
                actionMessage = nil
              } label: {
                HStack(spacing: 10) {
                  Image(systemName: "doc.text")
                    .foregroundStyle(.secondary)
                  VStack(alignment: .leading, spacing: 2) {
                    Text(model.displayTitle(for: note))
                      .lineLimit(1)
                    Text(note.dateString)
                      .font(.caption)
                      .foregroundStyle(.secondary)
                  }
                  Spacer()
                  Image(systemName: "plus")
                    .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
              }
              .buttonStyle(.plain)
              .accessibilityLabel("Add \(model.displayTitle(for: note))")
              .help("Add \(model.displayTitle(for: note))")

              Divider()
                .padding(.leading, 42)
            }
          }
        }
      }
    }
  }

  private var includedSources: some View {
    Group {
      if model.contextPackSources.isEmpty {
        ContentUnavailableView(
          "No Context Included",
          systemImage: "doc.on.doc",
          description: Text("Add at least one note before exporting.")
        )
      } else {
        ScrollView {
          LazyVStack(spacing: 0) {
            ForEach(Array(model.contextPackSources.enumerated()), id: \.element.id) { index, source in
              HStack(spacing: 10) {
                Image(systemName: source.isExcerpt ? "selection.pin.in.out" : "doc.text")
                  .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                  Text(source.title)
                    .lineLimit(1)
                  Text(source.isExcerpt ? "Selected text" : "Whole note")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                  model.moveContextPackSource(id: source.id, by: -1)
                  actionMessage = nil
                } label: {
                  Image(systemName: "chevron.up")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Move \(source.title) up")
                .disabled(index == 0)
                .help("Move up")

                Button {
                  model.moveContextPackSource(id: source.id, by: 1)
                  actionMessage = nil
                } label: {
                  Image(systemName: "chevron.down")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Move \(source.title) down")
                .disabled(index == model.contextPackSources.count - 1)
                .help("Move down")

                Button {
                  model.removeContextPackSource(id: source.id)
                  actionMessage = nil
                } label: {
                  Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Remove \(source.title)")
                .help("Remove")
              }
              .padding(.horizontal, 16)
              .padding(.vertical, 9)

              Divider()
                .padding(.leading, 42)
            }
          }
        }
      }
    }
  }

  private var previewPane: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack {
        Text("Preview")
          .font(.headline)
        Spacer()
        Text("Markdown")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      .padding(.horizontal, 18)
      .padding(.vertical, 14)

      Divider()

      ScrollView {
        Text(verbatim: model.contextPackMarkdown)
          .font(.system(.body, design: .monospaced))
          .textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .topLeading)
          .padding(18)
      }
      .background(Color(nsColor: .textBackgroundColor))
    }
  }

  private var footer: some View {
    HStack(spacing: 12) {
      Text("\(model.contextPackCharacterCount.formatted()) characters · ~\(model.contextPackApproximateTokenCount.formatted()) tokens")
        .foregroundStyle(.secondary)

      if let actionMessage {
        Label(actionMessage, systemImage: "checkmark.circle.fill")
          .foregroundStyle(.green)
      }

      Spacer()

      Button("Cancel") {
        model.dismissContextPack()
      }

      Button("Save Markdown…") {
        saveMarkdown()
      }
      .disabled(!model.isContextPackReady)

      Button("Copy Context Pack") {
        copyContextPack()
      }
      .buttonStyle(.borderedProminent)
      .disabled(!model.isContextPackReady)
    }
    .padding(14)
  }

  private func copyContextPack() {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    guard pasteboard.setString(model.contextPackMarkdown, forType: .string) else {
      actionError = "Lattice could not copy the Context Pack to the clipboard."
      return
    }
    actionMessage = "Copied to clipboard"
  }

  private func saveMarkdown() {
    let panel = NSSavePanel()
    panel.title = "Save Context Pack"
    panel.prompt = "Save"
    panel.nameFieldStringValue = "Context Pack.md"
    panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
    panel.canCreateDirectories = true
    panel.isExtensionHidden = false

    guard panel.runModal() == .OK, let url = panel.url else {
      return
    }

    do {
      try model.contextPackMarkdown.write(to: url, atomically: true, encoding: .utf8)
      actionMessage = "Saved \(url.lastPathComponent)"
    } catch {
      actionError = error.localizedDescription
    }
  }
}
