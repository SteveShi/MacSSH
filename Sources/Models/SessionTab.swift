import Foundation
import Observation

@Observable
@MainActor
final class SessionTab: Identifiable {
    let id: UUID
    var connection: SSHConnection
    var terminalModel: TerminalSessionViewModel?

    /// Cached surface view — created on first access and live for the tab lifetime.
    /// This ensures the SSH process (PTY) survives sidebar navigation in SwiftUI.
    var cachedSurface: GhosttySurfaceView?

    init(connection: SSHConnection) {
        self.id = UUID()
        self.connection = connection
    }
}
