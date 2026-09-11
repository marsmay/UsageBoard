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

                Button(store.isCheckingForUpdates ? strings.text(.checkingUpdate) : strings.text(.checkForUpdates)) {
                    isUserChecking = true
                    store.checkForUpdates()
                }
                .controlSize(.large)
                .disabled(store.isCheckingForUpdates || store.isUpdating)
                .padding(.top, 22)
            }
            .frame(maxWidth: 360)
            .padding(28)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: store.availableUpdate) { newValue in
            guard isUserChecking, let newValue else { return }
            isUserChecking = false
            UpdatePrompt.present(info: newValue, store: store)
        }
    }
}
