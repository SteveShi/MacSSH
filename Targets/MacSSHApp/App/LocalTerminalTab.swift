import Foundation
import Observation
import SwiftUI
import MactermKit

@Observable
@MainActor
final class LocalTerminalTab: Identifiable {
    let id: UUID
    var name: String
    /// The actual NSView is owned here so it survives SwiftUI navigation.
    let surfaceView: GhosttySurfaceView
    var isRenaming: Bool = false
    var hasCustomUserTitle: Bool = false
    var currentDirectoryPath: String? = NSHomeDirectory()
    let connectedAt: Date = Date()
    var showInspector: Bool = UserDefaults.standard.object(forKey: "showLocalInspector") as? Bool ?? false {
        didSet {
            UserDefaults.standard.set(showInspector, forKey: "showLocalInspector")
        }
    }
    var inspectorTab: InspectorTab = .snippets

    // Split terminal support
    var isSplit: Bool = false
    var splitDirection: SessionTab.SplitDirection = .right
    var splitSurface: GhosttySurfaceView?

    init(number: Int, surfaceView: GhosttySurfaceView) {
        self.id = UUID()
        self.name = "Terminal \(number)"
        self.surfaceView = surfaceView
        let settings = AppSettings()
        GhosttyTerminalView.applyFontConfig(to: surfaceView, fontName: settings.fontName, fontSize: settings.fontSize)
        setupMenuBuilder(for: surfaceView, localTab: self)
        configureSurfaceEvents(for: surfaceView)
    }

    init(id: UUID, name: String, surfaceView: GhosttySurfaceView) {
        self.id = id
        self.name = name
        self.surfaceView = surfaceView
        let settings = AppSettings()
        GhosttyTerminalView.applyFontConfig(to: surfaceView, fontName: settings.fontName, fontSize: settings.fontSize)
        setupMenuBuilder(for: surfaceView, localTab: self)
        configureSurfaceEvents(for: surfaceView)
    }

    func split(direction: SessionTab.SplitDirection) {
        let settings = AppSettings()
        var config = GhosttySurfaceConfiguration()
        config.fontSize = Float(settings.fontSize)
        config.environmentVariables = LocalShellEnvironment.make()
        config.workingDirectory = currentDirectoryPath ?? NSHomeDirectory()
        
        let surface = GhosttySurfaceView(config: config)
        GhosttyTerminalView.applyFontConfig(to: surface, fontName: settings.fontName, fontSize: settings.fontSize)
        setupMenuBuilder(for: surface, localTab: self)
        configureSurfaceEvents(for: surface)
        self.splitSurface = surface
        self.splitDirection = direction
        self.isSplit = true
    }

    func closeSplit() {
        self.isSplit = false
        self.splitSurface = nil
    }

    // MARK: - Shell Integration Events

    func configureSurfaceEvents(for surface: GhosttySurfaceView) {
        surface.onEvent = { [weak self] event in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.handleTerminalEvent(event)
            }
        }
    }

    private func handleTerminalEvent(_ event: GhosttyTerminalEvent) {
        let settings = AppSettings()
        switch event {
        case .currentDirectoryChanged(let rawURL):
            guard settings.shellIntegrationEnabled else { return }
            let path = SessionTab.extractPath(from: rawURL)
            guard !path.isEmpty else { return }
            self.currentDirectoryPath = path

        case .titleChanged(let title), .tabTitleChanged(let title):
            guard settings.shellIntegrationEnabled else { return }
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty && !self.isRenaming && !self.hasCustomUserTitle {
                self.name = trimmed
            }

        case .commandFinished(let exitCode, let durationNs):
            guard settings.commandCompletionNotification else { return }
            let durationSeconds = Double(durationNs) / 1_000_000_000.0
            guard durationSeconds >= 5.0 else { return }
            let formattedDuration: String
            if durationSeconds < 60.0 {
                formattedDuration = String(format: "%.1fs", durationSeconds)
            } else {
                formattedDuration = String(format: "%dm %ds", Int(durationSeconds) / 60, Int(durationSeconds) % 60)
            }
            let message = exitCode == 0
                ? String(localized: "Command completed (\(formattedDuration))")
                : String(localized: "Command failed with code \(exitCode) (\(formattedDuration))")
            ToastManager.shared.show(message, preset: exitCode == 0 ? .done : .error)

        case .bell, .desktopNotification, .childExited:
            break
        }
    }
}
