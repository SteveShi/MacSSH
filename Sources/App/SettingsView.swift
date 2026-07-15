import SwiftUI

struct SettingsView: View {
    @Bindable var settings: AppSettings
    @Bindable var model: AppModel
    
    @State private var pendingImportURL: URL?
    @State private var showImportDialog: Bool = false
    @State private var importMode: ImportMode = .merge
    @State private var syncStatus: String = ""
    @State private var syncSuccess: Bool = true
    
    private enum Tab: String, CaseIterable, Identifiable {
        case general, appearance, terminal, sftp, data, sync, about
        var id: String { rawValue }
        
        var label: String {
            switch self {
            case .general: return String(localized: "General")
            case .appearance: return String(localized: "Appearance")
            case .terminal: return String(localized: "Terminal")
            case .sftp: return String(localized: "SFTP")
            case .data: return String(localized: "Data")
            case .sync: return String(localized: "Sync")
            case .about: return String(localized: "About")
            }
        }
        
        var icon: String {
            switch self {
            case .general: return "gearshape"
            case .appearance: return "paintpalette"
            case .terminal: return "terminal"
            case .sftp: return "folder.badge.plus"
            case .data: return "square.and.arrow.up.on.square"
            case .sync: return "arrow.triangle.2.circlepath"
            case .about: return "info.circle"
            }
        }
    }
    
    @SceneStorage("settingsSelectedTab") private var selectedTab: Tab = .general

