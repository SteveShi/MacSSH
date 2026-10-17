import Foundation
import SwiftUI
import Observation
import MactermKit

public struct TerminalThemeItem: Identifiable, Hashable, Codable, Sendable {
    public var id: String { name }
    public let name: String
    public let background: String
    public let foreground: String
    public let cursorColor: String?
    public let cursorText: String?
    public let selectionBackground: String?
    public let selectionForeground: String?
    public let palette: [Int: String]
    public let isDark: Bool
    public var isCustom: Bool = false

    public init(
        name: String,
        background: String,
        foreground: String,
        cursorColor: String? = nil,
        cursorText: String? = nil,
        selectionBackground: String? = nil,
        selectionForeground: String? = nil,
        palette: [Int: String],
        isDark: Bool,
        isCustom: Bool = false
    ) {
        self.name = name
        self.background = background
        self.foreground = foreground
        self.cursorColor = cursorColor
        self.cursorText = cursorText
        self.selectionBackground = selectionBackground
        self.selectionForeground = selectionForeground
        self.palette = palette
        self.isDark = isDark
        self.isCustom = isCustom
    }

    enum CodingKeys: String, CodingKey {
        case name, background, foreground, cursorColor, cursorText, selectionBackground, selectionForeground, palette, isDark
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decode(String.self, forKey: .name)
        self.background = try container.decode(String.self, forKey: .background)
        self.foreground = try container.decode(String.self, forKey: .foreground)
        self.cursorColor = try container.decodeIfPresent(String.self, forKey: .cursorColor)
        self.cursorText = try container.decodeIfPresent(String.self, forKey: .cursorText)
        self.selectionBackground = try container.decodeIfPresent(String.self, forKey: .selectionBackground)
        self.selectionForeground = try container.decodeIfPresent(String.self, forKey: .selectionForeground)
        self.isDark = try container.decode(Bool.self, forKey: .isDark)
        self.isCustom = false

        // In JSON, palette keys are string numbers "0"..."15"
        let stringPalette = try container.decode([String: String].self, forKey: .palette)
        var intPalette: [Int: String] = [:]
        for (k, v) in stringPalette {
            if let idx = Int(k) {
                intPalette[idx] = v
            }
        }
        self.palette = intPalette
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(background, forKey: .background)
        try container.encode(foreground, forKey: .foreground)
        try container.encodeIfPresent(cursorColor, forKey: .cursorColor)
        try container.encodeIfPresent(cursorText, forKey: .cursorText)
        try container.encodeIfPresent(selectionBackground, forKey: .selectionBackground)
        try container.encodeIfPresent(selectionForeground, forKey: .selectionForeground)
        try container.encode(isDark, forKey: .isDark)

        var stringPalette: [String: String] = [:]
        for (k, v) in palette {
            stringPalette[String(k)] = v
        }
        try container.encode(stringPalette, forKey: .palette)
    }

    public func toGhosttyThemeDefinition() -> GhosttyThemeDefinition {
        GhosttyThemeDefinition(
            name: name,
            background: background,
            foreground: foreground,
            cursorColor: cursorColor,
            cursorText: cursorText,
            selectionBackground: selectionBackground,
            selectionForeground: selectionForeground,
            palette: palette
        )
    }
}

@Observable
@MainActor
public final class ThemeManager {
    public static let shared = ThemeManager()

