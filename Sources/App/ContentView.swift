import SwiftUI
import AppKit

struct ContentView: View {
    @Bindable var model: AppModel
    @Bindable var settings: AppSettings
    @State private var editorConnection: SSHConnection?
    @State private var pendingImportURL: URL?
    @State private var importMode: ImportMode = .merge
    @State private var showImportDialog: Bool = false
    @State private var showingDeleteAlert: Bool = false

    var body: some View {
        splitView
        .confirmationDialog(
            String(localized: "Import Connections"),
            isPresented: $showImportDialog,
            titleVisibility: .visible
        ) {
            Button(String(localized: "Merge (Recommended)")) {
                importMode = .merge
                confirmImport()
            }
            Button(String(localized: "Replace All"), role: .destructive) {
                importMode = .replace
                confirmImport()
            }
            Button(String(localized: "Cancel"), role: .cancel) {
                pendingImportURL = nil
            }
        } message: {
            Text("Choose how to import connections. 'Merge' will add new connections from the file, while 'Replace All' will remove all existing data first.", comment: "Import mode selection message")
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
        .onChange(of: model.sidebarSelection) { _, _ in
            // No longer auto-opening on selection.
            // Selection just changes the detail view state.
        }
    }

    private func exportConnections() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "connections.json"
        panel.title = String(localized: "Export Connections")
        if panel.runModal() == .OK, let url = panel.url {
            model.exportConnections(to: url)
        }
    }

    @ViewBuilder
    private var splitView: some View {
        NavigationSplitView {
            List(selection: $model.sidebarSelection) {
                Section(String(localized: "Local Shell")) {
                    NavigationLink(value: SidebarItem.localTerminal) {
                        Label(String(localized: "Local Terminal"), systemImage: "terminal")
                    }
                }

                Section(String(localized: "Connections")) {
                    ForEach(model.filteredConnections) { connection in
                        let isConnected = model.openTabs.first(where: { $0.connection.id == connection.id })?.terminalModel.status == .connected
                        let isActive = model.sidebarSelection == .connection(connection.id)
                        ConnectionRow(connection: connection, isSelected: isActive, isConnected: isConnected) {
                            model.openConnection(connection)
                        }
                        .tag(SidebarItem.connection(connection.id))
                        .contextMenu {
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

                            Button(role: .destructive) {
                                model.sidebarSelection = .connection(connection.id)
                                showingDeleteAlert = true
                            } label: {
                                Label(String(localized: "Delete"), systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .searchable(text: $model.searchText, placement: .sidebar, prompt: Text(String(localized: "Search connections")))
            .navigationTitle(String(localized: "MacSSH"))
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        editorConnection = SSHConnection(name: "", host: "", port: 22, username: "")
                    } label: {
                        Label(String(localized: "Add Connection"), systemImage: "plus")
                    }
                    .keyboardShortcut("n", modifiers: .command)
                    .help(String(localized: "Create a new SSH connection profile"))
                }
            }
        } detail: {
            Group {
                if model.sidebarSelection == .localTerminal {
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

    private func importConnections() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.title = String(localized: "Import Connections")
        if panel.runModal() == .OK, let url = panel.url {
            pendingImportURL = url
            showImportDialog = true
        }
    }

    private func confirmImport() {
        guard let url = pendingImportURL else { return }
        model.importConnections(from: url, mode: importMode)
        pendingImportURL = nil
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
