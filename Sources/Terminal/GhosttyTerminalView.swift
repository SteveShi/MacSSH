import SwiftUI
import libghostty_swift
import Foundation
import libssh2_swift
import ObjectiveC

// MARK: - Surface View Host (persistent surface reuse)

/// Hosts a pre-existing GhosttySurfaceView without ever creating a new one.
/// Use this when the GhosttySurfaceView is owned by a long-lived model object
/// (SessionTab.cachedSurface, LocalTerminalTab.surfaceView) so that the PTY
/// process survives SwiftUI navigation.
struct SurfaceViewHost: NSViewRepresentable {
    let surface: GhosttySurfaceView

    func makeNSView(context: Context) -> GhosttySurfaceView { surface }
    func updateNSView(_ nsView: GhosttySurfaceView, context: Context) {}
}

// MARK: - GhosttyTerminalView (creates a surface on first use, caches it back)

/// Used by TerminalView (SSH) and LocalTerminalView.
/// Pass a `tab`/`localTab` that stores `cachedSurface`/`surfaceView`.
/// On first make, builds configuration and stores the surface on the caller's model.
struct GhosttyTerminalView: NSViewRepresentable {
    var tab: SessionTab? = nil
    var localTab: LocalTerminalTab? = nil
    let settings: AppSettings

    var configuration: GhosttySurfaceConfiguration {
        var config = GhosttySurfaceConfiguration()
        config.fontSize = Float(settings.fontSize)

        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "xterm-256color"
        config.environmentVariables = env

        if let tab = self.tab {
            let connection = tab.connection

            if !connection.usePublicKey,
               let password = KeychainStore.loadPassword(account: connection.keychainAccount),
               !password.isEmpty {
                let uuidStr = connection.id.uuidString
                let scriptPath = NSTemporaryDirectory() + "macssh_\(uuidStr).exp"
                let pwdPath = NSTemporaryDirectory() + "macssh_\(uuidStr).pwd"

                try? password.write(toFile: pwdPath, atomically: true, encoding: .utf8)
                try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: pwdPath)

                let expectScript = """
                #!/usr/bin/expect -f
                set fp [open \(Self.tclQuoted(pwdPath)) r]
                set pwd [read -nonewline $fp]
                close $fp
                file delete -force \(Self.tclQuoted(pwdPath))
                file delete -force [info script]
                set timeout 30
                spawn /usr/bin/ssh -p \(connection.port) -o StrictHostKeyChecking=no -- \(Self.tclQuoted("\(connection.username)@\(connection.host)"))
                expect {
                    -nocase "*yes/no*" { send -- "yes\\r"; exp_continue }
                    -nocase "*assword:*" { send -- "$pwd\\r" }
                    timeout {}
                    eof { exit }
                }
                set timeout -1
                interact
                """
                try? expectScript.write(toFile: scriptPath, atomically: true, encoding: .utf8)
                try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptPath)

                config.command = "/usr/bin/expect \(Self.shellQuoted(scriptPath))"
            } else {
                var commandParts = ["/usr/bin/ssh"]
                commandParts.append("-p")
                commandParts.append("\(connection.port)")
                commandParts.append("-o")
                commandParts.append("StrictHostKeyChecking=no")

                if connection.usePublicKey {
                    if let keyPath = connection.keyPath, !keyPath.isEmpty {
                        commandParts.append("-i")
                        commandParts.append(Self.shellQuoted(keyPath))
                    } else if let defaultKey = connection.defaultKeyPath {
                        commandParts.append("-i")
                        commandParts.append(Self.shellQuoted(defaultKey))
                    }
                }

                commandParts.append(Self.shellQuoted("\(connection.username)@\(connection.host)"))
                config.command = commandParts.joined(separator: " ")
            }
        }

        config.workingDirectory = NSHomeDirectory()
        return config
    }

    func makeNSView(context: Context) -> GhosttySurfaceView {
        // If the tab already has a cached surface, return it directly.
        // This is the hot path: SwiftUI called makeNSView again due to
        // re-entry into this view hierarchy, but the PTY is still alive.
        if let cached = tab?.cachedSurface { return cached }
        let surface = GhosttySurfaceView(config: configuration)
        tab?.cachedSurface = surface
        
        if let tab = self.tab {
            setupMenuBuilder(for: surface, tab: tab)
        }
        
        return surface
    }

    func updateNSView(_ nsView: GhosttySurfaceView, context: Context) {}

    /// Removes stale auth helper files (expect scripts + plaintext password files)
    /// left in the temp dir by a previous session that exited before its expect
    /// script could delete them. Safe to call at launch: no live session's files
    /// exist yet. ponytail: bounds plaintext-password lifetime to one app session.
    static func cleanupStaleAuthFiles() {
        let tmp = NSTemporaryDirectory()
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: tmp) else { return }
        for name in names where name.hasPrefix("macssh_") && (name.hasSuffix(".pwd") || name.hasSuffix(".exp")) {
            try? FileManager.default.removeItem(atPath: tmp + name)
        }
    }

    private static func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func tclQuoted(_ value: String) -> String {
        var result = "\""
        for character in value {
            switch character {
            case "\\":
                result += "\\\\"
            case "\"":
                result += "\\\""
            case "$":
                result += "\\$"
            case "[":
                result += "\\["
            case "]":
                result += "\\]"
            default:
                result.append(character)
            }
        }
        result += "\""
        return result
    }
}

