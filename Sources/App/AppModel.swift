import Foundation
import Observation
import libghostty_swift

enum SidebarItem: Hashable, Identifiable {
    case localTerminal
    case connection(SSHConnection.ID)
    
    var id: String {
        switch self {
        case .localTerminal: return "localTerminal"
        case .connection(let id): return id.uuidString
        }
    }
}

@Observable
@MainActor
final class AppModel {
    var connections: [SSHConnection]
    var sidebarSelection: SidebarItem?
    var searchText: String = ""

    var openTabs: [SessionTab] = []
    var selectedTabID: SessionTab.ID?
    var reconnectRequests: [SSHConnection.ID: UUID] = [:]

    // Local terminal tab pool — lives at app scope so PTYs survive SwiftUI navigation
    var localTabs: [LocalTerminalTab] = []
    var selectedLocalTabID: UUID?
    private var localTabCounter: Int = 0

    var filteredConnections: [SSHConnection] {
        if searchText.isEmpty {
            return connections
        }
        return connections.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.host.localizedCaseInsensitiveContains(searchText) ||
            $0.username.localizedCaseInsensitiveContains(searchText)
        }
    }

    private enum TabKeys {
        static let openTabConnections = "openTabConnections"
        static let selectedTabConnection = "selectedTabConnection"
    }

    init() {
        let stored = ConnectionsStore.load()
        if stored.isEmpty {
            let seed = SSHConnection(name: "Example", host: "example.com", port: 22, username: "root")
            connections = [seed]
        } else {
            connections = stored
        }
        sidebarSelection = .localTerminal
        restoreTabs()
    }

    var selectedConnection: SSHConnection? {
        guard case .connection(let id) = sidebarSelection else { return nil }
        return connections.first { $0.id == id }
    }

    var selectedTab: SessionTab? {
        guard let selectedTabID else { return openTabs.first }
        return openTabs.first { $0.id == selectedTabID }
    }

    func upsertConnection(_ connection: SSHConnection) {
        if let index = connections.firstIndex(where: { $0.id == connection.id }) {
            connections[index] = connection
        } else {
            connections.append(connection)
        }
        sidebarSelection = .connection(connection.id)
        persist()
    }

    func removeSelectedConnection() {
        guard case .connection(let id) = sidebarSelection else { return }
        connections.removeAll { $0.id == id }
        openTabs.removeAll { $0.connection.id == id }
        if let first = connections.first {
            sidebarSelection = .connection(first.id)
        } else {
            sidebarSelection = .localTerminal
        }
        if !openTabs.contains(where: { $0.id == selectedTabID }) {
            selectedTabID = openTabs.first?.id
        }
        persist()
    }

    @MainActor
    func openConnection(_ connection: SSHConnection) {
        if let existing = openTabs.first(where: { $0.connection.id == connection.id }) {
            selectedTabID = existing.id
            sidebarSelection = .connection(existing.connection.id)
            persistTabs()
            return
        }
        let tab = SessionTab(connection: connection)
        openTabs.append(tab)
        selectedTabID = tab.id
        sidebarSelection = .connection(connection.id)
        persistTabs()
    }

    func closeTab(_ tabID: SessionTab.ID) {
        openTabs.removeAll { $0.id == tabID }
        if selectedTabID == tabID {
            selectedTabID = openTabs.last?.id
            if let lastTabConnectionID = openTabs.last?.connection.id {
                sidebarSelection = .connection(lastTabConnectionID)
            }
        }
        persistTabs()
    }

    // MARK: - Local Terminal Tab Management

    /// Creates a new local terminal tab with a pre-built surface and returns it.
    @MainActor
    func addLocalTab(config: GhosttySurfaceConfiguration) {
        localTabCounter += 1
        let surface = GhosttySurfaceView(config: config)
        let tab = LocalTerminalTab(number: localTabCounter, surfaceView: surface)
        localTabs.append(tab)
        selectedLocalTabID = tab.id
    }

    /// Removes a local terminal tab by ID.
    func removeLocalTab(_ id: UUID) {
        localTabs.removeAll { $0.id == id }
        selectedLocalTabID = localTabs.last?.id
    }



    @MainActor
    func requestReconnect(connectionID: SSHConnection.ID) {
        // Clear the cached surface so the next makeNSView call starts a fresh PTY.
        openTabs.first(where: { $0.connection.id == connectionID })?.cachedSurface = nil
        reconnectRequests[connectionID] = UUID()
    }

    func nextTab() {
        if sidebarSelection == .localTerminal {
            guard !localTabs.isEmpty else { return }
            guard let currentID = selectedLocalTabID,
                  let index = localTabs.firstIndex(where: { $0.id == currentID }) else {
                selectedLocalTabID = localTabs.first?.id
                return
            }
            let nextIndex = (index + 1) % localTabs.count
            selectedLocalTabID = localTabs[nextIndex].id
        } else {
            guard !openTabs.isEmpty else { return }
            guard let currentID = selectedTabID,
                  let index = openTabs.firstIndex(where: { $0.id == currentID }) else {
                selectedTabID = openTabs.first?.id
                if let firstID = openTabs.first?.connection.id {
                    sidebarSelection = .connection(firstID)
                }
                return
            }
            let nextIndex = (index + 1) % openTabs.count
            selectedTabID = openTabs[nextIndex].id
            sidebarSelection = .connection(openTabs[nextIndex].connection.id)
        }
    }

    func previousTab() {
        if sidebarSelection == .localTerminal {
            guard !localTabs.isEmpty else { return }
            guard let currentID = selectedLocalTabID,
                  let index = localTabs.firstIndex(where: { $0.id == currentID }) else {
                selectedLocalTabID = localTabs.last?.id
                return
            }
            let nextIndex = (index - 1 + localTabs.count) % localTabs.count
            selectedLocalTabID = localTabs[nextIndex].id
        } else {
            guard !openTabs.isEmpty else { return }
            guard let currentID = selectedTabID,
                  let index = openTabs.firstIndex(where: { $0.id == currentID }) else {
                selectedTabID = openTabs.last?.id
                if let lastID = openTabs.last?.connection.id {
                    sidebarSelection = .connection(lastID)
                }
                return
            }
            let nextIndex = (index - 1 + openTabs.count) % openTabs.count
            selectedTabID = openTabs[nextIndex].id
            sidebarSelection = .connection(openTabs[nextIndex].connection.id)
        }
    }

    func selectTab(at index: Int) {
        if sidebarSelection == .localTerminal {
            guard index >= 0 && index < localTabs.count else { return }
            selectedLocalTabID = localTabs[index].id
        } else {
            guard index >= 0 && index < openTabs.count else { return }
            selectedTabID = openTabs[index].id
            sidebarSelection = .connection(openTabs[index].connection.id)
        }
    }

    func exportConnections(to url: URL) {
        ConnectionsStore.export(connections, to: url)
    }

    func importConnections(from url: URL, mode: ImportMode) {
        guard let imported = ConnectionsStore.import(from: url) else { return }
        switch mode {
        case .merge:
            let merged = mergeConnections(existing: connections, incoming: imported)
            connections = merged
        case .replace:
            connections = imported
        }
        if let first = connections.first {
            sidebarSelection = .connection(first.id)
        }
        persist()
    }

    private func mergeConnections(existing: [SSHConnection], incoming: [SSHConnection]) -> [SSHConnection] {
        var result = existing
        for item in incoming {
            if result.contains(where: { $0.host == item.host && $0.port == item.port && $0.username == item.username }) {
                continue
            }
            result.append(item)
        }
        return result
    }

    func recordHistory(for connectionID: SSHConnection.ID, isSuccess: Bool) {
        guard let index = connections.firstIndex(where: { $0.id == connectionID }) else { return }
        var currentHistory = connections[index].history ?? []
        let newEntry = ConnectionHistoryEntry(timestamp: Date(), isSuccess: isSuccess)
        currentHistory.insert(newEntry, at: 0)
        if currentHistory.count > 10 {
            currentHistory = Array(currentHistory.prefix(10))
        }
        connections[index].history = currentHistory
        NotificationService.shared.notifyConnection(success: isSuccess, name: connections[index].name)
        
        // Also update any active tabs holding this connection
        for i in 0..<openTabs.count {
            if openTabs[i].connection.id == connectionID {
                openTabs[i].connection = connections[index]
            }
        }
        
        persist()
    }

    private func persist() {
        ConnectionsStore.save(connections)
        persistTabs()
    }

    private func persistTabs() {
        let defaults = UserDefaults.standard
        let connectionIDs = openTabs.map { $0.connection.id.uuidString }
        defaults.set(connectionIDs, forKey: TabKeys.openTabConnections)
        if let selected = selectedTab?.connection.id {
            defaults.set(selected.uuidString, forKey: TabKeys.selectedTabConnection)
        } else {
            defaults.removeObject(forKey: TabKeys.selectedTabConnection)
        }
    }

    @MainActor
    private func restoreTabs() {
        let defaults = UserDefaults.standard
        let ids = defaults.stringArray(forKey: TabKeys.openTabConnections) ?? []
        let connectionsByID = Dictionary(uniqueKeysWithValues: connections.map { ($0.id.uuidString, $0) })
        let tabs = ids.compactMap { connectionsByID[$0] }.map { SessionTab(connection: $0) }
        openTabs = tabs

        if let selectedID = defaults.string(forKey: TabKeys.selectedTabConnection),
           let uuid = UUID(uuidString: selectedID),
           let selectedConnection = connectionsByID[selectedID],
           let tab = openTabs.first(where: { $0.connection.id == selectedConnection.id }) {
            selectedTabID = tab.id
            sidebarSelection = .connection(uuid)
        } else {
            selectedTabID = openTabs.first?.id
            if let firstID = openTabs.first?.connection.id {
                sidebarSelection = .connection(firstID)
            } else {
                sidebarSelection = .localTerminal
            }
        }
    }
}
