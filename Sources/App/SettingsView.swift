import SwiftUI

struct SettingsView: View {
    @Bindable var settings: AppSettings
    @Bindable var model: AppModel
    
    @State private var pendingImportURL: URL?
    @State private var showImportDialog: Bool = false
    @State private var importMode: ImportMode = .merge
    
    private enum Tab: String, CaseIterable, Identifiable {
        case general, appearance, terminal, sftp, data, about
        var id: String { rawValue }
        
        var label: String {
            switch self {
            case .general: return String(localized: "General")
            case .appearance: return String(localized: "Appearance")
            case .terminal: return String(localized: "Terminal")
            case .sftp: return String(localized: "SFTP")
            case .data: return String(localized: "Data")
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
            case .about: return "info.circle"
            }
        }
    }
    
    @SceneStorage("settingsSelectedTab") private var selectedTab: Tab = .appearance

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
                Toggle(String(localized: "Confirm before disconnecting"), isOn: .constant(true))
                Toggle(String(localized: "Automatically reconnect on failure"), isOn: .constant(false))
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
                Toggle(String(localized: "Show hidden files"), isOn: .constant(false))
                Toggle(String(localized: "Overwrite existing files"), isOn: .constant(true))
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
                Text(String(localized: "Version 0.1.0 (1)"))
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
