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

    private func snapshot(_ view: NSView) throws -> Data {
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        return try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    }
}
