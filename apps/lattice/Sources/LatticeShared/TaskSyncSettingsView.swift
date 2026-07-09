import LatticeCore
import SwiftUI

#if os(macOS)
import AppKit
#endif

public struct TaskSyncSettingsView: View {
  @Bindable private var model: LatticeAppModel
  private let releaseNotesCatalog: ReleaseNotesCatalog
  private let releaseUpdateStatus: ReleaseUpdateStatus
  private let onCheckForUpdates: (() -> Void)?
  @Environment(\.dismiss) private var dismiss
  #if os(macOS)
  @State private var selectedMacPane: MacSettingsPane? = .general
  @State private var macSearchQuery = ""
  #endif

  public init(
    model: LatticeAppModel,
    releaseNotesCatalog: ReleaseNotesCatalog = .bundled(),
    releaseUpdateStatus: ReleaseUpdateStatus = .unavailable,
    onCheckForUpdates: (() -> Void)? = nil
  ) {
    self.model = model
    self.releaseNotesCatalog = releaseNotesCatalog
    self.releaseUpdateStatus = releaseUpdateStatus
    self.onCheckForUpdates = onCheckForUpdates
  }

  public var body: some View {
    settingsContent
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
  private var settingsContent: some View {
    #if os(macOS)
    macSettingsContent
    #else
    NavigationStack {
      Form {
        changelogSection
        themeSection
        editorSection
        #if os(macOS)
        keyboardShortcutsSection
        #endif
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
    #endif
  }

  #if os(macOS)
  private var macSettingsContent: some View {
    HStack(spacing: 0) {
      macSettingsSidebar
        .frame(width: 226)

      Divider()

      macSettingsDetail
    }
    .background(Color(nsColor: .controlBackgroundColor))
    .preferredColorScheme(model.theme.preferredColorScheme)
    .tint(model.theme.color(.accent))
    .onChange(of: macSearchQuery) { _, _ in
      if !filteredMacPanes.contains(selectedMacSettingsPane),
         let firstPane = filteredMacPanes.first {
        selectedMacPane = firstPane
      }
    }
  }

  private var macSettingsSidebar: some View {
    VStack(spacing: 12) {
      HStack(spacing: 7) {
        Image(systemName: "magnifyingglass")
          .foregroundStyle(.secondary)
        TextField("Search", text: $macSearchQuery)
          .textFieldStyle(.plain)
      }
      .padding(.horizontal, 10)
      .frame(height: 28)
      .background(.quaternary, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
      .padding(.horizontal, 16)
      .padding(.top, 18)

      List {
        ForEach(filteredMacPanes) { pane in
          Button {
            selectedMacPane = pane
          } label: {
            MacSettingsSidebarRow(
              pane: pane,
              isSelected: selectedMacSettingsPane == pane
            )
          }
          .buttonStyle(.plain)
        }

        if filteredMacPanes.isEmpty {
          Text("No Results")
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
        }
      }
      .listStyle(.sidebar)
      .scrollContentBackground(.hidden)
    }
    .background(.bar)
  }

  private var macSettingsDetail: some View {
    ScrollView {
      VStack(spacing: 22) {
        MacSettingsHeroCard(pane: selectedMacSettingsPane)
        macPaneSections
      }
      .frame(maxWidth: 520)
      .padding(.horizontal, 24)
      .padding(.top, 42)
      .padding(.bottom, 44)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(nsColor: .controlBackgroundColor))
    .toolbar {
      ToolbarItemGroup(placement: .navigation) {
        Button {
          selectPreviousMacPane()
        } label: {
          Label("Back", systemImage: "chevron.left")
            .labelStyle(.iconOnly)
        }
        .help("Back")
        .disabled(previousMacPane == nil)

        Button {
          selectNextMacPane()
        } label: {
          Label("Forward", systemImage: "chevron.right")
            .labelStyle(.iconOnly)
        }
        .help("Forward")
        .disabled(nextMacPane == nil)
      }
    }
  }

  @ViewBuilder
  private var macPaneSections: some View {
    switch selectedMacSettingsPane {
    case .general:
      macGeneralSections
    case .changelog:
      macChangelogSections
    case .appearance:
      macAppearanceSections
    case .editor:
      macEditorSections
    case .keyboard:
      macKeyboardSections
    case .reminders:
      macRemindersSections
    }
  }

  private var macGeneralSections: some View {
    VStack(spacing: 22) {
      MacSettingsSection(title: "Lattice") {
        MacSettingsValueRow(title: "Notes Folder", value: model.folderURL?.lastPathComponent ?? "Not selected")
        MacSettingsDivider()
        MacSettingsValueRow(title: "Status", value: model.status)
        MacSettingsDivider()
        MacSettingsValueRow(title: "Theme", value: model.theme.displayName)
        MacSettingsDivider()
        MacSettingsValueRow(title: "Task Sync", value: model.taskSyncStatus)
      }

      MacSettingsSection(title: "Task Provider") {
        MacSettingsValueRow(title: "Provider", value: model.taskSyncProviderName)
        MacSettingsDivider()
        MacSettingsValueRow(title: "Access", value: authorizationText)
        if !model.taskSyncAuthorizationStatus.allowsSync {
          MacSettingsDivider()
          MacSettingsActionRow(
            title: "Allow Reminders Access",
            systemImage: "checkmark.shield"
          ) {
            Task { @MainActor in
              await model.refreshTaskSyncProviderState()
              await model.requestEnableTaskSync()
            }
          }
        }
      }
    }
  }

  private var macAppearanceSections: some View {
    MacSettingsSection(title: "Theme") {
      MacSettingsControlRow(title: "Theme") {
        Picker("Theme", selection: themeBinding) {
          ForEach(LatticeThemeID.allCases) { themeID in
            Text(themeID.displayName).tag(themeID)
          }
        }
        .labelsHidden()
        .pickerStyle(.menu)
      }
      MacSettingsDivider()
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
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
      }
    }
  }

  private var macChangelogSections: some View {
    VStack(spacing: 16) {
      if releaseUpdateStatus.shouldShowInChangelog {
        macUpdateSection
      }

      if releaseNotesCatalog.entries.isEmpty {
        MacSettingsSection(title: "Release Notes") {
          MacSettingsTextRow(text: changelogEmptyMessage)
        }
      } else {
        ForEach(releaseNotesCatalog.entries) { entry in
          MacReleaseNoteCard(entry: entry)
        }
      }
    }
  }

  private var macUpdateSection: some View {
    MacSettingsSection(title: "Updates") {
      MacSettingsValueRow(title: "Status", value: releaseUpdateStatus.statusText)
      MacSettingsDivider()
      MacSettingsTextRow(text: releaseUpdateStatus.detailText)
      if let onCheckForUpdates {
        MacSettingsDivider()
        MacSettingsActionRow(
          title: releaseUpdateStatus.actionTitle,
          systemImage: releaseUpdateStatus.actionSystemImage
        ) {
          onCheckForUpdates()
        }
        .disabled(!releaseUpdateStatus.canCheckForUpdates)
      }
    }
  }

  private var macEditorSections: some View {
    MacSettingsSection(title: "Editor") {
      MacSettingsControlRow(title: "Font") {
        Picker("Font", selection: fontFamilyBinding) {
          ForEach(EditorFontFamily.allCases) { fontFamily in
            Text(fontFamily.displayName).tag(fontFamily)
          }
        }
        .labelsHidden()
        .pickerStyle(.menu)
      }
      MacSettingsDivider()
      MacSettingsToggleRow(title: "Vim Mode", isOn: vimModeBinding)
      MacSettingsDivider()
      MacSettingsToggleRow(title: "Relative Line Numbers", isOn: relativeLineNumbersBinding)
    }
  }

  private var macKeyboardSections: some View {
    MacSettingsSection(title: "Keyboard Shortcuts") {
      ForEach(Array(LatticeKeyboardShortcutID.allCases.enumerated()), id: \.element.id) { index, shortcutID in
        if index > 0 {
          MacSettingsDivider()
        }
        KeyboardShortcutSettingsRow(
          shortcutID: shortcutID,
          shortcut: model.keyboardShortcut(for: shortcutID)
        ) { shortcut in
          model.setKeyboardShortcut(shortcut, for: shortcutID)
        } onReset: {
          model.resetKeyboardShortcut(for: shortcutID)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 44)
      }
    }
  }

  private var macRemindersSections: some View {
    VStack(spacing: 22) {
      MacSettingsSection(title: "Reminders List") {
        if model.taskSyncDestinations.isEmpty {
          MacSettingsTextRow(
            text: model.taskSyncAuthorizationStatus.allowsSync
              ? "No Reminders lists are available."
              : "Allow Reminders access to choose a list."
          )
        } else {
          MacSettingsControlRow(title: "List") {
            Picker("List", selection: destinationBinding) {
              ForEach(model.taskSyncDestinations) { destination in
                Text(destination.title).tag(destination.id)
              }
            }
            .labelsHidden()
            .pickerStyle(.menu)
          }
        }
      }

      MacSettingsSection(title: "Sync") {
        if model.isTaskSyncEnabled {
          MacSettingsActionRow(title: "Sync Now", systemImage: "arrow.triangle.2.circlepath") {
            Task { @MainActor in
              await model.syncTasksNow()
            }
          }
          .disabled(!model.hasFolder)
          MacSettingsDivider()
          MacSettingsActionRow(
            title: "Disable Task Sync",
            systemImage: "xmark.circle",
            role: .destructive
          ) {
            model.disableTaskSync()
          }
        } else {
          MacSettingsActionRow(title: "Enable Task Sync", systemImage: "arrow.triangle.2.circlepath") {
            Task { @MainActor in
              await model.requestEnableTaskSync()
            }
          }
          .disabled(!model.hasFolder)
        }

        MacSettingsDivider()
        MacSettingsValueRow(title: "Status", value: model.taskSyncStatus)
        if let message = model.taskSyncErrorMessage, !message.isEmpty {
          MacSettingsDivider()
          MacSettingsTextRow(text: message, isError: true)
        }
        if !model.hasFolder {
          MacSettingsDivider()
          MacSettingsTextRow(text: "Choose a notes folder before enabling task sync.")
        }
      }
    }
  }

  private var generalSection: some View {
    Section("Lattice") {
      LabeledContent("Notes Folder", value: model.folderURL?.lastPathComponent ?? "Not selected")
      LabeledContent("Status", value: model.status)
      LabeledContent("Theme", value: model.theme.displayName)
      LabeledContent("Task Sync", value: model.taskSyncStatus)
    }
  }

  private var selectedMacSettingsPane: MacSettingsPane {
    selectedMacPane ?? .general
  }

  private var filteredMacPanes: [MacSettingsPane] {
    let query = macSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else {
      return MacSettingsPane.allCases
    }
    return MacSettingsPane.allCases.filter {
      $0.title.localizedCaseInsensitiveContains(query)
        || $0.subtitle.localizedCaseInsensitiveContains(query)
    }
  }

  private var previousMacPane: MacSettingsPane? {
    adjacentMacPane(offset: -1)
  }

  private var nextMacPane: MacSettingsPane? {
    adjacentMacPane(offset: 1)
  }

  private func adjacentMacPane(offset: Int) -> MacSettingsPane? {
    guard let index = MacSettingsPane.allCases.firstIndex(of: selectedMacSettingsPane) else {
      return nil
    }
    let nextIndex = index + offset
    guard MacSettingsPane.allCases.indices.contains(nextIndex) else {
      return nil
    }
    return MacSettingsPane.allCases[nextIndex]
  }

  private func selectPreviousMacPane() {
    if let previousMacPane {
      selectedMacPane = previousMacPane
    }
  }

  private func selectNextMacPane() {
    if let nextMacPane {
      selectedMacPane = nextMacPane
    }
  }
  #endif

  private var changelogSection: some View {
    Section("Changelog") {
      if releaseUpdateStatus.shouldShowInChangelog {
        ReleaseUpdateStatusDisclosure(
          status: releaseUpdateStatus,
          onCheckForUpdates: onCheckForUpdates
        )
      }

      if releaseNotesCatalog.entries.isEmpty {
        Text(changelogEmptyMessage)
          .foregroundStyle(.secondary)
      } else {
        ForEach(releaseNotesCatalog.entries) { entry in
          ReleaseNoteDisclosure(entry: entry)
        }
      }
    }
  }

  private var changelogEmptyMessage: String {
    "Release notes are included in release builds."
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
    Section("Editor") {
      Picker("Font", selection: fontFamilyBinding) {
        ForEach(EditorFontFamily.allCases) { fontFamily in
          Text(fontFamily.displayName).tag(fontFamily)
        }
      }

      #if os(macOS)
      Toggle("Vim Mode", isOn: vimModeBinding)
      Toggle("Relative Line Numbers", isOn: relativeLineNumbersBinding)
      #endif
    }
  }

  #if os(macOS)
  private var keyboardShortcutsSection: some View {
    Section("Keyboard Shortcuts") {
      ForEach(LatticeKeyboardShortcutID.allCases) { shortcutID in
        KeyboardShortcutSettingsRow(
          shortcutID: shortcutID,
          shortcut: model.keyboardShortcut(for: shortcutID)
        ) { shortcut in
          model.setKeyboardShortcut(shortcut, for: shortcutID)
        } onReset: {
          model.resetKeyboardShortcut(for: shortcutID)
        }
      }
    }
  }
  #endif

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

  private var fontFamilyBinding: Binding<EditorFontFamily> {
    Binding {
      model.editorFontFamily
    } set: { value in
      model.setEditorFontFamily(value)
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

private struct ReleaseNoteDisclosure: View {
  let entry: ReleaseNoteEntry

  var body: some View {
    DisclosureGroup {
      ReleaseNoteSectionsView(entry: entry)
        .padding(.top, 8)
    } label: {
      VStack(alignment: .leading, spacing: 3) {
        Text("Version \(entry.version)")
          .font(.headline)
        if let displayDate = entry.displayDate {
          Text(displayDate)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
      .padding(.vertical, 4)
    }
  }
}

private struct ReleaseUpdateStatusDisclosure: View {
  let status: ReleaseUpdateStatus
  let onCheckForUpdates: (() -> Void)?

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      LabeledContent("Update Status", value: status.statusText)
      Text(status.detailText)
        .font(.footnote)
        .foregroundStyle(.secondary)

      if let onCheckForUpdates {
        Button {
          onCheckForUpdates()
        } label: {
          Label(status.actionTitle, systemImage: status.actionSystemImage)
        }
        .disabled(!status.canPerformAction)
      }
    }
    .padding(.vertical, 4)
  }
}

private struct ReleaseNoteSectionsView: View {
  let entry: ReleaseNoteEntry

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      if entry.sections.isEmpty {
        Text("No release notes were published for this version.")
          .font(.footnote)
          .foregroundStyle(.secondary)
      } else {
        ForEach(entry.sections) { section in
          VStack(alignment: .leading, spacing: 7) {
            Text(section.title)
              .font(.subheadline.weight(.semibold))
            ForEach(section.items) { item in
              HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("*")
                  .foregroundStyle(.secondary)
                if let url = item.url {
                  Link(item.text, destination: url)
                } else {
                  Text(item.text)
                }
              }
              .font(.footnote)
            }
          }
        }
      }

      if let url = entry.url {
        Link("Open release", destination: url)
          .font(.footnote.weight(.semibold))
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

#if os(macOS)
private struct MacReleaseNoteCard: View {
  let entry: ReleaseNoteEntry

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(alignment: .firstTextBaseline, spacing: 12) {
        VStack(alignment: .leading, spacing: 3) {
          Text("Version \(entry.version)")
            .font(.system(size: 17, weight: .semibold))
          if let displayDate = entry.displayDate {
            Text(displayDate)
              .font(.system(size: 12, weight: .medium))
              .foregroundStyle(.secondary)
          }
        }

        Spacer(minLength: 12)

        if let url = entry.url {
          Link(destination: url) {
            Image(systemName: "arrow.up.forward")
              .font(.system(size: 12, weight: .semibold))
              .frame(width: 24, height: 24)
          }
          .buttonStyle(.plain)
          .foregroundStyle(Color.accentColor)
          .help("Open release")
        }
      }

      ReleaseNoteSectionsView(entry: entry)
    }
    .padding(16)
    .background(MacSettingsCardColor.fill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
  }
}

private enum MacSettingsPane: String, CaseIterable, Identifiable, Hashable {
  case general
  case changelog
  case appearance
  case editor
  case keyboard
  case reminders

  var id: String { rawValue }

  var title: String {
    switch self {
    case .general:
      return "General"
    case .changelog:
      return "Changelog"
    case .appearance:
      return "Appearance"
    case .editor:
      return "Editor"
    case .keyboard:
      return "Keyboard"
    case .reminders:
      return "Reminders"
    }
  }

  var subtitle: String {
    switch self {
    case .general:
      return "Manage your notes folder, appearance, and task sync setup."
    case .changelog:
      return "Review what changed in each Lattice release."
    case .appearance:
      return "Choose how Lattice looks across your workspace."
    case .editor:
      return "Adjust writing preferences, Vim mode, and editor chrome."
    case .keyboard:
      return "Review and customize the shortcuts used by Lattice."
    case .reminders:
      return "Connect Markdown tasks with Apple Reminders."
    }
  }

  var systemImage: String {
    switch self {
    case .general:
      return "gearshape"
    case .changelog:
      return "list.bullet.rectangle"
    case .appearance:
      return "circle.lefthalf.filled"
    case .editor:
      return "text.alignleft"
    case .keyboard:
      return "keyboard"
    case .reminders:
      return "checklist"
    }
  }
}

private struct MacSettingsHeroCard: View {
  let pane: MacSettingsPane

  var body: some View {
    VStack(spacing: 16) {
      Image(systemName: pane.systemImage)
        .font(.system(size: 36, weight: .medium))
        .symbolRenderingMode(.hierarchical)
        .foregroundStyle(.primary)
        .frame(width: 74, height: 74)
        .background(.tertiary, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

      VStack(spacing: 5) {
        Text(pane.title)
          .font(.system(size: 28, weight: .bold))
        Text(pane.subtitle)
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .lineLimit(2)
      }
    }
    .frame(maxWidth: .infinity)
    .padding(.horizontal, 28)
    .padding(.vertical, 26)
    .background(MacSettingsCardColor.fill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
  }
}

private struct MacSettingsSidebarRow: View {
  let pane: MacSettingsPane
  let isSelected: Bool

  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: pane.systemImage)
        .font(.system(size: 14, weight: .medium))
        .symbolRenderingMode(.hierarchical)
        .foregroundStyle(isSelected ? .white : Color.accentColor)
        .frame(width: 18)
      Text(pane.title)
        .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
        .foregroundStyle(isSelected ? .white : .primary)
      Spacer(minLength: 0)
    }
      .frame(maxWidth: .infinity, alignment: .leading)
      .frame(height: 32)
      .padding(.horizontal, 10)
      .background {
        if isSelected {
          RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color.accentColor)
        }
      }
      .contentShape(Rectangle())
      .accessibilityAddTraits(isSelected ? [.isSelected] : [])
  }
}

private struct MacSettingsSection<Content: View>: View {
  let title: String
  @ViewBuilder let content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title)
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(.primary)
        .padding(.leading, 14)

      VStack(spacing: 0) {
        content
      }
      .background(MacSettingsCardColor.fill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
      .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
  }
}

private struct MacSettingsValueRow: View {
  let title: String
  let value: String

  var body: some View {
    HStack(spacing: 16) {
      Text(title)
        .foregroundStyle(.primary)
      Spacer(minLength: 20)
      Text(value)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.trailing)
        .lineLimit(2)
    }
    .font(.system(size: 14))
    .padding(.horizontal, 14)
    .frame(minHeight: 42)
  }
}

private struct MacSettingsControlRow<Control: View>: View {
  let title: String
  @ViewBuilder let control: Control

  var body: some View {
    HStack(spacing: 16) {
      Text(title)
        .foregroundStyle(.primary)
      Spacer(minLength: 20)
      control
        .controlSize(.small)
    }
    .font(.system(size: 14))
    .padding(.horizontal, 14)
    .frame(minHeight: 42)
  }
}

private struct MacSettingsToggleRow: View {
  let title: String
  @Binding var isOn: Bool

  var body: some View {
    MacSettingsControlRow(title: title) {
      Toggle(title, isOn: $isOn)
        .labelsHidden()
        .toggleStyle(.switch)
    }
  }
}

private struct MacSettingsTextRow: View {
  let text: String
  var isError = false

  var body: some View {
    Text(text)
      .font(.system(size: 13))
      .foregroundStyle(isError ? .red : .secondary)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 14)
      .padding(.vertical, 12)
  }
}

private struct MacSettingsActionRow: View {
  let title: String
  let systemImage: String
  var role: ButtonRole?
  let action: () -> Void

