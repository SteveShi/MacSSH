import Foundation
import SwiftUI
import Observation
import MactermKit

enum InspectorTab: String, CaseIterable, Identifiable, Sendable {
    case sftp
    case monitor
    case snippets
    
    var id: String { self.rawValue }
    
    var title: String {
        switch self {
        case .sftp:
            return String(localized: "SFTP")
        case .monitor:
            return String(localized: "Monitor")
        case .snippets:
            return String(localized: "Snippets")
        }
    }
}

@Observable
@MainActor
final class SessionTab: Identifiable {
    let id: UUID
    var connection: SSHConnection
    let terminalModel: TerminalSessionViewModel
    let programStatusStore = TerminalProgramStatusStore()
    var showInspector: Bool = UserDefaults.standard.object(forKey: "showRemoteInspector") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(showInspector, forKey: "showRemoteInspector")
        }
    }
    var inspectorTab: InspectorTab = .sftp

    /// Cached surface view — created on first access and live for the tab lifetime.
    /// This ensures the SSH process (PTY) survives sidebar navigation in SwiftUI.
    var cachedSurface: GhosttySurfaceView?

    /// Connection timestamp for terminal duration tracking.
    var connectedAt: Date = Date()

    /// Whether the remote child process (ssh/expect) has exited.
    var isProcessExited: Bool = false

    /// Indicates whether the interactive terminal session is active and responsive.
    var isTerminalActive: Bool {
        cachedSurface != nil && !isProcessExited
    }

    /// Current remote working directory reported via OSC 7.
    var currentRemotePath: String?

    /// Dynamic title set by remote shell (OSC 0 / OSC 2) or manual override.
    var customTitle: String?

    var title: String {
        customTitle ?? connection.name
    }

    // Split terminal support
    var isSplit: Bool = false
    var splitDirection: SplitDirection = .right
    var splitTerminalModel: TerminalSessionViewModel?
    var splitSurface: GhosttySurfaceView?

    enum SplitDirection: Sendable {
        case right, left, down, up
    }

    init(connection: SSHConnection) {
        self.id = UUID()
        self.connection = connection
        let model = TerminalSessionViewModel(connection: connection)
        model.settings = AppSettings()
        self.terminalModel = model
    }

    func split(direction: SplitDirection) {
        let settings = AppSettings()
        let model = TerminalSessionViewModel(connection: connection)
        model.appModel = terminalModel.appModel
        model.settings = settings
        model.connect()
        
        let helper = GhosttyTerminalView(tab: self, settings: settings)
        let config = helper.configuration
        let surface = GhosttySurfaceView(config: config)
        GhosttyTerminalView.applyFontConfig(to: surface, fontName: settings.fontName, fontSize: settings.fontSize)
        setupMenuBuilder(for: surface, sshTab: self)
        configureSurfaceEvents(for: surface)
        
        self.splitTerminalModel = model
        self.splitSurface = surface
        self.splitDirection = direction
        self.isSplit = true
    }

    func closeSplit() {
        self.isSplit = false
        self.splitSurface = nil
        self.splitTerminalModel = nil
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
            let path = Self.extractPath(from: rawURL)
            guard !path.isEmpty else { return }
            self.currentRemotePath = path
            self.terminalModel.sftpViewModel.navigateTo(path: path)

        case .titleChanged(let title), .tabTitleChanged(let title):
            guard settings.shellIntegrationEnabled else { return }
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                self.customTitle = trimmed
            }

        case .commandFinished(let exitCode, let durationNs):
            self.programStatusStore.clearWorkingOnCommandFinished()
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
            self.isProcessExited = true

        case .programStatus(let report):
            if let transition = self.programStatusStore.apply(report) {
                let defaultName = self.customTitle ?? self.connection.name
                let appLabel = !transition.report.app.isEmpty ? transition.report.app : (!transition.report.title.isEmpty ? transition.report.title : defaultName)
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

    static func extractPath(from urlString: String) -> String {
        if let url = URL(string: urlString), url.scheme == "file" {
            return url.path
        }
        if urlString.hasPrefix("file://") {
            let withoutPrefix = urlString.dropFirst(7)
            if let slashIndex = withoutPrefix.firstIndex(of: "/") {
                return String(withoutPrefix[slashIndex...])
            }
        }
        return urlString
    }
}

