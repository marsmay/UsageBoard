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
                XCTAssertGreaterThan(host.fittingSize.height, readyHeight + 20)

                store.isUpdating = false
                store.updateMessage = language == .en ? "Update failed: connection interrupted. Try again." : "更新失败：连接中断，请重试。"
                try await Task.sleep(for: .milliseconds(150))
                host.layoutSubtreeIfNeeded()
                XCTAssertGreaterThan(host.fittingSize.height, readyHeight + 20, "Failure must remain visible after the spinner stops")
                XCTAssertLessThanOrEqual(host.fittingSize.width, 380)
                let output = FileManager.default.temporaryDirectory.appendingPathComponent("usageboard-update-\(language.rawValue)-\(appearance.rawValue).png")
                // ImageRenderer cannot render AppKit-backed borderless buttons;
                // capture only the changed SwiftUI controls for visual inspection.
                let availableUpdate = try XCTUnwrap(store.availableUpdate)
                let renderer = ImageRenderer(content: VStack(alignment: .leading, spacing: 0) {
                    UpdateBadgeButton(info: availableUpdate, store: store)
                        .padding(12)
                    UpdateStatusView(store: store)
                }
                    .frame(width: 380)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .environment(\.colorScheme, appearance == .darkAqua ? .dark : .light))
                renderer.scale = 2
                let rendered = try XCTUnwrap(renderer.cgImage)
                try XCTUnwrap(NSBitmapImageRep(cgImage: rendered).representation(using: .png, properties: [:])).write(to: output)

                store.updateMessage = nil
                try await Task.sleep(for: .milliseconds(100))
                host.layoutSubtreeIfNeeded()
                XCTAssertEqual(host.fittingSize.height, readyHeight, accuracy: 1)
            }
            await store.flushConfiguration()
        }
    }

    private func snapshot(_ view: NSView) throws -> Data {
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        return try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    }
}
