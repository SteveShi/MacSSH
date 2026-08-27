import Foundation
import SwiftUI
import Observation
import MactermKit

enum SidebarItem: Hashable, Identifiable {
    case localTab(UUID)
    case connection(SSHConnection.ID)
    
    var id: String {
        switch self {
        case .localTab(let id): return "local-\(id.uuidString)"
        case .connection(let id): return id.uuidString
        }
    }
    
    var isLocalTerminal: Bool {
        if case .localTab = self { return true }
        return false
    }
}

enum ImportMode: Sendable {
    case merge
    case replace
}

@Observable
@MainActor
final class AppModel {
    private var isRestoring: Bool = true

    var connections: [SSHConnection]
    var sidebarSelection: SidebarItem? {
        didSet {
            guard !isRestoring else { return }
            persistTabs()
        }
    }
    var searchText: String = ""

    var openTabs: [SessionTab] = []
    var selectedTabID: SessionTab.ID?
    var reconnectRequests: [SSHConnection.ID: UUID] = [:]
    var showingWhatsNew: Bool = false

    // Local terminal tab pool — lives at app scope so PTYs survive SwiftUI navigation
    var localTabs: [LocalTerminalTab] = []
    var selectedLocalTabID: UUID? {
        get {
            if case .localTab(let id) = sidebarSelection { return id }
            return nil
        }
        set {
            if let newValue {
                sidebarSelection = .localTab(newValue)
            }
        }
    }
    private var localTabCounter: Int = 0

    // Snippets
    var snippets: [Snippet] = []
    var selectedSnippetID: UUID?

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

    var filteredLocalTabs: [LocalTerminalTab] {
        if searchText.isEmpty { return localTabs }
        return localTabs.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    var filteredSnippets: [Snippet] {
        if searchText.isEmpty { return snippets }
        return snippets.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.command.localizedCaseInsensitiveContains(searchText) ||
            $0.category.localizedCaseInsensitiveContains(searchText)
        }
    }

    func upsertSnippet(_ snippet: Snippet) {
        if let index = snippets.firstIndex(where: { $0.id == snippet.id }) {
            snippets[index] = snippet
        } else {
            snippets.append(snippet)
        }
        SnippetStore.save(snippets)
    }

    func removeSnippet(_ id: UUID) {
        snippets.removeAll { $0.id == id }
        SnippetStore.save(snippets)
    }

    func sendSnippetToActiveTerminal(_ snippet: Snippet, autoExecute: Bool? = nil) {
        let shouldExecute = autoExecute ?? snippet.autoExecute
        let text = shouldExecute ? "\(snippet.command)\n" : snippet.command

        // 1. 如果选中了本地终端
        if case .localTab(let id) = sidebarSelection,
           let tab = localTabs.first(where: { $0.id == id }) {
            tab.surfaceView.writeText(text)
            return
        }

        // 2. 如果选中了远程 SSH Tab
        if let selectedTabID, let tab = openTabs.first(where: { $0.id == selectedTabID }) {
            tab.cachedSurface?.writeText(text)
            return
        }

        // 3. Fallback
        if let firstTab = openTabs.first {
            firstTab.cachedSurface?.writeText(text)
        } else if let firstLocal = localTabs.first {
            firstLocal.surfaceView.writeText(text)
        }
    }

    private enum TabKeys {
        static let openTabConnections = "openTabConnections"
        static let selectedTabConnection = "selectedTabConnection"
        static let localTabs = "localTabs"
        static let selectedLocalTabID = "selectedLocalTabID"
        static let localTabCounter = "localTabCounter"
    }

    init(settings: AppSettings = AppSettings()) {
        let stored = ConnectionsStore.load()
        if stored.isEmpty {
            let seed = SSHConnection(name: "Example", host: "example.com", port: 22, username: "root")
            connections = [seed]
        } else {
            connections = stored
        }
        sidebarSelection = nil
        snippets = SnippetStore.load()
        restoreTabs()
        restoreLocalTabs(settings: settings)
        if localTabs.isEmpty {
            var config = GhosttySurfaceConfiguration()
            config.fontSize = Float(settings.fontSize)
            config.environmentVariables = LocalShellEnvironment.make()
            config.workingDirectory = NSHomeDirectory()
            addLocalTab(config: config)
        }
        isRestoring = false
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
        } else if let firstLocal = localTabs.first {
            sidebarSelection = .localTab(firstLocal.id)
        } else {
            sidebarSelection = nil
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
            } else if let lastLocalTab = localTabs.last {
                sidebarSelection = .localTab(lastLocalTab.id)
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
        sidebarSelection = .localTab(tab.id)
        persistTabs()
    }

