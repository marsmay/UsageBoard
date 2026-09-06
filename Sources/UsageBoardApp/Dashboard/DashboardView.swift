import SwiftUI
import UsageBoardCore

struct DashboardView: View {
    @ObservedObject var store: UsageBoardStore
    var mode: DisplayMode
    var maximumHeight: CGFloat

    private var enabledPlugins: [PluginConfiguration] {
        store.configuration.plugins.filter(\.enabled)
    }

    private var enabledPluginIDs: [UUID] {
        store.configuration.plugins.compactMap { $0.enabled ? $0.id : nil }
    }

    private var strings: AppLocalization {
        .shared
    }

    var body: some View {
        Group {
            if enabledPlugins.isEmpty {
                EmptyPluginsView(language: store.activeLanguage)
            } else {
                switch mode {
                case .grouped:
                    MeasuredScrollView(maxHeight: maximumHeight) {
                        VStack(spacing: 8) {
                            ForEach(enabledPlugins) { plugin in
                                PluginGroupView(
                                    snapshot: store.snapshot(for: plugin),
                                    language: store.activeLanguage,
                                    chartMode: store.configuration.chartMode,
                                    nextRefreshAt: store.nextRefreshAt[plugin.id]
                                ) {
                                    store.refresh(pluginID: plugin.id, force: true)
                                }
                            }
                        }
                        .padding(10)
                    }
                    .background(UB.Canvas.canvasBackground)
                case .tabs:
                    MeasuredScrollView(maxHeight: maximumHeight) {
                        VStack(spacing: 0) {
                            ScrollViewReader { proxy in
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 6) {
                                        ForEach(enabledPlugins) { plugin in
                                            Button {
                                                store.selectedTabID = plugin.id
                                            } label: {
                                                Text(store.snapshot(for: plugin).displayName)
                                                    .font(.callout.weight(store.selectedTabID == plugin.id ? .semibold : .regular))
                                                    .foregroundStyle(store.selectedTabID == plugin.id ? .primary : .secondary)
                                                    .padding(.horizontal, 10)
                                                    .padding(.vertical, 4)
                                                    .background(
                                                        RoundedRectangle(cornerRadius: 6)
                                                            .fill(store.selectedTabID == plugin.id ? Color(nsColor: .selectedControlColor) : .clear)
                                                    )
                                            }
                                            .buttonStyle(.plain)
                                            .id(plugin.id)
                                        }
                                    }
                                    .padding(.horizontal, 10)
                                }
                                .padding(.vertical, 6)
                                .onAppear {
                                    scrollToSelectedTab(with: proxy)
                                }
                                .onChange(of: store.selectedTabID) { _ in
                                    scrollToSelectedTab(with: proxy)
                                }
                                .onChange(of: enabledPluginIDs) { _ in
                                    scrollToSelectedTab(with: proxy)
                                }
                            }
                            Divider()
                            if let plugin = selectedPlugin {
                                PluginGroupView(
                                    snapshot: store.snapshot(for: plugin),
                                    language: store.activeLanguage,
                                    chartMode: store.configuration.chartMode,
                                    nextRefreshAt: store.nextRefreshAt[plugin.id]
                                ) {
                                    store.refresh(pluginID: plugin.id, force: true)
                                }
                                .padding(10)
                            }
                        }
                    }
                }
            }
        }
        .onAppear {
            ensureSelectedTab()
        }
        .onChange(of: enabledPluginIDs) { _ in
            ensureSelectedTab()
        }
        .toolbar {
            Button {
                store.refreshAll()
            } label: {
                Label(strings.text(.refresh), systemImage: "arrow.clockwise")
            }
            QuitButton(language: store.activeLanguage)
        }
    }

    private var selectedPlugin: PluginConfiguration? {
        if let selectedTabID = store.selectedTabID,
           let plugin = enabledPlugins.first(where: { $0.id == selectedTabID }) {
            return plugin
        }
        return enabledPlugins.first
    }

    private func ensureSelectedTab() {
        guard !enabledPlugins.isEmpty else {
            store.selectedTabID = nil
            return
        }
        if let selectedTabID = store.selectedTabID,
           enabledPlugins.contains(where: { $0.id == selectedTabID }) {
            return
        }
        let firstID = enabledPlugins.first?.id
        if store.selectedTabID != firstID {
            store.selectedTabID = firstID
        }
    }

    private func scrollToSelectedTab(with proxy: ScrollViewProxy) {
        guard let selectedTabID = store.selectedTabID else { return }
        withAnimation(.easeInOut(duration: 0.15)) {
            proxy.scrollTo(selectedTabID, anchor: .center)
        }
    }
}

struct EmptyPluginsView: View {
    @Environment(\.openSettings) private var openSettings
    var language: AppLanguage
    private var strings: AppLocalization {
        .shared
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "puzzlepiece.extension")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(strings.text(.noPluginsTitle))
                .font(.headline)
            Text(strings.text(.noPluginsDescription))
                .font(.callout)
                .foregroundStyle(.secondary)
            Button(strings.text(.settingsWindowTitle), action: openSettings)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
}
