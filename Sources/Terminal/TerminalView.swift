import SwiftUI
import AppKit

struct TerminalView: View {
    let tab: SessionTab
    let settings: AppSettings
    @Bindable var appModel: AppModel

    @State private var showReconnectError: Bool = false
    @State private var reconnectErrorMessage: String = ""
    @FocusState private var isTerminalFocused: Bool

    private var model: TerminalSessionViewModel {
        tab.terminalModel
    }

    var body: some View {
        @Bindable var model = self.model
        @Bindable var settings = self.settings
        @Bindable var tab = self.tab

        VStack(spacing: 0) {
            // Use GhosttyTerminalView which caches back into tab.cachedSurface on first make.
            // The .id() on reconnectRequests causes it to discard the cached surface and
            // build a fresh one, which reconnects the SSH session.
            GhosttyTerminalView(tab: tab, settings: settings)
                .id("ghostty-\(tab.id)-\(appModel.reconnectRequests[tab.connection.id]?.uuidString ?? "")")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea(.container, edges: .bottom)
        }
        .navigationTitle(tab.connection.name)
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
        .alert(String(localized: "Reconnect Failed"), isPresented: $showReconnectError) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: {
            Text(reconnectErrorMessage)
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
