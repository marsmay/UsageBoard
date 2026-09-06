import AppKit
import SwiftUI
import UsageBoardCore

// MARK: - General Settings

struct GeneralSettingsView: View {
    @ObservedObject var store: UsageBoardStore
    @State private var isRestartAlertPresented = false
    private var strings: AppLocalization {
        .shared
    }

    var body: some View {
        VStack(spacing: 20) {
            SettingsSection(title: strings.text(.appearanceSection)) {
                SettingsRow(label: strings.text(.theme)) {
                    Picker(strings.text(.theme), selection: Binding(
                        get: { store.configuration.theme },
                        set: { store.setTheme($0) }
                    )) {
                        ForEach(AppTheme.allCases) { theme in
                            Text(strings.themeName(theme)).tag(theme)
                        }
                    }
                    .pickerStyle(.segmented)
                    .controlSize(.small)
                    .labelsHidden()
                    .accessibilityLabel(strings.text(.theme))
                    .frame(width: 210, alignment: .trailing)
                }
                Divider().padding(.horizontal, 14)
                SettingsRow(label: strings.text(.displayMode), hint: strings.text(.displayModeHint)) {
                    Picker(strings.text(.displayMode), selection: $store.configuration.overviewDisplayMode) {
                        ForEach(DisplayMode.allCases) { mode in
                            Text(strings.displayModeName(mode)).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .controlSize(.small)
                    .labelsHidden()
                    .accessibilityLabel(strings.text(.displayMode))
                    .frame(width: 210, alignment: .trailing)
                    .onChange(of: store.configuration.overviewDisplayMode) { _ in
                        store.persistConfiguration()
                    }
                }
                Divider().padding(.horizontal, 14)
                SettingsRow(label: strings.text(.chartMode), hint: strings.text(.chartModeHint)) {
                    Picker(strings.text(.chartMode), selection: $store.configuration.chartMode) {
                        ForEach(ChartMode.allCases) { mode in
                            Text(strings.chartModeName(mode)).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .controlSize(.small)
                    .labelsHidden()
                    .accessibilityLabel(strings.text(.chartMode))
                    .frame(width: 210, alignment: .trailing)
                    .onChange(of: store.configuration.chartMode) { _ in
                        store.persistConfiguration()
                    }
                }
            }

            SettingsSection(title: strings.text(.behaviorSection)) {
                SettingsRow(label: strings.text(.launchAtLogin), hint: strings.text(.launchAtLoginHint)) {
                    Toggle(strings.text(.launchAtLogin), isOn: Binding(
                        get: { store.configuration.launchAtLogin },
                        set: { store.requestLaunchAtLogin($0) }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
                    .accessibilityLabel(strings.text(.launchAtLogin))
                }
                Divider().padding(.horizontal, 14)
                SettingsRow(label: strings.text(.language), hint: strings.text(.languageRestartHint)) {
                    Picker(strings.text(.language), selection: $store.configuration.language) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.displayName).tag(language)
                        }
                    }
                    .pickerStyle(.segmented)
                    .controlSize(.small)
                    .labelsHidden()
                    .accessibilityLabel(strings.text(.language))
                    .frame(width: 210, alignment: .trailing)
                    .onChange(of: store.configuration.language) { newValue in
                        store.persistConfiguration()
                        isRestartAlertPresented = newValue != store.activeLanguage
                    }
                }
            }
        }
        .alert(strings.text(.restartRequiredTitle), isPresented: $isRestartAlertPresented) {
            Button(strings.text(.restartNow)) {
                restartApplication()
            }
            Button(strings.text(.restartLater), role: .cancel) {}
        } message: {
            Text(strings.text(.restartRequiredMessage))
        }
    }

    private func restartApplication() {
        do {
            try AppRelauncher.relaunchCurrent()
            NSApp.terminate(nil)
        } catch {
            store.lastError = "\(strings.text(.relaunchFailed)): \(error.localizedDescription)"
        }
    }
}