    /// Removes a local terminal tab by ID.
    func removeLocalTab(_ id: UUID) {
        guard let index = localTabs.firstIndex(where: { $0.id == id }) else { return }
        SessionHistoryStore.shared.remove(tabID: id)
        let wasSelected = (selectedLocalTabID == id)
        localTabs.remove(at: index)
        if wasSelected {
            if !localTabs.isEmpty {
                let nextIndex = min(index, localTabs.count - 1)
                sidebarSelection = .localTab(localTabs[nextIndex].id)
            } else if let firstConn = connections.first {
                sidebarSelection = .connection(firstConn.id)
            } else {
                sidebarSelection = nil
            }
        }
        persistTabs()
    }

    /// Closes all local tabs except the specified one.
    func closeOtherLocalTabs(_ keepID: UUID) {
        guard localTabs.contains(where: { $0.id == keepID }) else { return }
        for tab in localTabs where tab.id != keepID {
            SessionHistoryStore.shared.remove(tabID: tab.id)
        }
        localTabs.removeAll { $0.id != keepID }
        sidebarSelection = .localTab(keepID)
        persistTabs()
    }

    /// Closes all local tabs positioned below the specified one.
    func closeLocalTabsBelow(_ id: UUID) {
        guard let index = localTabs.firstIndex(where: { $0.id == id }) else { return }
        for tab in localTabs.suffix(from: index + 1) {
            SessionHistoryStore.shared.remove(tabID: tab.id)
        }
        localTabs = Array(localTabs.prefix(index + 1))
        if let currentSelected = selectedLocalTabID, !localTabs.contains(where: { $0.id == currentSelected }) {
            sidebarSelection = .localTab(id)
        }
        persistTabs()
    }

    /// Moves the specified local tab up by one position.
    func moveLocalTabUp(_ id: UUID) {
        guard let index = localTabs.firstIndex(where: { $0.id == id }), index > 0 else { return }
        localTabs.swapAt(index, index - 1)
        persistTabs()
    }

    /// Moves the specified local tab down by one position.
    func moveLocalTabDown(_ id: UUID) {
        guard let index = localTabs.firstIndex(where: { $0.id == id }), index < localTabs.count - 1 else { return }
        localTabs.swapAt(index, index + 1)
        persistTabs()
    }

    /// Duplicates a local tab with a fresh surface.
    @MainActor
    func duplicateLocalTab(_ id: UUID, settings: AppSettings) {
        guard let sourceTab = localTabs.first(where: { $0.id == id }) else { return }
        localTabCounter += 1
        var config = GhosttySurfaceConfiguration()
        config.fontSize = Float(settings.fontSize)
        config.environmentVariables = LocalShellEnvironment.make()
        config.workingDirectory = NSHomeDirectory()

        let surface = GhosttySurfaceView(config: config)
        let newTab = LocalTerminalTab(id: UUID(), name: "\(sourceTab.name) (Copy)", surfaceView: surface)
        if let index = localTabs.firstIndex(where: { $0.id == id }) {
            localTabs.insert(newTab, at: index + 1)
        } else {
            localTabs.append(newTab)
        }
        sidebarSelection = .localTab(newTab.id)
        persistTabs()
    }

    @MainActor
    func requestReconnect(connectionID: SSHConnection.ID) {
        // Clear the cached surface so the next makeNSView call starts a fresh PTY.
        openTabs.first(where: { $0.connection.id == connectionID })?.cachedSurface = nil
        reconnectRequests[connectionID] = UUID()
    }

