import AppKit
import SwiftUI
import UsageBoardCore

// MARK: - General Settings

struct GeneralSettingsView: View {
    @ObservedObject var store: UsageBoardStore
    private var strings: AppLocalization {
        .shared
    }

    var body: some View {
        SettingsSection {
            SettingsRow(label: strings.text(.launchAtLogin), hint: strings.text(.launchAtLoginHint)) {
                Toggle("", isOn: Binding(
                    get: { store.configuration.launchAtLogin },
                    set: { newValue in store.requestLaunchAtLogin(newValue) }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
                .accessibilityLabel(strings.text(.launchAtLogin))
                .frame(width: 120, alignment: .leading)
            }

            SettingsRow(label: strings.text(.displayMode), hint: strings.text(.displayModeHint)) {
                Picker("", selection: $store.configuration.overviewDisplayMode) {
                    ForEach(DisplayMode.allCases) { mode in
                        Text(strings.displayModeName(mode)).tag(mode)
                    }
                }
                .labelsHidden()
                .accessibilityLabel(strings.text(.displayMode))
                .frame(width: 120, alignment: .leading)
                .onChange(of: store.configuration.overviewDisplayMode) { _ in
                    store.persistConfiguration()
                }
            }

            SettingsRow(label: strings.text(.chartMode), hint: strings.text(.chartModeHint)) {
                Picker("", selection: $store.configuration.chartMode) {
                    ForEach(ChartMode.allCases) { mode in
                        Text(strings.chartModeName(mode)).tag(mode)
                    }
                }
                .labelsHidden()
                .accessibilityLabel(strings.text(.chartMode))
                .frame(width: 120, alignment: .leading)
                .onChange(of: store.configuration.chartMode) { _ in
                    store.persistConfiguration()
                }
            }

            SettingsRow(label: strings.text(.language)) {
                Picker("", selection: $store.configuration.language) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                }
                .labelsHidden()
                .accessibilityLabel(strings.text(.language))
                .frame(width: 120, alignment: .leading)
                .onChange(of: store.configuration.language) { newValue in
                    store.persistConfiguration()
                    if newValue != store.activeLanguage {
                        showRestartRequiredAlert()
                    }
                }
            }
        }
    }

    private func showRestartRequiredAlert() {
        let alert = NSAlert()
        alert.messageText = strings.text(.restartRequiredTitle)
        alert.informativeText = strings.text(.restartRequiredMessage)
        alert.alertStyle = .informational
        alert.addButton(withTitle: strings.text(.restartNow))
        alert.addButton(withTitle: strings.text(.restartLater))

        if alert.runModal() == .alertFirstButtonReturn {
            do {
                try AppRelauncher.relaunchCurrent()
                NSApp.terminate(nil)
            } catch {
                store.lastError = "\(strings.text(.relaunchFailed)): \(error.localizedDescription)"
            }
        }
    }
}
