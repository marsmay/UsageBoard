import AppKit
import SwiftUI
import UsageBoardCore
import XCTest
@testable import UsageBoardApp

@MainActor
final class AppMenuTests: XCTestCase {
    func testSelectAllCommandSelectsPlainAndSecureSwiftUIFields() async throws {
        let app = NSApplication.shared
        let originalMenu = app.mainMenu
        defer { app.mainMenu = originalMenu }

        for language in AppLanguage.allCases {
            app.mainMenu = AppMenu.make(strings: AppLocalization(language: language))
            for secure in [false, true] {
                let host = NSHostingView(rootView: MenuFieldFixture(secure: secure))
                let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 100),
                                      styleMask: [.titled], backing: .buffered, defer: false)
                window.contentView = host
                defer { window.orderOut(nil); window.contentView = nil }
                try await Task.sleep(for: .milliseconds(100))
                let field = try XCTUnwrap(descendants(host).compactMap { $0 as? NSTextField }.first)
                XCTAssertTrue(window.makeFirstResponder(field))
                let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
                editor.setSelectedRange(NSRange(location: 3, length: 0))
                let event = try XCTUnwrap(NSEvent.keyEvent(
                    with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
                    windowNumber: window.windowNumber, context: nil, characters: "a",
                    charactersIgnoringModifiers: "a", isARepeat: false, keyCode: 0
                ))
                // XCTest does not run NSApplication's event loop or establish a key window.
                // Supply the field editor explicitly to exercise the real menu command.
                let editMenu = try XCTUnwrap(app.mainMenu?.items.dropFirst().first?.submenu)
                let selectAll = try XCTUnwrap(editMenu.items.first { $0.keyEquivalent == "a" })
                XCTAssertNil(selectAll.target, "Production commands must use the responder chain")
                selectAll.target = editor
                XCTAssertTrue(editMenu.performKeyEquivalent(with: event))
                selectAll.target = nil
                XCTAssertEqual(editor.selectedRange(), NSRange(location: 0, length: 15),
                               "Command-A must reach the focused field (secure: \(secure), language: \(language))")
            }
        }
    }

    func testMenuProvidesSettingsCommandAndWindowCommands() throws {
        let app = NSApplication.shared
        let originalMenu = app.mainMenu
        defer { app.mainMenu = originalMenu }

        app.mainMenu = AppMenu.make(strings: AppLocalization(language: .en))

        let appMenu = try XCTUnwrap(app.mainMenu?.items.first?.submenu)
        let settingsItem = try XCTUnwrap(appMenu.items.first { $0.keyEquivalent == "," })
        XCTAssertEqual(settingsItem.title, "Settings…")
        XCTAssertNil(settingsItem.target, "Settings command must use the responder chain")

        let windowMenu = try XCTUnwrap(app.mainMenu?.items.first { $0.submenu?.title == "Window" }?.submenu)
        let close = try XCTUnwrap(windowMenu.items.first { $0.keyEquivalent == "w" })
        let minimize = try XCTUnwrap(windowMenu.items.first { $0.keyEquivalent == "m" })
        XCTAssertNil(close.target)
        XCTAssertNil(minimize.target)
    }

    private func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }
}

private struct MenuFieldFixture: View {
    var secure: Bool
    @State private var value = "probe-only-text"

    var body: some View {
        Group {
            if secure {
                SecureField("Test", text: $value)
            } else {
                TextField("Test", text: $value)
            }
        }
        .padding()
    }
}