    func nextTab() {
        if case .localTab(let currentID) = sidebarSelection {
            guard !localTabs.isEmpty else { return }
            guard let index = localTabs.firstIndex(where: { $0.id == currentID }) else {
                if let first = localTabs.first {
                    sidebarSelection = .localTab(first.id)
                }
                return
            }
            let nextIndex = (index + 1) % localTabs.count
            sidebarSelection = .localTab(localTabs[nextIndex].id)
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
        if case .localTab(let currentID) = sidebarSelection {
            guard !localTabs.isEmpty else { return }
            guard let index = localTabs.firstIndex(where: { $0.id == currentID }) else {
                if let first = localTabs.first {
                    sidebarSelection = .localTab(first.id)
                }
                return
            }
            let nextIndex = (index - 1 + localTabs.count) % localTabs.count
            sidebarSelection = .localTab(localTabs[nextIndex].id)
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
        if case .localTab = sidebarSelection {
            guard index >= 0 && index < localTabs.count else { return }
            sidebarSelection = .localTab(localTabs[index].id)
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

    func importConnectionsData(_ data: Data, mode: ImportMode) throws {
        let decoder = JSONDecoder()
        guard let imported = try? decoder.decode([SSHConnection].self, from: data) else {
            throw NSError(domain: "MacSSH", code: -1, userInfo: [NSLocalizedDescriptionKey: String(localized: "Failed to decode connections")])
        }
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

    func persistTabs() {
        let defaults = UserDefaults.standard
        let connectionIDs = openTabs.map { $0.connection.id.uuidString }
        defaults.set(connectionIDs, forKey: TabKeys.openTabConnections)
        if let selected = selectedTab?.connection.id {
            defaults.set(selected.uuidString, forKey: TabKeys.selectedTabConnection)
        } else {
            defaults.removeObject(forKey: TabKeys.selectedTabConnection)
        }

        let localTabsData = localTabs.map { tab -> [String: String] in
            return [
                "id": tab.id.uuidString,
                "name": tab.name
            ]
        }
        defaults.set(localTabsData, forKey: TabKeys.localTabs)
        defaults.set(selectedLocalTabID?.uuidString, forKey: TabKeys.selectedLocalTabID)
        defaults.set(localTabCounter, forKey: TabKeys.localTabCounter)
        
        saveLocalSessionsHistory()
    }

    // MARK: - Local Terminal Session History

    /// Saves the scrollback history for all active local terminal tabs.
    @MainActor
    func saveLocalSessionsHistory(settings: AppSettings = AppSettings()) {
        guard !isRestoring else { return }
        guard settings.restoreLocalTerminalHistory else { return }
        guard !localTabs.isEmpty else { return }
        let store = SessionHistoryStore.shared
        let activeIDs = Set(localTabs.map { $0.id })

        for tab in localTabs {
            if let text = tab.surfaceView.readFullText(maxLines: settings.scrollbackHistoryLimit) {
                let metadata = SessionHistoryStore.Metadata(
                    quittedAt: Date(),
                    tabName: tab.name
                )
                store.save(tabID: tab.id, text: text, metadata: metadata)
            }
        }

        store.prune(activeTabIDs: activeIDs)
    }

    private static func shellQuoted(_ string: String) -> String {
        "'" + string.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Generates a restore bootstrap script for a local terminal tab if history is present.
    @MainActor
    private static func prepareHistoryRestoreCommand(
        tabID: UUID,
        historyText: String,
        quittedAt: Date,
        restoredAt: Date = Date()
    ) -> String? {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MM/dd HH:mm"
        let quitStr = dateFormatter.string(from: quittedAt)
        let restoreStr = dateFormatter.string(from: restoredAt)

        let dividerQuit = "─── >_* Quitted at \(quitStr) ───"
        let dividerRestore = "─── >_* Restored at \(restoreStr) ───"

        let combined = """
        \(historyText)

        \(dividerQuit)

        \(dividerRestore)

        """

        let tmpTxtPath = NSTemporaryDirectory() + "macssh_restore_\(tabID.uuidString).txt"
        let tmpShPath = NSTemporaryDirectory() + "macssh_restore_\(tabID.uuidString).sh"

        do {
            try combined.write(toFile: tmpTxtPath, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tmpTxtPath)
        } catch {
            NSLog("[MacSSH] Failed to write restore history file: \(error)")
            return nil
        }

        let userShell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let escapedTxtPath = shellQuoted(tmpTxtPath)
        let escapedShPath = shellQuoted(tmpShPath)
        let escapedShell = shellQuoted(userShell)

        let bootstrapScript = """
        #!\(userShell)
        if [ -f \(escapedTxtPath) ]; then
            cat \(escapedTxtPath)
            rm -f \(escapedTxtPath)
        fi
        rm -f \(escapedShPath)
        exec \(escapedShell) -i
        """

        do {
            try bootstrapScript.write(toFile: tmpShPath, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tmpShPath)
        } catch {
            NSLog("[MacSSH] Failed to write restore bootstrap script: \(error)")
            return nil
        }

        NSLog("[MacSSH] History restore prepared successfully for tab \(tabID), script: \(tmpShPath)")
        return tmpShPath
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
        } else if let selectedLocalIDStr = defaults.string(forKey: TabKeys.selectedLocalTabID),
                  let localUUID = UUID(uuidString: selectedLocalIDStr) {
            selectedTabID = openTabs.first?.id
            sidebarSelection = .localTab(localUUID)
        } else {
            selectedTabID = openTabs.first?.id
            if let firstID = openTabs.first?.connection.id {
                sidebarSelection = .connection(firstID)
            } else {
                sidebarSelection = nil
            }
        }
    }

    @MainActor
    func restoreLocalTabs(settings: AppSettings) {
        let defaults = UserDefaults.standard
        self.localTabCounter = defaults.integer(forKey: TabKeys.localTabCounter)
        
        guard let savedTabs = defaults.array(forKey: TabKeys.localTabs) as? [[String: String]],
              !savedTabs.isEmpty else {
            return
        }
        
        let env = LocalShellEnvironment.make()

        for tabDict in savedTabs {
            guard let idString = tabDict["id"],
                  let uuid = UUID(uuidString: idString),
                  let name = tabDict["name"] else {
                continue
            }

            if localTabs.contains(where: { $0.id == uuid }) {
                continue
            }

            var config = GhosttySurfaceConfiguration()
            config.fontSize = Float(settings.fontSize)
            config.environmentVariables = env
            config.workingDirectory = NSHomeDirectory()
            
            if settings.restoreLocalTerminalHistory,
               let (historyText, meta) = SessionHistoryStore.shared.load(tabID: uuid),
               let restoreCmd = Self.prepareHistoryRestoreCommand(
                   tabID: uuid,
                   historyText: historyText,
                   quittedAt: meta.quittedAt
               ) {
                config.command = restoreCmd
            }
            
            let surface = GhosttySurfaceView(config: config)
            let restoredTab = LocalTerminalTab(id: uuid, name: name, surfaceView: surface)
            localTabs.append(restoredTab)
        }
        
        if let selectedIDString = defaults.string(forKey: TabKeys.selectedLocalTabID),
           let selectedUUID = UUID(uuidString: selectedIDString),
           localTabs.contains(where: { $0.id == selectedUUID }) {
            self.selectedLocalTabID = selectedUUID
        } else if sidebarSelection == nil, let first = localTabs.first {
            self.sidebarSelection = .localTab(first.id)
        }
    }

    @MainActor
    func handleURL(_ url: URL) {
        guard let scheme = url.scheme?.lowercased(), scheme == "macssh" else { return }
        
        var host = ""
        var port = 22
        var username = "root"
        
        // Parse macssh://connect?host=xxx&port=xxx&user=xxx
        guard url.host == "connect" else { return }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true) else { return }
        guard let queryItems = components.queryItems else { return }
        
        for item in queryItems {
            if item.name == "host", let val = item.value {
                host = val
            } else if item.name == "port", let val = item.value, let p = Int(val) {
                port = p
            } else if item.name == "user", let val = item.value {
                username = val
            }
        }
        
        guard !host.isEmpty else { return }
        
        // Find existing connection to reuse saved credentials (like Keychain password)
        if let existingConnection = connections.first(where: {
            $0.host.lowercased() == host.lowercased() &&
            $0.port == port &&
            $0.username.lowercased() == username.lowercased()
        }) {
            openConnection(existingConnection)
        } else {
            // Create a new connection profile dynamically
            let newConnection = SSHConnection(
                name: "\(username)@\(host)",
                host: host,
                port: port,
                username: username
            )
            connections.append(newConnection)
            persist()
            openConnection(newConnection)
        }
    }
}