  var body: some View {
    Button(role: role, action: action) {
      Label(title, systemImage: systemImage)
        .font(.system(size: 14))
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .foregroundStyle(role == .destructive ? .red : Color.accentColor)
    .padding(.horizontal, 14)
    .frame(minHeight: 42)
  }
}

private struct MacSettingsDivider: View {
  var body: some View {
    Divider()
      .padding(.leading, 14)
  }
}

private enum MacSettingsCardColor {
  static var fill: Color {
    Color(nsColor: .separatorColor).opacity(0.12)
  }
}

private struct KeyboardShortcutSettingsRow: View {
  let shortcutID: LatticeKeyboardShortcutID
  let shortcut: LatticeKeyboardShortcut?
  let onChange: (LatticeKeyboardShortcut) -> Void
  let onReset: () -> Void

  var body: some View {
    HStack(spacing: 12) {
      Text(shortcutID.displayName)
      Spacer(minLength: 12)
      KeyboardShortcutRecorder(
        shortcut: shortcut,
        onChange: onChange
      )
      .frame(width: 132)
      Button("Reset", action: onReset)
    }
  }
}

private struct KeyboardShortcutRecorder: NSViewRepresentable {
  let shortcut: LatticeKeyboardShortcut?
  let onChange: (LatticeKeyboardShortcut) -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator(parent: self)
  }

