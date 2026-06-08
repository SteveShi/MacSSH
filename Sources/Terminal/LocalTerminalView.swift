import SwiftUI
import libghostty_swift

struct LocalTerminalView: View {
    let settings: AppSettings
    @Bindable var appModel: AppModel
    @State private var hoveredTabID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            if !appModel.localTabs.isEmpty {
                tabBarContainer
            }
            content
        }
        .navigationTitle(selectedTabName)
        .onAppear {
            if appModel.localTabs.isEmpty {
                appModel.restoreLocalTabs(settings: settings)
                if appModel.localTabs.isEmpty {
                    addTab()
                }
            }
        }
        .sheet(item: renamingTab) { tab in
            RenameTabSheet(tab: tab, appModel: appModel)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if appModel.localTabs.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            // All surfaces stay mounted so PTYs survive tab switching; only the
            // selected one is visible and interactive.
            ZStack {
                ForEach(appModel.localTabs) { tab in
                    SurfaceViewHost(surface: tab.surfaceView)
                        .opacity(tab.id == appModel.selectedLocalTabID ? 1 : 0)
                        .allowsHitTesting(tab.id == appModel.selectedLocalTabID)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea(.container, edges: .bottom)
        }
    }

    // MARK: - Tab bar (Liquid Glass on macOS 26+, material fallback below)

    @ViewBuilder
    private var tabBarContainer: some View {
        if #available(macOS 26, *) {
            glassTabBar
        } else {
            flatTabBar
                .overlay(Divider(), alignment: .bottom)
        }
    }

    @available(macOS 26, *)
    private var glassTabBar: some View {
        GlassEffectContainer(spacing: 4) {
            HStack(spacing: 4) {
                ForEach(appModel.localTabs) { tab in
                    decorate(tab, tabLabel(tab).glassEffect(glass(for: tab), in: .capsule))
                }

                Button {
                    addTab()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 30, height: 30)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .circle)
                .help(String(localized: "New Tab"))
                .keyboardShortcut("t", modifiers: .command)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
        }
    }

    @available(macOS 26, *)
    private func glass(for tab: LocalTerminalTab) -> Glass {
        tab.id == appModel.selectedLocalTabID
            ? .regular.tint(.accentColor.opacity(0.55)).interactive()
            : .regular.interactive()
    }

    private var flatTabBar: some View {
        HStack(spacing: 0) {
            ForEach(appModel.localTabs) { tab in
                let isSelected = tab.id == appModel.selectedLocalTabID
                let isHovered = hoveredTabID == tab.id
                decorate(
                    tab,
                    tabLabel(tab)
                        .background(isSelected
                                    ? Color.primary.opacity(0.10)
                                    : (isHovered ? Color.primary.opacity(0.04) : Color.clear))
                        .overlay(alignment: .trailing) {
                            Divider()
                                .frame(height: 14)
                                .opacity(isSelected ? 0 : 1)
                        }
                )
            }

            Button {
                addTab()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(String(localized: "New Tab"))
            .keyboardShortcut("t", modifiers: .command)
            .padding(.horizontal, 2)
        }
        .frame(height: 28)
        .background(.bar)
    }

    // MARK: - Shared tab cell

    /// Visual content of a tab: centered title + a leading close button on hover.
    private func tabLabel(_ tab: LocalTerminalTab) -> some View {
        let isSelected = tab.id == appModel.selectedLocalTabID
        let isHovered = hoveredTabID == tab.id
        let canClose = appModel.localTabs.count > 1

        return ZStack {
            Text(tab.name)
                .font(.system(size: 12, weight: isSelected ? .medium : .regular))
                .foregroundStyle(isSelected ? .primary : .secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, 24)

            HStack {
                Button {
                    closeTab(tab)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .frame(width: 16, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .opacity(isHovered && canClose ? 1 : 0)
                .padding(.leading, 6)
                Spacer(minLength: 0)
            }
        }
        .frame(minWidth: 60, maxWidth: .infinity)
        .frame(height: 28)
    }

    /// Adds selection / hover / context-menu behavior shared by both styles.
    private func decorate(_ tab: LocalTerminalTab, _ content: some View) -> some View {
        let canClose = appModel.localTabs.count > 1
        return content
            .contentShape(Rectangle())
            .onTapGesture {
                appModel.selectedLocalTabID = tab.id
            }
            .onHover { hovering in
                if hovering {
                    hoveredTabID = tab.id
                } else if hoveredTabID == tab.id {
                    hoveredTabID = nil
                }
            }
            .contextMenu {
                Button(String(localized: "Rename Tab")) {
                    tab.isRenaming = true
                }
                Button(role: .destructive) {
                    closeTab(tab)
                } label: {
                    Text(String(localized: "Close Tab"))
                }
                .disabled(!canClose)
            }
    }

    // MARK: - Helpers

    private var selectedTab: LocalTerminalTab? {
        appModel.localTabs.first { $0.id == appModel.selectedLocalTabID }
    }

    private var selectedTabName: String {
        selectedTab?.name ?? String(localized: "Local Terminal")
    }

    /// Drives the rename sheet from the tab's `isRenaming` flag.
    private var renamingTab: Binding<LocalTerminalTab?> {
        Binding(
            get: { appModel.localTabs.first { $0.isRenaming } },
            set: { newValue in
                if newValue == nil {
                    for tab in appModel.localTabs where tab.isRenaming {
                        tab.isRenaming = false
                    }
                }
            }
        )
    }

    private func closeTab(_ tab: LocalTerminalTab) {
        guard appModel.localTabs.count > 1 else { return }
        appModel.removeLocalTab(tab.id)
    }

    private func addTab() {
        var config = GhosttySurfaceConfiguration()
        config.fontSize = Float(settings.fontSize)
        var env = ProcessInfo.processInfo.environment
        if env["TERM"] == nil || env["TERM"] == "dumb" {
            env["TERM"] = "xterm-256color"
        }
        config.environmentVariables = env
        config.workingDirectory = NSHomeDirectory()
        appModel.addLocalTab(config: config)
    }
}

// MARK: - Rename Sheet

private struct RenameTabSheet: View {
    @Bindable var tab: LocalTerminalTab
    let appModel: AppModel
    @State private var text: String = ""

    var body: some View {
        VStack(spacing: 16) {
            Text(String(localized: "Rename Terminal Tab"))
                .font(.headline)
            TextField(String(localized: "Tab name"), text: $text)
                .textFieldStyle(.roundedBorder)
                .onSubmit { apply() }
            HStack {
                Button(String(localized: "Cancel")) { dismiss() }
                    .keyboardShortcut(.escape, modifiers: [])
                Spacer()
                Button(String(localized: "Rename")) { apply() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: [])
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 300)
        .onAppear { text = tab.name }
    }

    private func apply() {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            tab.name = trimmed
            appModel.persistTabs()
        }
        dismiss()
    }

    private func dismiss() {
        tab.isRenaming = false
    }
}