    var body: some View {
        TabView(selection: $selectedTab) {
            generalTab
                .tabItem {
                    Label(Tab.general.label, systemImage: Tab.general.icon)
                }
                .tag(Tab.general)
            
            appearanceTab
                .tabItem {
                    Label(Tab.appearance.label, systemImage: Tab.appearance.icon)
                }
                .tag(Tab.appearance)
            
            terminalTab
                .tabItem {
                    Label(Tab.terminal.label, systemImage: Tab.terminal.icon)
                }
                .tag(Tab.terminal)
            
            sftpTab
                .tabItem {
                    Label(Tab.sftp.label, systemImage: Tab.sftp.icon)
                }
                .tag(Tab.sftp)
            
            dataTab
                .tabItem {
                    Label(Tab.data.label, systemImage: Tab.data.icon)
                }
                .tag(Tab.data)
            
            syncTab
                .tabItem {
                    Label(Tab.sync.label, systemImage: Tab.sync.icon)
                }
                .tag(Tab.sync)
            
            aboutTab
                .tabItem {
                    Label(Tab.about.label, systemImage: Tab.about.icon)
                }
                .tag(Tab.about)
        }
        .frame(width: 500, height: 400)
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
            Text(String(localized: "Choose how to import connections. 'Merge' will add new connections from the file, while 'Replace All' will remove all existing data first."))
        }
    }
    
    @State private var availableInputSources: [InputSourceManager.InputSource] = []

    private var generalTab: some View {
        Form {
            Section {
                Text(String(localized: "Application behavior and general preferences."))
                    .foregroundStyle(.secondary)
            } header: {
                Text(String(localized: "App Behavior"))
            }
            
            Section {
                Toggle(String(localized: "Confirm before disconnecting"), isOn: $settings.confirmBeforeDisconnect)
                Toggle(String(localized: "Automatically reconnect on failure"), isOn: $settings.autoReconnect)
            }

            Section {
                Picker(String(localized: "Default Input Method"), selection: $settings.defaultInputSourceID) {
                    Text(String(localized: "Do Not Switch")).tag("")
                    ForEach(availableInputSources) { source in
                        Text(source.localizedName).tag(source.id)
                    }
                }
            } header: {
                Text(String(localized: "Input Method"))
            } footer: {
                Text(String(localized: "Automatically switch to the selected input method when the app is activated."))
            }

            Section {
                Toggle(String(localized: "Enable Notifications"), isOn: $settings.notificationsEnabled)
                Group {
                    Toggle(String(localized: "SSH connection events"), isOn: $settings.notifyConnectionEvents)
                    Toggle(String(localized: "SFTP transfer events"), isOn: $settings.notifySFTPEvents)
                    Toggle(String(localized: "Terminal app notifications & process exit"), isOn: $settings.notifyTerminalEvents)
                    Toggle(String(localized: "Terminal Bell"), isOn: $settings.notifyTerminalBell)
                    Toggle(String(localized: "Only when app is in the background"), isOn: $settings.notifyOnlyWhenInactive)
                }
                .disabled(!settings.notificationsEnabled)
            } header: {
                Text(String(localized: "Notifications"))
            } footer: {
                Text(String(localized: "Receive system notifications for connection, transfer, and terminal events."))
            }
        }
        .formStyle(.grouped)
        .onAppear {
            availableInputSources = InputSourceManager.enabledInputSources()
        }
    }
    
    private var terminalTab: some View {
        Form {
            Section {
                Picker(String(localized: "Theme"), selection: $settings.theme) {
                    ForEach(AppSettings.TerminalTheme.allCases) { theme in
                        Text(theme.rawValue.capitalized).tag(theme)
                    }
                }
            } header: {
                Text(String(localized: "Engine"))
            }

            Section {
                Picker(String(localized: "Font Family"), selection: $settings.fontName) {
                    ForEach(settings.availableFonts, id: \.self) { font in
                        Text(font).tag(font)
                    }
                }
                
                HStack {
                    Text(String(localized: "Font Size"))
                    Slider(value: $settings.fontSize, in: 9...24, step: 1)
                    Text("\(Int(settings.fontSize))")
                        .monospacedDigit()
                        .frame(width: 30)
                }
            } header: {
                Text(String(localized: "Typography"))
            }
        }
        .formStyle(.grouped)
    }

    private var appearanceTab: some View {
        Form {
            Section {
                Toggle(String(localized: "Enable Vibrancy (Glass Effect)"), isOn: $settings.vibrancyEnabled)
                Toggle(String(localized: "Show Subtle Grid"), isOn: $settings.showGrid)
                Toggle(String(localized: "Enable Terminal Text Glow"), isOn: $settings.terminalGlow)
            } header: {
                Text(String(localized: "Premium Effects"))
            } footer: {
                Text(String(localized: "Enable these effects for a more modern, state-of-the-art macOS experience."))
            }

            Section {
                HStack {
                    Text(String(localized: "Terminal Engine"))
                    Spacer()
                    Text(String(localized: "Native Ghostty (Metal)"))
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text(String(localized: "Rendering"))
            }
        }
        .formStyle(.grouped)
    }
    
    private var sftpTab: some View {
        Form {
            Section {
                Text(String(localized: "Configure SFTP file transfer preferences."))
                    .foregroundStyle(.secondary)
            } header: {
                Text(String(localized: "Transfers"))
            }
            
            Section {
                Toggle(String(localized: "Show hidden files"), isOn: $settings.showHiddenFiles)
                Toggle(String(localized: "Overwrite existing files"), isOn: $settings.overwriteExistingFiles)
            }
        }
        .formStyle(.grouped)
    }

    private var dataTab: some View {
        Form {
            Section {
                Text(String(localized: "Manage your connection data. You can back up all your SSH server configurations to a JSON file and restore them later."))
                    .foregroundStyle(.secondary)
            } header: {
                Text(String(localized: "Backup & Restore"))
            }

            Section {
                Button {
                    exportConnections()
                } label: {
                    Label(String(localized: "Export Connections..."), systemImage: "square.and.arrow.up")
                }
                
                Button {
                    importConnections()
                } label: {
                    Label(String(localized: "Import Connections..."), systemImage: "square.and.arrow.down")
                }
            }
        }
        .formStyle(.grouped)
    }

    private var syncTab: some View {
        Form {
            Section {
                Text(String(localized: "Configure cloud synchronization for all your connection configurations."))
                    .foregroundStyle(.secondary)
            } header: {
                Text(String(localized: "Cloud Sync"))
            }

            Section {
                Toggle(String(localized: "Encrypt Sync Data"), isOn: $settings.syncEncryptData)
                if settings.syncEncryptData {
                    SecureField(String(localized: "Sync Master Password"), text: $settings.syncMasterPassword)
                }
            } header: {
                Text(String(localized: "Security"))
            }

            Section {
                TextField(String(localized: "Personal Access Token"), text: $settings.syncGithubToken)
                TextField(String(localized: "Gist ID (Optional)"), text: $settings.syncGithubGistId)
                
                HStack(spacing: 12) {
                    Button(String(localized: "Upload to Gist")) {
                        Task {
                            await performGistSync(upload: true)
                        }
                    }
                    .disabled(settings.syncGithubToken.isEmpty || (settings.syncEncryptData && settings.syncMasterPassword.isEmpty))
                    
                    Button(String(localized: "Download & Merge")) {
                        Task {
                            await performGistSync(upload: false)
                        }
                    }
                    .disabled(settings.syncGithubToken.isEmpty || settings.syncGithubGistId.isEmpty)
                }
            } header: {
                Text(String(localized: "GitHub Gist"))
            }

            Section {
                SecureField(String(localized: "Access Token"), text: $settings.syncDropboxToken)
                
                HStack(spacing: 12) {
                    Button(String(localized: "Upload to Dropbox")) {
                        Task {
                            await performDropboxSync(upload: true)
                        }
                    }
                    .disabled(settings.syncDropboxToken.isEmpty || (settings.syncEncryptData && settings.syncMasterPassword.isEmpty))
                    
                    Button(String(localized: "Download & Merge")) {
                        Task {
                            await performDropboxSync(upload: false)
                        }
                    }
                    .disabled(settings.syncDropboxToken.isEmpty)
                }
            } header: {
                Text(String(localized: "Dropbox"))
            }

            if !syncStatus.isEmpty {
                Section {
                    Text(syncStatus)
                        .foregroundStyle(syncSuccess ? .green : .red)
                        .font(.subheadline)
                        .textSelection(.enabled)
                } header: {
                    Text(String(localized: "Sync Status"))
                }
            }
        }
        .formStyle(.grouped)
    }

    private func performGistSync(upload: Bool) async {
        syncStatus = String(localized: "Syncing...")
        syncSuccess = true
        do {
            let password = settings.syncEncryptData ? settings.syncMasterPassword : nil
            if upload {
                let gistId = try await GistSyncService.upload(
                    token: settings.syncGithubToken,
                    gistId: settings.syncGithubGistId,
                    connections: model.connections,
                    password: password
                )
                settings.syncGithubGistId = gistId
                syncStatus = String(localized: "Successfully uploaded to Gist.")
            } else {
                let data = try await GistSyncService.download(
                    token: settings.syncGithubToken,
                    gistId: settings.syncGithubGistId
                )
                
                let finalData: Data
                if let contentString = String(data: data, encoding: .utf8), contentString.hasPrefix("MACSSH_ENC:") {
                    guard !settings.syncMasterPassword.isEmpty else {
                        throw NSError(domain: "MacSSH", code: -1, userInfo: [NSLocalizedDescriptionKey: String(localized: "Data is encrypted. Please provide your master password.")])
                    }
                    let decryptedString = try EncryptionHelper.decrypt(encryptedText: contentString, password: settings.syncMasterPassword)
                    guard let decryptedData = decryptedString.data(using: .utf8) else {
                        throw NSError(domain: "MacSSH", code: -1, userInfo: [NSLocalizedDescriptionKey: String(localized: "Failed to convert decrypted text to data")])
                    }
                    finalData = decryptedData
                } else {
                    finalData = data
                }
                
                try model.importConnectionsData(finalData, mode: .merge)
                syncStatus = String(localized: "Successfully downloaded and merged from Gist.")
            }
        } catch {
            syncSuccess = false
            syncStatus = String(localized: "Gist sync failed: ") + error.localizedDescription
        }
    }

    private func performDropboxSync(upload: Bool) async {
        syncStatus = String(localized: "Syncing...")
        syncSuccess = true
        do {
            let password = settings.syncEncryptData ? settings.syncMasterPassword : nil
            if upload {
                try await DropboxSyncService.upload(
                    token: settings.syncDropboxToken,
                    connections: model.connections,
                    password: password
                )
                syncStatus = String(localized: "Successfully uploaded to Dropbox.")
            } else {
                let data = try await DropboxSyncService.download(token: settings.syncDropboxToken)
                
                let finalData: Data
                if let contentString = String(data: data, encoding: .utf8), contentString.hasPrefix("MACSSH_ENC:") {
                    guard !settings.syncMasterPassword.isEmpty else {
                        throw NSError(domain: "MacSSH", code: -1, userInfo: [NSLocalizedDescriptionKey: String(localized: "Data is encrypted. Please provide your master password.")])
                    }
                    let decryptedString = try EncryptionHelper.decrypt(encryptedText: contentString, password: settings.syncMasterPassword)
                    guard let decryptedData = decryptedString.data(using: .utf8) else {
                        throw NSError(domain: "MacSSH", code: -1, userInfo: [NSLocalizedDescriptionKey: String(localized: "Failed to convert decrypted text to data")])
                    }
                    finalData = decryptedData
                } else {
                    finalData = data
                }
                
                try model.importConnectionsData(finalData, mode: .merge)
                syncStatus = String(localized: "Successfully downloaded and merged from Dropbox.")
            }
        } catch {
            syncSuccess = false
            syncStatus = String(localized: "Dropbox sync failed: ") + error.localizedDescription
        }
    }
    
    // MARK: - Handlers
    
    private func exportConnections() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "connections.json"
        panel.title = String(localized: "Export Connections")
        if panel.runModal() == .OK, let url = panel.url {
            model.exportConnections(to: url)
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
    
    private var aboutTab: some View {
        VStack(spacing: 20) {
            Image(systemName: "desktopcomputer")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 64, height: 64)
                .foregroundStyle(Color.accentColor)
            
            VStack(spacing: 4) {
                Text(String(localized: "MacSSH"))
                    .font(.title).bold()
                let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–"
                let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "–"
                Text("Version \(version) (\(build))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            Text(String(localized: "A modern SSH client for macOS."))
                .font(.body)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Divider()
                .padding(.horizontal, 40)
            
            Text(String(localized: "© 2026 Steve"))
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }
}
