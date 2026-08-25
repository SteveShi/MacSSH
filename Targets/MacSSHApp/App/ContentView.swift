import SwiftUI
import AppKit
import SSH2Kit
import MactermKit

struct ContentView: View {
    @Bindable var model: AppModel
    @Bindable var settings: AppSettings
    @State private var editorConnection: SSHConnection?
    @State private var showingDeleteAlert: Bool = false
    @AppStorage("isLocalShellCollapsed") private var isLocalShellCollapsed: Bool = false
    @AppStorage("isConnectionsCollapsed") private var isConnectionsCollapsed: Bool = false

    var body: some View {
        splitView
        .frame(minWidth: 800, minHeight: 550)
        .background(WindowAccessor())
        .confirmationDialog(
            String(localized: "Delete Connection"),
            isPresented: $showingDeleteAlert,
            titleVisibility: .visible
        ) {
            Button(String(localized: "Delete"), role: .destructive) {
                model.removeSelectedConnection()
            }
            Button(String(localized: "Cancel"), role: .cancel) { }
        } message: {
            Text("Are you sure you want to delete the selected connection?", comment: "Delete connection confirmation message")
        }
        .onChange(of: model.sidebarSelection) { _, _ in
            triggerInputSourceSwitch()
        }
        .onChange(of: model.selectedTabID) { _, _ in
            triggerInputSourceSwitch()
        }
        .onChange(of: model.selectedLocalTabID) { _, _ in
            triggerInputSourceSwitch()
        }
        .onAppear {
            if model.localTabs.isEmpty {
                model.restoreLocalTabs(settings: settings)
                if model.localTabs.isEmpty {
                    addLocalTab()
                }
            }
            if model.sidebarSelection == nil {
                if let firstLocal = model.localTabs.first {
                    model.sidebarSelection = .localTab(firstLocal.id)
                } else if let firstConn = model.connections.first {
                    model.sidebarSelection = .connection(firstConn.id)
                }
            }
            triggerInputSourceSwitch()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            triggerInputSourceSwitch()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            triggerInputSourceSwitch()
        }
        .onChange(of: model.sidebarSelection) { _, _ in
            triggerInputSourceSwitch()
        }
        .onChange(of: settings.defaultInputSourceID) { _, _ in
            triggerInputSourceSwitch()
        }
    }

    private func triggerInputSourceSwitch() {
        guard !settings.defaultInputSourceID.isEmpty else { return }
        InputSourceManager.applyDefaultInputSource(id: settings.defaultInputSourceID)
    }

    private func copyToPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private func hasPassword(for connection: SSHConnection) -> Bool {
        KeychainStore.loadPassword(account: connection.keychainAccount) != nil
    }

    private func addLocalTab() {
        if isLocalShellCollapsed {
            withAnimation(.easeInOut(duration: 0.2)) {
                isLocalShellCollapsed = false
            }
        }
        var config = GhosttySurfaceConfiguration()
        config.fontSize = Float(settings.fontSize)
        config.environmentVariables = LocalShellEnvironment.make()
        config.workingDirectory = NSHomeDirectory()
        model.addLocalTab(config: config)
    }

    @ViewBuilder
    private var splitView: some View {
        NavigationSplitView {
            List(selection: $model.sidebarSelection) {
                Section {
                    if !isLocalShellCollapsed {
                        ForEach(model.localTabs) { tab in
                            let isSelected = model.selectedLocalTabID == tab.id
                            LocalTabRow(tab: tab, isSelected: isSelected, canClose: model.localTabs.count > 1) {
                                model.removeLocalTab(tab.id)
                            }
                            .tag(SidebarItem.localTab(tab.id))
                            .contextMenu {
                                localTabContextMenu(for: tab)
                            }
                        }
                    }
                } header: {
                    HStack(spacing: 4) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isLocalShellCollapsed.toggle()
                            }
                        } label: {
                            Image(systemName: isLocalShellCollapsed ? "chevron.right" : "chevron.down")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                                .frame(width: 16, height: 16)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        Text(String(localized: "Local Shell"))
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.secondary)

                        Spacer()

                        Button {
                            addLocalTab()
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 18, height: 18)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .keyboardShortcut("t", modifiers: .command)
                        .help(String(localized: "New Tab"))
                    }
                }

