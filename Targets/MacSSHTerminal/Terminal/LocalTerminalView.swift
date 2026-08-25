import SwiftUI
import MactermKit

struct LocalTerminalView: View {
    let settings: AppSettings
    @Bindable var appModel: AppModel

    var body: some View {
        content
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
                    let mainTerminal = SurfaceViewHost(surface: tab.surfaceView)
                    
                    Group {
                        if tab.isSplit, let splitSurface = tab.splitSurface {
                            let splitView = SurfaceViewHost(surface: splitSurface)
                            
                            SplitTerminalLayout(direction: tab.splitDirection) {
                                mainTerminal
                            } split: {
                                splitView
                            }
                        } else {
                            mainTerminal
                        }
                    }
                    .opacity(tab.id == appModel.selectedLocalTabID ? 1 : 0)
                    .allowsHitTesting(tab.id == appModel.selectedLocalTabID)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea(.container, edges: .bottom)
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

    private func addTab() {
        var config = GhosttySurfaceConfiguration()
        config.fontSize = Float(settings.fontSize)
        config.environmentVariables = LocalShellEnvironment.make()
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
