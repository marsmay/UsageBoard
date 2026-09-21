import AppKit
import SwiftUI
import UsageBoardCore
import XCTest
@testable import UsageBoardApp

@MainActor
final class SettingsSegmentsTests: XCTestCase {
    func testSelectionWritesOptionValueAndRefreshesFromBinding() async throws {
        let state = SelectionState()
        let options = ["Pro", "Max 5X", "Max 20X"].enumerated().map {
            PluginParameterOption(label: $0.element, value: String($0.offset))
        }
        let host = NSHostingView(rootView: SelectionFixture(state: state, options: options))
        let window = show(host, width: 420)
        defer { window.orderOut(nil); window.contentView = nil }
        try await Task.sleep(for: .milliseconds(100))
        let control = try XCTUnwrap(descendants(host).compactMap { $0 as? NSSegmentedControl }.first)
        XCTAssertEqual(control.selectedSegment, 0)
        XCTAssertEqual(control.accessibilityLabel(), "Plan")
        control.selectedSegment = 2
        control.sendAction(control.action, to: control.target)
        XCTAssertEqual(state.value, "2")
        state.value = "1"
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(control.selectedSegment, 1)
    }

    func testChoiceFitsOnFirstLayoutAndFallsBackForLongLabels() async throws {
        for longLabels in [false, true] {
            let options = (0..<3).map {
                PluginParameterOption(label: longLabels ? String(repeating: "Long option ", count: 8) + String($0) : ["Pro", "Max 5X", "Max 20X"][$0], value: String($0))
            }
            let parameter = PluginParameterMetadata(name: "PLAN", label: "Plan", type: .choice, defaultValue: "0", options: options)
            let host = NSHostingView(rootView: PluginParameterField(
                plugin: .constant(PluginConfiguration(name: "Fixture", executablePath: "")),
                parameter: parameter, language: .en
            ).controlSize(.regular))
            let window = show(host, width: 420)
            defer { window.orderOut(nil); window.contentView = nil }
            host.layoutSubtreeIfNeeded()
            let initialSegments = descendants(host).compactMap { $0 as? NSSegmentedControl }
            XCTAssertEqual(initialSegments.count, longLabels ? 0 : 1)
            let initialFrames = initialSegments.map(\.frame)
            try await Task.sleep(for: .milliseconds(150))
            let segments = descendants(host).compactMap { $0 as? NSSegmentedControl }
            XCTAssertEqual(segments.map(\.frame), initialFrames)
            if let control = segments.first {
                XCTAssertTrue(host.bounds.contains(control.convert(control.bounds, to: host)))
            }
        }
    }

    private func show(_ host: NSView, width: CGFloat) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 90), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        window.orderFront(nil)
        return window
    }

    private func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap { descendants($0) }
    }
}

@MainActor
private final class SelectionState: ObservableObject {
    @Published var value = "0"
}

@MainActor
private struct SelectionFixture: View {
    @ObservedObject var state: SelectionState
    var options: [PluginParameterOption]
    var body: some View {
        SettingsSegments(options: options.map(\.value), title: { value in options.first { $0.value == value }!.label }, selection: $state.value, label: "Plan")
            .fixedSize().padding(20)
    }
}
