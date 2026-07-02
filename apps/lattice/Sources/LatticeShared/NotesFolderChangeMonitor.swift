import Foundation

public protocol NotesFolderChangeMonitoring: AnyObject {
  func start(notesFolderURL: URL, selectedNoteURL: URL?, onChange: @escaping () -> Void)
  func updateSelectedNoteURL(_ url: URL?)
  func stop()
}

public final class NotesFolderChangeMonitor: NotesFolderChangeMonitoring {
  private final class Presenter: NSObject, NSFilePresenter {
    let presentedItemOperationQueue = OperationQueue.main
    let presentedItemURL: URL?
    private let onChange: () -> Void

    init(url: URL, onChange: @escaping () -> Void) {
      presentedItemURL = url.standardizedFileURL
      self.onChange = onChange
      super.init()
    }

    func presentedItemDidChange() {
      onChange()
    }

    func presentedItemDidMove(to newURL: URL) {
      onChange()
    }

    func presentedSubitemDidAppear(at url: URL) {
      onChange()
    }

    func presentedSubitemDidChange(at url: URL) {
      onChange()
    }

    func presentedSubitem(at oldURL: URL, didMoveTo newURL: URL) {
      onChange()
    }

    func presentedSubitemDidDisappear(at url: URL) {
      onChange()
    }
  }

  private let debounceInterval: TimeInterval
  private var selectedNoteURL: URL?
  private var folderPresenter: Presenter?
  private var selectedNotePresenter: Presenter?
  private var pendingChange: DispatchWorkItem?
  private var onChange: (() -> Void)?

  public init(debounceInterval: TimeInterval = 0.5) {
    self.debounceInterval = debounceInterval
  }

  deinit {
    stop()
  }

  public func start(notesFolderURL: URL, selectedNoteURL: URL?, onChange: @escaping () -> Void) {
    stop()
    self.onChange = onChange

    let notesDirectoryURL = notesFolderURL
      .appendingPathComponent("notes", isDirectory: true)
      .standardizedFileURL
    folderPresenter = Presenter(url: notesDirectoryURL) { [weak self] in
      self?.scheduleChange()
    }
    if let folderPresenter {
      NSFileCoordinator.addFilePresenter(folderPresenter)
    }

    updateSelectedNoteURL(selectedNoteURL)
  }

  public func updateSelectedNoteURL(_ url: URL?) {
    let standardizedURL = url?.standardizedFileURL
    guard selectedNoteURL != standardizedURL else {
      return
    }

    if let selectedNotePresenter {
      NSFileCoordinator.removeFilePresenter(selectedNotePresenter)
    }
    selectedNotePresenter = nil
    selectedNoteURL = standardizedURL

    guard let standardizedURL, FileManager.default.fileExists(atPath: standardizedURL.path) else {
      return
    }

    selectedNotePresenter = Presenter(url: standardizedURL) { [weak self] in
      self?.scheduleChange()
    }
    if let selectedNotePresenter {
      NSFileCoordinator.addFilePresenter(selectedNotePresenter)
    }
  }

  public func stop() {
    pendingChange?.cancel()
    pendingChange = nil
    if let folderPresenter {
      NSFileCoordinator.removeFilePresenter(folderPresenter)
    }
    if let selectedNotePresenter {
      NSFileCoordinator.removeFilePresenter(selectedNotePresenter)
    }
    folderPresenter = nil
    selectedNotePresenter = nil
    selectedNoteURL = nil
    onChange = nil
  }

  private func scheduleChange() {
    pendingChange?.cancel()
    let workItem = DispatchWorkItem { [weak self] in
      self?.onChange?()
    }
    pendingChange = workItem
    DispatchQueue.main.asyncAfter(deadline: .now() + debounceInterval, execute: workItem)
  }
}
