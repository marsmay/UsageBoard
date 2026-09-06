import AppKit
import SwiftUI
import XCTest
import UsageBoardCore
@testable import UsageBoardApp

@MainActor
final class AppThemeTests: XCTestCase {
    func testLiveApplicationAppearanceReachesExistingSwiftUIView() async throws {
        _ = NSApplication.shared
        let original = NSApp.appearance
        defer { NSApp.appearance = original }
        var observed: ColorScheme?
        let host = NSHostingView(rootView: SchemeProbe(report: { observed = $0 }))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 120, height: 100), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        defer { window.contentView = nil }
        for theme in [AppTheme.light, .dark, .light, .system] {
            NSApp.appearance = theme.appearance
            try await Task.sleep(for: .milliseconds(200))
            let expected: ColorScheme = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .dark : .light
            XCTAssertEqual(observed, expected)
        }
        XCTAssertNil(NSApp.appearance)
    }

    func testLegacyConfigurationFollowsSystemAndThemesRoundTrip() throws {
        let legacy = try UsageBoardJSON.decoder().decode(AppConfiguration.self, from: Data("{}".utf8))
        XCTAssertEqual(legacy.theme, .system)
        for theme in AppTheme.allCases {
            let data = try UsageBoardJSON.encoder().encode(AppConfiguration(theme: theme))
            let decoded = try UsageBoardJSON.decoder().decode(AppConfiguration.self, from: data)
            XCTAssertEqual(decoded.theme, theme)
        }
    }

    func testStorePersistsThemeAndRestoresItOnNextLaunch() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("usageboard-theme-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let config = ConfigStore(fileURL: root.appendingPathComponent("config.json"))
        try config.save(AppConfiguration(theme: .dark))
        let states = PluginStateStore(directoryURL: root.appendingPathComponent("states"))
        let store = UsageBoardStore(configStore: config, stateStore: states)
        XCTAssertEqual(store.configuration.theme, .dark)
        store.setTheme(.light)
        store.setTheme(.system)
        await store.flushConfiguration()
        XCTAssertEqual(try config.load().theme, .system)
        let restored = UsageBoardStore(configStore: config, stateStore: states)
        XCTAssertEqual(restored.configuration.theme, .system)
    }

    func testSystemThemeReleasesExplicitAppearanceOverride() {
        XCTAssertEqual(AppTheme.light.appearance?.name, .aqua)
        XCTAssertEqual(AppTheme.dark.appearance?.name, .darkAqua)
        XCTAssertNil(AppTheme.system.appearance)
    }
}

private struct SchemeProbe: View {
    @Environment(\.colorScheme) var scheme
    var report: (ColorScheme) -> Void
    var body: some View {
        Color(nsColor: .windowBackgroundColor)
            .task(id: scheme) { report(scheme) }
    }
}
