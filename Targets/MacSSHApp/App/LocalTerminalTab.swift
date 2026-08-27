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
    }

    init(id: UUID, name: String, surfaceView: GhosttySurfaceView) {
        self.id = id
        self.name = name
        self.surfaceView = surfaceView
        let settings = AppSettings()
        GhosttyTerminalView.applyFontConfig(to: surfaceView, fontName: settings.fontName, fontSize: settings.fontSize)
        setupMenuBuilder(for: surfaceView, localTab: self)
    }

    func split(direction: SessionTab.SplitDirection) {
        let settings = AppSettings()
        var config = GhosttySurfaceConfiguration()
        config.fontSize = Float(settings.fontSize)
        config.environmentVariables = LocalShellEnvironment.make()
        config.workingDirectory = NSHomeDirectory()
        
        let surface = GhosttySurfaceView(config: config)
        GhosttyTerminalView.applyFontConfig(to: surface, fontName: settings.fontName)
        setupMenuBuilder(for: surface, localTab: self)
        self.splitSurface = surface
        self.splitDirection = direction
        self.isSplit = true
    }

    func closeSplit() {
        self.isSplit = false
        self.splitSurface = nil
    }
}
