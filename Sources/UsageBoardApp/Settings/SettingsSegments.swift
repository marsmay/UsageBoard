import AppKit
import SwiftUI

struct SettingsSegments<Selection: Hashable>: NSViewRepresentable {
    var options: [Selection]
    var title: (Selection) -> String
    @Binding var selection: Selection
    var label: String
    @Environment(\.isEnabled) private var isEnabled

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl()
        control.segmentStyle = .rounded
        control.selectedSegmentBezelColor = .controlAccentColor
        control.segmentDistribution = .fillEqually
        control.trackingMode = .selectOne
        control.controlSize = .regular
        control.font = .systemFont(ofSize: NSFont.systemFontSize)
        control.target = context.coordinator
        control.action = #selector(Coordinator.select(_:))
        return control
    }

    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        context.coordinator.parent = self
        control.segmentCount = options.count
        for (index, option) in options.enumerated() {
            control.setLabel(title(option), forSegment: index)
        }
        control.selectedSegment = options.firstIndex(of: selection) ?? -1
        control.isEnabled = isEnabled
        control.setAccessibilityLabel(label)
        control.invalidateIntrinsicContentSize()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSSegmentedControl, context: Context) -> CGSize? {
        // Use AppKit's measured size so ViewThatFits can choose the menu before rendering.
        nsView.intrinsicContentSize
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    @MainActor
    final class Coordinator: NSObject {
        var parent: SettingsSegments

        init(parent: SettingsSegments) {
            self.parent = parent
        }

        @objc func select(_ sender: NSSegmentedControl) {
            guard parent.options.indices.contains(sender.selectedSegment) else { return }
            parent.selection = parent.options[sender.selectedSegment]
        }
    }
}
