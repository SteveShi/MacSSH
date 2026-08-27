import SwiftUI
import AppKit
import MactermKit

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
            if (model.status == .idle || model.status == .failed(model.lastErrorMessage ?? "")) && tab.cachedSurface == nil {
                unconnectedPromptView
            } else {
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

    // MARK: - Unconnected Prompt View

    @ViewBuilder
    private var unconnectedPromptView: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "desktopcomputer")
                .font(.system(size: 48))
                .foregroundStyle(Color.secondary.opacity(0.7))

            VStack(spacing: 6) {
                Text(tab.connection.name)
                    .font(.title2.bold())
                    .foregroundStyle(.primary)

                Text("\(tab.connection.username)@\(tab.connection.host):\(tab.connection.port)")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            if case .failed(let reason) = model.status {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.red.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            Button {
                startConnection()
            } label: {
                HStack(spacing: 8) {
                    if model.status == .connecting {
                        ProgressView()
                            .controlSize(.small)
                        Text(String(localized: "Connecting..."))
                    } else {
                        Image(systemName: "play.fill")
                        Text(String(localized: "Connect"))
                    }
                }
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 18)
                .padding(.vertical, 7)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0.2, green: 0.85, blue: 0.4))
            .controlSize(.large)
            .disabled(model.status == .connecting)
            .keyboardShortcut(.return, modifiers: [])

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 36.0 / 255.0, green: 39.0 / 255.0, blue: 46.0 / 255.0))
    }

    // MARK: - Actions

    private func startConnection() {
        model.appModel = appModel
        model.connect()
        appModel.requestReconnect(connectionID: tab.connection.id)
    }

    private func stopConnection() {
        model.disconnect()
        tab.cachedSurface = nil
        tab.closeSplit()
    }

    // MARK: - Toolbar Buttons

    @ViewBuilder
    private var toolbarActionButtons: some View {
        @Bindable var tab = self.tab
        let isConnected = model.status == .connected

        if !isConnected {
            Button {
                startConnection()
            } label: {
                Label(String(localized: "Connect"), systemImage: "play.fill")
            }
            .help(String(localized: "Start Terminal Session"))
            .disabled(model.status == .connecting)
        } else {
            Button {
                startConnection()
            } label: {
                Label(String(localized: "Reconnect"), systemImage: "arrow.clockwise")
            }
            .help(String(localized: "Restart Terminal Session"))

            Button {
                stopConnection()
            } label: {
                Label(String(localized: "Disconnect"), systemImage: "stop.fill")
            }
            .help(String(localized: "Disconnect Session"))
            .foregroundStyle(.red)
        }

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
