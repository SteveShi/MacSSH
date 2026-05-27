import SwiftUI
import libghostty_swift

struct LocalTerminalView: View {
    let settings: AppSettings
    @Bindable var appModel: AppModel
    @Environment(\.openSettings) private var openSettings

    // Rename sheet state
    @State private var renamingTab: LocalTerminalTab? = nil
    @State private var renameText: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // Tab Bar Area
            if appModel.localTabs.count > 1 {
                tabBar
                    .background(.ultraThinMaterial)
                    .overlay(Divider(), alignment: .bottom)
            }

            Group {
                if appModel.localTabs.isEmpty {
                    ProgressView()
                } else {
                    ZStack {
                        ForEach(appModel.localTabs) { tab in
                            SurfaceViewHost(surface: tab.surfaceView)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .opacity(tab.id == appModel.selectedLocalTabID ? 1 : 0)
                                .allowsHitTesting(tab.id == appModel.selectedLocalTabID)
                        }
                    }
                    .ignoresSafeArea(.container, edges: .bottom)
                }
            }
        }
        .navigationTitle(selectedTabName)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    addTab()
                } label: {
                    Label(String(localized: "New Tab"), systemImage: "plus")
                }
                .keyboardShortcut("t", modifiers: .command)

                Button {
                    if let id = appModel.selectedLocalTabID {
                        appModel.removeLocalTab(id)
                    }
                } label: {
                    Label(String(localized: "Close Tab"), systemImage: "xmark")
                }
                .keyboardShortcut("w", modifiers: .command)
                .disabled(appModel.localTabs.count <= 1)
            }
        }
        .onAppear {
            if appModel.localTabs.isEmpty {
                addTab()
            }
        }
        .sheet(item: $renamingTab) { tab in
            RenameTabSheet(tab: tab, text: $renameText) {
                renamingTab = nil
            }
            .frame(width: 300)
        }
    }

    // MARK: - Helpers

    private var selectedTab: LocalTerminalTab? {
        appModel.localTabs.first { $0.id == appModel.selectedLocalTabID }
    }

    private var selectedTabName: String {
        selectedTab?.name ?? String(localized: "Local Terminal")
    }

    // MARK: - Subviews

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(appModel.localTabs) { tab in
                    tabButton(tab)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .frame(height: 38)
    }

    @ViewBuilder
    private func tabButton(_ tab: LocalTerminalTab) -> some View {
        let isSelected = tab.id == appModel.selectedLocalTabID
        Button {
            appModel.selectedLocalTabID = tab.id
        } label: {
            Text(tab.name)
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .foregroundStyle(isSelected ? .primary : .secondary)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .stroke(.white.opacity(0.1), lineWidth: 0.5)
                            )
                    }
                }
                .contentShape(Rectangle())
                .contextMenu {
                    Button {
                        renameText = tab.name
                        renamingTab = tab
                    } label: {
                        Label(String(localized: "Rename Tab"), systemImage: "pencil")
                    }
                    
                    Button(role: .destructive) {
                        appModel.removeLocalTab(tab.id)
                    } label: {
                        Label(String(localized: "Close Tab"), systemImage: "xmark")
                    }
                    .disabled(appModel.localTabs.count <= 1)
                }
        }
        .buttonStyle(.plain)
        .focusable()
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
    let tab: LocalTerminalTab
    @Binding var text: String
    let dismiss: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Rename Terminal Tab")
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
    }

    private func apply() {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { tab.name = trimmed }
        dismiss()
    }
}
