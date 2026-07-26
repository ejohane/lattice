import Foundation
import LatticeMacCore
import Observation

@MainActor
@Observable
final class MacMarkdownAppModel {
  private let bookmarkStore: MarkdownFolderBookmarkStore
  private var folder: MarkdownFolder?
  private var selectedFile: MarkdownFile?
  private var selectedDocument: MarkdownDocument?
  private var hasLoadedSelectedFile = false
  private var hasStarted = false
  private var isAccessingSecurityScopedFolder = false
  private var loadGeneration = 0
  private var pendingNoteCreations = 0
  private var automaticallyNamedFileIDs: Set<MarkdownFile.ID> = []
  private var namingFileIDs: Set<MarkdownFile.ID> = []

  @ObservationIgnored private var fileLoadTask: Task<Void, Never>?
  @ObservationIgnored private var saveTask: Task<Void, Never>?

  private(set) var folderURL: URL?
  private(set) var files: [MarkdownFile] = []
  private(set) var selectedFileID: MarkdownFile.ID?
  private(set) var text = ""
  private(set) var isLoadingFiles = false
  private(set) var isLoadingFile = false
  private(set) var isCreatingNote = false
  private(set) var editorFocusRequest = 0
  private(set) var editorContentRevision = 0
  var errorMessage: String?

  var canCreateNote: Bool {
    folder != nil && !isLoadingFiles
  }

  init(bookmarkStore: MarkdownFolderBookmarkStore = MarkdownFolderBookmarkStore()) {
    self.bookmarkStore = bookmarkStore
  }

  init(folderURL: URL, bookmarkStore: MarkdownFolderBookmarkStore = MarkdownFolderBookmarkStore()) {
    self.bookmarkStore = bookmarkStore
    hasStarted = true
    activateFolder(folderURL)
  }

  func start() {
    guard !hasStarted else { return }
    hasStarted = true

    do {
      if let restoredURL = try bookmarkStore.restoreFolderURL() {
        activateFolder(restoredURL)
      }
    } catch {
      bookmarkStore.clear()
      present(error)
    }
  }

  func chooseFolder(_ url: URL) {
    do {
      try bookmarkStore.save(folderURL: url)
      isLoadingFiles = true
      Task {
        await saveAndFinalizeSelectedNote()
        activateFolder(url)
      }
    } catch {
      present(error)
    }
  }

  func createNote() {
    guard canCreateNote else { return }
    pendingNoteCreations += 1
    startNextNoteCreationIfNeeded()
  }

  private func startNextNoteCreationIfNeeded() {
    guard !isCreatingNote,
          pendingNoteCreations > 0,
          let activeFolder = folder
    else { return }

    pendingNoteCreations -= 1
    saveTask?.cancel()
    fileLoadTask?.cancel()
    loadGeneration += 1
    let generation = loadGeneration
    isCreatingNote = true

    fileLoadTask = Task {
      defer {
        if generation == loadGeneration {
          isCreatingNote = false
          startNextNoteCreationIfNeeded()
        }
      }
      do {
        try await saveSelectedNote(in: activeFolder)
        do {
          try await finalizeAutomaticNameIfPossible(in: activeFolder)
        } catch {
          present(error)
        }

        let createdFile = try await activeFolder.createNote()
        let discoveredFiles = try await activeFolder.files()
        guard generation == loadGeneration else { return }

        automaticallyNamedFileIDs.insert(createdFile.id)
        files = discoveredFiles
        selectedFileID = createdFile.id
        selectedFile = createdFile
        selectedDocument = MarkdownDocument(fileContents: "")
        hasLoadedSelectedFile = true
        text = ""
        editorContentRevision += 1
        isLoadingFile = false
        editorFocusRequest += 1
      } catch is CancellationError {
        return
      } catch {
        guard generation == loadGeneration else { return }
        present(error)
      }
    }
  }

  func selectFile(_ id: MarkdownFile.ID?) {
    guard id != selectedFileID else { return }

    let previousFile = selectedFile
    var previousDocument = selectedDocument
    previousDocument?.body = text
    let shouldSavePreviousFile = hasLoadedSelectedFile
    let nextFile = files.first { $0.id == id }
    let activeFolder = folder

    saveTask?.cancel()
    fileLoadTask?.cancel()
    isCreatingNote = false
    pendingNoteCreations = 0
    loadGeneration += 1
    let generation = loadGeneration

    selectedFileID = nextFile?.id
    selectedFile = nextFile
    selectedDocument = nil
    hasLoadedSelectedFile = false
    text = ""
    editorContentRevision += 1
    isLoadingFile = nextFile != nil

    guard let activeFolder, let nextFile else {
      isLoadingFile = false
      if shouldSavePreviousFile,
         let activeFolder,
         let previousFile,
         let previousDocument {
        Task {
          do {
            try await activeFolder.write(previousDocument, to: previousFile)
            try await finalizeAutomaticNameIfPossible(
              file: previousFile,
              document: previousDocument,
              in: activeFolder
            )
          } catch {
            present(error)
          }
        }
      }
      return
    }

    fileLoadTask = Task {
      do {
        if shouldSavePreviousFile, let previousFile, let previousDocument {
          try await activeFolder.write(previousDocument, to: previousFile)
          do {
            try await finalizeAutomaticNameIfPossible(
              file: previousFile,
              document: previousDocument,
              in: activeFolder
            )
          } catch {
            present(error)
          }
        }
        let loadedDocument = try await activeFolder.read(nextFile)
        guard !Task.isCancelled, generation == loadGeneration else { return }
        selectedDocument = loadedDocument
        text = loadedDocument.body
        editorContentRevision += 1
        hasLoadedSelectedFile = true
        isLoadingFile = false
      } catch is CancellationError {
        return
      } catch {
        guard generation == loadGeneration else { return }
        isLoadingFile = false
        present(error)
      }
    }
  }

