import AppKit
import SwiftUI

enum MacJotMetrics {
  static let width: CGFloat = 520
  static let height: CGFloat = 260
}

struct MacJotView: View {
  @Bindable var model: MacMarkdownAppModel
  let onDismiss: @MainActor () -> Void
  @State private var editorFocusRequest = 0
  @State private var isSubmitHovered = false

  var body: some View {
    VStack(spacing: 0) {
      LiveMarkdownEditor(
        text: model.jotDraft,
        contentRevision: 0,
        externalRefreshRequest: 0,
        focusRequest: editorFocusRequest,
        isEditable: !model.isSubmittingJot,
        treatsEmptyDocumentAsTitle: false,
        accessibilityIdentifier: "jotEditor",
        onEdit: { range, replacement in
          model.applyJotEdit(range: range, replacement: replacement)
        },
        onReplaceAll: { replacement in
          model.jotDraft = replacement
        },
        onOpenWikiLink: { target in
          model.openWikiLink(target)
        },
        onEnsureTodayNote: { now, calendar in
          model.ensureTodayNote(now: now, calendar: calendar)
        },
        onSubmit: submit,
        onCancel: dismiss
      )
        .padding(.horizontal, 28)
        .padding(.top, 30)
        .padding(.bottom, 12)

      HStack(spacing: 12) {
        if let message = model.jotAvailabilityMessage ?? model.jotErrorMessage {
          Text(message)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .accessibilityIdentifier("jotError")
        }

        Spacer(minLength: 12)

        if model.isSubmittingJot {
          ProgressView()
            .controlSize(.small)
            .accessibilityLabel("Adding to Today")
        }

        Button(action: submit) {
          HStack(spacing: 8) {
            Text("Add to Today")
            Text("⌘↩")
              .foregroundStyle(.secondary)
          }
          .font(.callout.weight(.medium))
          .padding(.horizontal, 10)
          .padding(.vertical, 7)
          .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
              .fill(isSubmitHovered ? Color.primary.opacity(0.08) : .clear)
          }
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.return, modifiers: .command)
        .disabled(!model.canSubmitJot)
        .opacity(model.canSubmitJot ? 1 : 0.45)
        .onHover { isSubmitHovered = $0 }
        .accessibilityHint("Appends this text to today's note")
        .accessibilityIdentifier("jotSubmit")
      }
      .padding(.leading, 30)
      .padding(.trailing, 22)
      .padding(.bottom, 20)
    }
    .background {
      Color(nsColor: .windowBackgroundColor)
    }
    .overlay(alignment: .top) {
      MacJotDragRegion()
        .frame(height: 18)
    }
    .onAppear {
      model.start()
      DispatchQueue.main.async {
        editorFocusRequest += 1
      }
    }
    .onExitCommand(perform: dismiss)
  }

  private func submit() {
    guard model.canSubmitJot else { return }
    Task {
      if await model.submitJot() {
        onDismiss()
      }
    }
  }

  private func dismiss() {
    onDismiss()
  }
}

private struct MacJotDragRegion: NSViewRepresentable {
  func makeNSView(context: Context) -> NSView {
    MacJotDraggableView()
  }

  func updateNSView(_ nsView: NSView, context: Context) {}
}

@MainActor
private final class MacJotDraggableView: NSView {
  override var mouseDownCanMoveWindow: Bool { true }
}
