import Foundation
import Observation

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

    init(connection: SSHConnection) {
        self.id = UUID()
        self.connection = connection
        self.terminalModel = TerminalSessionViewModel(connection: connection)
    }
}

