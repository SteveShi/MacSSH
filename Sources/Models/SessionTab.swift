import Foundation
import Observation
import libghostty_swift

enum InspectorTab: String, CaseIterable, Identifiable, Sendable {
    case sftp
    case monitor
    
    var id: String { self.rawValue }
    
    var title: String {
        switch self {
        case .sftp:
            return String(localized: "SFTP")
        case .monitor:
            return String(localized: "Monitor")
        }
    }
}

@Observable
@MainActor
final class SessionTab: Identifiable {
    let id: UUID
    var connection: SSHConnection
    let terminalModel: TerminalSessionViewModel
    
    var showInspector: Bool = true
    var inspectorTab: InspectorTab = .sftp

    /// Cached surface view — created on first access and live for the tab lifetime.
    /// This ensures the SSH process (PTY) survives sidebar navigation in SwiftUI.
    var cachedSurface: GhosttySurfaceView?

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
        self.terminalModel = TerminalSessionViewModel(connection: connection)
    }

    func split(direction: SplitDirection) {
        let model = TerminalSessionViewModel(connection: connection)
        model.appModel = terminalModel.appModel
        model.connect()
        
        let settings = AppSettings()
        let helper = GhosttyTerminalView(tab: self, settings: settings)
        let config = helper.configuration
        let surface = GhosttySurfaceView(config: config)
        setupMenuBuilder(for: surface, sshTab: self)
        
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
}

