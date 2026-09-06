import AppKit
import SwiftUI
import UsageBoardCore

// MARK: - Plugin Settings

struct PluginSettingsView: View {
    @ObservedObject var store: UsageBoardStore
    @State private var selectedPluginID: UUID?
    @State private var draggingPluginID: UUID?
    @Binding var draft: PluginConfiguration?
    @State private var searchText = ""
    private var strings: AppLocalization {
        .shared
    }

    private var hasChanges: Bool {
        guard let id = selectedPluginID,
              let original = store.configuration.plugins.first(where: { $0.id == id }),
              let draft else { return false }
        return draft.name != original.name
            || draft.executablePath != original.executablePath
            || draft.refreshIntervalSeconds != original.refreshIntervalSeconds
            || draft.parameterValues != original.parameterValues
            || draft.metadata != original.metadata
    }

    private var filteredPlugins: [PluginConfiguration] {
        guard !searchText.isEmpty else { return store.configuration.plugins }
        let needle = searchText.lowercased()
        return store.configuration.plugins.filter {
            PluginDisplayNames.displayName(for: $0, language: store.activeLanguage)
                .lowercased()
                .contains(needle)
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            // Plugin list sidebar
            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                    TextField(strings.text(.searchPlugins), text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11.5))
                }
                .padding(.horizontal, 8)
                .frame(height: 22)
                .background(Color.primary.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .padding(.horizontal, 10)
                .padding(.top, 10)
                .padding(.bottom, 6)

                ScrollView {
                    LazyVStack(spacing: 0) {
                        if filteredPlugins.isEmpty && !searchText.isEmpty {
                            Text(strings.text(.noSearchResults))
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .padding()
                        }
                        ForEach(filteredPlugins) { plugin in
                            pluginListRow(plugin)
                                .tag(plugin.id)
                                .onDrag {
                                    draggingPluginID = plugin.id
                                    return NSItemProvider(object: plugin.id.uuidString as NSString)
                                }
                                .onDrop(of: [.text], delegate: PluginDropDelegate(
                                    plugins: $store.configuration.plugins,
                                    targetID: plugin.id,
                                    draggingID: $draggingPluginID,
                                    onDropCompleted: {
                                        store.rebuildSnapshots()
                                        store.persistConfiguration()
                                    }
                                ))
                        }
                    }
                }
                .frame(maxHeight: .infinity)

                Divider()

                // Add/Remove buttons
                HStack(spacing: 4) {
                    Button {
                        choosePlugin()
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 12))
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.borderless)
                    .help(strings.text(.addPlugin))
                    .accessibilityLabel(strings.text(.addPlugin))

                    Button {
                        if let id = selectedPluginID {
                            store.removePlugin(id: id)
                            selectedPluginID = nil
                            draft = nil
                        }
                    } label: {
                        Image(systemName: "minus")
                            .font(.system(size: 12))
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.borderless)
                    .disabled(selectedPluginID == nil)
                    .help(strings.text(.removePlugin))
                    .accessibilityLabel(strings.text(.removePlugin))

                    Spacer()

                    Button {
                        NSWorkspace.shared.open(store.pluginsDirectoryURL)
                    } label: {
                        Image(systemName: "folder")
                            .font(.system(size: 12))
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.borderless)
                    .help(strings.text(.openPluginsFolder))

