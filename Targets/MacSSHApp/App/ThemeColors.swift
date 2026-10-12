import SwiftUI
import AppKit

public enum ThemeColors {
    // MARK: - Dark Palette (Slate Liquid Glass)
    // Terminal, titlebar, statusbar unified slate background (#24272e)
    public static let darkSlateBackground = Color(red: 36.0 / 255.0, green: 39.0 / 255.0, blue: 46.0 / 255.0)
    public static let darkSlateBackgroundNS = NSColor(red: 36.0 / 255.0, green: 39.0 / 255.0, blue: 46.0 / 255.0, alpha: 1.0)
    public static let darkSlateHex = "24272e"
    
    // Sidebar: slightly deeper dark slate (#1c1e23)
    public static let darkSidebarBackground = Color(red: 28.0 / 255.0, green: 30.0 / 255.0, blue: 35.0 / 255.0)
    public static let darkSidebarBackgroundNS = NSColor(red: 28.0 / 255.0, green: 30.0 / 255.0, blue: 35.0 / 255.0, alpha: 1.0)

    // Dark text & accents
    public static let darkForegroundHex = "c9d1d9"
    public static let darkCursorHex = "58a6ff"
    public static let darkCursorTextHex = "24272e"
    public static let darkSelectionBgHex = "3b5070"
    public static let darkSelectionFgHex = "ffffff"

    // MARK: - Light Palette (Warm Beige Cream 米色)
    // Terminal, titlebar, statusbar unified warm beige cream background (#f5f2eb)
    public static let lightBeigeBackground = Color(red: 245.0 / 255.0, green: 242.0 / 255.0, blue: 235.0 / 255.0)
    public static let lightBeigeBackgroundNS = NSColor(red: 245.0 / 255.0, green: 242.0 / 255.0, blue: 235.0 / 255.0, alpha: 1.0)
    public static let lightBeigeHex = "f5f2eb"

    // Sidebar: slightly deeper warm beige (#ebe5da)
    public static let lightSidebarBackground = Color(red: 235.0 / 255.0, green: 229.0 / 255.0, blue: 218.0 / 255.0)
    public static let lightSidebarBackgroundNS = NSColor(red: 235.0 / 255.0, green: 229.0 / 255.0, blue: 218.0 / 255.0, alpha: 1.0)

    // Light text & accents
    public static let lightForegroundHex = "24292f"
    public static let lightCursorHex = "0969da"
    public static let lightCursorTextHex = "f5f2eb"
    public static let lightSelectionBgHex = "d8d0bf"
    public static let lightSelectionFgHex = "24292f"

    // MARK: - Dynamic Accessors

    public static func terminalBackground(isDark: Bool) -> Color {
        isDark ? darkSlateBackground : lightBeigeBackground
    }

    public static func terminalBackgroundNSColor(isDark: Bool) -> NSColor {
        isDark ? darkSlateBackgroundNS : lightBeigeBackgroundNS
    }

    public static func terminalBackgroundHex(isDark: Bool) -> String {
        isDark ? darkSlateHex : lightBeigeHex
    }

    public static func sidebarBackground(isDark: Bool) -> Color {
        isDark ? darkSidebarBackground : lightSidebarBackground
    }

    public static func sidebarBackgroundNSColor(isDark: Bool) -> NSColor {
        isDark ? darkSidebarBackgroundNS : lightSidebarBackgroundNS
    }
}
