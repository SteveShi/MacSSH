import Foundation
import Observation
import libghostty_swift

@Observable
@MainActor
final class LocalTerminalTab: Identifiable {
    let id: UUID
    var name: String
    /// The actual NSView is owned here so it survives SwiftUI navigation.
    let surfaceView: GhosttySurfaceView
    /// Drives the rename sheet hosted by the tab's own window.
    var isRenaming: Bool = false

    init(number: Int, surfaceView: GhosttySurfaceView) {
        self.id = UUID()
        self.name = "Terminal \(number)"
        self.surfaceView = surfaceView
    }

    init(id: UUID, name: String, surfaceView: GhosttySurfaceView) {
        self.id = id
        self.name = name
        self.surfaceView = surfaceView
    }
}
