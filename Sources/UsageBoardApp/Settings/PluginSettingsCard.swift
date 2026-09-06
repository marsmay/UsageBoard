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
                        .fixedSize(horizontal: false, vertical: true)
                    if let desc = plugin.metadata?.localizedDescription(language: language), !desc.isEmpty {
                        Text(desc)
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Toggle(strings.text(.enabled), isOn: enabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.mini)
                    .accessibilityLabel(strings.text(.enabled))
            }

            Divider()

            // Fields
            VStack(alignment: .leading, spacing: 0) {
                SettingsRow(label: strings.text(.name), labelWidth: 96) {
                    TextField(strings.text(.pluginNamePlaceholder), text: $plugin.name)
                        .textFieldStyle(.roundedBorder)
                }

                SettingsRow(label: strings.text(.script), labelWidth: 96) {
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
                        .help(strings.text(.chooseScript))
                        .accessibilityLabel(strings.text(.chooseScript))
                        Button {
                            onReloadMetadata()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.borderless)
                        .help(strings.text(.reloadMetadata))
                        .accessibilityLabel(strings.text(.reloadMetadata))
                    }
                }

                SettingsRow(label: strings.text(.refreshInterval), labelWidth: 96) {
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
        .controlSize(.small)
    }

    private func chooseExecutable() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = pluginsDirectoryURL
        if panel.runModal() == .OK, let url = panel.url {
            plugin.executablePath = url.path
            onReloadMetadata()
        }
    }
}

struct PluginParameterField: View {
    @Binding var plugin: PluginConfiguration
    var parameter: PluginParameterMetadata
    var language: AppLanguage

    var body: some View {
        SettingsRow(
            label: parameter.localizedLabel(language: language),
            labelWidth: 96,
            required: parameter.required
        ) {
            input
                .accessibilityLabel(parameter.localizedLabel(language: language))
        }
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
                .frame(width: 80)
        case .boolean:
            Toggle("", isOn: boolBinding)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
        case .choice:
            GeometryReader { geometry in
                Group {
                    if segmentedChoiceWidth <= geometry.size.width {
                        choicePicker
                            .pickerStyle(.segmented)
                            .frame(width: segmentedChoiceWidth)
                    } else {
                        choicePicker
                            .pickerStyle(.menu)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
            }
            .frame(height: 22)
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
                .accessibilityLabel(parameter.localizedLabel(language: language))
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
                .accessibilityLabel(parameter.localizedLabel(language: language))
            }
        }
    }

    private var choicePicker: some View {
        Picker("", selection: valueBinding) {
            ForEach(parameter.options) { option in
                Text(option.localizedLabel(language: language)).tag(option.value)
            }
        }
        .labelsHidden()
    }

    private var segmentedChoiceWidth: CGFloat {
        let font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        let labelWidth = parameter.options.map {
            ($0.localizedLabel(language: language) as NSString).size(withAttributes: [.font: font]).width
        }.reduce(0, +)
        return ceil(labelWidth + 20 * CGFloat(parameter.options.count))
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