                    Button {
                        openPluginHelp()
                    } label: {
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 12))
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.borderless)
                    .help(strings.text(.pluginAuthoringGuide))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            .frame(width: 220)
            .frame(maxHeight: .infinity)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.7))

            Divider()

            // Plugin detail
            if let draft, draft.id == selectedPluginID {
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            PluginSettingsCard(
                                plugin: draftBinding,
                                enabled: pluginEnabledBinding(draft),
                                pluginsDirectoryURL: store.pluginsDirectoryURL,
                                language: store.activeLanguage,
                                displayName: PluginDisplayNames.displayName(for: draft, language: store.activeLanguage)
                            ) {
                                reloadDraftMetadata()
                            }
                        }
                        .padding(20)
                    }

                    Divider()

                    // Save / Reset buttons
                    HStack {
                        Spacer()
                        Button(strings.text(.reset)) {
                            loadDraft(for: draft.id)
                        }
                        .disabled(!hasChanges)
                        Button(strings.text(.save)) {
                            saveDraft()
                        }
                        .disabled(!hasChanges)
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut("s", modifiers: .command)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color(nsColor: .windowBackgroundColor).opacity(0.7))
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "puzzlepiece.extension")
                        .font(.system(size: 28))
                        .foregroundStyle(.tertiary)
                    Text(strings.text(.selectPlugin))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minHeight: 400)
        .onAppear {
            if let draft, store.configuration.plugins.contains(where: { $0.id == draft.id }) {
                selectedPluginID = draft.id
            } else if let id = store.configuration.plugins.first?.id {
                loadDraft(for: id)
            }
        }
    }

    private var draftBinding: Binding<PluginConfiguration> {
        Binding(
            get: { draft ?? PluginConfiguration(name: "", executablePath: "") },
            set: { draft = $0 }
        )
    }

    private func loadDraft(for id: UUID) {
        selectedPluginID = id
        if let plugin = store.configuration.plugins.first(where: { $0.id == id }) {
            draft = plugin
        }
    }

    @discardableResult
    private func saveDraft() -> Bool {
        if let draft,
           let original = store.configuration.plugins.first(where: { $0.id == draft.id }),
           original.executablePath != draft.executablePath {
            reloadDraftMetadata()
        }
        guard let draft, store.updatePlugin(draft) else { return false }
        self.draft = store.configuration.plugins.first(where: { $0.id == draft.id })
        return true
    }

    private func selectPlugin(_ id: UUID) {
        guard id != selectedPluginID else { return }
        guard resolveUnsavedChanges() else { return }
        loadDraft(for: id)
    }

    private func resolveUnsavedChanges() -> Bool {
        if hasChanges {
            let alert = NSAlert()
            alert.messageText = strings.text(.unsavedChanges)
            alert.addButton(withTitle: strings.text(.save))
            alert.addButton(withTitle: strings.text(.discardChanges))
            alert.addButton(withTitle: strings.text(.cancel))
            switch alert.runModal() {
            case .alertFirstButtonReturn:
                guard saveDraft() else { return false }
            case .alertSecondButtonReturn: break
            default: return false
            }
        }
        return true
    }

    private func reloadDraftMetadata() {
        guard let draft else { return }
        let fileURL = URL(fileURLWithPath: draft.executablePath)
        let metadata = PluginMetadataParser.parse(fileURL: fileURL)
        var updated = draft
        updated.metadata = metadata
        for parameter in metadata?.parameters ?? [] where updated.parameterValues[parameter.name] == nil {
            updated.parameterValues[parameter.name] = parameter.defaultValue ?? ""
        }
        self.draft = updated
    }

    private func pluginListRow(_ plugin: PluginConfiguration) -> some View {
        HStack(spacing: 8) {
            Button { selectPlugin(plugin.id) } label: {
                HStack(spacing: 8) {
                    BrandTile(
                        iconURL: plugin.metadata?.icon,
                        fallbackName: PluginDisplayNames.displayName(for: plugin, language: store.activeLanguage),
                        size: 22
                    )
                    Text(PluginDisplayNames.displayName(for: plugin, language: store.activeLanguage))
                        .font(.system(size: 12.5, weight: selectedPluginID == plugin.id ? .semibold : .regular))
                        .foregroundStyle(plugin.enabled ? Color.primary : Color.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selectedPluginID == plugin.id ? .isSelected : [])
            Toggle("", isOn: pluginEnabledBinding(plugin))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .accessibilityLabel("\(strings.text(.enabled)) \(store.displayNames[plugin.id] ?? PluginDisplayNames.displayName(for: plugin, language: store.activeLanguage))")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(selectedPluginID == plugin.id ? Color.accentColor.opacity(0.16) : Color.clear)
        )
        .contentShape(Rectangle())
    }

    private func pluginEnabledBinding(_ plugin: PluginConfiguration) -> Binding<Bool> {
        Binding(
            get: {
                store.configuration.plugins.first(where: { $0.id == plugin.id })?.enabled ?? false
            },
            set: { newValue in
                store.setPluginEnabled(id: plugin.id, enabled: newValue)
                if draft?.id == plugin.id {
                    draft?.enabled = newValue
                }
            }
        )
    }

    private func choosePlugin() {
        guard resolveUnsavedChanges() else { return }
        store.ensurePluginsDirectory()
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = store.pluginsDirectoryURL
        if panel.runModal() == .OK, let url = panel.url {
            store.addPlugin(fileURL: url)
            let newID = store.configuration.plugins.last?.id
            selectedPluginID = newID
            if let newID { loadDraft(for: newID) }
        }
    }

    private func openPluginHelp() {
        if let url = Bundle.main.url(forResource: "PluginAuthoringGuide", withExtension: "html") {
            NSWorkspace.shared.open(url)
            return
        }

        let developmentURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Resources/PluginAuthoringGuide.html")
        if FileManager.default.fileExists(atPath: developmentURL.path) {
            NSWorkspace.shared.open(developmentURL)
            return
        }

        store.lastError = store.activeLanguage == .en
            ? "Plugin authoring guide was not found"
            : "未找到插件编写说明文档"
    }
}

// MARK: - Drag & Drop

struct PluginDropDelegate: DropDelegate {
    @Binding var plugins: [PluginConfiguration]
    let targetID: UUID
    @Binding var draggingID: UUID?
    var onDropCompleted: () -> Void

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let draggingID else { return false }
        guard let fromIndex = plugins.firstIndex(where: { $0.id == draggingID }),
              let toIndex = plugins.firstIndex(where: { $0.id == targetID }),
              fromIndex != toIndex else {
            self.draggingID = nil
            return false
        }
        let moved = plugins.remove(at: fromIndex)
        plugins.insert(moved, at: toIndex)
        self.draggingID = nil
        onDropCompleted()
        return true
    }
}
