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

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.shared = self
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
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
        guard let button = statusItem?.button else { return }
        if let popover, popover.isShown {
            popover.performClose(nil)
            return
        }
        let newPopover = NSPopover()
        newPopover.contentSize = NSSize(width: 380, height: 400)
        newPopover.behavior = .applicationDefined
        newPopover.animates = false
        newPopover.delegate = self
        newPopover.appearance = NSApp.effectiveAppearance
        let hostingController = NSHostingController(
            rootView: OverviewView(store: store)
                .environment(\.openSettings) { [weak self] in self?.openSettings() }
                .frame(width: 380)
                .background(Color(nsColor: .windowBackgroundColor))
        )
        hostingController.view.appearance = NSApp.effectiveAppearance
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
        stopGlobalClickMonitor()
        popover = nil
    }

    // MARK: - NSWindowDelegate

    @objc func windowWillClose(_ notification: Notification) {
        settingsWindowController = nil
    }
}

@main
struct UsageBoardApplication: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}
