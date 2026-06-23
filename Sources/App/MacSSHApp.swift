import SwiftUI
import libghostty_swift

@main
struct MacSSHApp: App {
    @StateObject private var updater = Updater()
    @State private var model = AppModel()
    @State private var settings = AppSettings()

    init() {
        // Ensure Ghostty is initialized on the main thread immediately
        _ = GhosttyRuntime.shared
        // Purge any plaintext password / expect files leaked by a prior crash.
        GhosttyTerminalView.cleanupStaleAuthFiles()
    }

    var body: some Scene {
        WindowGroup {
            ContentView(model: model, settings: settings)
                .onAppear {
                    NotificationService.shared.configure(settings: settings)
                    GhosttyRuntime.shared.onTerminalEvent = { event in
                        MainActor.assumeIsolated {
                            NotificationService.shared.notifyTerminal(event)
                        }
                    }
                    NotificationService.shared.requestAuthorizationIfNeeded()
                }
                .onOpenURL { url in
                    model.handleURL(url)
                }
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Button(String(localized: "Check for Updates...")) {
                    updater.checkForUpdates()
                }
                .disabled(!updater.canCheckForUpdates)
            }

            CommandMenu(String(localized: "Session")) {
                Button(String(localized: "Reconnect")) {
                    if let connectionID = model.selectedTab?.connection.id {
                        model.requestReconnect(connectionID: connectionID)
                    }
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(model.selectedTab == nil)

                Button(String(localized: "Close Tab")) {
                    if model.sidebarSelection == .localTerminal {
                        if let id = model.selectedLocalTabID {
                            model.removeLocalTab(id)
                        }
                    } else if let tabID = model.selectedTabID {
                        model.closeTab(tabID)
                    }
                }
                .keyboardShortcut("w", modifiers: .command)
                .disabled(model.sidebarSelection == .localTerminal
                          ? model.localTabs.count <= 1
                          : model.selectedTabID == nil)
            }
            
            CommandMenu(String(localized: "Tab")) {
                Button(String(localized: "Next Tab")) {
                    model.nextTab()
                }
                .keyboardShortcut("]", modifiers: .command)
                
                Button(String(localized: "Previous Tab")) {
                    model.previousTab()
                }
                .keyboardShortcut("[", modifiers: .command)

                Button(String(localized: "Rename Tab")) {
                    if let id = model.selectedLocalTabID,
                       let tab = model.localTabs.first(where: { $0.id == id }) {
                        tab.isRenaming = true
                    }
                }
                .disabled(model.sidebarSelection != .localTerminal || model.selectedLocalTabID == nil)

                Divider()
                
                if model.sidebarSelection == .localTerminal {
                    // Show Local Terminal tabs
                    let tabs = Array(model.localTabs.prefix(9))
                    ForEach(Array(tabs.enumerated()), id: \.element.id) { index, tab in
                        Button(tab.name) {
                            model.selectTab(at: index)
                        }
                        .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                    }
                } else if !model.openTabs.isEmpty {
                    // Show SSH session tabs (if any exist)
                    let tabs = Array(model.openTabs.prefix(9))
                    ForEach(Array(tabs.enumerated()), id: \.element.id) { index, tab in
                        Button(tab.connection.name) {
                            model.selectTab(at: index)
                        }
                        .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                    }
                }
            }
        }

        Settings {
            SettingsView(settings: settings, model: model)
        }
    }
}
