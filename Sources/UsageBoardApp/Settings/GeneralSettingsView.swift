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
                    SettingsSegments(
                        options: AppTheme.allCases,
                        title: strings.themeName,
                        selection: Binding(
                            get: { store.configuration.theme },
                            set: { store.setTheme($0) }
                        ),
                        label: strings.text(.theme)
                    )
                    .fixedSize()
                }
                Divider().padding(.horizontal, 14)
                SettingsRow(label: strings.text(.displayMode), hint: strings.text(.displayModeHint)) {
                    SettingsSegments(
                        options: DisplayMode.allCases,
                        title: strings.displayModeName,
                        selection: $store.configuration.overviewDisplayMode,
                        label: strings.text(.displayMode)
                    )
                    .fixedSize()
                    .onChange(of: store.configuration.overviewDisplayMode) { _ in
                        store.persistConfiguration()
                    }
                }
                Divider().padding(.horizontal, 14)
                SettingsRow(label: strings.text(.chartMode), hint: strings.text(.chartModeHint)) {
                    SettingsSegments(
                        options: ChartMode.allCases,
                        title: strings.chartModeName,
                        selection: $store.configuration.chartMode,
                        label: strings.text(.chartMode)
                    )
                    .fixedSize()
                    .onChange(of: store.configuration.chartMode) { _ in
                        store.persistConfiguration()
                    }
                }
            }

            SettingsSection(title: strings.text(.behaviorSection)) {
                SettingsRow(label: strings.text(.updateBadge), hint: strings.text(.updateBadgeHint)) {
                    Toggle(strings.text(.updateBadge), isOn: Binding(
                        get: { store.configuration.showUpdateBadge },
                        set: { store.setShowUpdateBadge($0) }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
                    .accessibilityLabel(strings.text(.updateBadge))
                }
                Divider().padding(.horizontal, 14)
                SettingsRow(label: strings.text(.launchAtLogin), hint: strings.text(.launchAtLoginHint)) {
                    Toggle(strings.text(.launchAtLogin), isOn: Binding(
                        get: { store.configuration.launchAtLogin },
                        set: { store.requestLaunchAtLogin($0) }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
                    .accessibilityLabel(strings.text(.launchAtLogin))
                }
                Divider().padding(.horizontal, 14)
                SettingsRow(label: strings.text(.language), hint: strings.text(.languageRestartHint)) {
                    SettingsSegments(
                        options: AppLanguage.allCases,
                        title: { $0.displayName },
                        selection: $store.configuration.language,
                        label: strings.text(.language)
                    )
                    .fixedSize()
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
