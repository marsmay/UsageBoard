import AppKit
import SwiftUI
import UsageBoardCore

// MARK: - Environment Key

private struct OpenSettingsKey: EnvironmentKey {
    nonisolated(unsafe) static let defaultValue: () -> Void = {}
}

extension EnvironmentValues {
    var openSettings: () -> Void {
        get { self[OpenSettingsKey.self] }
        set { self[OpenSettingsKey.self] = newValue }
    }
}

struct OverviewView: View {
    @ObservedObject var store: UsageBoardStore
    var maximumHeight: CGFloat
    @State private var headerHeight: CGFloat = 45

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    AppIconSquircle(size: 22)
                    Text("UsageBoard")
                        .font(UB.Font.popoverTitle)
                        .tracking(-0.1)
                    Spacer()
                    Button {
                        store.refreshAll()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 13, weight: .medium))
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.borderless)
                    .help(AppLocalization.shared.text(.refresh))
                    .accessibilityLabel(AppLocalization.shared.text(.refresh))
                    SettingsButton(iconSize: 13, buttonSize: 24)
                    QuitButton(language: store.activeLanguage, iconSize: 13, buttonSize: 24)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

                Divider()
            }
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: PopoverHeaderHeightKey.self, value: proxy.size.height)
                }
            )

            DashboardView(
                store: store,
                mode: store.configuration.overviewDisplayMode,
                maximumHeight: PopoverLayout.dashboardMaximumHeight(
                    popoverMaximumHeight: maximumHeight,
                    headerHeight: headerHeight
                )
            )
        }
        .frame(maxHeight: maximumHeight)
        .onPreferenceChange(PopoverHeaderHeightKey.self) { height in
            if height > 0, abs(headerHeight - height) > 0.5 {
                headerHeight = height
            }
        }
    }
}

enum PopoverLayout {
    static let width: CGFloat = 380
    static let initialHeight: CGFloat = 400
    static let maximumHeightRatio: CGFloat = 0.75

    static func maximumHeight(for visibleScreenHeight: CGFloat) -> CGFloat {
        max(visibleScreenHeight, 0) * maximumHeightRatio
    }

    static func dashboardMaximumHeight(popoverMaximumHeight: CGFloat, headerHeight: CGFloat) -> CGFloat {
        max(popoverMaximumHeight - max(headerHeight, 0), 0)
    }
}

private struct PopoverHeaderHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct SettingsButton: View {
    @Environment(\.openSettings) private var openSettings
    var iconSize: CGFloat = 13
    var buttonSize: CGFloat = 24

    var body: some View {
        Button {
            openSettings()
        } label: {
            Image(systemName: "gear")
                .font(.system(size: iconSize, weight: .medium))
                .frame(width: buttonSize, height: buttonSize)
        }
        .buttonStyle(.borderless)
        .help(AppLocalization.shared.text(.settingsWindowTitle))
        .accessibilityLabel(AppLocalization.shared.text(.settingsWindowTitle))
    }
}

struct QuitButton: View {
    var language: AppLanguage = .zhHans
    var iconSize: CGFloat = 13
    var buttonSize: CGFloat = 24
    private var strings: AppLocalization {
        .shared
    }

    var body: some View {
        Button {
            NSApp.terminate(nil)
        } label: {
            Image(systemName: "power")
                .font(.system(size: iconSize, weight: .medium))
                .frame(width: buttonSize, height: buttonSize)
        }
        .buttonStyle(.borderless)
        .help(strings.text(.quitUsageBoard))
        .accessibilityLabel(strings.text(.quitUsageBoard))
    }
}