  func makeNSView(context: Context) -> ShortcutRecorderButton {
    let button = ShortcutRecorderButton()
    button.bezelStyle = .rounded
    button.target = context.coordinator
    button.action = #selector(Coordinator.beginRecording(_:))
    button.recorder = context.coordinator
    context.coordinator.update(button)
    return button
  }

  func updateNSView(_ button: ShortcutRecorderButton, context: Context) {
    context.coordinator.parent = self
    context.coordinator.update(button)
  }

  final class Coordinator: NSObject {
    var parent: KeyboardShortcutRecorder
    private weak var button: ShortcutRecorderButton?
    private var monitor: Any?
    private var isRecording = false

    init(parent: KeyboardShortcutRecorder) {
      self.parent = parent
    }

    deinit {
      if let monitor {
        NSEvent.removeMonitor(monitor)
      }
    }

    @MainActor
    func update(_ button: ShortcutRecorderButton) {
      self.button = button
      guard !isRecording else {
        button.title = "Type shortcut"
        return
      }
      button.title = parent.shortcut?.displayText ?? "Unassigned"
    }

    @MainActor
    @objc func beginRecording(_ sender: ShortcutRecorderButton) {
      if let monitor {
        NSEvent.removeMonitor(monitor)
        self.monitor = nil
      }
      isRecording = true
      button = sender
      sender.title = "Type shortcut"
      sender.window?.makeFirstResponder(sender)
      monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
        guard let self else {
          return event
        }

        if event.keyCode == 53 {
          MainActor.assumeIsolated {
            self.finishRecording()
          }
          return nil
        }

        guard let shortcut = Self.shortcut(from: event) else {
          MainActor.assumeIsolated {
            NSSound.beep()
          }
          return nil
        }

        MainActor.assumeIsolated {
          self.parent.onChange(shortcut)
          self.finishRecording()
        }
        return nil
      }
    }

