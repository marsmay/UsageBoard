import AppKit
import SwiftUI
import UsageBoardCore

/// 统一的"发现新版本"提示弹窗：立即更新，或稍后更新（跳过该版本，不再自动提示）。
/// AboutView 手动检查、popover 指示灯胶囊和自动弹出提示共用。
enum UpdatePrompt {
    @MainActor
    static func present(info: UpdateInfo, store: UsageBoardStore) {
        guard !store.isUpdating else { return }
        let strings = AppLocalization.shared
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
            ?? strings.text(.unknownVersion)
        let alert = NSAlert()
        alert.messageText = strings.updateAvailableTitle(latestVersion: info.latestVersion)
        alert.informativeText = info.notes?.isEmpty == false
            ? info.notes!
            : strings.updateAvailableMessage(currentVersion: currentVersion, latestVersion: info.latestVersion)
        alert.addButton(withTitle: strings.text(.updateNow))
        alert.addButton(withTitle: strings.text(.updateLater))
        alert.alertStyle = .informational
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            store.performUpdate()
        } else {
            store.dismissUpdate(version: info.latestVersion)
        }
    }
}

/// 所有更新入口共用的反馈，弹层和设置页均可看到进度与失败信息。
struct UpdateStatusView: View {
    @ObservedObject var store: UsageBoardStore

    var body: some View {
        if store.isCheckingForUpdates || store.isUpdating || store.updateMessage != nil {
            HStack(alignment: .top, spacing: 8) {
                if store.isCheckingForUpdates || store.isUpdating {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel(store.updateMessage ?? AppLocalization.shared.text(.checkingUpdate))
                }
                if let message = store.updateMessage {
                    Text(message)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.accentColor.opacity(0.06))
        }
    }
}