                Section {
                    if !isConnectionsCollapsed {
                        ForEach(model.filteredConnections) { connection in
                            let isConnected = model.openTabs.first(where: { $0.connection.id == connection.id })?.terminalModel.status == .connected
                            let isActive = model.sidebarSelection == .connection(connection.id)
                            ConnectionRow(connection: connection, isSelected: isActive, isConnected: isConnected) {
                                model.openConnection(connection)
                            }
                            .tag(SidebarItem.connection(connection.id))
                            .contextMenu {
                                connectionContextMenu(for: connection)
                            }
                        }
                    }
                } header: {
                    HStack(spacing: 4) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isConnectionsCollapsed.toggle()
                            }
                        } label: {
                            Image(systemName: isConnectionsCollapsed ? "chevron.right" : "chevron.down")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                                .frame(width: 16, height: 16)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        Text(String(localized: "Connections"))
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.secondary)

                        Spacer()

                        Button {
                            if isConnectionsCollapsed {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    isConnectionsCollapsed = false
                                }
                            }
                            editorConnection = SSHConnection(name: "", host: "", port: 22, username: "")
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 18, height: 18)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .keyboardShortcut("n", modifiers: .command)
                        .help(String(localized: "Add Connection"))
                    }
                }
            }
            .searchable(text: $model.searchText, placement: .sidebar, prompt: Text(String(localized: "Search connections")))
            .navigationTitle(String(localized: "MacSSH"))
            .navigationSplitViewColumnWidth(min: 180, ideal: 240, max: 400)
        } detail: {
            Group {
                if case .localTab = model.sidebarSelection {
                    LocalTerminalView(settings: settings, appModel: model)
                } else if case .connection(let id) = model.sidebarSelection {
                    if let tab = model.openTabs.first(where: { $0.connection.id == id }) {
                        // Connection is OPEN (has a session tab)
                        TerminalView(tab: tab, settings: settings, appModel: model)
                    } else if let conn = model.connections.first(where: { $0.id == id }) {
                        // Connection is NOT open (placeholder view)
                        ContentUnavailableView {
                            Label(conn.name, systemImage: "terminal")
                        } description: {
                            Text(String(localized: "Connection is not open."))
                        } actions: {
                            Button(String(localized: "Open Connection")) {
                                model.openConnection(conn)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .toolbar {
                            ToolbarItemGroup(placement: .primaryAction) {
                                Button {
                                    model.openConnection(conn)
                                } label: {
                                    Label(String(localized: "Connect"), systemImage: "play.fill")
                                }
                                .help(String(localized: "Open SSH Session"))
                            }
                        }
                    } else {
                        EmptyStateView()
                    }
                } else {
                    EmptyStateView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationSplitViewStyle(.balanced)
        .sheet(item: $editorConnection) { connection in
            ConnectionEditorView(connection: connection) { updated in
                model.upsertConnection(updated)
                model.openConnection(updated)
            }
        }
    }

    @ViewBuilder
    private func localTabContextMenu(for tab: LocalTerminalTab) -> some View {
        let index = model.localTabs.firstIndex(where: { $0.id == tab.id }) ?? 0
        let isFirst = index == 0
        let isLast = index == model.localTabs.count - 1
        let canClose = model.localTabs.count > 1

        Button(String(localized: "Rename Tab...")) {
            tab.isRenaming = true
        }

        Divider()

        Button(role: .destructive) {
            model.removeLocalTab(tab.id)
        } label: {
            Text(String(localized: "Close Tab"))
        }
        .disabled(!canClose)

        Button(String(localized: "Close Other Tabs")) {
            model.closeOtherLocalTabs(tab.id)
        }
        .disabled(!canClose)

        Button(String(localized: "Close Tabs Below")) {
            model.closeLocalTabsBelow(tab.id)
        }
        .disabled(isLast)

        Divider()

        Button(String(localized: "Move Up")) {
            model.moveLocalTabUp(tab.id)
        }
        .disabled(isFirst)

        Button(String(localized: "Move Down")) {
            model.moveLocalTabDown(tab.id)
        }
        .disabled(isLast)

        Divider()

        Button(String(localized: "Duplicate Tab")) {
            model.duplicateLocalTab(tab.id, settings: settings)
        }
    }

    @ViewBuilder
    private func connectionContextMenu(for connection: SSHConnection) -> some View {
        Button {
            model.openConnection(connection)
        } label: {
            Label(String(localized: "Open in Tab"), systemImage: "terminal")
        }

        Divider()

        Button {
            editorConnection = connection
        } label: {
            Label(String(localized: "Edit"), systemImage: "pencil")
        }

        Button {
            copyToPasteboard(connection.host)
        } label: {
            Label(String(localized: "Copy IP"), systemImage: "doc.on.doc")
        }

        Button {
            if let password = KeychainStore.loadPassword(account: connection.keychainAccount) {
                copyToPasteboard(password)
            }
        } label: {
            Label(String(localized: "Copy Password"), systemImage: "key")
        }
        .disabled(!hasPassword(for: connection))

        Button(role: .destructive) {
            model.sidebarSelection = .connection(connection.id)
            showingDeleteAlert = true
        } label: {
            Label(String(localized: "Delete"), systemImage: "trash")
        }
    }


}

private struct EmptyStateView: View {
    var body: some View {
        ContentUnavailableView {
            Label {
                Text(String(localized: "Start a New Connection", comment: "Empty state title"))
                    .font(.title2)
            } icon: {
                Image(systemName: "terminal.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.blue)
                    .font(.system(size: 48))
            }
        } description: {
            Text(String(localized: "Select a server from the sidebar to begin your session, or add a new one to get started.", comment: "Empty state description"))
                .font(.body)
                .foregroundStyle(.secondary)
        } actions: {
            Text(String(localized: "Shortcut: ⌘N New Connection", comment: "Empty state shortcut hint"))
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }
}

private struct LocalTabRow: View {
    let tab: LocalTerminalTab
    let isSelected: Bool
    let canClose: Bool
    var onClose: (() -> Void)? = nil
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "terminal")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isSelected ? AnyShapeStyle(Color.blue.gradient) : AnyShapeStyle(Color.gray))
                .frame(width: 20, height: 20)

            Text(tab.name)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer()

            if isHovered && canClose {
                Button {
                    onClose?()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .padding(4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

private struct ConnectionRow: View {
    let connection: SSHConnection
    let isSelected: Bool
    var isConnected: Bool = false
    @State private var isHovered = false
    var onConnect: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Image(systemName: "desktopcomputer")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isSelected ? AnyShapeStyle(Color.blue.gradient) : AnyShapeStyle(Color.gray))
                
                Circle()
                    .fill(isConnected ? Color.green : Color.gray.opacity(0.5))
                    .frame(width: 8, height: 8)
                    .overlay(Circle().stroke(Color.black.opacity(0.2), lineWidth: 1))
                    .offset(x: 10, y: 10)
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(connection.name)
                    .font(.system(size: 13, weight: .semibold))
                
                Text("\(connection.username)@\(connection.host)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            if isHovered {
                Button {
                    onConnect?()
                } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(6)
                        .background(Color.blue.gradient)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isHovered = hovering
            }
        }
    }
}

enum ImportMode {
    case merge
    case replace
}

private struct WindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                window.setFrameAutosaveName("MacSSHMainWindow")
                window.setFrameUsingName("MacSSHMainWindow")
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
