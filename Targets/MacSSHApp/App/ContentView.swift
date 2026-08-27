import SwiftUI
import AppKit
import SSH2Kit
import MactermKit

// MARK: - Sidebar Tab Enum

private enum SidebarTab: String, CaseIterable {
    case local
    case remote
}

// MARK: - ContentView

struct ContentView: View {
    @Bindable var model: AppModel
    @Bindable var settings: AppSettings
    @State private var editorConnection: SSHConnection?
    @State private var showingDeleteAlert: Bool = false
    @State private var showingWhatsNew: Bool = false
    @AppStorage("sidebarTab") private var sidebarTab: SidebarTab = .remote
    @AppStorage("lastSeenWhatsNewVersion") private var lastSeenWhatsNewVersion: String = ""

    var body: some View {
        splitView
        .frame(minWidth: 850, minHeight: 560)
        .background(WindowAccessor())
        .sheet(isPresented: $showingWhatsNew) {
            WhatsNewSheetView()
        }
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
        .onChange(of: model.sidebarSelection) { _, newValue in
            triggerInputSourceSwitch()
            switch newValue {
            case .localTab:
                if sidebarTab != .local { sidebarTab = .local }
            case .connection:
                if sidebarTab != .remote { sidebarTab = .remote }
            case nil:
                break
            }
        }
        .onChange(of: model.selectedTabID) { _, _ in
            triggerInputSourceSwitch()
        }
        .onChange(of: model.selectedLocalTabID) { _, _ in
            triggerInputSourceSwitch()
        }
        .onChange(of: sidebarTab) { _, newTab in
            model.searchText = ""
            switch newTab {
            case .local:
                if case .connection = model.sidebarSelection {
                    if let first = model.localTabs.first {
                        model.sidebarSelection = .localTab(first.id)
                    }
                }
            case .remote:
                if case .localTab = model.sidebarSelection {
                    if let first = model.connections.first {
                        model.sidebarSelection = .connection(first.id)
                    }
                }
            }
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
        var config = GhosttySurfaceConfiguration()
        config.fontSize = Float(settings.fontSize)
        config.environmentVariables = LocalShellEnvironment.make()
        config.workingDirectory = NSHomeDirectory()
        model.addLocalTab(config: config)
    }

    private func addConnection() {
        sidebarTab = .remote
        editorConnection = SSHConnection(name: "", host: "", port: 22, username: "")
    }

    // MARK: - Split View

    @ViewBuilder
    private var splitView: some View {
        NavigationSplitView {
            sidebarContent
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
        } detail: {
            Group {
                if case .localTab = model.sidebarSelection {
                    LocalTerminalView(settings: settings, appModel: model)
                } else if case .connection(let id) = model.sidebarSelection {
                    if let tab = model.openTabs.first(where: { $0.connection.id == id }) {
                        TerminalView(tab: tab, settings: settings, appModel: model)
                    } else if let conn = model.connections.first(where: { $0.id == id }) {
                        unopenedConnectionView(for: conn)
                    } else {
                        EmptyStateView()
                    }
                } else {
                    if let firstTab = model.openTabs.first {
                        TerminalView(tab: firstTab, settings: settings, appModel: model)
                    } else if let firstLocal = model.localTabs.first {
                        LocalTerminalView(settings: settings, appModel: model)
                    } else {
                        EmptyStateView()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(red: 36.0 / 255.0, green: 39.0 / 255.0, blue: 46.0 / 255.0))
            .toolbarBackground(.hidden, for: .windowToolbar)
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    TitlebarSessionTabBar(
                        model: model,
                        isLocalMode: sidebarTab == .local,
                        onAdd: {
                            if sidebarTab == .local {
                                addLocalTab()
                            } else {
                                addConnection()
                            }
                        }
                    )
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .sheet(item: $editorConnection) { connection in
            ConnectionEditorView(connection: connection) { updated in
                model.upsertConnection(updated)
                model.openConnection(updated)
            }
        }
        .background {
            Group {
                Button("") { addLocalTab() }
                    .keyboardShortcut("t", modifiers: .command)
                Button("") { addConnection() }
                    .keyboardShortcut("n", modifiers: .command)
            }
            .frame(width: 0, height: 0)
            .opacity(0)
            .allowsHitTesting(false)
        }
    }

    // MARK: - Sidebar Content (Berth Parity)

    @ViewBuilder
    private var sidebarContent: some View {
        VStack(spacing: 0) {
            // Sidebar Header: 2-Icon Switcher + Search + Add Button
            sidebarHeader
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .padding(.bottom, 6)

            // Hosts / Tabs List
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if sidebarTab == .local {
                        localTabsRows
                    } else {
                        connectionsRows
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: - Sidebar Header (2-Icon Switcher + Search + Plus)

    @ViewBuilder
    private var sidebarHeader: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                // Pure Icon Switcher (Local / Remote)
                LiquidGlassIconPicker(
                    selection: $sidebarTab,
                    items: [
                        (.local, "terminal", String(localized: "Local Shell")),
                        (.remote, "desktopcomputer", String(localized: "Remote SSH"))
                    ]
                )

                // Search Bar for Remote
                if sidebarTab == .remote {
                    HStack(spacing: 5) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)

                        TextField(String(localized: "Search hosts"), text: $model.searchText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12))

                        if !model.searchText.isEmpty {
                            Button {
                                model.searchText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(.tertiary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4.5)
                    .background(
                        Capsule()
                            .fill(Color.primary.opacity(0.05))
                    )
                } else {
                    Spacer()
                }

                // Plus (+) Button
                Button {
                    if sidebarTab == .local {
                        addLocalTab()
                    } else {
                        addConnection()
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 24, height: 24)
                        .background(
                            Circle()
                                .fill(Color.primary.opacity(0.05))
                        )
                        .contentShape(Circle())
                }
                .buttonStyle(PressableIconStyle())
                .foregroundStyle(.secondary)
                .help(sidebarTab == .local ? String(localized: "New Tab") : String(localized: "Add Connection"))
            }
        }
    }

    // MARK: - Local Tabs Rows

    @ViewBuilder
    private var localTabsRows: some View {
        if model.localTabs.isEmpty {
            Text(String(localized: "No Terminals"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.top, 24)
        } else {
            ForEach(model.localTabs) { tab in
                let isSelected = model.selectedLocalTabID == tab.id
                BerthLocalTabRow(
                    tab: tab,
                    isSelected: isSelected,
                    canClose: model.localTabs.count > 1,
                    onSelect: {
                        model.selectedLocalTabID = tab.id
                        model.sidebarSelection = .localTab(tab.id)
                    },
                    onClose: {
                        model.removeLocalTab(tab.id)
                    }
                )
                .contextMenu {
                    localTabContextMenu(for: tab)
                }
            }
        }
    }

    // MARK: - Connections Rows

    @ViewBuilder
    private var connectionsRows: some View {
        if model.filteredConnections.isEmpty {
            Text(model.searchText.isEmpty ? String(localized: "No Hosts") : String(localized: "没有匹配的主机"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.top, 24)
        } else {
            ForEach(model.filteredConnections) { connection in
                let isConnected = model.openTabs.first(where: { $0.connection.id == connection.id })?.terminalModel.status == .connected
                let isSelected = model.sidebarSelection == .connection(connection.id)
                BerthHostRow(
                    connection: connection,
                    isSelected: isSelected,
                    isConnected: isConnected,
                    onSelect: {
                        model.sidebarSelection = .connection(connection.id)
                        if !model.openTabs.contains(where: { $0.connection.id == connection.id }) {
                            model.openConnection(connection)
                        } else {
                            model.selectedTabID = model.openTabs.first(where: { $0.connection.id == connection.id })?.id
                        }
                    }
                )
                .contextMenu {
                    connectionContextMenu(for: connection)
                }
            }
        }
    }

    // MARK: - Unopened Connection View

    @ViewBuilder
    private func unopenedConnectionView(for conn: SSHConnection) -> some View {
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
    }

    // MARK: - Context Menus

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
        let existingTab = model.openTabs.first(where: { $0.connection.id == connection.id })
        let isConnected = existingTab?.terminalModel.status == .connected

        if !isConnected {
            Button {
                model.openConnection(connection)
                if let tab = model.openTabs.first(where: { $0.connection.id == connection.id }) {
                    model.selectedTabID = tab.id
                    model.sidebarSelection = .connection(connection.id)
                    tab.terminalModel.appModel = model
                    tab.terminalModel.connect()
                    model.requestReconnect(connectionID: connection.id)
                }
            } label: {
                Label(String(localized: "Connect"), systemImage: "play.fill")
            }
        } else {
            Button {
                existingTab?.terminalModel.disconnect()
                existingTab?.cachedSurface = nil
                existingTab?.closeSplit()
            } label: {
                Label(String(localized: "Disconnect"), systemImage: "stop.fill")
            }
        }

        if let tab = existingTab {
            Button {
                model.closeTab(tab.id)
            } label: {
                Label(String(localized: "Close Tab"), systemImage: "xmark")
            }
        } else {
            Button {
                model.openConnection(connection)
            } label: {
                Label(String(localized: "Open in Tab"), systemImage: "terminal")
            }
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

        Divider()

        Button(role: .destructive) {
            model.sidebarSelection = .connection(connection.id)
            showingDeleteAlert = true
        } label: {
            Label(String(localized: "Delete"), systemImage: "trash")
        }
    }
}

// MARK: - Berth Parity Host Row

private struct BerthHostRow: View {
    let connection: SSHConnection
    let isSelected: Bool
    var isConnected: Bool = false
    var onSelect: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            // Finder-style icon
            Image(systemName: "desktopcomputer")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 20)

            // Status bar vertical indicator (with glow on connected)
            RoundedRectangle(cornerRadius: 1.5)
                .fill(isConnected ? Color.green : Color.gray.opacity(0.3))
                .frame(width: 3, height: 26)
                .shadow(color: isConnected ? Color.green.opacity(0.6) : .clear, radius: 3)

            // 13pt title + 10pt monospaced subtitle
            VStack(alignment: .leading, spacing: 1.5) {
                Text(connection.name)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text("\(connection.username)@\(connection.host)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 4)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .background {
            if isSelected {
                RaisedCapsule()
            } else if hovering {
                Capsule().fill(Color.primary.opacity(0.05))
            }
        }
        .foregroundStyle(isSelected ? .primary : .secondary)
        .contentShape(Capsule())
        .animation(.easeOut(duration: 0.12), value: hovering)
        .onHover { hovering = $0 }
        .onTapGesture { onSelect() }
    }
}

// MARK: - Berth Parity Local Tab Row

private struct BerthLocalTabRow: View {
    let tab: LocalTerminalTab
    let isSelected: Bool
    let canClose: Bool
    var onSelect: () -> Void
    var onClose: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "terminal")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 20)

            RoundedRectangle(cornerRadius: 1.5)
                .fill(Color.green.opacity(0.8))
                .frame(width: 3, height: 26)

            Text(tab.name)
                .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                .lineLimit(1)

            Spacer()

            if hovering && canClose {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                        .padding(4)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .background {
            if isSelected {
                RaisedCapsule()
            } else if hovering {
                Capsule().fill(Color.primary.opacity(0.05))
            }
        }
        .foregroundStyle(isSelected ? .primary : .secondary)
        .contentShape(Capsule())
        .animation(.easeOut(duration: 0.12), value: hovering)
        .onHover { hovering = $0 }
        .onTapGesture { onSelect() }
    }
}

// MARK: - Empty State

private struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "server.rack")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
            Text(String(localized: "Start a New Connection", comment: "Empty state title"))
                .font(.headline)
                .foregroundStyle(.secondary)
            Text(String(localized: "Shortcut: ⌘N New Connection", comment: "Empty state shortcut hint"))
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Window Accessor

private struct WindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                window.titlebarAppearsTransparent = true
                window.titlebarSeparatorStyle = .none
                window.styleMask.insert(.fullSizeContentView)
                window.backgroundColor = NSColor(red: 36.0 / 255.0, green: 39.0 / 255.0, blue: 46.0 / 255.0, alpha: 1.0)
                window.titleVisibility = .hidden
                window.toolbarStyle = .unified
                window.isMovableByWindowBackground = true
                window.setFrameAutosaveName("MacSSHMainWindow")
                window.setFrameUsingName("MacSSHMainWindow")
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
