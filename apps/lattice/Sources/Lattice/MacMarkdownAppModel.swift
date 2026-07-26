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

  @ObservationIgnored private var fileLoadTask: Task<Void, Never>?
  @ObservationIgnored private var saveTask: Task<Void, Never>?

  private(set) var folderURL: URL?
  private(set) var files: [MarkdownFile] = []
  private(set) var selectedFileID: MarkdownFile.ID?
  private(set) var text = ""
  private(set) var isLoadingFiles = false
  private(set) var isLoadingFile = false
  var errorMessage: String?

  init(bookmarkStore: MarkdownFolderBookmarkStore = MarkdownFolderBookmarkStore()) {
    self.bookmarkStore = bookmarkStore
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
      activateFolder(url)
    } catch {
      present(error)
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
    loadGeneration += 1
    let generation = loadGeneration

    selectedFileID = nextFile?.id
    selectedFile = nextFile
    selectedDocument = nil
    hasLoadedSelectedFile = false
    text = ""
    isLoadingFile = nextFile != nil

    guard let activeFolder, let nextFile else {
      isLoadingFile = false
      if shouldSavePreviousFile,
         let activeFolder,
         let previousFile,
         let previousDocument {
        Task {
          try? await activeFolder.write(previousDocument, to: previousFile)
        }
      }
      return
    }

    fileLoadTask = Task {
      do {
        if shouldSavePreviousFile, let previousFile, let previousDocument {
          try await activeFolder.write(previousDocument, to: previousFile)
        }
        let loadedDocument = try await activeFolder.read(nextFile)
        guard !Task.isCancelled, generation == loadGeneration else { return }
        selectedDocument = loadedDocument
        text = loadedDocument.body
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

    saveTask?.cancel()
    saveTask = Task {
      do {
        try await Task.sleep(for: .milliseconds(300))
        try Task.checkCancellation()
        try await folder.write(document, to: selectedFile)
      } catch is CancellationError {
        return
      } catch {
        present(error)
      }
    }
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
    selectedFile = nil
    selectedDocument = nil
    hasLoadedSelectedFile = false
    selectedFileID = nil
    text = ""
    isLoadingFile = false
    isLoadingFiles = true

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
}
