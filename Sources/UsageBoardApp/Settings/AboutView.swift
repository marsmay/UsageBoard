import AppKit
import SwiftUI
import UsageBoardCore

// MARK: - About View

struct AboutView: View {
    @ObservedObject var store: UsageBoardStore
    @State private var isUserChecking = false
    private var strings: AppLocalization {
        .shared
    }

    private var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? strings.text(.unknownVersion)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 22) {
            AppIconSquircle(size: 88)
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("UsageBoard")
                        .font(.system(size: 20, weight: .bold))
                        .tracking(-0.3)
                    Text(strings.text(.aboutDescription))
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }

                HStack(spacing: 10) {
                    Text(strings.text(.version))
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                    Text(currentVersion)
                        .font(.system(size: 12.5))
                        .monospacedDigit()
                    Button(store.isCheckingForUpdates ? strings.text(.checkingUpdate) : strings.text(.checkForUpdates)) {
                        isUserChecking = true
                        store.checkForUpdates()
                    }
                    .controlSize(.regular)
                    .disabled(store.isCheckingForUpdates || store.isUpdating)
                    if store.isCheckingForUpdates || store.isUpdating {
                        ProgressView()
                            .controlSize(.small)
                    } else if let updateMessage = store.updateMessage {
                        Text(updateMessage)
                            .font(.system(size: 11.5))
                            .fixedSize(horizontal: false, vertical: true)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            Spacer()
        }
        .padding(.horizontal, 32)
        .padding(.top, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: store.availableUpdate) { newValue in
            guard isUserChecking, let newValue else { return }
            isUserChecking = false
            showUpdateAlert(newValue)
        }
    }

    private func showUpdateAlert(_ info: UpdateInfo) {
        let alert = NSAlert()
        alert.messageText = strings.updateAvailableTitle(latestVersion: info.latestVersion)
        alert.informativeText = info.notes?.isEmpty == false
            ? info.notes!
            : strings.updateAvailableMessage(currentVersion: currentVersion, latestVersion: info.latestVersion)
        alert.addButton(withTitle: strings.text(.updateNow))
        alert.addButton(withTitle: strings.text(.cancel))
        alert.alertStyle = .informational

        if alert.runModal() == .alertFirstButtonReturn {
            store.performUpdate()
        }
    }
}
