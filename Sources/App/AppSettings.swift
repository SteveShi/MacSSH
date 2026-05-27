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
    }

    var availableFonts: [String] {
        ["SF Mono", "Menlo", "Monaco"]
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
    }
}
