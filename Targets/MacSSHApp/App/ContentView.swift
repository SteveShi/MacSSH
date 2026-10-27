import SwiftUI
import AppKit
import SSH2Kit
import MactermKit

// MARK: - Sidebar Tab Enum

enum SidebarTab: String, CaseIterable {
    case local
    case remote
}

// MARK: - ContentView

struct ContentView: View {
    @Bindable var model: AppModel
    @Bindable var settings: AppSettings
    @State private var editorConnection: SSHConnection?
    @State private var showingDeleteAlert: Bool = false
    @AppStorage("sidebarTab") private var sidebarTab: SidebarTab = .remote
    @AppStorage("lastSeenWhatsNewVersion") private var lastSeenWhatsNewVersion: String = ""

    var body: some View {
        splitView
        .frame(minWidth: 850, minHeight: 560)
        .background(WindowAccessor(settings: settings))
        .sheet(isPresented: $model.showingWhatsNew) {
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
        .onChange(of: model.sidebarSelection) { oldValue, newValue in
            triggerInputSourceSwitch()
            if oldValue != newValue, case .connection(let oldId) = oldValue {
                let oldTab = model.openTabs.first(where: { $0.connection.id == oldId })
                oldTab?.cachedSurface?.setOccluded(true)
                oldTab?.splitSurface?.setOccluded(true)
            }
            switch newValue {
            case .localTab(let id):
                if sidebarTab != .local { sidebarTab = .local }
                model.localTabs.first(where: { $0.id == id })?.programStatusStore.acknowledgeDoneStatuses()
            case .connection(let id):
                if sidebarTab != .remote { sidebarTab = .remote }
                let openTab = model.openTabs.first(where: { $0.connection.id == id })
                openTab?.cachedSurface?.setOccluded(false)
                openTab?.splitSurface?.setOccluded(false)
                openTab?.programStatusStore.acknowledgeDoneStatuses()
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
            if lastSeenWhatsNewVersion != "2.4.0" {
                model.showingWhatsNew = true
                lastSeenWhatsNewVersion = "2.4.0"
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
                .background(ThemeColors.sidebarBackground(isDark: settings.isDarkMode))
        } detail: {
            Group {
                if case .localTab = model.sidebarSelection {
                    LocalTerminalView(settings: settings, appModel: model)
                } else if case .connection(let id) = model.sidebarSelection {
                    if let conn = model.connections.first(where: { $0.id == id }) {
                        let tab = model.tabForConnection(conn)
                        TerminalView(tab: tab, settings: settings, appModel: model)
                    } else {
                        EmptyStateView()
                    }
                } else {
                    if let firstLocal = model.localTabs.first {
                        LocalTerminalView(settings: settings, appModel: model)
                    } else if let firstConn = model.connections.first {
                        let tab = model.tabForConnection(firstConn)
                        TerminalView(tab: tab, settings: settings, appModel: model)
                    } else {
                        EmptyStateView()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ThemeColors.terminalBackground(isDark: settings.isDarkMode))
            .toolbarBackground(.hidden, for: .windowToolbar)
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    TitlebarSessionTabBar(
                        model: model,
                        settings: settings,
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
        .confirmationDialog(
            String(localized: "Disconnect Session"),
            isPresented: Binding(
                get: { model.pendingDisconnectTab != nil },
                set: { if !$0 { model.pendingDisconnectTab = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(String(localized: "Disconnect"), role: .destructive) {
                model.confirmClosePendingTab()
            }
            Button(String(localized: "Cancel"), role: .cancel) {
                model.pendingDisconnectTab = nil
            }
        } message: {
            if let tab = model.pendingDisconnectTab {
                Text(String(localized: "Are you sure you want to disconnect from \(tab.connection.name)?"))
            } else {
                Text(String(localized: "Are you sure you want to disconnect?"))
            }
        }
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
        .overlay(alignment: .top) {
            ToastOverlayView()
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
                let openTab = model.openTabs.first(where: { $0.connection.id == connection.id })
                let isConnected = openTab?.terminalModel.status == .connected
                let isSelected = model.sidebarSelection == .connection(connection.id)
                BerthHostRow(
                    connection: connection,
                    isSelected: isSelected,
                    isConnected: isConnected,
                    programStatusStore: openTab?.programStatusStore,
                    onSelect: {
                        model.sidebarSelection = .connection(connection.id)
                        if let openTab {
                            model.selectedTabID = openTab.id
                        }
                    }
                )
                .contextMenu {
                    connectionContextMenu(for: connection)
                }
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
                model.requestCloseTab(tab.id, settings: settings)
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
    var programStatusStore: TerminalProgramStatusStore? = nil
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

            if let store = programStatusStore {
                ProgramStatusBadgeView(store: store)
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

            ProgramStatusBadgeView(store: tab.programStatusStore)

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

// MARK: - Window Frame Store & Accessor

enum WindowFrameStore {
    static let frameKey = "MacSSHMainWindowFrame"
    static let minWindowWidth: CGFloat = 850
    static let minWindowHeight: CGFloat = 560
    static let defaultWindowWidth: CGFloat = 1120
    static let defaultWindowHeight: CGFloat = 720

    /// Provides the persisted window size to SwiftUI's `WindowGroup.defaultSize`
    /// so SwiftUI's own scene-sizing engine creates the window at the saved size from frame 0.
    static var initialDefaultSize: CGSize {
        guard let frameString = UserDefaults.standard.string(forKey: frameKey),
              !frameString.isEmpty else {
            return CGSize(width: defaultWindowWidth, height: defaultWindowHeight)
        }
        let rawRect = NSRectFromString(frameString)
        guard rawRect.width >= minWindowWidth, rawRect.height >= minWindowHeight else {
            return CGSize(width: defaultWindowWidth, height: defaultWindowHeight)
        }
        return CGSize(width: rawRect.width, height: rawRect.height)
    }
}

private struct WindowAccessor: NSViewRepresentable {
    let settings: AppSettings

    func makeNSView(context: Context) -> WindowAccessorView {
        let view = WindowAccessorView()
        view.settings = settings
        return view
    }

    func updateNSView(_ nsView: WindowAccessorView, context: Context) {
        nsView.settings = settings
        nsView.applyAppearance()
    }
}

/// Configures the host NSWindow's appearance and deterministically persists/restores
/// the window frame under a stable UserDefaults key.
///
/// Guardrails against SwiftUI/AppKit window-sizing races:
/// 1. Snapshot the saved frame from UserDefaults BEFORE mutating window style/toolbar
///    or registering NotificationCenter observers.
/// 2. Lock out persistence (`isRestoringFrame = true`) during the initial launch and
///    SwiftUI NavigationSplitView / .inspector layout passes so initial placement
///    notifications (`didMoveNotification` / `didResizeNotification`) never clobber
///    the saved frame in UserDefaults.
/// 3. Apply the restored frame synchronously in `viewDidMoveToWindow()` and re-assert
///    it across initial layout checkpoints if SwiftUI resets the window geometry.
/// 4. Observe all resize/move/lifecycle notifications (`didResize`, `didEndLiveResize`,
///    `didMove`, `didExitFullScreen`, `didResignActive`, `willClose`, `willTerminate`)
///    and freeze persistence once close/termination starts.
private final class WindowAccessorView: NSView {
    private static let frameKey = WindowFrameStore.frameKey
    private static let minWindowWidth: CGFloat = WindowFrameStore.minWindowWidth
    private static let minWindowHeight: CGFloat = WindowFrameStore.minWindowHeight

    private weak var configuredWindow: NSWindow?
    private var targetRestoredFrame: NSRect?
    private var isRestoringFrame = false
    private var hasCompletedInitialRestore = false
    private var isApplyingProgrammaticFrame = false
    private var isWindowClosingOrTerminating = false
    var settings: AppSettings?

    func applyAppearance() {
        guard let window else { return }
        let isDark = settings?.isDarkMode ?? AppearanceController.shared.isDark
        window.backgroundColor = ThemeColors.terminalBackgroundNSColor(isDark: isDark)
        // Inherit from NSApp.appearance (driven by AppearanceController); a
        // per-window override would desync from the app-wide resolved appearance.
        window.appearance = nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        if configuredWindow === window {
            applyAppearance()
            return
        }

        NotificationCenter.default.removeObserver(self)
        configuredWindow = window

        Self.purgeLegacySwiftUIWindowFrameKeys()

        // 1. Snapshot the saved frame BEFORE any window style mutation or observer registration.
        targetRestoredFrame = Self.loadValidatedSavedFrame(for: window)
        isRestoringFrame = true
        hasCompletedInitialRestore = false
        isWindowClosingOrTerminating = false

        // 2. Configure window chrome and appearance.
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.styleMask.insert(.fullSizeContentView)
        window.titleVisibility = .hidden
        window.toolbarStyle = .unified
        window.isMovableByWindowBackground = true
        window.minSize = NSSize(width: Self.minWindowWidth, height: Self.minWindowHeight)
        window.isRestorable = false
        window.setFrameAutosaveName("")

        applyAppearance()

        // 3. Apply the saved frame synchronously before the window is ordered on screen.
        if let target = targetRestoredFrame {
            applyFrameIfNeeded(target, to: window, display: false)
        }

        // 4. Register appearance and geometry/lifecycle observers.
        let center = NotificationCenter.default
        center.addObserver(
            self, selector: #selector(handleAppearanceChange),
            name: .terminalAppearanceDidChange, object: nil
        )

        center.addObserver(
            self, selector: #selector(handleWillStartLiveResize),
            name: NSWindow.willStartLiveResizeNotification, object: window
        )
        center.addObserver(
            self, selector: #selector(handleWindowGeometryChange),
            name: NSWindow.didResizeNotification, object: window
        )
        center.addObserver(
            self, selector: #selector(handleWindowGeometryChange),
            name: NSWindow.didEndLiveResizeNotification, object: window
        )
        center.addObserver(
            self, selector: #selector(handleWindowGeometryChange),
            name: NSWindow.didMoveNotification, object: window
        )
        center.addObserver(
            self, selector: #selector(handleWindowGeometryChange),
            name: NSWindow.didExitFullScreenNotification, object: window
        )
        center.addObserver(
            self, selector: #selector(handleWindowDidBecomeKey),
            name: NSWindow.didBecomeKeyNotification, object: window
        )
        center.addObserver(
            self, selector: #selector(handleAppDidResignActive),
            name: NSApplication.didResignActiveNotification, object: nil
        )
        center.addObserver(
            self, selector: #selector(handleWindowWillCloseOrTerminate),
            name: NSWindow.willCloseNotification, object: window
        )
        center.addObserver(
            self, selector: #selector(handleWindowWillCloseOrTerminate),
            name: NSApplication.willTerminateNotification, object: nil
        )

        // 5. Re-assert restored frame across SwiftUI's multi-pass launch layout
        // (WindowGroup presentation, onAppear tab restoration, NavigationSplitView
        // and .inspector column attachment), then unlock persistence.
        for delay in [0.0, 0.05, 0.15, 0.30] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.reassertRestoredFrame()
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.60) { [weak self] in
            self?.completeInitialRestoration()
        }
    }

    @objc private func handleAppearanceChange() {
        DispatchQueue.main.async { [weak self] in
            self?.applyAppearance()
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Frame Restoration & Persistence

    private func isUserInteractingWithWindow(_ window: NSWindow) -> Bool {
        window.inLiveResize || (window.isVisible && window.isKeyWindow && NSEvent.pressedMouseButtons != 0)
    }

    private func unlockRestorationForUserInteraction() {
        guard isRestoringFrame else { return }
        isRestoringFrame = false
        hasCompletedInitialRestore = true
        targetRestoredFrame = nil
    }

    private func reassertRestoredFrame() {
        guard isRestoringFrame, !isWindowClosingOrTerminating, let window = configuredWindow else { return }
        window.setFrameAutosaveName("")
        if isUserInteractingWithWindow(window) {
            unlockRestorationForUserInteraction()
            persistCurrentFrame(of: window)
            return
        }
        if let target = targetRestoredFrame {
            applyFrameIfNeeded(target, to: window, display: window.isVisible)
        }
    }

    private func completeInitialRestoration() {
        guard isRestoringFrame, !isWindowClosingOrTerminating else { return }
        if let window = configuredWindow {
            window.setFrameAutosaveName("")
            if !isUserInteractingWithWindow(window), let target = targetRestoredFrame {
                applyFrameIfNeeded(target, to: window, display: window.isVisible)
            }
        }
        isRestoringFrame = false
        hasCompletedInitialRestore = true
        targetRestoredFrame = nil
        if let window = configuredWindow {
            persistCurrentFrame(of: window)
        }
    }

    @objc private func handleWillStartLiveResize(_ notification: Notification) {
        // User manually grabbed the window edge/corner: release restoration lock immediately.
        unlockRestorationForUserInteraction()
    }

    @objc private func handleWindowDidBecomeKey(_ notification: Notification) {
        guard isRestoringFrame, !isWindowClosingOrTerminating, let window = configuredWindow else { return }
        window.setFrameAutosaveName("")
        if let target = targetRestoredFrame, !window.inLiveResize {
            applyFrameIfNeeded(target, to: window, display: true)
        }
    }

    @objc private func handleWindowGeometryChange(_ notification: Notification) {
        guard !isApplyingProgrammaticFrame, !isWindowClosingOrTerminating, let window = configuredWindow else { return }

        if isRestoringFrame {
            if isUserInteractingWithWindow(window) {
                unlockRestorationForUserInteraction()
                persistCurrentFrame(of: window)
                return
            }
            // Counteract SwiftUI's initial layout pass if it resets window geometry,
            // and never overwrite UserDefaults with transient launch frames.
            if let target = targetRestoredFrame {
                applyFrameIfNeeded(target, to: window, display: window.isVisible)
            }
            return
        }

        guard hasCompletedInitialRestore else { return }
        persistCurrentFrame(of: window)
    }

    @objc private func handleAppDidResignActive(_ notification: Notification) {
        guard hasCompletedInitialRestore, !isRestoringFrame, !isWindowClosingOrTerminating,
              let window = configuredWindow else { return }
        persistCurrentFrame(of: window)
    }

    @objc private func handleWindowWillCloseOrTerminate(_ notification: Notification) {
        guard !isWindowClosingOrTerminating else { return }
        if hasCompletedInitialRestore, !isRestoringFrame, let window = configuredWindow {
            persistCurrentFrame(of: window)
        }
        // Freeze further writes so view/inspector teardown during close cannot clobber the frame.
        isWindowClosingOrTerminating = true
    }

    private func applyFrameIfNeeded(_ target: NSRect, to window: NSWindow, display: Bool) {
        let clamped = Self.clampFrameToVisibleScreen(target, fallbackWindow: window)
        guard !Self.framesMatch(window.frame, clamped) else { return }
        isApplyingProgrammaticFrame = true
        window.setFrame(clamped, display: display)
        isApplyingProgrammaticFrame = false
    }

    private func persistCurrentFrame(of window: NSWindow) {
        guard hasCompletedInitialRestore, !isRestoringFrame, !isWindowClosingOrTerminating, !isApplyingProgrammaticFrame else { return }
        guard window.isVisible, !window.isMiniaturized else { return }
        guard !window.styleMask.contains(.fullScreen) else { return }

        let frame = window.frame
        guard frame.width >= Self.minWindowWidth, frame.height >= Self.minWindowHeight else { return }

        UserDefaults.standard.set(NSStringFromRect(frame), forKey: Self.frameKey)
    }

    private static func loadValidatedSavedFrame(for window: NSWindow) -> NSRect? {
        guard let frameString = UserDefaults.standard.string(forKey: frameKey), !frameString.isEmpty else {
            return nil
        }
        let rawRect = NSRectFromString(frameString)
        guard rawRect.width >= minWindowWidth, rawRect.height >= minWindowHeight else {
            return nil
        }
        return clampFrameToVisibleScreen(rawRect, fallbackWindow: window)
    }

    private static func clampFrameToVisibleScreen(_ rect: NSRect, fallbackWindow: NSWindow?) -> NSRect {
        let screens = NSScreen.screens
        let bestScreen = screens.max { a, b in
            let areaA = a.frame.intersection(rect)
            let areaB = b.frame.intersection(rect)
            let scoreA = areaA.isNull ? 0 : areaA.width * areaA.height
            let scoreB = areaB.isNull ? 0 : areaB.width * areaB.height
            return scoreA < scoreB
        }

        let targetScreen: NSScreen?
        if let bestScreen, !bestScreen.frame.intersection(rect).isNull {
            targetScreen = bestScreen
        } else {
            targetScreen = fallbackWindow?.screen ?? NSScreen.main ?? screens.first
        }

        guard let visible = targetScreen?.visibleFrame else {
            return NSRect(
                x: rect.origin.x,
                y: rect.origin.y,
                width: max(rect.width, minWindowWidth),
                height: max(rect.height, minWindowHeight)
            )
        }

        let width = min(max(rect.width, minWindowWidth), visible.width)
        let height = min(max(rect.height, minWindowHeight), visible.height)
        let x = min(max(rect.origin.x, visible.minX), visible.maxX - width)
        let y = min(max(rect.origin.y, visible.minY), visible.maxY - height)
        return NSRect(x: x, y: y, width: width, height: height)
    }

    private static func framesMatch(_ a: NSRect, _ b: NSRect, tolerance: CGFloat = 0.5) -> Bool {
        abs(a.origin.x - b.origin.x) <= tolerance &&
        abs(a.origin.y - b.origin.y) <= tolerance &&
        abs(a.size.width - b.size.width) <= tolerance &&
        abs(a.size.height - b.size.height) <= tolerance
    }

    private static func purgeLegacySwiftUIWindowFrameKeys() {
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("NSWindow Frame SwiftUI.") {
            defaults.removeObject(forKey: key)
        }
    }
}