// MARK: - Associated keys
nonisolated(unsafe) private var menuHandlerKey: UInt8 = 0

// MARK: - Menu Setup Helpers
@MainActor
func setupMenuBuilder(for surface: GhosttySurfaceView, tab: SessionTab) {
    let handler = TerminalMenuHandler(surface: surface, tab: tab)
    objc_setAssociatedObject(surface, &menuHandlerKey, handler, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    
    surface.menuBuilder = { [weak handler] (view, event) in
        guard let handler else { return nil }
        let menu = NSMenu()
        
        let copyItem = NSMenuItem(title: String(localized: "Copy"), action: #selector(view.copyAction(_:)), keyEquivalent: "c")
        copyItem.target = view
        copyItem.isEnabled = view.selectedText != nil
        menu.addItem(copyItem)
        
        let searchItem = NSMenuItem(title: String(localized: "Search with Google"), action: #selector(view.searchWithGoogleAction(_:)), keyEquivalent: "")
        searchItem.target = view
        searchItem.isEnabled = view.selectedText != nil
        menu.addItem(searchItem)
        
        let pasteItem = NSMenuItem(title: String(localized: "Paste"), action: #selector(view.pasteAction(_:)), keyEquivalent: "v")
        pasteItem.target = view
        menu.addItem(pasteItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let splitRight = NSMenuItem(title: String(localized: "Split Right"), action: #selector(TerminalMenuHandler.splitRightAction(_:)), keyEquivalent: "")
        splitRight.target = handler
        menu.addItem(splitRight)
        
        let splitLeft = NSMenuItem(title: String(localized: "Split Left"), action: #selector(TerminalMenuHandler.splitLeftAction(_:)), keyEquivalent: "")
        splitLeft.target = handler
        menu.addItem(splitLeft)
        
        let splitDown = NSMenuItem(title: String(localized: "Split Down"), action: #selector(TerminalMenuHandler.splitDownAction(_:)), keyEquivalent: "")
        splitDown.target = handler
        menu.addItem(splitDown)
        
        let splitUp = NSMenuItem(title: String(localized: "Split Up"), action: #selector(TerminalMenuHandler.splitUpAction(_:)), keyEquivalent: "")
        splitUp.target = handler
        menu.addItem(splitUp)
        
        menu.addItem(NSMenuItem.separator())
        
        let resetItem = NSMenuItem(title: String(localized: "Reset Terminal"), action: #selector(TerminalMenuHandler.resetAction(_:)), keyEquivalent: "")
        resetItem.target = handler
        menu.addItem(resetItem)
        
        let inspectorItem = NSMenuItem(title: String(localized: "Toggle Terminal Inspector"), action: #selector(TerminalMenuHandler.toggleInspectorAction(_:)), keyEquivalent: "")
        inspectorItem.target = handler
        menu.addItem(inspectorItem)
        
        let readOnlyItem = NSMenuItem(title: String(localized: "Terminal Read-only"), action: #selector(TerminalMenuHandler.toggleReadOnlyAction(_:)), keyEquivalent: "")
        readOnlyItem.target = handler
        readOnlyItem.state = view.isReadOnly ? .on : .off
        menu.addItem(readOnlyItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let changeTabTitle = NSMenuItem(title: String(localized: "Change Tab Title..."), action: #selector(TerminalMenuHandler.changeTabTitleAction(_:)), keyEquivalent: "")
        changeTabTitle.target = handler
        menu.addItem(changeTabTitle)
        
        let changeTerminalTitle = NSMenuItem(title: String(localized: "Change Terminal Title..."), action: #selector(TerminalMenuHandler.changeTerminalTitleAction(_:)), keyEquivalent: "")
        changeTerminalTitle.target = handler
        menu.addItem(changeTerminalTitle)
        
        menu.addItem(NSMenuItem.separator())
        
        let autoFillItem = NSMenuItem(title: String(localized: "AutoFill"), action: nil, keyEquivalent: "")
        let autoFillSubmenu = NSMenu()
        
        let fillUser = NSMenuItem(title: String(localized: "Fill Username"), action: #selector(TerminalMenuHandler.fillUsernameAction(_:)), keyEquivalent: "")
        fillUser.target = handler
        autoFillSubmenu.addItem(fillUser)
        
        let fillPwd = NSMenuItem(title: String(localized: "Fill Password"), action: #selector(TerminalMenuHandler.fillPasswordAction(_:)), keyEquivalent: "")
        fillPwd.target = handler
        autoFillSubmenu.addItem(fillPwd)
        
        autoFillItem.submenu = autoFillSubmenu
        menu.addItem(autoFillItem)
        
        let servicesItem = NSMenuItem(title: String(localized: "Services"), action: nil, keyEquivalent: "")
        let servicesSubmenu = NSMenu()
        NSApp.servicesMenu = servicesSubmenu
        servicesItem.submenu = servicesSubmenu
        menu.addItem(servicesItem)
        
        return menu
    }
}

@MainActor
func setupLocalMenuBuilder(for surface: GhosttySurfaceView, tab: LocalTerminalTab) {
    let handler = LocalTerminalMenuHandler(surface: surface, tab: tab)
    objc_setAssociatedObject(surface, &menuHandlerKey, handler, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    
    surface.menuBuilder = { [weak handler] (view, event) in
        guard let handler else { return nil }
        let menu = NSMenu()
        
        let copyItem = NSMenuItem(title: String(localized: "Copy"), action: #selector(view.copyAction(_:)), keyEquivalent: "c")
        copyItem.target = view
        copyItem.isEnabled = view.selectedText != nil
        menu.addItem(copyItem)
        
        let searchItem = NSMenuItem(title: String(localized: "Search with Google"), action: #selector(view.searchWithGoogleAction(_:)), keyEquivalent: "")
        searchItem.target = view
        searchItem.isEnabled = view.selectedText != nil
        menu.addItem(searchItem)
        
        let pasteItem = NSMenuItem(title: String(localized: "Paste"), action: #selector(view.pasteAction(_:)), keyEquivalent: "v")
        pasteItem.target = view
        menu.addItem(pasteItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let splitRight = NSMenuItem(title: String(localized: "Split Right"), action: #selector(LocalTerminalMenuHandler.splitRightAction(_:)), keyEquivalent: "")
        splitRight.target = handler
        menu.addItem(splitRight)
        
        let splitLeft = NSMenuItem(title: String(localized: "Split Left"), action: #selector(LocalTerminalMenuHandler.splitLeftAction(_:)), keyEquivalent: "")
        splitLeft.target = handler
        menu.addItem(splitLeft)
        
        let splitDown = NSMenuItem(title: String(localized: "Split Down"), action: #selector(LocalTerminalMenuHandler.splitDownAction(_:)), keyEquivalent: "")
        splitDown.target = handler
        menu.addItem(splitDown)
        
        let splitUp = NSMenuItem(title: String(localized: "Split Up"), action: #selector(LocalTerminalMenuHandler.splitUpAction(_:)), keyEquivalent: "")
        splitUp.target = handler
        menu.addItem(splitUp)
        
        menu.addItem(NSMenuItem.separator())
        
        let resetItem = NSMenuItem(title: String(localized: "Reset Terminal"), action: #selector(LocalTerminalMenuHandler.resetAction(_:)), keyEquivalent: "")
        resetItem.target = handler
        menu.addItem(resetItem)
        
        let readOnlyItem = NSMenuItem(title: String(localized: "Terminal Read-only"), action: #selector(LocalTerminalMenuHandler.toggleReadOnlyAction(_:)), keyEquivalent: "")
        readOnlyItem.target = handler
        readOnlyItem.state = view.isReadOnly ? .on : .off
        menu.addItem(readOnlyItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let changeTabTitle = NSMenuItem(title: String(localized: "Change Tab Title..."), action: #selector(LocalTerminalMenuHandler.changeTabTitleAction(_:)), keyEquivalent: "")
        changeTabTitle.target = handler
        menu.addItem(changeTabTitle)
        
        let changeTerminalTitle = NSMenuItem(title: String(localized: "Change Terminal Title..."), action: #selector(LocalTerminalMenuHandler.changeTerminalTitleAction(_:)), keyEquivalent: "")
        changeTerminalTitle.target = handler
        menu.addItem(changeTerminalTitle)
        
        menu.addItem(NSMenuItem.separator())
        
        let servicesItem = NSMenuItem(title: String(localized: "Services"), action: nil, keyEquivalent: "")
        let servicesSubmenu = NSMenu()
        NSApp.servicesMenu = servicesSubmenu
        servicesItem.submenu = servicesSubmenu
        menu.addItem(servicesItem)
        
        return menu
    }
}

// MARK: - Action Handlers
@MainActor
final class TerminalMenuHandler: NSObject {
    weak var surface: GhosttySurfaceView?
    let tab: SessionTab
    
    init(surface: GhosttySurfaceView, tab: SessionTab) {
        self.surface = surface
        self.tab = tab
    }
    
    @objc func splitRightAction(_ sender: Any) {
        tab.split(direction: .right)
    }
    
    @objc func splitLeftAction(_ sender: Any) {
        tab.split(direction: .left)
    }
    
    @objc func splitDownAction(_ sender: Any) {
        tab.split(direction: .down)
    }
    
    @objc func splitUpAction(_ sender: Any) {
        tab.split(direction: .up)
    }
    
    @objc func resetAction(_ sender: Any) {
        surface?.resetTerminal()
    }
    
    @objc func toggleInspectorAction(_ sender: Any) {
        tab.showInspector.toggle()
    }
    
    @objc func toggleReadOnlyAction(_ sender: Any) {
        guard let surface else { return }
        surface.isReadOnly.toggle()
    }
    
    @objc func changeTabTitleAction(_ sender: Any) {
        let alert = NSAlert()
        alert.messageText = String(localized: "Change Tab Title")
        alert.informativeText = String(localized: "Enter new title for this tab:")
        alert.addButton(withTitle: String(localized: "OK"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        input.stringValue = tab.connection.name
        alert.accessoryView = input
        
        if alert.runModal() == .alertFirstButtonReturn {
            let val = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !val.isEmpty {
                tab.connection.name = val
            }
        }
    }
    
    @objc func changeTerminalTitleAction(_ sender: Any) {
        changeTabTitleAction(sender)
    }
    
    @objc func fillUsernameAction(_ sender: Any) {
        surface?.writeText(tab.connection.username)
    }
    
    @objc func fillPasswordAction(_ sender: Any) {
        if let password = KeychainStore.loadPassword(account: tab.connection.keychainAccount) {
            surface?.writeText(password)
        }
    }
}

@MainActor
final class LocalTerminalMenuHandler: NSObject {
    weak var surface: GhosttySurfaceView?
    let tab: LocalTerminalTab
    
    init(surface: GhosttySurfaceView, tab: LocalTerminalTab) {
        self.surface = surface
        self.tab = tab
    }
    
    @objc func splitRightAction(_ sender: Any) {
        tab.split(direction: .right)
    }
    
    @objc func splitLeftAction(_ sender: Any) {
        tab.split(direction: .left)
    }
    
    @objc func splitDownAction(_ sender: Any) {
        tab.split(direction: .down)
    }
    
    @objc func splitUpAction(_ sender: Any) {
        tab.split(direction: .up)
    }
    
    @objc func resetAction(_ sender: Any) {
        surface?.resetTerminal()
    }
    
    @objc func toggleReadOnlyAction(_ sender: Any) {
        guard let surface else { return }
        surface.isReadOnly.toggle()
    }
    
    @objc func changeTabTitleAction(_ sender: Any) {
        let alert = NSAlert()
        alert.messageText = String(localized: "Change Tab Title")
        alert.informativeText = String(localized: "Enter new title for this tab:")
        alert.addButton(withTitle: String(localized: "OK"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        input.stringValue = tab.name
        alert.accessoryView = input
        
        if alert.runModal() == .alertFirstButtonReturn {
            let val = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !val.isEmpty {
                tab.name = val
            }
        }
    }
    
    @objc func changeTerminalTitleAction(_ sender: Any) {
        changeTabTitleAction(sender)
    }
}
