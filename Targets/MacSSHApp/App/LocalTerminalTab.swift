import Foundation
import Observation
import SwiftUI
import MactermKit

@Observable
@MainActor
final class LocalTerminalTab: Identifiable {
    let id: UUID
    var name: String {
        didSet {
            guard name != oldValue else { return }
            let sessionKey = id.uuidString
            let updatedTitle = name
            Task {
                await DaemonClient.shared.setAttributes(
                    target: sessionKey,
                    attributes: ["title": updatedTitle]
                )
            }
        }
    }
    /// The actual NSView is owned here so it survives SwiftUI navigation.
    let surfaceView: GhosttySurfaceView
    let programStatusStore = TerminalProgramStatusStore()
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

    var splitSessionKey: String { "\(id.uuidString)-split" }

    static func makeSurfaceConfig(
        sessionKey: String,
        title: String,
        workingDirectory: String?,
        fallbackCommand: String? = nil,
        settings: AppSettings
    ) -> GhosttySurfaceConfiguration {
        var config = GhosttySurfaceConfiguration()
        config.fontSize = Float(settings.fontSize)
        config.environmentVariables = LocalShellEnvironment.make()
        let resolvedCwd = workingDirectory ?? NSHomeDirectory()
        config.workingDirectory = resolvedCwd
        if settings.keepLocalSessionsAlive {
            config.command = DaemonClient.bridgeCommand(
                sessionKey: sessionKey,
                title: title,
                workingDirectory: resolvedCwd
            ) ?? fallbackCommand
        } else {
            config.command = fallbackCommand
        }
        return config
    }

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
        let config = Self.makeSurfaceConfig(
            sessionKey: splitSessionKey,
            title: "\(name) (Split)",
            workingDirectory: currentDirectoryPath,
            settings: settings
        )

        let surface = GhosttySurfaceView(config: config)
        GhosttyTerminalView.applyFontConfig(to: surface, fontName: settings.fontName, fontSize: settings.fontSize)
        setupMenuBuilder(for: surface, localTab: self)
        configureSurfaceEvents(for: surface)
        self.splitSurface = surface
        self.splitDirection = direction
        self.isSplit = true
    }

    func closeSplit(killDaemonSession: Bool = true) {
        self.isSplit = false
        self.splitSurface = nil
        if killDaemonSession {
            let targetKey = splitSessionKey
            Task {
                await DaemonClient.shared.closeSession(target: targetKey)
            }
        }
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
            self.programStatusStore.clearWorkingOnCommandFinished()
            // If the terminal has been cleared (e.g. user ran 'clear'), purge persisted history immediately
            if let text = surfaceView.readFullText(maxLines: 10) {
                let cleaned = AppModel.sanitizeHistoryText(text)
                let lines = cleaned.components(separatedBy: "\n").filter { !AppModel.stripANSI($0).trimmingCharacters(in: .whitespaces).isEmpty }
                if lines.count <= 3 {
                    SessionHistoryStore.shared.remove(tabID: self.id)
                }
            }

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

        case .bell, .desktopNotification:
            break

        case .childExited:
            self.programStatusStore.reset()

        case .programStatus(let report):
            if let transition = self.programStatusStore.apply(report) {
                let appLabel = !transition.report.app.isEmpty ? transition.report.app : (!transition.report.title.isEmpty ? transition.report.title : self.name)
                if transition.report.state == .blocked {
                    ToastManager.shared.show(
                        String(localized: "\(appLabel) needs input"),
                        message: transition.report.message.isEmpty ? nil : transition.report.message,
                        preset: .warning,
                        duration: 4.0
                    )
                } else if transition.report.state == .error && !transition.report.message.isEmpty {
                    ToastManager.shared.show(
                        String(localized: "\(appLabel) error"),
                        message: transition.report.message,
                        preset: .error,
                        duration: 4.0
                    )
                }
            }

        case .progressReport(let report):
            self.programStatusStore.applyProgress(report)

        case .hoverLink(let url):
            self.programStatusStore.hoveredLink = url
        }
    }
}
