import Foundation
import LatticeCore
import LatticeEditor
import SwiftUI
import UniformTypeIdentifiers

#if os(iOS)
import PhotosUI
import UIKit
#endif

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
    rootContent
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

  @ViewBuilder
  private var rootContent: some View {
    if model.isZenModeEnabled && model.hasFolder {
      ZenNoteEditorPane(model: model)
    } else {
      splitRoot
    }
  }

  private var splitRoot: some View {
    NavigationSplitView(preferredCompactColumn: preferredColumnBinding) {
      NoteSidebar(model: model)
    } detail: {
      editorPane
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

#if os(iOS)
private struct ThemedWindowBackground: UIViewRepresentable {
  let color: UIColor

  func makeUIView(context: Context) -> UIView {
    let view = UIView(frame: .zero)
    view.isUserInteractionEnabled = false
    view.backgroundColor = color
    return view
  }

  func updateUIView(_ view: UIView, context: Context) {
    view.backgroundColor = color
    DispatchQueue.main.async {
      view.window?.backgroundColor = color
      var ancestor: UIView? = view
      while let current = ancestor {
        if current.backgroundColor == nil || current.backgroundColor == .clear {
          current.backgroundColor = color
        }
        ancestor = current.superview
      }
    }
  }
}

private struct LeftEdgeBackSwipeView: UIViewRepresentable {
  let action: @MainActor () -> Void

  func makeUIView(context: Context) -> UIView {
    let view = UIView(frame: .zero)
    view.backgroundColor = .clear
    view.isOpaque = false

    let recognizer = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
    recognizer.delegate = context.coordinator
    recognizer.cancelsTouchesInView = false
    view.addGestureRecognizer(recognizer)
    return view
  }

  func updateUIView(_ view: UIView, context: Context) {
    context.coordinator.action = action
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(action: action)
  }

  final class Coordinator: NSObject, UIGestureRecognizerDelegate {
    var action: @MainActor () -> Void

    init(action: @escaping @MainActor () -> Void) {
      self.action = action
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
      guard let pan = gestureRecognizer as? UIPanGestureRecognizer,
            let view = pan.view
      else {
        return false
      }

      let translation = pan.translation(in: view)
      let velocity = pan.velocity(in: view)
      return velocity.x > 0 && abs(velocity.x) > abs(velocity.y) && translation.x >= 0
    }

    @objc func handlePan(_ recognizer: UIPanGestureRecognizer) {
      guard recognizer.state == .ended,
            let view = recognizer.view
      else {
        return
      }

      let translation = recognizer.translation(in: view)
      let velocity = recognizer.velocity(in: view)
      if translation.x > 44 || velocity.x > 450 {
        Task { @MainActor in
          action()
        }
      }
    }
  }
}
#endif

private struct NoteEditorPane: View {
  @Bindable var model: LatticeAppModel
  @Environment(\.latticeTheme) private var theme
  @State private var wikiAutocompleteAnchor: CGRect?
  private let maximumEditorWidth: CGFloat = 920
  private let editorHorizontalPadding: CGFloat = 12
  #if os(iOS)
  @State private var isShowingPhotoPicker = false
  @State private var selectedPhotoItem: PhotosPickerItem?
  #endif

  @ViewBuilder
  var body: some View {
    let content = editorContent
      .frame(maxWidth: maximumEditorWidth, maxHeight: .infinity)
      .padding(.horizontal, editorHorizontalPadding)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(theme.color(.appBackground))

    #if os(iOS)
    content
      .toolbar(.hidden, for: .navigationBar)
      .background(ThemedWindowBackground(color: theme.uiColor(.editorBackground)))
      .overlay(alignment: .leading) {
        LeftEdgeBackSwipeView {
          model.preferredCompactColumn = .sidebar
        }
        .frame(width: 32)
        .ignoresSafeArea(.container, edges: .vertical)
      }
      .photosPicker(
        isPresented: $isShowingPhotoPicker,
        selection: $selectedPhotoItem,
        matching: .images
      )
      .onChange(of: selectedPhotoItem) { _, item in
        importSelectedPhoto(item)
      }
    #else
    content
      .navigationSplitViewColumnWidth(min: 260, ideal: 720)
    #endif
  }

  private var editorContent: some View {
    VStack(spacing: 0) {
      ZStack(alignment: .topLeading) {
        MarkdownTextEditor(
          text: $model.text,
          selectedRange: $model.selectedRange,
          vimState: $model.vimState,
          fontSize: CGFloat(model.editorFontSize),
          fontFamily: model.editorFontFamily,
          focusToken: model.editorFocusToken,
          isVimModeEnabled: model.effectiveIsVimModeEnabled,
          showsRelativeLineNumbers: model.showsRelativeLineNumbers,
          autocompleteAnchor: $wikiAutocompleteAnchor,
          keyboardAccessoryActions: keyboardAccessoryActions,
          hasAutocompleteSuggestions: !model.wikiAutocompleteSuggestions.isEmpty,
          wikiLinkStates: model.wikiLinkStates,
          theme: theme,
          imagePreviewStates: model.imagePreviewStates,
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
          onMoveAutocompleteSelection: { delta in
            model.moveWikiAutocompleteSelection(by: delta)
          },
          onCommitAutocomplete: {
            model.commitSelectedWikiAutocompleteSuggestion()
          },
          onVimWrite: {
            model.vimWrite()
          },
          onVimStatusChange: { message in
            model.setVimStatusMessage(message)
          },
          onImageAttachmentsImported: { imports in
            model.insertImageAttachments(imports)
          },
          onImageAttachmentResized: { lineLocation, width in
            model.resizeImageAttachment(lineLocation: lineLocation, width: width)
          }
        )
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.color(.editorBackground))

        wikiAutocompleteOverlay
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      if model.showsStatusBar {
        statusBar
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  #if os(iOS)
  private var keyboardAccessoryActions: [MarkdownKeyboardAccessoryAction] {
    [
      MarkdownKeyboardAccessoryAction(
        id: "search",
        title: "Search",
        systemImage: "magnifyingglass"
      ) {
        model.showCommandPalette()
      },
      MarkdownKeyboardAccessoryAction(
        id: "commands",
        title: "Commands",
        systemImage: "command",
        menuChildren: [
          zenKeyboardAction(),
          markdownKeyboardAction(.heading, title: "Heading", systemImage: nil, displayTitle: "Aa"),
          markdownKeyboardAction(.bold, title: "Bold", systemImage: "bold"),
          markdownKeyboardAction(.italic, title: "Italic", systemImage: "italic"),
          markdownKeyboardAction(.bulletList, title: "List", systemImage: "list.bullet"),
          markdownKeyboardAction(.taskList, title: "Checklist", systemImage: "checklist"),
          MarkdownKeyboardAccessoryAction(
            id: "indent",
            title: "Indent",
            systemImage: "increase.indent",
            isEnabled: model.hasFolder
          ) {
            model.indentSelectedListItems()
          },
          MarkdownKeyboardAccessoryAction(
            id: "outdent",
            title: "Outdent",
            systemImage: "decrease.indent",
            isEnabled: model.hasFolder
          ) {
            model.outdentSelectedListItems()
          },
          markdownKeyboardAction(.code, title: "Code", systemImage: "chevron.left.forwardslash.chevron.right"),
          markdownKeyboardAction(.link, title: "Link", systemImage: "link"),
          markdownKeyboardAction(.horizontalRule, title: "Divider", systemImage: "minus"),
          MarkdownKeyboardAccessoryAction(
            id: "attach-photo",
            title: "Add Attachment",
            systemImage: "plus",
            isEnabled: model.hasFolder
          ) {
            isShowingPhotoPicker = true
          },
          MarkdownKeyboardAccessoryAction(
            id: "settings",
            title: "Settings",
            systemImage: "gearshape"
          ) {
            model.showSettings()
          }
        ],
        symbolPointSize: 17
      )
    ]
  }

  private func zenKeyboardAction() -> MarkdownKeyboardAccessoryAction {
    MarkdownKeyboardAccessoryAction(
      id: "zenMode",
      title: model.isZenModeEnabled ? "Exit Zen Mode" : "Enter Zen Mode",
      systemImage: model.isZenModeEnabled
        ? "arrow.down.right.and.arrow.up.left"
        : "arrow.up.left.and.arrow.down.right",
      isEnabled: model.hasFolder
    ) {
      model.toggleZenMode()
    }
  }

  private func markdownKeyboardAction(
    _ command: MarkdownCommand,
    title: String,
    systemImage: String?,
    displayTitle: String? = nil
  ) -> MarkdownKeyboardAccessoryAction {
    MarkdownKeyboardAccessoryAction(
      id: "markdown.\(command)",
      title: title,
      systemImage: systemImage,
      displayTitle: displayTitle,
      isEnabled: model.hasFolder
    ) {
      model.apply(command)
    }
  }

  private func importSelectedPhoto(_ item: PhotosPickerItem?) {
    guard let item else {
      return
    }

    Task { @MainActor in
      defer {
        selectedPhotoItem = nil
      }

      do {
        guard let data = try await item.loadTransferable(type: Data.self) else {
          return
        }
        let fileExtension = Self.imageFileExtension(for: item)
        model.insertImageAttachments([
          ImageAttachmentImport(
            data: data,
            suggestedFilename: "attachment.\(fileExtension)",
            preferredExtension: fileExtension
          )
        ])
      } catch {
        model.errorMessage = error.localizedDescription
      }
    }
  }

  private static func imageFileExtension(for item: PhotosPickerItem) -> String {
    let imageType = item.supportedContentTypes.first { $0.conforms(to: .image) }
    return imageType?.preferredFilenameExtension?.lowercased() ?? "png"
  }
  #else
  private var keyboardAccessoryActions: [MarkdownKeyboardAccessoryAction] {
    []
  }
  #endif

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
  private var wikiAutocompleteOverlay: some View {
    if let wikiAutocompleteAnchor, !model.wikiAutocompleteSuggestions.isEmpty {
      GeometryReader { proxy in
        let visibleRange = wikiAutocompleteVisibleRange(
          suggestionCount: model.wikiAutocompleteSuggestions.count,
          selectedIndex: model.wikiAutocompleteSelectionIndex,
          maxVisibleCount: 5
        )
        let suggestions = Array(model.wikiAutocompleteSuggestions[visibleRange])
        let selectedIndex = max(0, model.wikiAutocompleteSelectionIndex - visibleRange.lowerBound)
        let width = min(640, max(0, proxy.size.width - 24))
        let rowHeight: CGFloat = 48
        let panelHeight = CGFloat(suggestions.count) * rowHeight + 12
        let x = min(max(12, wikiAutocompleteAnchor.minX), max(12, proxy.size.width - width - 12))
        let preferredY = wikiAutocompleteAnchor.maxY + 8
        let y = preferredY + panelHeight <= proxy.size.height - 12
          ? preferredY
          : max(12, wikiAutocompleteAnchor.minY - panelHeight - 8)

        WikiAutocompletePanel(
          suggestions: suggestions,
          selectedIndex: selectedIndex,
          theme: theme
        ) { suggestion in
          model.selectWikiAutocompleteSuggestion(suggestion)
        }
        .frame(width: width, height: panelHeight, alignment: .top)
        .position(x: x + width / 2, y: y + panelHeight / 2)
        .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .topLeading)))
      }
      .allowsHitTesting(true)
    }
  }

  private func wikiAutocompleteVisibleRange(
    suggestionCount: Int,
    selectedIndex: Int,
    maxVisibleCount: Int
  ) -> Range<Int> {
    guard suggestionCount > 0, maxVisibleCount > 0 else {
      return 0..<0
    }

    let visibleCount = min(suggestionCount, maxVisibleCount)
    let clampedSelection = min(max(selectedIndex, 0), suggestionCount - 1)
    let maximumStart = suggestionCount - visibleCount
    let start = min(max(0, clampedSelection - visibleCount + 1), maximumStart)
    return start..<(start + visibleCount)
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
    guard model.effectiveIsVimModeEnabled else {
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

}

private struct WikiAutocompletePanel: View {
  let suggestions: [WikiAutocompleteSuggestion]
  let selectedIndex: Int
  let theme: LatticeTheme
  let onSelect: (WikiAutocompleteSuggestion) -> Void

  var body: some View {
    VStack(spacing: 0) {
      ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, suggestion in
        let isSelected = index == selectedIndex
        Button {
          onSelect(suggestion)
        } label: {
          HStack(spacing: 12) {
            Image(systemName: "doc.text")
              .font(.system(size: 22, weight: .regular))
              .symbolRenderingMode(.hierarchical)
              .foregroundStyle(isSelected ? theme.color(.accent) : theme.color(.secondaryText))
              .frame(width: 28)

            Text(suggestion.title)
              .font(.title3.weight(isSelected ? .semibold : .regular))
              .foregroundStyle(theme.color(.primaryText))
              .lineLimit(1)
              .truncationMode(.tail)

            Spacer(minLength: 0)
          }
          .frame(height: 48)
          .padding(.horizontal, 14)
          .background {
            if isSelected {
              RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(theme.color(.secondaryText).opacity(0.18))
            }
          }
          .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(suggestion.subtitle.isEmpty ? suggestion.title : "\(suggestion.title), \(suggestion.subtitle)")
      }
    }
    .padding(6)
    .background {
      RoundedRectangle(cornerRadius: 22, style: .continuous)
        .fill(theme.color(.barBackground).opacity(0.96))
        .shadow(color: .black.opacity(0.24), radius: 18, x: 0, y: 10)
    }
    .overlay {
      RoundedRectangle(cornerRadius: 22, style: .continuous)
        .stroke(theme.color(.separator).opacity(0.68), lineWidth: 1)
    }
  }
}

private struct ZenNoteEditorPane: View {
  @Bindable var model: LatticeAppModel
  @Environment(\.latticeTheme) private var theme
  private let maximumEditorWidth: CGFloat = 980

  var body: some View {
    editorContent
      .frame(maxWidth: maximumEditorWidth, maxHeight: .infinity)
      .padding(.horizontal, 12)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(theme.color(.appBackground))
  }

  private var editorContent: some View {
    MarkdownTextEditor(
      text: $model.text,
      selectedRange: $model.selectedRange,
      vimState: $model.vimState,
      fontSize: CGFloat(model.editorFontSize),
      fontFamily: model.editorFontFamily,
      focusToken: model.editorFocusToken,
      isVimModeEnabled: model.effectiveIsVimModeEnabled,
      showsRelativeLineNumbers: false,
      dimsInactiveParagraphs: true,
      caretAnchorFraction: 1.0 / 3.0,
      keyboardAccessoryActions: zenKeyboardAccessoryActions,
      hasAutocompleteSuggestions: false,
      wikiLinkStates: model.wikiLinkStates,
      theme: theme,
      imagePreviewStates: model.imagePreviewStates,
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
      },
      onImageAttachmentsImported: { imports in
        model.insertImageAttachments(imports)
      },
      onImageAttachmentResized: { lineLocation, width in
        model.resizeImageAttachment(lineLocation: lineLocation, width: width)
      }
    )
    .ignoresSafeArea(.keyboard, edges: .bottom)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(theme.color(.editorBackground))
  }

  #if os(iOS)
  private var zenKeyboardAccessoryActions: [MarkdownKeyboardAccessoryAction] {
    [
      MarkdownKeyboardAccessoryAction(
        id: "search",
        title: "Search",
        systemImage: "magnifyingglass"
      ) {
        model.showCommandPalette()
      },
      MarkdownKeyboardAccessoryAction(
        id: "commands",
        title: "Commands",
        systemImage: "command",
        menuChildren: [
          MarkdownKeyboardAccessoryAction(
            id: "zenMode",
            title: "Exit Zen Mode",
            systemImage: "arrow.down.right.and.arrow.up.left",
            isEnabled: model.hasFolder
          ) {
            model.toggleZenMode()
          }
        ],
        symbolPointSize: 17
      )
    ]
  }
  #else
  private var zenKeyboardAccessoryActions: [MarkdownKeyboardAccessoryAction] {
    []
  }
  #endif
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
