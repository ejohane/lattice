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
        themeSection
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

  private var themeSection: some View {
    Section("Theme") {
      Picker("Theme", selection: themeBinding) {
        ForEach(LatticeThemeID.allCases) { themeID in
          Text(themeID.displayName).tag(themeID)
        }
      }
      #if os(macOS)
      .pickerStyle(.menu)
      #endif

      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 12) {
          ForEach(LatticeThemeID.allCases) { themeID in
            ThemePreviewCard(
              theme: LatticeTheme(id: themeID),
              isSelected: model.selectedThemeID == themeID
            ) {
              model.setTheme(themeID)
            }
          }
        }
        .padding(.vertical, 4)
      }
    }
  }

  @ViewBuilder
  private var editorSection: some View {
    #if os(macOS)
    Section("Editor") {
      Toggle("Vim Mode", isOn: vimModeBinding)
      Toggle("Relative Line Numbers", isOn: relativeLineNumbersBinding)
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

  private var themeBinding: Binding<LatticeThemeID> {
    Binding {
      model.selectedThemeID
    } set: { value in
      model.setTheme(value)
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

private struct ThemePreviewCard: View {
  let theme: LatticeTheme
  let isSelected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      VStack(alignment: .leading, spacing: 10) {
        HStack {
          Text(theme.displayName)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
          Spacer(minLength: 12)
          Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .imageScale(.small)
        }
        .foregroundStyle(theme.color(.primaryText))

        VStack(alignment: .leading, spacing: 5) {
          RoundedRectangle(cornerRadius: 2)
            .fill(theme.color(.primaryText))
            .frame(width: 92, height: 5)
          RoundedRectangle(cornerRadius: 2)
            .fill(theme.color(.secondaryText))
            .frame(width: 116, height: 5)
          RoundedRectangle(cornerRadius: 2)
            .fill(theme.color(.accent))
            .frame(width: 76, height: 5)
        }
      }
      .padding(12)
      .frame(width: 170, height: 96, alignment: .leading)
      .background(theme.color(.editorBackground))
      .overlay {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .stroke(isSelected ? theme.color(.accent) : theme.color(.separator), lineWidth: isSelected ? 2 : 1)
      }
      .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
    .buttonStyle(.plain)
    .accessibilityLabel(theme.displayName)
  }
}
