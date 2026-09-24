import SwiftUI
import UsageBoardCore

// MARK: - About View

struct AboutView: View {
    @ObservedObject var store: UsageBoardStore
    private var strings: AppLocalization {
        .shared
    }

    private var currentVersion: String {
        let infoDictionary = Bundle.main.infoDictionary
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? strings.text(.unknownVersion)
        guard let build = infoDictionary?["CFBundleVersion"] as? String, !build.isEmpty else { return version }
        return "\(version) (\(build))"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                AppIconSquircle(size: 64)
                    .padding(.bottom, 14)
                Text("UsageBoard")
                    .font(.system(size: 23, weight: .semibold))
                Text(strings.text(.aboutDescription))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
                Text(currentVersion)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .padding(.top, 10)

                Link("usageboard.may.ltd", destination: URL(string: "https://usageboard.may.ltd")!)
                    .font(.system(size: 12))
                    .tint(.blue)
                    .padding(.top, 6)

                Button(store.isCheckingForUpdates ? strings.text(.checkingUpdate) : strings.text(.checkForUpdates)) {
                    store.checkForUpdates { info in
                        UpdatePrompt.present(info: info, store: store)
                    }
                }
                .buttonStyle(CheckForUpdatesButtonStyle())
                .disabled(store.isCheckingForUpdates || store.isUpdating)
                .padding(.top, 22)

                VStack(spacing: 8) {
                    if store.isCheckingForUpdates || store.isUpdating {
                        ProgressView().controlSize(.small)
                    }
                    if let message = store.updateMessage {
                        Text(message)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                }
                .padding(.top, 12)
            }
            .frame(maxWidth: 360)
            .padding(28)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct CheckForUpdatesButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(Capsule().fill(Color.blue.opacity(configuration.isPressed ? 0.8 : 1)))
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(Capsule())
    }
}
