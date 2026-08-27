import SwiftUI
import MactermKit

struct LocalTerminalView: View {
    let settings: AppSettings
    @Bindable var appModel: AppModel

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let selected = selectedTab {
                LocalTerminalStatusBar(tab: selected)
            }
        }
        .background(Color(red: 36.0 / 255.0, green: 39.0 / 255.0, blue: 46.0 / 255.0))
        .navigationTitle("")
        .inspector(isPresented: inspectorBinding) {
            if let selected = selectedTab {
                InspectorContentView(localTab: selected, appModel: appModel)
            }
        }
        .inspectorColumnWidth(min: 280, ideal: 340, max: 600)
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
        .toolbar {
            if #available(macOS 26.0, *) {
                ToolbarItemGroup(placement: .primaryAction) {
                    toolbarActionButtons
                }
                .sharedBackgroundVisibility(.hidden)
            } else {
                ToolbarItemGroup(placement: .primaryAction) {
                    toolbarActionButtons
                }
            }
        }
    }

    private var inspectorBinding: Binding<Bool> {
        Binding(
            get: { selectedTab?.showInspector ?? false },
            set: { selectedTab?.showInspector = $0 }
        )
    }

    @ViewBuilder
    private var toolbarActionButtons: some View {
        if let selected = selectedTab {
            Menu {
                Button {
                    selected.split(direction: .right)
                } label: {
                    Label(String(localized: "Split Right"), systemImage: "rectangle.split.2x1")
                }
                Button {
                    selected.split(direction: .down)
                } label: {
                    Label(String(localized: "Split Down"), systemImage: "rectangle.split.1x2")
                }
                if selected.isSplit {
                    Divider()
                    Button(role: .destructive) {
                        selected.closeSplit()
                    } label: {
                        Label(String(localized: "Close Split"), systemImage: "xmark.square")
                    }
                }
            } label: {
                Label(String(localized: "Split Terminal"), systemImage: "rectangle.split.2x1")
            }
            .help(String(localized: "Split Terminal"))

            @Bindable var sel = selected
            Toggle(isOn: $sel.showInspector) {
                Label(String(localized: "Snippets"), systemImage: "sidebar.right")
            }
            .toggleStyle(.button)
            .help(String(localized: "Show Snippets Inspector"))
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if let selected = selectedTab {
            LocalTerminalSurfaceHost(tab: selected)
        } else {
            ContentUnavailableView {
                Label(String(localized: "No Terminal Open"), systemImage: "terminal")
            } description: {
                Text(String(localized: "Add a new terminal tab to get started."))
            } actions: {
                Button(String(localized: "New Tab")) {
                    addTab()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - Selected Tab

    private var selectedTab: LocalTerminalTab? {
        if case .localTab(let id) = appModel.sidebarSelection {
            return appModel.localTabs.first { $0.id == id }
        }
        return appModel.localTabs.first
    }

    // MARK: - Renaming Tab Binding

    private var renamingTab: Binding<LocalTerminalTab?> {
        Binding(
            get: { appModel.localTabs.first(where: { $0.isRenaming }) },
            set: { tab in
                if let tab {
                    tab.isRenaming = true
                } else {
                    for t in appModel.localTabs { t.isRenaming = false }
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

// MARK: - Local Terminal Surface Host

private struct LocalTerminalSurfaceHost: View {
    let tab: LocalTerminalTab

    var body: some View {
        if tab.isSplit, let splitSurface = tab.splitSurface {
            if tab.splitDirection == .down || tab.splitDirection == .up {
                VSplitView {
                    SurfaceViewHost(surface: tab.surfaceView)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    SurfaceViewHost(surface: splitSurface)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                HSplitView {
                    SurfaceViewHost(surface: tab.surfaceView)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    SurfaceViewHost(surface: splitSurface)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        } else {
            SurfaceViewHost(surface: tab.surfaceView)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Rename Tab Sheet

private struct RenameTabSheet: View {
    @Bindable var tab: LocalTerminalTab
    @Bindable var appModel: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var newName: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(String(localized: "Rename Tab"))
                .font(.headline)

            TextField(String(localized: "Tab Name"), text: $newName)
                .textFieldStyle(.roundedBorder)
                .onAppear { newName = tab.name }

            HStack {
                Button(String(localized: "Cancel")) {
                    tab.isRenaming = false
                    dismiss()
                }
                .keyboardShortcut(.escape, modifiers: [])

                Spacer()

                Button(String(localized: "Save")) {
                    let trimmed = newName.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty {
                        tab.name = trimmed
                    }
                    tab.isRenaming = false
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: [])
                .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 280)
    }
}
