import AppKit
import Foundation
import LatticeMacCore
import SwiftUI

enum MacFileAction: String, CaseIterable, Identifiable, Sendable {
  case showInFinder
  case copyFilePath

  var id: Self { self }

  var title: String {
    switch self {
    case .showInFinder:
      "Show in Finder"
    case .copyFilePath:
      "Copy File Path"
    }
  }

  var systemImage: String {
    switch self {
    case .showInFinder:
      "folder"
    case .copyFilePath:
      "doc.on.doc"
    }
  }
}

@MainActor
struct MacFileActionClient {
  let reveal: (URL) throws -> Void
  let copyPath: (String) throws -> Void

  static let live = MacFileActionClient(
    reveal: { url in
      NSWorkspace.shared.activateFileViewerSelecting([url])
    },
    copyPath: { path in
      let pasteboard = NSPasteboard.general
      pasteboard.clearContents()
      guard pasteboard.setString(path, forType: .string) else {
        throw MacFileActionError.copyFailed
      }
    }
  )
}

enum MacFileActionError: LocalizedError {
  case fileUnavailable(URL)
  case folderChanged
  case copyFailed

  var errorDescription: String? {
    switch self {
    case .fileUnavailable(let url):
      "The note file “\(url.lastPathComponent)” is missing or has moved."
    case .folderChanged:
      "The notes folder changed before the file action finished."
    case .copyFailed:
      "Lattice could not copy the file path."
    }
  }
}

struct MacFileActionsMenu<Label: View>: View {
  let file: MarkdownFile?
  let noteTitle: String?
  let action: (MacFileAction, MarkdownFile.ID) -> Void
  @ViewBuilder let label: () -> Label

  var body: some View {
    Menu {
      if let file {
        MacFileActionMenuItems(file: file, action: action)
      }
    } label: {
      label()
    }
    .disabled(file == nil)
    .help(MacFileActionAccessibility.label(noteTitle: noteTitle))
    .accessibilityLabel(MacFileActionAccessibility.label(noteTitle: noteTitle))
  }
}

struct MacFileActionMenuItems: View {
  let file: MarkdownFile
  let action: (MacFileAction, MarkdownFile.ID) -> Void

  var body: some View {
    Text(MacFileActionMenuPath.short(file.relativePath))
      .foregroundStyle(.secondary)

    Divider()

    ForEach(MacFileAction.allCases) { fileAction in
      Button {
        action(fileAction, file.id)
      } label: {
        Label(fileAction.title, systemImage: fileAction.systemImage)
      }
    }
  }
}

enum MacFileActionMenuPath {
  static func short(_ relativePath: String, limit: Int = 42) -> String {
    guard relativePath.count > limit, limit > 1 else { return relativePath }
    return "…" + relativePath.suffix(limit - 1)
  }
}

enum MacFileActionAccessibility {
  static func label(noteTitle: String?) -> String {
    guard let noteTitle else { return "File Actions" }
    return "File Actions for \(noteTitle)"
  }
}

enum MacSidebarFileActionVisibility {
  static func isVisible(isHovered: Bool, isSelected: Bool) -> Bool {
    isHovered || isSelected
  }
}
