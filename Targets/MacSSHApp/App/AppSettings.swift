import SwiftUI
import Observation

@Observable
final class AppSettings {
    enum TerminalTheme: String, CaseIterable, Identifiable, Codable {
        case system
        case light
        case dark

        var id: String { rawValue }
    }

    private enum Keys {
        static let fontSize = "terminalFontSize"
        static let fontName = "terminalFontName"
        static let theme = "terminalTheme"
        static let vibrancyEnabled = "vibrancyEnabled"
        static let showGrid = "showGrid"
        static let terminalGlow = "terminalGlow"
        static let defaultInputSourceID = "defaultInputSourceID"
        static let confirmBeforeDisconnect = "confirmBeforeDisconnect"
        static let autoReconnect = "autoReconnect"
        static let showHiddenFiles = "showHiddenFiles"
        static let overwriteExistingFiles = "overwriteExistingFiles"
        static let notificationsEnabled = "notificationsEnabled"
        static let notifyConnectionEvents = "notifyConnectionEvents"
        static let notifySFTPEvents = "notifySFTPEvents"
        static let notifyTerminalEvents = "notifyTerminalEvents"
        static let notifyTerminalBell = "notifyTerminalBell"
        static let notifyOnlyWhenInactive = "notifyOnlyWhenInactive"
        static let syncGithubToken = "syncGithubToken"
        static let syncGithubGistId = "syncGithubGistId"
        static let syncDropboxToken = "syncDropboxToken"
        static let syncEncryptData = "syncEncryptData"
        static let syncMasterPassword = "syncMasterPassword"
        static let syncLastTime = "syncLastTime"
        static let syncLastStatus = "syncLastStatus"
        static let restoreLocalTerminalHistory = "restoreLocalTerminalHistory"
        static let scrollbackHistoryLimit = "scrollbackHistoryLimit"
    }

    var fontSize: Double {
        didSet { save() }
    }

    var fontName: String {
        didSet { save() }
    }

    var theme: TerminalTheme {
        didSet { save() }
    }


    var vibrancyEnabled: Bool {
        didSet { save() }
    }

    var showGrid: Bool {
        didSet { save() }
    }

    var terminalGlow: Bool {
        didSet { save() }
    }

    var defaultInputSourceID: String {
        didSet { save() }
    }

    var confirmBeforeDisconnect: Bool {
        didSet { save() }
    }

    var autoReconnect: Bool {
        didSet { save() }
    }

    var showHiddenFiles: Bool {
        didSet { save() }
    }

    var overwriteExistingFiles: Bool {
        didSet { save() }
    }

    // MARK: - Notifications

    var notificationsEnabled: Bool {
        didSet { save() }
    }

    var notifyConnectionEvents: Bool {
        didSet { save() }
    }

    var notifySFTPEvents: Bool {
        didSet { save() }
    }

    var notifyTerminalEvents: Bool {
        didSet { save() }
    }

    var notifyTerminalBell: Bool {
        didSet { save() }
    }

    var notifyOnlyWhenInactive: Bool {
        didSet { save() }
    }

    var syncGithubToken: String {
        didSet { save() }
    }

    var syncGithubGistId: String {
        didSet { save() }
    }

    var syncDropboxToken: String {
        didSet { save() }
    }

    var syncEncryptData: Bool {
        didSet { save() }
    }

    var syncMasterPassword: String {
        didSet { save() }
    }

    var syncLastTime: Date? {
        didSet { save() }
    }

    var syncLastStatus: String {
        didSet { save() }
    }

    var restoreLocalTerminalHistory: Bool {
        didSet { save() }
    }

    var scrollbackHistoryLimit: Int {
        didSet { save() }
    }

    init() {
        let defaults = UserDefaults.standard
        let savedSize = defaults.double(forKey: Keys.fontSize)
        fontSize = savedSize == 0 ? 13 : savedSize
        fontName = defaults.string(forKey: Keys.fontName) ?? "SF Mono"
        if let raw = defaults.string(forKey: Keys.theme), let theme = TerminalTheme(rawValue: raw) {
            self.theme = theme
        } else {
            self.theme = .system
        }
        vibrancyEnabled = defaults.object(forKey: Keys.vibrancyEnabled) as? Bool ?? true
        showGrid = defaults.object(forKey: Keys.showGrid) as? Bool ?? false
        terminalGlow = defaults.object(forKey: Keys.terminalGlow) as? Bool ?? true
        defaultInputSourceID = defaults.string(forKey: Keys.defaultInputSourceID) ?? ""
        confirmBeforeDisconnect = defaults.object(forKey: Keys.confirmBeforeDisconnect) as? Bool ?? true
        autoReconnect = defaults.object(forKey: Keys.autoReconnect) as? Bool ?? false
        showHiddenFiles = defaults.object(forKey: Keys.showHiddenFiles) as? Bool ?? false
        overwriteExistingFiles = defaults.object(forKey: Keys.overwriteExistingFiles) as? Bool ?? true
        restoreLocalTerminalHistory = defaults.object(forKey: Keys.restoreLocalTerminalHistory) as? Bool ?? true
        let savedLimit = defaults.integer(forKey: Keys.scrollbackHistoryLimit)
        scrollbackHistoryLimit = savedLimit == 0 ? 10000 : savedLimit
        notificationsEnabled = defaults.object(forKey: Keys.notificationsEnabled) as? Bool ?? true
        notifyConnectionEvents = defaults.object(forKey: Keys.notifyConnectionEvents) as? Bool ?? true
        notifySFTPEvents = defaults.object(forKey: Keys.notifySFTPEvents) as? Bool ?? true
        notifyTerminalEvents = defaults.object(forKey: Keys.notifyTerminalEvents) as? Bool ?? true
        notifyTerminalBell = defaults.object(forKey: Keys.notifyTerminalBell) as? Bool ?? false
        notifyOnlyWhenInactive = defaults.object(forKey: Keys.notifyOnlyWhenInactive) as? Bool ?? true
        syncGithubToken = defaults.string(forKey: Keys.syncGithubToken) ?? ""
        syncGithubGistId = defaults.string(forKey: Keys.syncGithubGistId) ?? ""
        syncDropboxToken = defaults.string(forKey: Keys.syncDropboxToken) ?? ""
        syncEncryptData = defaults.object(forKey: Keys.syncEncryptData) as? Bool ?? false
        syncMasterPassword = defaults.string(forKey: Keys.syncMasterPassword) ?? ""
        syncLastTime = defaults.object(forKey: Keys.syncLastTime) as? Date
        syncLastStatus = defaults.string(forKey: Keys.syncLastStatus) ?? ""
    }

