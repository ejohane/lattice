import LatticeCore
import SwiftUI

public struct TaskSyncSettingsView: View {
  @Bindable private var model: LatticeAppModel
  @Environment(\.dismiss) private var dismiss

  public init(model: LatticeAppModel) {
    self.model = model
  }

  public var body: some View {
    NavigationStack {
      Form {
        editorSection
        providerSection
        destinationSection
        syncSection
      }
      .navigationTitle("Settings")
      #if os(iOS)
      .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") {
            dismiss()
          }
        }
      }
    }
    .task {
      await model.refreshTaskSyncProviderState()
    }
    .alert("Sync existing tasks?", isPresented: initialSyncConfirmationBinding) {
      Button("Cancel", role: .cancel) {
        model.cancelInitialTaskSync()
      }
      Button("Sync Tasks") {
        Task { @MainActor in
          await model.confirmInitialTaskSync()
        }
      }
    } message: {
      Text(initialSyncMessage)
    }
  }

  @ViewBuilder
  private var editorSection: some View {
    #if os(macOS)
    Section("Editor") {
      Toggle("Vim Mode", isOn: vimModeBinding)
      Toggle("Relative Line Numbers", isOn: relativeLineNumbersBinding)
      Toggle("Timeline Ruler", isOn: timelineRulerBinding)
    }
    #else
    EmptyView()
    #endif
  }

  private var providerSection: some View {
    Section("Task Provider") {
      LabeledContent("Provider", value: model.taskSyncProviderName)
      LabeledContent("Access", value: authorizationText)
      if !model.taskSyncAuthorizationStatus.allowsSync {
        Button {
          Task { @MainActor in
            await model.refreshTaskSyncProviderState()
            await model.requestEnableTaskSync()
          }
        } label: {
          Label("Allow Reminders Access", systemImage: "checkmark.shield")
        }
      }
    }
  }

  private var destinationSection: some View {
    Section("Reminders List") {
      if model.taskSyncDestinations.isEmpty {
        Text(model.taskSyncAuthorizationStatus.allowsSync
          ? "No Reminders lists are available."
          : "Allow Reminders access to choose a list.")
          .foregroundStyle(.secondary)
      } else {
        Picker("List", selection: destinationBinding) {
          ForEach(model.taskSyncDestinations) { destination in
            Text(destination.title).tag(destination.id)
          }
        }
      }
    }
  }

  private var syncSection: some View {
    Section("Sync") {
      if model.isTaskSyncEnabled {
        Button {
          Task { @MainActor in
            await model.syncTasksNow()
          }
        } label: {
          Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
        }
        .disabled(!model.hasFolder)

        Button(role: .destructive) {
          model.disableTaskSync()
        } label: {
          Label("Disable Task Sync", systemImage: "xmark.circle")
        }
      } else {
        Button {
          Task { @MainActor in
            await model.requestEnableTaskSync()
          }
        } label: {
          Label("Enable Task Sync", systemImage: "arrow.triangle.2.circlepath")
        }
        .disabled(!model.hasFolder)
      }

      LabeledContent("Status", value: model.taskSyncStatus)
      if let message = model.taskSyncErrorMessage, !message.isEmpty {
        Text(message)
          .font(.footnote)
          .foregroundStyle(.red)
      }
      if !model.hasFolder {
        Text("Choose a notes folder before enabling task sync.")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
    }
  }

  private var destinationBinding: Binding<String> {
    Binding {
      model.selectedTaskDestinationID ?? model.taskSyncDestinations.first?.id ?? ""
    } set: { value in
      model.selectTaskSyncDestination(value)
    }
  }

  private var vimModeBinding: Binding<Bool> {
    Binding {
      model.isVimModeEnabled
    } set: { value in
      model.setVimModeEnabled(value)
    }
  }

  private var relativeLineNumbersBinding: Binding<Bool> {
    Binding {
      model.showsRelativeLineNumbers
    } set: { value in
      model.setRelativeLineNumbersEnabled(value)
    }
  }

  private var timelineRulerBinding: Binding<Bool> {
    Binding {
      model.showsTimelineRuler
    } set: { value in
      model.setTimelineRulerEnabled(value)
    }
  }

  private var initialSyncConfirmationBinding: Binding<Bool> {
    Binding {
      model.pendingInitialSyncTaskCount != nil
    } set: { isPresented in
      if !isPresented {
        model.cancelInitialTaskSync()
      }
    }
  }

  private var initialSyncMessage: String {
    let count = model.pendingInitialSyncTaskCount ?? 0
    let unit = count == 1 ? "task" : "tasks"
    return "Lattice found \(count) existing Markdown \(unit). Syncing will create matching reminders in the selected list."
  }

  private var authorizationText: String {
    switch model.taskSyncAuthorizationStatus {
    case .notDetermined:
      return "Not requested"
    case .authorized:
      return "Allowed"
    case .denied:
      return "Denied"
    case .restricted:
      return "Restricted"
    }
  }
}
