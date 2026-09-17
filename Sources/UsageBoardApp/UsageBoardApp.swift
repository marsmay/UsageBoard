import Combine
import SwiftUI
import UsageBoardCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate, NSWindowDelegate {
    static var shared: AppDelegate!
    let store = UsageBoardStore()
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var globalClickMonitor: Any?
    private var localClickMonitor: Any?
    private var settingsWindowController: NSWindowController?
    private var themeSubscription: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.shared = self
        NSApp.setActivationPolicy(.accessory)
        themeSubscription = store.$configuration
            .map(\.theme)
            .removeDuplicates()
            .sink { [weak self] theme in
                NSApp.appearance = theme.appearance
                self?.popover?.appearance = theme.appearance
                self?.popover?.contentViewController?.view.appearance = theme.appearance
            }
        setupStatusItem()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // A MainActor Task may not run in the termination modal loop. Wait for
        // background saves synchronously, cancelling this quit if they time out.
        return store.flushConfigurationBlocking() ? .terminateNow : .terminateCancel
    }

    // MARK: - Status Item

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "chart.bar.xaxis", accessibilityDescription: "UsageBoard")
            button.action = #selector(togglePopover)
            button.target = self
        }
        statusItem = item
    }

    private func showPopover() {
        // 更新提示等 modal 会话期间禁止关闭/重建 popover：modal 事件循环会饿死
        // 弹层的 SwiftUI 布局测量，重建的弹层会卡在最小高度。
        guard NSApp.modalWindow == nil else {
            NSSound.beep()
            return
        }
        guard let button = statusItem?.button else { return }
        if let popover, popover.isShown {
            popover.performClose(nil)
            return
        }
        let newPopover = NSPopover()
        let visibleScreenHeight = button.window?.screen?.visibleFrame.height
            ?? NSScreen.main?.visibleFrame.height
            ?? 800
        let maximumHeight = PopoverLayout.maximumHeight(for: visibleScreenHeight)
        newPopover.contentSize = NSSize(
            width: PopoverLayout.width,
            height: min(PopoverLayout.initialHeight, maximumHeight)
        )
        newPopover.behavior = .applicationDefined
        newPopover.animates = false
        newPopover.delegate = self
        newPopover.appearance = store.configuration.theme.appearance
        let hostingController = NSHostingController(
            rootView: OverviewView(store: store, maximumHeight: maximumHeight)
                .environment(\.openSettings) { [weak self] in self?.openSettings() }
                .frame(width: PopoverLayout.width)
                .background(Color(nsColor: .windowBackgroundColor))
        )
        hostingController.view.appearance = store.configuration.theme.appearance
        newPopover.contentViewController = hostingController
        newPopover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover = newPopover
        startGlobalClickMonitor()
    }

    private func startGlobalClickMonitor() {
        stopGlobalClickMonitor()

        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            DispatchQueue.main.async {
                self?.closePopoverIfNeeded(event: event)
            }
        }

        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            self?.closePopoverIfNeeded(event: event)
            return event
        }
    }

    private func closePopoverIfNeeded(event: NSEvent) {
        // Keep the originating popover visible while interacting with an update alert.
        guard NSApp.modalWindow == nil else { return }
        guard let popover, popover.isShown else { return }
        if let button = statusItem?.button,
           let window = event.window,
           window === button.window {
            return
        }
        if let popoverWindow = popover.contentViewController?.view.window,
           let window = event.window,
           window === popoverWindow {
            return
        }
        popover.performClose(nil)
    }

    private func stopGlobalClickMonitor() {
        if let monitor = globalClickMonitor {
            NSEvent.removeMonitor(monitor)
            globalClickMonitor = nil
        }
        if let monitor = localClickMonitor {
            NSEvent.removeMonitor(monitor)
            localClickMonitor = nil
        }
    }

    @objc private func togglePopover() {
        showPopover()
    }

    // MARK: - Settings

    func openSettings() {
        // Close popover if open
        if let popover, popover.isShown {
            popover.performClose(nil)
        }
        // Bring existing window to front if it's still visible
        if let controller = settingsWindowController, let window = controller.window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        // Clean up any residual controller whose window is already closing
        settingsWindowController?.close()
        settingsWindowController = nil

        let settingsView = SettingsView(store: store)
            .frame(minWidth: 800, minHeight: 480)
        let hostingController = NSHostingController(rootView: settingsView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = AppLocalization.shared.text(.settingsWindowTitle)
        window.setContentSize(NSSize(width: 800, height: 520))
        window.minSize = NSSize(width: 800, height: 480)
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = false
        window.delegate = self
        window.center()
        let controller = NSWindowController(window: window)
        controller.showWindow(nil)
        settingsWindowController = controller
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - NSPopoverDelegate

    func popoverDidClose(_ notification: Notification) {
        // 只响应当前 popover 的关闭，忽略延迟到达的旧 popover 通知。
        guard let closed = notification.object as? NSPopover, closed === popover else { return }
        stopGlobalClickMonitor()
        popover = nil
    }

    // MARK: - NSWindowDelegate

    @objc func windowWillClose(_ notification: Notification) {
        settingsWindowController = nil
    }
}

@main
enum UsageBoardApplication {
    // 纯 AppKit 启动：不再声明 SwiftUI Settings scene——新版 macOS 会把
    // `Settings { EmptyView() }` 占位窗口在启动时直接显示出来。
    // 菜单栏、弹层和设置窗口均由 AppDelegate 用 AppKit 自建。
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
