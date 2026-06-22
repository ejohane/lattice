import LatticeCore
import SwiftUI
import UIKit
import UniformTypeIdentifiers

@main
struct LatticeIOSApp: App {
  @State private var model = LatticeAppModel()

  var body: some Scene {
    WindowGroup {
      LatticeRootView(model: model)
        .task {
          model.start()
        }
    }
  }
}

@MainActor
@Observable
final class LatticeAppModel {
  private let bookmarkStore = FolderBookmarkStore()
  private let noteStore = NoteStore()
  private let session: NoteEditingSession
  private var autosaveWorkItem: DispatchWorkItem?
  private var scopedFolderURL: URL?

  var sections: [NoteSection] = []
  var text = ""
  var selectedRange = NSRange(location: 0, length: 0)
  var selectedNote: SavedNote?
  var folderURL: URL?
  var status = "Choose a notes folder"
  var errorMessage: String?
  var isShowingFolderPicker = false
  var preferredCompactColumn: NavigationSplitViewColumn = .sidebar
  var editorFocusToken = 0

  init() {
    session = NoteEditingSession(store: noteStore)
  }

  var hasFolder: Bool {
    folderURL != nil
  }

  func start() {
    guard folderURL == nil else {
      return
    }

    do {
      if let url = try bookmarkStore.restoreFolderURL() {
        try activateFolder(url)
        restoreActiveNote()
      } else {
        isShowingFolderPicker = true
      }
    } catch {
      errorMessage = error.localizedDescription
      isShowingFolderPicker = true
    }
  }

