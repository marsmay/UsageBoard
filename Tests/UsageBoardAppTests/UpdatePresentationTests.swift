import AppKit
import SwiftUI
import UsageBoardCore
import XCTest
@testable import UsageBoardApp

@MainActor
final class UpdatePresentationTests: XCTestCase {
    func testPopoverRetainsBadgeAfterLaterAndShowsUpdateFeedback() async throws {
        for language in AppLanguage.allCases {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("usageboard-update-ui-\(UUID())")
            defer { try? FileManager.default.removeItem(at: root) }
            let config = ConfigStore(fileURL: root.appendingPathComponent("config.json"))
            try config.save(AppConfiguration(language: language, autoUpdateCheck: false))
            let store = UsageBoardStore(configStore: config, stateStore: PluginStateStore(directoryURL: root.appendingPathComponent("states")))
            store.availableUpdate = UpdateInfo(latestVersion: "9.9.10", downloadURL: "https://example.com/update.zip")
            let host = NSHostingView(rootView: OverviewView(store: store, maximumHeight: 600).frame(width: 380))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 400), styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = host
            defer { window.contentView = nil }

            for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                host.appearance = NSAppearance(named: appearance)
                try await Task.sleep(for: .milliseconds(150))
                host.layoutSubtreeIfNeeded()
                let readyHeight = host.fittingSize.height
                let before = try snapshot(host)
                store.dismissUpdate(version: "9.9.10")
                try await Task.sleep(for: .milliseconds(150))
                host.layoutSubtreeIfNeeded()
                XCTAssertEqual(try snapshot(host), before, "Later must not change the visible badge")

                store.isUpdating = true
                store.updateMessage = language == .en ? "Downloading update…" : "正在下载更新…"
                try await Task.sleep(for: .milliseconds(150))
                host.layoutSubtreeIfNeeded()
                XCTAssertEqual(host.fittingSize.height, readyHeight, accuracy: 1,
                               "Update status must not shift popover layout")
                XCTAssertEqual(try snapshot(host), before, "Popover no longer renders update status")

                store.isUpdating = false
                store.updateMessage = language == .en ? "Update failed: connection interrupted. Try again." : "更新失败：连接中断，请重试。"
                try await Task.sleep(for: .milliseconds(150))
                host.layoutSubtreeIfNeeded()
                XCTAssertEqual(host.fittingSize.height, readyHeight, accuracy: 1)
                XCTAssertEqual(try snapshot(host), before)
                XCTAssertLessThanOrEqual(host.fittingSize.width, 380)
                let output = FileManager.default.temporaryDirectory.appendingPathComponent("usageboard-update-\(language.rawValue)-\(appearance.rawValue).png")
                // ImageRenderer cannot render AppKit-backed borderless buttons;
                // capture only the changed SwiftUI controls for visual inspection.
                let availableUpdate = try XCTUnwrap(store.availableUpdate)
                let renderer = ImageRenderer(content: UpdateBadgeButton(info: availableUpdate, store: store)
                    .padding(12)
                    .frame(width: 380, alignment: .leading)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .environment(\.colorScheme, appearance == .darkAqua ? .dark : .light))
                renderer.scale = 2
                let rendered = try XCTUnwrap(renderer.cgImage)
                try XCTUnwrap(NSBitmapImageRep(cgImage: rendered).representation(using: .png, properties: [:])).write(to: output)

                store.updateMessage = nil
                try await Task.sleep(for: .milliseconds(150))
                host.layoutSubtreeIfNeeded()
                XCTAssertEqual(host.fittingSize.height, readyHeight, accuracy: 1)
                XCTAssertEqual(try snapshot(host), before)
            }
            await store.flushConfiguration()
        }
    }

    func testUpdatePromptViewLaysOutInBothLanguagesAndAppearances() throws {
        let previous = AppLocalization.shared
        defer { AppLocalization.shared = previous }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("usageboard-prompt-ui-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let config = ConfigStore(fileURL: root.appendingPathComponent("config.json"))
        try config.save(AppConfiguration(autoUpdateCheck: false))
        let store = UsageBoardStore(configStore: config, stateStore: PluginStateStore(directoryURL: root.appendingPathComponent("states")))
        let notes = "1. First change;\n2. Second change;\n3. Third change."
        for language in AppLanguage.allCases {
            AppLocalization.shared = AppLocalization(language: language)
            for scheme in [ColorScheme.light, ColorScheme.dark] {
                let withNotes = UpdatePromptView(
                    store: store,
                    info: UpdateInfo(latestVersion: "1.0.20", downloadURL: "https://example.com/u.zip", notes: notes, latestBuild: 260911200),
                    currentVersion: "1.0.19 (2)", onLater: {}
                )
                let renderer = ImageRenderer(content: withNotes.environment(\.colorScheme, scheme))
                renderer.scale = 2
                let image = try XCTUnwrap(renderer.cgImage)
                XCTAssertEqual(image.width, 800, "Prompt width must stay fixed at 400pt @2x")
                XCTAssertGreaterThan(image.height, 300)

                let withoutNotes = UpdatePromptView(
                    store: store,
                    info: UpdateInfo(latestVersion: "1.0.20", downloadURL: "https://example.com/u.zip"),
                    currentVersion: "1.0.19 (2)", onLater: {}
                )
                let compactRenderer = ImageRenderer(content: withoutNotes.environment(\.colorScheme, scheme))
                compactRenderer.scale = 2
                let compact = try XCTUnwrap(compactRenderer.cgImage)
                XCTAssertEqual(compact.width, 800)
                XCTAssertLessThan(compact.height, image.height, "No notes means no notes card")
            }
        }
    }

    func testOpenPanelTracksNewResultAndClosesWhenUpdateDisappears() async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("usageboard-panel-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try makePromptStore(root: root)
        let first = UpdateInfo(latestVersion: "9.9.9", downloadURL: "https://example.com/first.zip")
        let second = UpdateInfo(latestVersion: "9.9.10", downloadURL: "https://example.com/second.zip", notes: "New release notes", latestBuild: 42)
        store.availableUpdate = first
        UpdatePrompt.present(info: first, store: store)
        try await Task.sleep(for: .milliseconds(100))
        let panel = try XCTUnwrap(promptPanels.first)
        defer { panel.close() }
        let host = try XCTUnwrap(panel.contentViewController as? NSHostingController<UpdatePromptView>)
        let firstHeight = panel.frame.height
        let staleLater = host.rootView.onLater

        // Automatic checks can replace the result without another present() call.
        store.availableUpdate = second
        staleLater()
        XCTAssertNil(store.configuration.dismissedUpdateVersion)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(host.rootView.info, second)
        XCTAssertGreaterThan(panel.frame.height, firstHeight, "New notes must fit in the existing panel")
        UpdatePrompt.present(info: second, store: store)
        XCTAssertEqual(promptPanels.count, 1)

        // Removing notes must shrink the existing panel again.
        store.availableUpdate = first
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(host.rootView.info, first)
        XCTAssertEqual(panel.frame.height, firstHeight, accuracy: 1)

        store.runUpdateCheck(url: URL(string: "https://example.com/version.json")!, automatic: true)
        for _ in 0..<100 where store.isCheckingForUpdates {
            try await Task.sleep(for: .milliseconds(10))
        }
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertNil(store.availableUpdate)
        XCTAssertFalse(panel.isVisible)

        // A closed panel must release its subscription and permit a new prompt.
        store.availableUpdate = second
        UpdatePrompt.present(info: second, store: store)
        try await Task.sleep(for: .milliseconds(100))
        let reopened = try XCTUnwrap(promptPanels.first)
        defer { reopened.close() }
        XCTAssertFalse(reopened === panel)
        let reopenedHost = try XCTUnwrap(reopened.contentViewController as? NSHostingController<UpdatePromptView>)
        reopenedHost.rootView.onLater()
        XCTAssertEqual(store.configuration.dismissedUpdateVersion, second.latestVersion)
        XCTAssertFalse(reopened.isVisible)
        await store.flushConfiguration()
    }

    func testDeferredPresentationRevalidatesCurrentResult() async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("usageboard-deferred-panel-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try makePromptStore(root: root)
        let info = UpdateInfo(latestVersion: "9.9.9", downloadURL: "https://example.com/u.zip")
        store.availableUpdate = info
        UpdatePrompt.present(info: info, store: store)
        store.availableUpdate = nil
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(promptPanels.isEmpty)
        await store.flushConfiguration()
    }

    func testUpdateRejectsStaleConfirmationAndInProgressCheck() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("usageboard-confirmation-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try makePromptStore(root: root)
        let first = UpdateInfo(latestVersion: "9.9.9", downloadURL: "https://example.com/first.zip")
        let replacement = UpdateInfo(latestVersion: "9.9.9", downloadURL: "https://example.com/replacement.zip")
        store.availableUpdate = replacement
        store.performUpdate(info: first)
        XCTAssertFalse(store.isUpdating, "Same version with a changed download must require fresh confirmation")
        XCTAssertEqual(store.updatePhase, .idle)

        store.runUpdateCheck(url: URL(string: "https://example.com/version.json")!, automatic: true)
        store.performUpdate(info: replacement)
        XCTAssertFalse(store.isUpdating, "Do not start installing while a check is in flight")
        for _ in 0..<100 where store.isCheckingForUpdates {
            try await Task.sleep(for: .milliseconds(10))
        }
        store.performUpdate(info: replacement)
        XCTAssertFalse(store.isUpdating, "A withdrawn update must not install")
        XCTAssertEqual(store.updatePhase, .idle)

        // A current confirmation still starts the downloader. An invalid scheme
        // fails locally, without making a request or installing anything.
        let invalid = UpdateInfo(latestVersion: "9.9.10", downloadURL: "http://example.com/u.zip")
        store.availableUpdate = invalid
        store.performUpdate(info: invalid)
        XCTAssertTrue(store.isUpdating)
        XCTAssertEqual(store.updatePhase, .downloading)
        for _ in 0..<100 where store.isUpdating {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertFalse(store.isUpdating)
        XCTAssertEqual(store.updatePhase, .failed)
        await store.flushConfiguration()
    }

    private var promptPanels: [NSPanel] {
        NSApp.windows.compactMap { $0 as? NSPanel }.filter {
            $0.isVisible && $0.contentViewController is NSHostingController<UpdatePromptView>
        }
    }

    private func makePromptStore(root: URL) throws -> UsageBoardStore {
        let config = ConfigStore(fileURL: root.appendingPathComponent("config.json"))
        try config.save(AppConfiguration(autoUpdateCheck: false))
        return UsageBoardStore(
            configStore: config,
            stateStore: PluginStateStore(directoryURL: root.appendingPathComponent("states")),
            updateChecker: NoAvailableUpdateChecker()
        )
    }

    private func snapshot(_ view: NSView) throws -> Data {
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        return try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    }
}

private struct NoAvailableUpdateChecker: UpdateChecking {
    func check(currentVersion: String, url: URL) async throws -> UpdateCheckResult {
        UpdateCheckResult(
            info: UpdateInfo(latestVersion: currentVersion, downloadURL: "https://example.com/u.zip"),
            hasUpdate: false
        )
    }
}
