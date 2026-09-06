import AppKit
import SwiftUI
import UsageBoardCore
import XCTest
@testable import UsageBoardApp

@MainActor
final class LanguageSettingsTests: XCTestCase {
    func testLanguagePromptCanDeferAndPreservesSelection() async throws {
        for activeLanguage in AppLanguage.allCases {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("usageboard-language-\(UUID())")
            defer { try? FileManager.default.removeItem(at: root) }
            let config = ConfigStore(fileURL: root.appendingPathComponent("config.json"))
            try config.save(AppConfiguration(language: activeLanguage))
            let store = UsageBoardStore(configStore: config, stateStore: PluginStateStore(directoryURL: root.appendingPathComponent("states")))
            let strings = AppLocalization(language: activeLanguage)
            let host = NSHostingView(rootView: GeneralSettingsView(store: store).padding(20))
            let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 612, height: 460), styleMask: [.titled], backing: .buffered, defer: false)
            window.contentView = host
            window.orderFront(nil)
            defer { window.orderOut(nil); window.contentView = nil }
            try await Task.sleep(for: .milliseconds(200))
            XCTAssertNil(window.attachedSheet)

            let selectedLanguage: AppLanguage = activeLanguage == .zhHans ? .en : .zhHans
            store.configuration.language = selectedLanguage
            try await Task.sleep(for: .milliseconds(300))
            let sheet = try XCTUnwrap(window.attachedSheet)
            let buttons = descendants(of: try XCTUnwrap(sheet.contentView)).compactMap { $0 as? NSButton }
            let later = try XCTUnwrap(buttons.first { $0.title == strings.text(.restartLater) })
            XCTAssertEqual(buttons.filter { !$0.title.isEmpty }.map(\.title).sorted(),
                           [strings.text(.restartNow), strings.text(.restartLater)].sorted())
            later.performClick(nil)
            try await Task.sleep(for: .milliseconds(300))
            XCTAssertNil(window.attachedSheet)
            await store.flushConfiguration()
            XCTAssertEqual(try config.load().language, selectedLanguage)
            XCTAssertEqual(store.activeLanguage, activeLanguage)

            store.configuration.language = activeLanguage
            try await Task.sleep(for: .milliseconds(300))
            XCTAssertNil(window.attachedSheet, "Returning to the active language does not require a restart")
            await store.flushConfiguration()
            XCTAssertEqual(try config.load().language, activeLanguage)
        }
    }

    private func descendants(of view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap { descendants(of: $0) }
    }
}
