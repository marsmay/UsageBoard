import AppKit
import SwiftUI
import UsageBoardCore

struct PluginSettingsCard: View {
    @Binding var plugin: PluginConfiguration
    var enabled: Binding<Bool>
    var pluginsDirectoryURL: URL
    var language: AppLanguage
    var displayName: String
    var onReloadMetadata: () -> Void
    var onRemove: () -> Void

    private var strings: AppLocalization {
        .shared
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(spacing: 10) {
                BrandTile(iconURL: plugin.metadata?.icon, fallbackName: displayName, size: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(displayName)
                        .font(UB.Font.detailTitle)
                    if let desc = plugin.metadata?.localizedDescription(language: language), !desc.isEmpty {
                        Text(desc)
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Toggle(strings.text(.enabled), isOn: enabled)
            }

            Divider()

            // Fields
            VStack(alignment: .leading, spacing: 0) {
                pluginRow(strings.text(.name)) {
                    TextField(strings.text(.pluginNamePlaceholder), text: $plugin.name)
                        .textFieldStyle(.roundedBorder)
                }

                pluginRow(strings.text(.script)) {
                    HStack(spacing: 4) {
                        TextField(strings.text(.scriptPathPlaceholder), text: $plugin.executablePath)
                            .textFieldStyle(.roundedBorder)
                        Button {
                            chooseExecutable()
                        } label: {
                            Image(systemName: "folder")
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.borderless)
                        Button {
                            onReloadMetadata()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.borderless)
                    }
                }

                pluginRow(strings.text(.refreshInterval)) {
                    HStack(spacing: 4) {
                        TextField(strings.text(.seconds), value: $plugin.refreshIntervalSeconds, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                        Text(strings.text(.seconds))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Plugin parameters
            if let metadata = plugin.metadata, !metadata.parameters.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text(strings.text(.pluginParameters).uppercased())
                        .font(.system(size: 11.5, weight: .semibold))
                        .tracking(0.4)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(metadata.parameters) { parameter in
                            PluginParameterField(plugin: $plugin, parameter: parameter, language: language)
                        }
                    }
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            } else {
                Text(strings.text(.noParameterMetadata))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func pluginRow<Content: View>(_ label: String, @ViewBuilder value: () -> Content) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .lineLimit(1)
                .frame(width: 100, alignment: .trailing)
                .foregroundStyle(.primary)
            value()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
    }

    private func chooseExecutable() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = pluginsDirectoryURL
        if panel.runModal() == .OK, let url = panel.url {
            plugin.executablePath = url.path
        }
    }
}

struct PluginParameterField: View {
    @Binding var plugin: PluginConfiguration
    var parameter: PluginParameterMetadata
    var language: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                HStack(spacing: 2) {
                    Text(parameter.localizedLabel(language: language))
                        .font(.system(size: 13))
                        .lineLimit(1)
                    if parameter.required {
                        Text("*")
                            .foregroundStyle(.red)
                    }
                }
                .frame(width: 100, alignment: .trailing)
                input
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var input: some View {
        switch parameter.type {
        case .secret:
            SecureField(parameter.localizedPlaceholder(language: language) ?? "", text: valueBinding)
                .textFieldStyle(.roundedBorder)
        case .integer:
            TextField(parameter.localizedPlaceholder(language: language) ?? "", text: valueBinding)
                .textFieldStyle(.roundedBorder)
                .frame(width: 160)
        case .boolean:
            Toggle("", isOn: boolBinding)
                .labelsHidden()
        case .choice:
            Picker("", selection: valueBinding) {
                ForEach(parameter.options) { option in
                    Text(option.localizedLabel(language: language)).tag(option.value)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        case .string:
            TextField(parameter.localizedPlaceholder(language: language) ?? "", text: valueBinding)
                .textFieldStyle(.roundedBorder)
        case .directory:
            HStack(spacing: 6) {
                TextField(parameter.localizedPlaceholder(language: language) ?? "", text: valueBinding)
                    .textFieldStyle(.roundedBorder)
                Button {
                    let panel = NSOpenPanel()
                    panel.title = parameter.localizedLabel(language: language)
                    panel.canChooseFiles = false
                    panel.canChooseDirectories = true
                    panel.allowsMultipleSelection = false
                    panel.canCreateDirectories = false
                    let current = valueBinding.wrappedValue
                    if !current.isEmpty {
                        let expanded = NSString(string: current).expandingTildeInPath
                        let url = URL(fileURLWithPath: expanded)
                        panel.directoryURL = url
                    }
                    if panel.runModal() == .OK, let url = panel.url {
                        valueBinding.wrappedValue = url.path
                    }
                } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(.borderless)
            }
        case .file:
            HStack(spacing: 6) {
                TextField(parameter.localizedPlaceholder(language: language) ?? "", text: valueBinding)
                    .textFieldStyle(.roundedBorder)
                Button {
                    let panel = NSOpenPanel()
                    panel.title = parameter.localizedLabel(language: language)
                    panel.canChooseFiles = true
                    panel.canChooseDirectories = false
                    panel.allowsMultipleSelection = false
                    if panel.runModal() == .OK, let url = panel.url {
                        valueBinding.wrappedValue = url.path
                    }
                } label: {
                    Image(systemName: "doc")
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private var valueBinding: Binding<String> {
        Binding(
            get: { plugin.parameterValues[parameter.name] ?? parameter.defaultValue ?? "" },
            set: { plugin.parameterValues[parameter.name] = $0 }
        )
    }

    private var boolBinding: Binding<Bool> {
        Binding(
            get: {
                let value = plugin.parameterValues[parameter.name] ?? parameter.defaultValue ?? "false"
                return ["1", "true", "yes", "on"].contains(value.lowercased())
            },
            set: { plugin.parameterValues[parameter.name] = $0 ? "true" : "false" }
        )
    }
}
