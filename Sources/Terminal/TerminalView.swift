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
                .ignoresSafeArea(.container, edges: .bottom)
            
            if tab.isSplit, let splitSurface = tab.splitSurface {
                let splitView = SurfaceViewHost(surface: splitSurface)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea(.container, edges: .bottom)
                
                SplitTerminalLayout(direction: tab.splitDirection) {
                    mainTerminal
                } split: {
                    splitView
                }
            } else {
                mainTerminal
            }
        }
        .navigationTitle(tab.connection.name)
        .inspector(isPresented: $tab.showInspector) {
            InspectorContentView(tab: tab)
        }
        .inspectorColumnWidth(min: 280, ideal: 340, max: 600)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
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
