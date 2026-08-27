import SwiftUI
import AppKit

struct TerminalView: View {
    let tab: SessionTab
    let settings: AppSettings
    @Bindable var appModel: AppModel

    private var model: TerminalSessionViewModel {
        tab.terminalModel
    }

    var body: some View {
        @Bindable var model = self.model
        @Bindable var settings = self.settings
        @Bindable var tab = self.tab

        VStack(spacing: 0) {
            let mainTerminal = GhosttyTerminalView(tab: tab, settings: settings)
                .id("ghostty-\(tab.id)-\(appModel.reconnectRequests[tab.connection.id]?.uuidString ?? "")")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            if tab.isSplit, let splitSurface = tab.splitSurface {
                let splitView = SurfaceViewHost(surface: splitSurface)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                SplitTerminalLayout(direction: tab.splitDirection) {
                    mainTerminal
                } split: {
                    splitView
                }
            } else {
                mainTerminal
            }

            // Bottom Status Bar placed inside VStack so it never overlaps terminal prompt
            TerminalStatusBar(
                connection: tab.connection,
                status: model.status,
                metrics: model.metrics,
                connectedAt: model.connectedAt
            )
        }
        .background(Color(red: 36.0 / 255.0, green: 39.0 / 255.0, blue: 46.0 / 255.0))
        .navigationTitle("")
        .inspector(isPresented: $tab.showInspector) {
            InspectorContentView(tab: tab, appModel: appModel)
        }
        .inspectorColumnWidth(min: 280, ideal: 340, max: 600)
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
        .task {
            model.appModel = appModel
            model.connect()
        }
        .confirmationDialog(
            hostKeyPromptTitle,
            isPresented: hostKeyPromptBinding,
            titleVisibility: .visible
        ) {
            Button(String(localized: "Trust and Continue")) {
                model.trustHostKeyAndConnect()
            }
            Button(String(localized: "Cancel"), role: .cancel) {
                model.hostKeyPrompt = nil
            }
        } message: {
            Text(hostKeyPromptMessage)
        }
    }

    @ViewBuilder
    private var toolbarActionButtons: some View {
        @Bindable var tab = self.tab
        let isConnected = model.status == .connected
        
        if !isConnected {
            Button {
                appModel.requestReconnect(connectionID: tab.connection.id)
            } label: {
                Label(String(localized: "Connect"), systemImage: "play.fill")
            }
            .help(String(localized: "Start Terminal Session"))
        } else {
            Button {
                appModel.requestReconnect(connectionID: tab.connection.id)
            } label: {
                Label(String(localized: "Reconnect"), systemImage: "arrow.clockwise")
            }
            .help(String(localized: "Restart Terminal Session"))
        }

        Button {
            appModel.closeTab(tab.id)
        } label: {
            Label(String(localized: "Disconnect"), systemImage: "stop.fill")
        }
        .help(String(localized: "Close Session Tab"))
        .foregroundStyle(.red)

        Toggle(isOn: $tab.showInspector) {
            Label(String(localized: "SFTP"), systemImage: "sidebar.right")
        }
        .toggleStyle(.button)
        .help(String(localized: "Show SFTP Inspector"))
    }

    private var hostKeyPromptTitle: String {
        guard let prompt = model.hostKeyPrompt else { return "" }
        switch prompt.status {
        case .notFound:
            return String(localized: "Unknown Host Key")
        case .mismatch:
            return String(localized: "Host Key Changed")
        }
    }

    private var hostKeyPromptMessage: String {
        guard let prompt = model.hostKeyPrompt else { return "" }
        switch prompt.status {
        case .notFound:
            return String(localized: "The authenticity of \(prompt.host) can't be established. Do you want to trust this host key and continue?")
        case .mismatch:
            return String(localized: "WARNING: The host key for \(prompt.host) has changed. This could indicate a security issue. Only continue if you trust the new key.")
        }
    }

    private var hostKeyPromptBinding: Binding<Bool> {
        Binding(
            get: { model.hostKeyPrompt != nil },
            set: { newValue in
                if !newValue { model.hostKeyPrompt = nil }
            }
        )
    }
}
