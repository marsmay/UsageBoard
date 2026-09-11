import AppKit
import SwiftUI
import UsageBoardCore

// MARK: - Tab Enum

enum SettingsTab: CaseIterable, Identifiable {
    case general
    case plugins
    case about

    var id: Self { self }

    var icon: String {
        switch self {
        case .general: return "gear"
        case .plugins: return "powerplug"
        case .about: return "info.circle"
        }
    }
}

// MARK: - Main Settings View

struct SettingsView: View {
    @ObservedObject var store: UsageBoardStore
    @State private var selectedTab: SettingsTab = .general
    @State private var pluginDraft: PluginConfiguration?

    private var strings: AppLocalization {
        .shared
    }

    var body: some View {
        HStack(spacing: 0) {
            // Sidebar
            sidebar

            Divider()

            // Content
            VStack(spacing: 0) {
                // Page header
                pageHeader

                Divider()

                if let error = store.lastError {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Color.red.opacity(0.08))
                }

                // Content area
                switch selectedTab {
                case .general:
                    ScrollView {
                        GeneralSettingsView(store: store)
                            .padding(20)
                    }
                case .plugins:
                    PluginSettingsView(store: store, draft: $pluginDraft)
                case .about:
                    AboutView(store: store)
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                AppIconSquircle(size: 44)
                Text("UsageBoard")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 14)
            .padding(.bottom, 14)

            VStack(alignment: .leading, spacing: 2) {
                ForEach(SettingsTab.allCases) { tab in
                    sidebarItem(tab)
                }
            }
            .padding(.horizontal, 10)

            Spacer()
        }
        .frame(width: 188)
        .background(.regularMaterial)
    }

    private func sidebarItem(_ tab: SettingsTab) -> some View {
        Button {
            selectedTab = tab
        } label: {
            HStack(spacing: 8) {
                Image(systemName: tab.icon)
                    .font(.system(size: 13))
                    .frame(width: 16)
                Text(strings.tabTitle(tab))
                    .font(.system(size: 13))
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(selectedTab == tab ? Color.accentColor : Color.clear)
            )
            .foregroundStyle(selectedTab == tab ? Color.white : Color.primary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
    }

    // MARK: Page Header

    private var pageHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(strings.tabTitle(selectedTab))
                .font(.system(size: 20, weight: .semibold))
            Text(strings.tabSubtitle(selectedTab))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