    @MainActor
    private func finishRecording() {
      isRecording = false
      if let monitor {
        NSEvent.removeMonitor(monitor)
        self.monitor = nil
      }
      if let button {
        update(button)
      }
    }

    private static func shortcut(from event: NSEvent) -> LatticeKeyboardShortcut? {
      let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
      var modifiers = LatticeKeyboardModifiers()
      if flags.contains(.command) {
        modifiers.insert(.command)
      }
      if flags.contains(.shift) {
        modifiers.insert(.shift)
      }
      if flags.contains(.option) {
        modifiers.insert(.option)
      }
      if flags.contains(.control) {
        modifiers.insert(.control)
      }
      guard modifiers.contains(.command) || modifiers.contains(.option) || modifiers.contains(.control),
            let key = event.charactersIgnoringModifiers?.lowercased().first,
            let scalar = key.unicodeScalars.first,
            !CharacterSet.whitespacesAndNewlines.contains(scalar)
      else {
        return nil
      }
      return LatticeKeyboardShortcut(key: String(key), modifiers: modifiers)
    }
  }
}

private final class ShortcutRecorderButton: NSButton {
  weak var recorder: KeyboardShortcutRecorder.Coordinator?

  override var acceptsFirstResponder: Bool {
    true
  }
}
#endif

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
