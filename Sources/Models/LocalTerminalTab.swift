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

    // Split terminal support
    var isSplit: Bool = false
    var splitDirection: SessionTab.SplitDirection = .right
    var splitSurface: GhosttySurfaceView?

    init(number: Int, surfaceView: GhosttySurfaceView) {
        self.id = UUID()
        self.name = "Terminal \(number)"
        self.surfaceView = surfaceView
        setupLocalMenuBuilder(for: surfaceView, tab: self)
    }

    init(id: UUID, name: String, surfaceView: GhosttySurfaceView) {
        self.id = id
        self.name = name
        self.surfaceView = surfaceView
        setupLocalMenuBuilder(for: surfaceView, tab: self)
    }

    func split(direction: SessionTab.SplitDirection) {
        let settings = AppSettings()
        var config = GhosttySurfaceConfiguration()
        config.fontSize = Float(settings.fontSize)
        config.environmentVariables = LocalShellEnvironment.make()
        config.workingDirectory = NSHomeDirectory()
        
        let surface = GhosttySurfaceView(config: config)
        setupLocalMenuBuilder(for: surface, tab: self)
        self.splitSurface = surface
        self.splitDirection = direction
        self.isSplit = true
    }

    func closeSplit() {
        self.isSplit = false
        self.splitSurface = nil
    }
}