    var availableFonts: [String] {
        let families = NSFontManager.shared.availableFontFamilies
        let keywords = ["mono", "nerd", "code", "console", "terminal", "courier", "menlo", "monaco", "jetbrains", "fira", "hack", "source", "cascadia", "inconsolata", "meslo", "symbols"]
        let monospaced = families.filter { family in
            let lower = family.lowercased()
            if keywords.contains(where: { lower.contains($0) }) { return true }
            guard let font = NSFont(name: family, size: 13) else { return false }
            return font.isFixedPitch || font.fontDescriptor.symbolicTraits.contains(.monoSpace)
        }
        // Prioritize fonts commonly bundled with Nerd Font / Powerline glyph support
        let preferred = [
            "JetBrains Mono",
            "JetBrainsMono Nerd Font",
            "JetBrainsMono Nerd Font Mono",
            "Fira Code",
            "FiraCode Nerd Font",
            "FiraCode Nerd Font Mono",
            "Hack",
            "Hack Nerd Font",
            "Hack Nerd Font Mono",
            "Source Code Pro",
            "SauceCodePro Nerd Font",
            "SauceCodePro Nerd Font Mono",
            "Cascadia Code",
            "CaskaydiaCove Nerd Font",
            "CaskaydiaCove Nerd Font Mono",
            "Inconsolata",
            "Inconsolata Nerd Font",
            "Inconsolata Nerd Font Mono",
            "MesloLGS NF",
            "MesloLGS Nerd Font",
            "MesloLGS Nerd Font Mono",
            "SFMono Nerd Font Mono",
            "Symbols Nerd Font",
            "Symbols Nerd Font Mono",
            "SF Mono",
            "Menlo",
            "Monaco"
        ]
        let top = preferred.filter { monospaced.contains($0) }
        let rest = monospaced.filter { !preferred.contains($0) }.sorted()
        let result = top + rest
        return result.isEmpty ? ["SF Mono", "Menlo", "Monaco"] : result
    }

    var backgroundColor: Color {
        switch theme {
        case .system:
            return Color(NSColor.textBackgroundColor)
        case .light:
            return Color.white
        case .dark:
            return Color.black
        }
    }

    var textColor: Color {
        switch theme {
        case .system:
            return Color.primary
        case .light:
            return Color.black
        case .dark:
            return Color.green
        }
    }

    private func save() {
        let defaults = UserDefaults.standard
        defaults.set(fontSize, forKey: Keys.fontSize)
        defaults.set(fontName, forKey: Keys.fontName)
        defaults.set(theme.rawValue, forKey: Keys.theme)
        defaults.set(vibrancyEnabled, forKey: Keys.vibrancyEnabled)
        defaults.set(showGrid, forKey: Keys.showGrid)
        defaults.set(terminalGlow, forKey: Keys.terminalGlow)
        defaults.set(defaultInputSourceID, forKey: Keys.defaultInputSourceID)
        defaults.set(confirmBeforeDisconnect, forKey: Keys.confirmBeforeDisconnect)
        defaults.set(autoReconnect, forKey: Keys.autoReconnect)
        defaults.set(showHiddenFiles, forKey: Keys.showHiddenFiles)
        defaults.set(overwriteExistingFiles, forKey: Keys.overwriteExistingFiles)
        defaults.set(notificationsEnabled, forKey: Keys.notificationsEnabled)
        defaults.set(notifyConnectionEvents, forKey: Keys.notifyConnectionEvents)
        defaults.set(notifySFTPEvents, forKey: Keys.notifySFTPEvents)
        defaults.set(notifyTerminalEvents, forKey: Keys.notifyTerminalEvents)
        defaults.set(notifyTerminalBell, forKey: Keys.notifyTerminalBell)
        defaults.set(notifyOnlyWhenInactive, forKey: Keys.notifyOnlyWhenInactive)
        defaults.set(syncGithubToken, forKey: Keys.syncGithubToken)
        defaults.set(syncGithubGistId, forKey: Keys.syncGithubGistId)
        defaults.set(syncDropboxToken, forKey: Keys.syncDropboxToken)
        defaults.set(syncEncryptData, forKey: Keys.syncEncryptData)
        defaults.set(syncMasterPassword, forKey: Keys.syncMasterPassword)
        defaults.set(syncLastTime, forKey: Keys.syncLastTime)
        defaults.set(syncLastStatus, forKey: Keys.syncLastStatus)
        defaults.set(restoreLocalTerminalHistory, forKey: Keys.restoreLocalTerminalHistory)
        defaults.set(scrollbackHistoryLimit, forKey: Keys.scrollbackHistoryLimit)
    }
}