  func chooseFolder(_ url: URL) {
    do {
      try bookmarkStore.save(folderURL: url)
      try activateFolder(url)
      restoreActiveNote()
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func showFolderPicker() {
    isShowingFolderPicker = true
  }

  func createNewNote() {
    flushAutosave()
    session.resetForNewNote()
    selectedNote = nil
    text = ""
    selectedRange = NSRange(location: 0, length: 0)
    status = "New note"
    preferredCompactColumn = .detail
    editorFocusToken += 1
    reloadNotes()
  }

  func open(_ note: SavedNote) {
    flushAutosave()
    do {
      let restored = try session.open(note)
      selectedNote = restored.note
      text = restored.body
      selectedRange = NSRange(location: (restored.body as NSString).length, length: 0)
      status = "Opened \(restored.note.title)"
      preferredCompactColumn = .detail
      reloadNotes(selecting: restored.note)
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func apply(_ command: MarkdownCommand) {
    let result = MarkdownTextEditing.apply(command, to: text, selection: selectedRange)
    text = result.body
    selectedRange = result.selection
    scheduleAutosave()
  }

  func scheduleAutosave() {
    autosaveWorkItem?.cancel()
    let workItem = DispatchWorkItem { [weak self] in
      Task { @MainActor in
        self?.autosave(showStatus: true)
      }
    }
    autosaveWorkItem = workItem
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: workItem)
  }

  func flushAutosave() {
    autosaveWorkItem?.cancel()
    autosaveWorkItem = nil
    autosave(showStatus: false)
  }

  private func activateFolder(_ url: URL) throws {
    scopedFolderURL?.stopAccessingSecurityScopedResource()
    _ = url.startAccessingSecurityScopedResource()
    scopedFolderURL = url
    try noteStore.selectNotesFolder(url)
    folderURL = url
    status = url.lastPathComponent
    reloadNotes()
  }

  private func restoreActiveNote() {
    do {
      if let restored = try session.restoreActiveNote() {
        selectedNote = restored.note
        text = restored.body
        selectedRange = NSRange(location: (restored.body as NSString).length, length: 0)
        status = "Opened \(restored.note.title)"
        preferredCompactColumn = .detail
      }
      reloadNotes(selecting: selectedNote)
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func autosave(showStatus: Bool) {
    autosaveWorkItem?.cancel()
    autosaveWorkItem = nil
    do {
      switch try session.save(body: text) {
      case .skippedEmptyDraft, .unchanged:
        return
      case .saved(let note):
        selectedNote = note
        reloadNotes(selecting: note)
        if showStatus {
          status = "Autosaved \(note.title)"
        }
      }
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func reloadNotes(selecting note: SavedNote? = nil) {
    do {
      sections = try noteStore.listNotes()
      selectedNote = note ?? session.currentNote
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}

struct LatticeRootView: View {
  @Bindable var model: LatticeAppModel

  var body: some View {
    NavigationSplitView(preferredCompactColumn: $model.preferredCompactColumn) {
      sidebar
    } detail: {
      editor
    }
    .sheet(isPresented: $model.isShowingFolderPicker) {
      FolderPicker { url in
        model.chooseFolder(url)
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
  }

  private var sidebar: some View {
    List {
      if model.hasFolder {
        ForEach(model.sections) { section in
          Section(section.dateString) {
            ForEach(section.notes) { note in
              Button {
                model.open(note)
              } label: {
                HStack {
                  Text(note.title)
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
            }
          }
        }
      } else {
        ContentUnavailableView(
          "Choose a Folder",
          systemImage: "folder",
          description: Text("Select a Lattice notes folder to begin.")
        )
      }
    }
    .navigationTitle("Lattice")
    .toolbar {
      ToolbarItem(placement: .topBarLeading) {
        Button {
          model.showFolderPicker()
        } label: {
          Label("Folder", systemImage: "folder")
        }
      }
      ToolbarItem(placement: .topBarTrailing) {
        Button {
          model.createNewNote()
        } label: {
          Label("New Note", systemImage: "square.and.pencil")
        }
        .disabled(!model.hasFolder)
      }
    }
  }

  private var editor: some View {
    VStack(spacing: 0) {
      if model.hasFolder {
        MarkdownTextEditor(
          text: $model.text,
          selectedRange: $model.selectedRange,
          focusToken: model.editorFocusToken,
          onTextChange: {
            model.scheduleAutosave()
          }
        )
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .toolbar {
          ToolbarItemGroup(placement: .keyboard) {
            markdownButton(.heading, title: "Heading", systemImage: "textformat.size")
            markdownButton(.bold, title: "Bold", systemImage: "bold")
            markdownButton(.italic, title: "Italic", systemImage: "italic")
            markdownButton(.bulletList, title: "List", systemImage: "list.bullet")
            markdownButton(.code, title: "Code", systemImage: "chevron.left.forwardslash.chevron.right")
            markdownButton(.link, title: "Link", systemImage: "link")
          }
        }
        statusBar
      } else {
        ContentUnavailableView {
          Label("No Notes Folder", systemImage: "folder.badge.questionmark")
        } description: {
          Text("Choose a folder to store plain Markdown notes.")
        } actions: {
          Button("Choose Folder") {
            model.showFolderPicker()
          }
          .buttonStyle(.borderedProminent)
        }
      }
    }
    .navigationTitle(model.selectedNote?.title ?? "New Note")
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button {
          model.createNewNote()
        } label: {
          Label("New Note", systemImage: "square.and.pencil")
        }
        .disabled(!model.hasFolder)
      }
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

  private var statusText: String {
    let count = model.text.count
    let unit = count == 1 ? "character" : "characters"
    return model.status.isEmpty ? "\(count) \(unit)" : "\(model.status) · \(count) \(unit)"
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

struct FolderPicker: UIViewControllerRepresentable {
  let onSelect: (URL) -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator(onSelect: onSelect)
  }

  func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
    let picker = UIDocumentPickerViewController(
      forOpeningContentTypes: [.folder],
      asCopy: false
    )
    picker.allowsMultipleSelection = false
    picker.delegate = context.coordinator
    return picker
  }

  func updateUIViewController(
    _ uiViewController: UIDocumentPickerViewController,
    context: Context
  ) {}

  final class Coordinator: NSObject, UIDocumentPickerDelegate {
    private let onSelect: (URL) -> Void

    init(onSelect: @escaping (URL) -> Void) {
      self.onSelect = onSelect
    }

    func documentPicker(
      _ controller: UIDocumentPickerViewController,
      didPickDocumentsAt urls: [URL]
    ) {
      guard let url = urls.first else {
        return
      }
      onSelect(url)
    }
  }
}

final class FolderBookmarkStore {
  private enum Key {
    static let folderBookmark = "selectedNotesFolderBookmark"
  }

  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  func save(folderURL: URL) throws {
    let didAccess = folderURL.startAccessingSecurityScopedResource()
    defer {
      if didAccess {
        folderURL.stopAccessingSecurityScopedResource()
      }
    }
    let data = try folderURL.bookmarkData(
      options: bookmarkCreationOptions,
      includingResourceValuesForKeys: nil,
      relativeTo: nil
    )
    defaults.set(data, forKey: Key.folderBookmark)
  }

  func restoreFolderURL() throws -> URL? {
    guard let data = defaults.data(forKey: Key.folderBookmark) else {
      return nil
    }

    var isStale = false
    let url = try URL(
      resolvingBookmarkData: data,
      options: bookmarkResolutionOptions,
      relativeTo: nil,
      bookmarkDataIsStale: &isStale
    )
    if isStale {
      try save(folderURL: url)
    }
    return url
  }

  private var bookmarkCreationOptions: URL.BookmarkCreationOptions {
    #if os(macOS)
    return [.withSecurityScope]
    #else
    return []
    #endif
  }

  private var bookmarkResolutionOptions: URL.BookmarkResolutionOptions {
    #if os(macOS)
    return [.withSecurityScope]
    #else
    return []
    #endif
  }
}

struct MarkdownTextEditor: UIViewRepresentable {
  @Binding var text: String
  @Binding var selectedRange: NSRange
  let focusToken: Int
  let onTextChange: () -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator(parent: self)
  }

  func makeUIView(context: Context) -> UITextView {
    let textView = UITextView()
    textView.delegate = context.coordinator
    textView.backgroundColor = .clear
    textView.isScrollEnabled = true
    textView.alwaysBounceVertical = true
    textView.keyboardDismissMode = .interactive
    textView.textContainerInset = UIEdgeInsets(top: 34, left: 22, bottom: 34, right: 22)
    textView.font = .preferredFont(forTextStyle: .title3)
    textView.adjustsFontForContentSizeCategory = true
    textView.autocorrectionType = .yes
    textView.smartDashesType = .no
    textView.smartQuotesType = .no
    textView.accessibilityIdentifier = "noteEditor"
    return textView
  }

  func updateUIView(_ textView: UITextView, context: Context) {
    context.coordinator.parent = self
    if textView.text != text {
      let selection = selectedRange
      textView.attributedText = MarkdownRenderer.render(text)
      textView.selectedRange = clamped(selection, length: (text as NSString).length)
    }
    if context.coordinator.lastFocusToken != focusToken {
      context.coordinator.lastFocusToken = focusToken
      DispatchQueue.main.async {
        textView.becomeFirstResponder()
      }
    }
  }

  private func clamped(_ range: NSRange, length: Int) -> NSRange {
    let location = max(0, min(range.location, length))
    return NSRange(location: location, length: max(0, min(range.length, length - location)))
  }

  final class Coordinator: NSObject, UITextViewDelegate {
    var parent: MarkdownTextEditor
    var lastFocusToken = 0

    init(parent: MarkdownTextEditor) {
      self.parent = parent
    }

    func textViewDidChange(_ textView: UITextView) {
      parent.text = textView.text
      parent.selectedRange = textView.selectedRange
      parent.onTextChange()
      let selection = textView.selectedRange
      textView.attributedText = MarkdownRenderer.render(textView.text)
      textView.selectedRange = selection
    }

    func textViewDidChangeSelection(_ textView: UITextView) {
      parent.selectedRange = textView.selectedRange
    }
  }
}

enum MarkdownRenderer {
  static func render(_ text: String) -> NSAttributedString {
    let bodyFont = UIFont.preferredFont(forTextStyle: .title3)
    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.lineSpacing = 5
    paragraphStyle.paragraphSpacing = 12

    let attributed = NSMutableAttributedString(
      string: text,
      attributes: [
        .font: bodyFont,
        .foregroundColor: UIColor.label,
        .paragraphStyle: paragraphStyle
      ]
    )
    let fullRange = NSRange(location: 0, length: (text as NSString).length)
    guard fullRange.length > 0 else {
      return attributed
    }

    applyBlockStyles(to: attributed)
    applyInlineStyles(to: attributed, fullRange: fullRange)
    return attributed
  }

  private static func applyBlockStyles(to attributed: NSMutableAttributedString) {
    let nsString = attributed.string as NSString
    var location = 0
    while location < nsString.length {
      let lineRange = nsString.lineRange(for: NSRange(location: location, length: 0))
      let line = nsString.substring(with: lineRange)
      if let match = firstMatch("^\\s*(#{1,6})\\s+(.+)$", in: line) {
        let level = min(match.range(at: 1).length, 6)
        let sizes: [CGFloat] = [34, 30, 26, 23, 21, 20]
        let contentRange = shifted(match.range(at: 2), by: lineRange.location)
        attributed.addAttributes([
          .font: UIFont.systemFont(ofSize: sizes[level - 1], weight: .bold)
        ], range: contentRange)
        attributed.addAttributes([
          .foregroundColor: UIColor.tertiaryLabel,
          .font: UIFont.monospacedSystemFont(ofSize: 16, weight: .regular)
        ], range: shifted(match.range(at: 1), by: lineRange.location))
      } else if let match = firstMatch("^\\s*([-*+])\\s+(.+)$", in: line) {
        attributed.addAttributes([
          .foregroundColor: UIColor.tintColor,
          .font: UIFont.systemFont(ofSize: 21, weight: .semibold)
        ], range: shifted(match.range(at: 1), by: lineRange.location))
      }
      location = NSMaxRange(lineRange)
    }
  }

  private static func applyInlineStyles(
    to attributed: NSMutableAttributedString,
    fullRange: NSRange
  ) {
    apply(pattern: "`([^`\\n]+)`", to: attributed, fullRange: fullRange) { match in
      [
        (match.range(at: 0), [
          .foregroundColor: UIColor.systemPink,
          .font: UIFont.monospacedSystemFont(ofSize: 18, weight: .regular),
          .backgroundColor: UIColor.secondarySystemBackground
        ])
      ]
    }
    apply(pattern: "(\\*\\*|__)(.+?)\\1", to: attributed, fullRange: fullRange) { match in
      [(match.range(at: 2), [.font: UIFont.systemFont(ofSize: 21, weight: .semibold)])]
    }
    apply(pattern: "(?<!\\*)\\*(?!\\*)([^*\\n]+)(?<!\\*)\\*(?!\\*)", to: attributed, fullRange: fullRange) { match in
      [(match.range(at: 1), [.font: italicBodyFont()])]
    }
    apply(pattern: "\\[([^\\]\\n]+)\\]\\(([^)\\n]+)\\)", to: attributed, fullRange: fullRange) { match in
      [(match.range(at: 1), [
        .foregroundColor: UIColor.systemBlue,
        .underlineStyle: NSUnderlineStyle.single.rawValue
      ])]
    }
  }

  private static func apply(
    pattern: String,
    to attributed: NSMutableAttributedString,
    fullRange: NSRange,
    attributes: (NSTextCheckingResult) -> [(NSRange, [NSAttributedString.Key: Any])]
  ) {
    guard let regex = try? NSRegularExpression(pattern: pattern) else {
      return
    }
    for match in regex.matches(in: attributed.string, range: fullRange) {
      for (range, attrs) in attributes(match) where range.location != NSNotFound {
        attributed.addAttributes(attrs, range: range)
      }
    }
  }

  private static func firstMatch(_ pattern: String, in string: String) -> NSTextCheckingResult? {
    guard let regex = try? NSRegularExpression(pattern: pattern) else {
      return nil
    }
    return regex.firstMatch(
      in: string,
      range: NSRange(location: 0, length: (string as NSString).length)
    )
  }

  private static func shifted(_ range: NSRange, by offset: Int) -> NSRange {
    NSRange(location: range.location + offset, length: range.length)
  }

  private static func italicBodyFont() -> UIFont {
    let descriptor = UIFont.systemFont(ofSize: 21).fontDescriptor.withSymbolicTraits(.traitItalic)
      ?? UIFont.systemFont(ofSize: 21).fontDescriptor
    return UIFont(descriptor: descriptor, size: 21)
  }
}
