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
                let editMenu = try XCTUnwrap(app.mainMenu?.items.last?.submenu)
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
