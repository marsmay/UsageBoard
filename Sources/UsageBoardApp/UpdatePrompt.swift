import AppKit
import SwiftUI
import UsageBoardCore

/// 统一的"发现新版本"提示：图标 + 版本信息 + 更新内容卡片 + 胶囊按钮。
/// AboutView 手动检查、popover 指示灯胶囊和自动弹出提示共用。
/// 非模态浮动面板：不劫持事件循环，下载/安装期间 MainActor 正常工作。
enum UpdatePrompt {
    @MainActor
    private static var currentPanel: NSPanel?

    @MainActor
    static func present(info: UpdateInfo, store: UsageBoardStore) {
        if let panel = currentPanel {
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        guard !store.isUpdating else { return }
        let infoDictionary = Bundle.main.infoDictionary
        let version = infoDictionary?["CFBundleShortVersionString"] as? String
            ?? AppLocalization.shared.text(.unknownVersion)
        let currentVersion = (infoDictionary?["CFBundleVersion"] as? String)
            .map { "\(version) (\($0))" } ?? version

        // Defer one turn: presenting synchronously from a SwiftUI update cycle
        // (e.g. AboutView.onChange) wedges the new panel's event handling —
        // it renders but never receives clicks.
        DispatchQueue.main.async {
            presentPanel(info: info, currentVersion: currentVersion, store: store)
        }
    }

    @MainActor
    private static func presentPanel(info: UpdateInfo, currentVersion: String, store: UsageBoardStore) {
        guard currentPanel == nil else { return }
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 160),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            panel.standardWindowButton(button)?.isHidden = true
        }

        let view = UpdatePromptView(
            store: store,
            info: info,
            currentVersion: currentVersion,
            onLater: { [weak panel] in
                store.dismissUpdate(version: info.latestVersion)
                panel?.close()
            }
        )
        let controller = NSHostingController(rootView: view)
        panel.contentViewController = controller
        panel.setContentSize(controller.sizeThatFits(in: CGSize(width: 400, height: CGFloat.greatestFiniteMagnitude)))
        panel.center()

        // 浮在 popover（popUpMenu 层级）之上，非模态，不会被 modal 会话重置层级。
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 1)
        currentPanel = panel
        let observerBox = CloseObserverBox()
        observerBox.observer = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: panel, queue: .main
        ) { _ in
            MainActor.assumeIsolated { currentPanel = nil }
            if let observer = observerBox.observer {
                NotificationCenter.default.removeObserver(observer)
                observerBox.observer = nil
            }
        }

        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// 供 NotificationCenter 闭包按引用持有的观察令牌盒（面板关闭后自清理）。
private final class CloseObserverBox: @unchecked Sendable {
    var observer: NSObjectProtocol?
}

// MARK: - Prompt View

struct UpdatePromptView: View {
    @ObservedObject var store: UsageBoardStore
    let info: UpdateInfo
    let currentVersion: String
    let onLater: () -> Void
    @State private var didStartUpdate = false

    private var strings: AppLocalization {
        .shared
    }

    /// 新版本号带 build（version.json 提供 latestBuild 时）。
    private var latestVersionText: String {
        info.latestBuild.map { "\(info.latestVersion) (\($0))" } ?? info.latestVersion
    }

    /// 开始更新后，主按钮文字跟随当前阶段（下载中、安装中、更新失败）。
    private var primaryTitle: String {
        if store.isUpdating {
            switch store.updatePhase {
            case .downloading: return strings.text(.updatePhaseDownloading)
            case .installing: return strings.text(.updatePhaseInstalling)
            default: break
            }
        }
        if didStartUpdate, store.updatePhase == .failed {
            return strings.text(.updatePhaseFailed)
        }
        return strings.text(.updateNow)
    }

    /// 更新进行中禁用两个按钮；失败后可重试或稍后更新。
    private var buttonsDisabled: Bool {
        store.isUpdating
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                AppIconSquircle(size: 56)
                VStack(alignment: .leading, spacing: 4) {
                    Text(strings.updateAvailableTitle(latestVersion: latestVersionText))
                        .font(.system(size: 18, weight: .bold))
                    Text(strings.updateVersionSummary(currentVersion: currentVersion))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 6)
                Spacer()
            }

            if let notes = info.notes, !notes.isEmpty {
                Text(strings.text(.updateNotesTitle))
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.top, 16)

                ScrollView {
                    Text(notes)
                        .font(.system(size: 12))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(10)
                }
                .frame(maxHeight: 160)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                )
                .padding(.top, 8)
            }

            HStack(spacing: 10) {
                Spacer()
                Button(strings.text(.updateLater), action: onLater)
                    .buttonStyle(UpdatePromptSecondaryButtonStyle())
                    .keyboardShortcut(.cancelAction)
                    .disabled(buttonsDisabled)
                Button(primaryTitle) {
                    didStartUpdate = true
                    store.performUpdate()
                }
                .buttonStyle(UpdatePromptPrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
                .disabled(buttonsDisabled)
                .help(didStartUpdate && store.updatePhase == .failed ? (store.updateMessage ?? "") : "")
            }
            .padding(.top, 16)
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 20)
        .frame(width: 400)
    }
}

// MARK: - Button Styles

/// 深色填充胶囊（立即更新）。
private struct UpdatePromptPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Color(nsColor: .windowBackgroundColor))
            .padding(.horizontal, 18)
            .padding(.vertical, 7)
            .background(Capsule().fill(Color.primary.opacity(configuration.isPressed ? 0.75 : 1)))
    }
}

/// 描边胶囊（稍后更新）。
private struct UpdatePromptSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, 18)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.1 : 0.04))
            )
            .overlay(
                Capsule().stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            )
    }
}