  func updateText(_ newText: String) {
    guard !isLoadingFile,
          let selectedFile,
          let folder,
          var document = selectedDocument
    else { return }

    text = newText
    document.body = newText
    selectedDocument = document
    let shouldFinalizeName = automaticallyNamedFileIDs.contains(selectedFile.id)
      && MarkdownFilename.hasTerminatedMeaningfulLine(in: newText)

    saveTask?.cancel()
    saveTask = Task {
      do {
        try await Task.sleep(for: .milliseconds(300))
        try Task.checkCancellation()
        try await folder.write(document, to: selectedFile)
        try Task.checkCancellation()
        if shouldFinalizeName {
          try await finalizeAutomaticNameIfPossible(
            file: selectedFile,
            document: document,
            in: folder
          )
        }
      } catch is CancellationError {
        return
      } catch {
        present(error)
      }
    }
  }

  func applyEditorEdit(range: NSRange, replacement: String) {
    let source = text as NSString
    let location = max(0, min(range.location, source.length))
    let clampedRange = NSRange(
      location: location,
      length: max(0, min(range.length, source.length - location))
    )
    updateText(source.replacingCharacters(in: clampedRange, with: replacement))
  }

  func flushSave() {
    guard hasLoadedSelectedFile,
          let selectedFile,
          var document = selectedDocument
    else { return }

    saveTask?.cancel()
    document.body = text
    selectedDocument = document
    do {
      try document.fileContents.write(to: selectedFile.url, atomically: true, encoding: .utf8)
    } catch {
      present(error)
    }
  }

  func finishSession() {
    flushSave()
    Task {
      await saveAndFinalizeSelectedNote()
    }
  }

  func present(_ error: Error) {
    errorMessage = error.localizedDescription
  }

  private func activateFolder(_ url: URL) {
    flushSave()
    fileLoadTask?.cancel()
    loadGeneration += 1

    if isAccessingSecurityScopedFolder {
      folderURL?.stopAccessingSecurityScopedResource()
    }

    isAccessingSecurityScopedFolder = url.startAccessingSecurityScopedResource()
    folderURL = url
    folder = MarkdownFolder(rootURL: url)
    files = []
    pendingNoteCreations = 0
    automaticallyNamedFileIDs = []
    namingFileIDs = []
    selectedFile = nil
    selectedDocument = nil
    hasLoadedSelectedFile = false
    selectedFileID = nil
    text = ""
    editorContentRevision += 1
    isLoadingFile = false
    isLoadingFiles = true
    isCreatingNote = false

    guard let folder else { return }
    let generation = loadGeneration
    Task {
      do {
        let discoveredFiles = try await folder.files()
        guard generation == loadGeneration else { return }
        files = discoveredFiles
        isLoadingFiles = false
        selectFile(discoveredFiles.first?.id)
      } catch {
        guard generation == loadGeneration else { return }
        isLoadingFiles = false
        present(error)
      }
    }
  }

  private func saveSelectedNote(in activeFolder: MarkdownFolder) async throws {
    guard hasLoadedSelectedFile,
          let selectedFile,
          var document = selectedDocument
    else { return }

    document.body = text
    selectedDocument = document
    try await activeFolder.write(document, to: selectedFile)
  }

  private func saveAndFinalizeSelectedNote() async {
    guard let activeFolder = folder else { return }

    saveTask?.cancel()
    do {
      try await saveSelectedNote(in: activeFolder)
      try await finalizeAutomaticNameIfPossible(in: activeFolder)
    } catch {
      present(error)
    }
  }

  private func finalizeAutomaticNameIfPossible(
    in activeFolder: MarkdownFolder
  ) async throws {
    guard let selectedFile,
          var document = selectedDocument
    else { return }

    document.body = text
    selectedDocument = document
    try await finalizeAutomaticNameIfPossible(
      file: selectedFile,
      document: document,
      in: activeFolder
    )
  }

  private func finalizeAutomaticNameIfPossible(
    file: MarkdownFile,
    document: MarkdownDocument,
    in activeFolder: MarkdownFolder
  ) async throws {
    guard automaticallyNamedFileIDs.contains(file.id),
          MarkdownFilename.suggestedStem(from: document.body) != nil,
          namingFileIDs.insert(file.id).inserted
    else { return }

    defer { namingFileIDs.remove(file.id) }
    guard let renamedFile = try await activeFolder.renameUsingFirstMeaningfulLine(
      file,
      body: document.body
    ) else { return }

    automaticallyNamedFileIDs.remove(file.id)
    replaceFile(file, with: renamedFile)

    if selectedFileID == file.id {
      selectedFileID = renamedFile.id
      selectedFile = renamedFile
    }
  }

  private func replaceFile(_ oldFile: MarkdownFile, with newFile: MarkdownFile) {
    files.removeAll { $0.id == oldFile.id }
    files.append(newFile)
    files.sort {
      $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending
    }
  }
}