    public private(set) var themes: [TerminalThemeItem] = []
    private let customThemesDirectory: URL

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        self.customThemesDirectory = appSupport.appendingPathComponent("MacSSH/themes")
        ensureDirectoryExists()
        loadAllThemes()
    }

    private func ensureDirectoryExists() {
        if !FileManager.default.fileExists(atPath: customThemesDirectory.path) {
            try? FileManager.default.createDirectory(at: customThemesDirectory, withIntermediateDirectories: true)
        }
    }

    public func loadAllThemes() {
        var loaded: [TerminalThemeItem] = []

        // 1. Built-in themes from Themes.json
        if let bundleURL = Bundle.main.url(forResource: "Themes", withExtension: "json"),
           let data = try? Data(contentsOf: bundleURL),
           let builtin = try? JSONDecoder().decode([TerminalThemeItem].self, from: data) {
            loaded.append(contentsOf: builtin)
        }

        // 2. Custom themes from ~/Library/Application Support/MacSSH/themes
        if let files = try? FileManager.default.contentsOfDirectory(at: customThemesDirectory, includingPropertiesForKeys: nil) {
            for file in files {
                if file.pathExtension.lowercased() == "itermcolors" {
                    if let item = try? parseITermColors(from: file) {
                        loaded.append(item)
                    }
                } else if ["ghostty", "conf", "txt"].contains(file.pathExtension.lowercased()) || file.pathExtension.isEmpty {
                    if let item = try? parseGhosttyTheme(from: file) {
                        loaded.append(item)
                    }
                }
            }
        }

        // Fallback default builtins if json loading failed
        if loaded.isEmpty {
            loaded = [
                TerminalThemeItem(name: "GitHub Dark", background: "101216", foreground: "8b949e", palette: [:], isDark: true),
                TerminalThemeItem(name: "GitHub Light", background: "ffffff", foreground: "1f2328", palette: [:], isDark: false),
                TerminalThemeItem(name: "Dracula", background: "282a36", foreground: "f8f8f2", palette: [:], isDark: true)
            ]
        }

        self.themes = loaded.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedSame ? false : $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public func theme(named name: String) -> TerminalThemeItem? {
        themes.first { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }
    }

    /// Resolves the Ghostty theme definition given optional per-connection theme override, dark/light state, and app settings.
    public func resolveTheme(
        connectionTheme: String?,
        isDark: Bool,
        preferredDarkTheme: String = "GitHub Dark",
        preferredLightTheme: String = "GitHub Light"
    ) -> GhosttyThemeDefinition {
        if let connectionTheme, !connectionTheme.isEmpty,
           let match = theme(named: connectionTheme) {
            return match.toGhosttyThemeDefinition()
        }

        let targetName = isDark ? preferredDarkTheme : preferredLightTheme
        if let match = theme(named: targetName) {
            return match.toGhosttyThemeDefinition()
        }

        return isDark ? GhosttyThemeDefinition.gitHub_Dark : GhosttyThemeDefinition.gitHub_Light
    }

    /// Imports a theme file (.itermcolors or Ghostty format) into custom themes directory.
    @discardableResult
    public func importTheme(from sourceURL: URL) throws -> TerminalThemeItem {
        ensureDirectoryExists()
        let filename = sourceURL.lastPathComponent
        let destURL = customThemesDirectory.appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: destURL.path) {
            try FileManager.default.removeItem(at: destURL)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destURL)

        loadAllThemes()
        let themeName = sourceURL.deletingPathExtension().lastPathComponent
        guard let imported = theme(named: themeName) else {
            throw NSError(domain: "ThemeManager", code: 404, userInfo: [NSLocalizedDescriptionKey: "Failed to parse imported theme."])
        }
        return imported
    }

    // MARK: - Parsers

    private func parseGhosttyTheme(from fileURL: URL) throws -> TerminalThemeItem {
        let content = try String(contentsOf: fileURL, encoding: .utf8)
        let name = fileURL.deletingPathExtension().lastPathComponent
        var bg = "000000"
        var fg = "ffffff"
        var cursor: String? = nil
        var cursorTxt: String? = nil
        var selBg: String? = nil
        var selFg: String? = nil
        var palette: [Int: String] = [:]

        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            guard let eqIdx = trimmed.firstIndex(of: "=") else { continue }
            let key = trimmed[..<eqIdx].trimmingCharacters(in: .whitespaces)
            let val = trimmed[trimmed.index(after: eqIdx)...].trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "#"))

            if key == "background" { bg = val }
            else if key == "foreground" { fg = val }
            else if key == "cursor-color" { cursor = val }
            else if key == "cursor-text" { cursorTxt = val }
            else if key == "selection-background" { selBg = val }
            else if key == "selection-foreground" { selFg = val }
            else if key.hasPrefix("palette") {
                let parts = val.components(separatedBy: "=")
                if parts.count == 2, let idx = Int(parts[0].trimmingCharacters(in: .whitespaces)) {
                    palette[idx] = parts[1].trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "#"))
                }
            }
        }

        let isDark = isColorDark(hex: bg)
        return TerminalThemeItem(
            name: name,
            background: bg,
            foreground: fg,
            cursorColor: cursor,
            cursorText: cursorTxt,
            selectionBackground: selBg,
            selectionForeground: selFg,
            palette: palette,
            isDark: isDark,
            isCustom: true
        )
    }

    private func parseITermColors(from fileURL: URL) throws -> TerminalThemeItem {
        guard let plist = NSDictionary(contentsOf: fileURL) as? [String: [String: Any]] else {
            throw NSError(domain: "ThemeManager", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid plist structure"])
        }
        let name = fileURL.deletingPathExtension().lastPathComponent

        func colorHex(for key: String) -> String? {
            guard let dict = plist[key] else { return nil }
            let r = (dict["Red Component"] as? Double) ?? 0
            let g = (dict["Green Component"] as? Double) ?? 0
            let b = (dict["Blue Component"] as? Double) ?? 0
            return String(format: "%02x%02x%02x", Int(r * 255), Int(g * 255), Int(b * 255))
        }

        let bg = colorHex(for: "Background Color") ?? "000000"
        let fg = colorHex(for: "Foreground Color") ?? "ffffff"
        let cursor = colorHex(for: "Cursor Color")
        let cursorTxt = colorHex(for: "Cursor Text Color")
        let selBg = colorHex(for: "Selection Color")
        let selFg = colorHex(for: "Selected Text Color")

        var palette: [Int: String] = [:]
        for i in 0...15 {
            if let hex = colorHex(for: "Ansi \(i) Color") {
                palette[i] = hex
            }
        }

        let isDark = isColorDark(hex: bg)
        return TerminalThemeItem(
            name: name,
            background: bg,
            foreground: fg,
            cursorColor: cursor,
            cursorText: cursorTxt,
            selectionBackground: selBg,
            selectionForeground: selFg,
            palette: palette,
            isDark: isDark,
            isCustom: true
        )
    }

    private func isColorDark(hex: String) -> Bool {
        let clean = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard clean.count == 6, let num = UInt64(clean, radix: 16) else { return true }
        let r = Double((num >> 16) & 0xFF)
        let g = Double((num >> 8) & 0xFF)
        let b = Double(num & 0xFF)
        let lum = 0.299 * r + 0.587 * g + 0.114 * b
        return lum < 128
    }
}
