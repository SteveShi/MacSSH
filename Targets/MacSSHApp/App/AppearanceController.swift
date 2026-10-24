import AppKit
import Observation

/// Single source of truth for the app-wide light/dark appearance.
///
/// The user's `AppSettings.TerminalTheme` is applied to `NSApplication.shared.appearance`
/// (`nil` for "Follow System"), and every window, SwiftUI view, sheet and the
/// Settings scene inherit from it. The resolved appearance is then read back
/// from `NSApplication.shared.effectiveAppearance` via KVO, which fires only *after* AppKit has
/// actually switched — unlike `AppleInterfaceThemeChangedNotification`, which is
/// delivered before `effectiveAppearance` updates and therefore yields stale
/// values.
///
/// Do not use SwiftUI's `.preferredColorScheme` or per-window `appearance`
/// overrides alongside this: pinning an explicit scheme in "Follow System" mode
/// freezes `NSApplication.shared.effectiveAppearance`, so system changes are never observed.
@MainActor
@Observable
final class AppearanceController {
    static let shared = AppearanceController()

    /// Whether the app is currently rendered with a dark appearance.
    private(set) var isDark: Bool

    @ObservationIgnored private var observation: NSKeyValueObservation?

    private init() {
        isDark = Self.resolveIsDark(NSApplication.shared.effectiveAppearance)
        observation = NSApplication.shared.observe(\.effectiveAppearance, options: []) { _, _ in
            // effectiveAppearance changes are delivered on the main thread.
            MainActor.assumeIsolated {
                AppearanceController.shared.update(from: NSApplication.shared.effectiveAppearance)
            }
        }
    }

    /// Applies the user's appearance preference to the whole application.
    func apply(_ theme: AppSettings.TerminalTheme) {
        let target: NSAppearance?
        switch theme {
        case .system: target = nil
        case .light: target = NSAppearance(named: .aqua)
        case .dark: target = NSAppearance(named: .darkAqua)
        }
        if NSApplication.shared.appearance?.name != target?.name {
            NSApplication.shared.appearance = target
        }
        // KVO normally covers this; resolve synchronously so callers that read
        // `isDark` right after `apply` never see the previous value.
        update(from: NSApplication.shared.effectiveAppearance)
    }

    private func update(from appearance: NSAppearance) {
        let newValue = Self.resolveIsDark(appearance)
        guard newValue != isDark else { return }
        isDark = newValue
        NotificationCenter.default.post(name: .terminalAppearanceDidChange, object: self)
    }

    private static func resolveIsDark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}
