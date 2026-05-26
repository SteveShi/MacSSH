import AppKit
import Foundation
import GhosttyKit

@MainActor
final class GhosttySurfaceView: NSView {
    private let runtime: GhosttyRuntime
    private struct SurfaceHandle: @unchecked Sendable {
        var value: ghostty_surface_t?
    }
    private var surface = SurfaceHandle(value: nil)
    private var surfaceConfig = GhosttySurfaceConfiguration()

    var rawSurface: ghostty_surface_t? {
        surface.value
    }

    init(runtime: GhosttyRuntime = .shared, config: GhosttySurfaceConfiguration = GhosttySurfaceConfiguration()) {
        self.runtime = runtime
        self.surfaceConfig = config
        super.init(frame: .zero)
        wantsLayer = true
        setupSurfaceIfPossible()
    }

    required init?(coder: NSCoder) {
        return nil
    }

    deinit {
        guard let surface = surface.value else { return }
        DispatchQueue.main.async {
            ghostty_surface_free(surface)
        }
    }

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result, let surface = surface.value { ghostty_surface_set_focus(surface, true) }
        return result
    }

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        if result, let surface = surface.value { ghostty_surface_set_focus(surface, false) }
        return result
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateContentScale()
        // First async pass: size may not be final yet (SwiftUI layout in-flight)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.updateSurfaceSize()
            self.window?.makeFirstResponder(self)
        }
        // Second pass with a short delay: ensures the PTY receives the correct
        // TIOCSWINSZ *after* Auto Layout has fully resolved the view frame.
        // Without this, $COLUMNS reports the Ghostty default (80) and tools like
        // `brew` truncate their output.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.updateSurfaceSize()
        }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateSurfaceSize()
    }

    override func layout() {
        super.layout()
        updateSurfaceSize()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateContentScale()
        updateSurfaceSize()
    }

    override func keyDown(with event: NSEvent) {
        guard let surface = surface.value else { return }
        var keyEvent = event.ghosttyKeyEvent(GHOSTTY_ACTION_PRESS)
        if let text = event.ghosttyCharacters {
            text.withCString { cString in
                keyEvent.text = cString
                ghostty_surface_key(surface, keyEvent)
            }
        } else {
            ghostty_surface_key(surface, keyEvent)
        }
    }

    override func keyUp(with event: NSEvent) {
        guard let surface = surface.value else { return }
        let keyEvent = event.ghosttyKeyEvent(GHOSTTY_ACTION_RELEASE)
        ghostty_surface_key(surface, keyEvent)
    }

    override func flagsChanged(with event: NSEvent) {
        guard let surface = surface.value else { return }
        let keyEvent = event.ghosttyKeyEvent(GHOSTTY_ACTION_PRESS)
        ghostty_surface_key(surface, keyEvent)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.rightMouseDown(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        guard let surface = surface.value else { return }

        // First tell Ghostty where the mouse is so it can resolve the correct surface
        let loc = convert(event.locationInWindow, from: nil)
        ghostty_surface_mouse_pos(surface, loc.x, bounds.height - loc.y,
                                  ghostty_input_mods_e(GHOSTTY_MODS_NONE.rawValue))

        // Build scroll mods:
        //   bit 0 = precision_scroll (trackpad / smooth scroll events)
        //   bit 1 = momentum_scroll  (kinetic deceleration phase)
        //   bit 2 = begin            (gesture began)
        //   bit 3 = end              (gesture ended)
        var scrollMods: Int32 = 0

        let isPrecise = event.hasPreciseScrollingDeltas
        if isPrecise { scrollMods |= 1 }

        // Treat either non-stationary phase or non-empty momentumPhase as momentum
        let hasMomentum = (event.momentumPhase != []) || (event.phase == .changed && event.momentumPhase != [])
        if hasMomentum { scrollMods |= 2 }

        if event.phase == .began { scrollMods |= 1 << 2 }
        if event.phase == .ended || event.phase == .cancelled { scrollMods |= 1 << 3 }

        // Reduce tiny jitter during .mayBegin to better match NSScrollView feel
        if event.phase == .mayBegin {
            let threshold: CGFloat = 0.5
            if abs(event.scrollingDeltaX) < threshold && abs(event.scrollingDeltaY) < threshold {
                return
            }
        }

        // macOS scrollingDeltaY is already adjusted for the "Natural Scrolling"
        // preference, so pass it directly. Ghostty's Y axis is positive-up
        // (same convention as macOS), so no negation needed.
        let deltaX = event.scrollingDeltaX
        let deltaY: CGFloat
        if isPrecise {
            deltaY = event.scrollingDeltaY
        } else {
            let lineScale: CGFloat = 10.0
            deltaY = (event.scrollingDeltaY != 0 ? event.scrollingDeltaY : event.deltaY) * lineScale
        }

        ghostty_surface_mouse_scroll(surface,
                                     deltaX,
                                     deltaY,
                                     scrollMods)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    private func setupSurfaceIfPossible() {
        guard let app = runtime.app else { return }
        var config = ghostty_surface_config_new()

        config.userdata = Unmanaged.passUnretained(self).toOpaque()
        config.platform_tag = GHOSTTY_PLATFORM_MACOS
        config.platform = ghostty_platform_u(macos: ghostty_platform_macos_s(
            nsview: Unmanaged.passUnretained(self).toOpaque()
        ))
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2.0
        config.scale_factor = Double(scale)
        config.font_size = max(10.0, surfaceConfig.fontSize)
        config.wait_after_command = surfaceConfig.waitAfterCommand
        config.context = surfaceConfig.context

        let workingDirectory = surfaceConfig.workingDirectory
        let command = surfaceConfig.command
        let initialInput = surfaceConfig.initialInput

        var envVars = surfaceConfig.environmentVariables.map { key, value in
            ghostty_env_var_s(key: strdup(key), value: strdup(value))
        }

        let createSurface: () -> Void = {
            envVars.withUnsafeMutableBufferPointer { buffer in
                config.env_vars = buffer.baseAddress
                config.env_var_count = buffer.count
                self.surface.value = ghostty_surface_new(app, &config)
            }
        }

        if let workingDirectory, let command, let initialInput {
            workingDirectory.withCString { wd in
                config.working_directory = wd
                command.withCString { cmd in
                    config.command = cmd
                    initialInput.withCString { input in
                        config.initial_input = input
                        createSurface()
                    }
                }
            }
        } else if let workingDirectory, let command {
            workingDirectory.withCString { wd in
                config.working_directory = wd
                command.withCString { cmd in
                    config.command = cmd
                    createSurface()
                }
            }
        } else if let workingDirectory, let initialInput {
            workingDirectory.withCString { wd in
                config.working_directory = wd
                initialInput.withCString { input in
                    config.initial_input = input
                    createSurface()
                }
            }
        } else if let command, let initialInput {
            command.withCString { cmd in
                config.command = cmd
                initialInput.withCString { input in
                    config.initial_input = input
                    createSurface()
                }
            }
        } else if let workingDirectory {
            workingDirectory.withCString { wd in
                config.working_directory = wd
                createSurface()
            }
        } else if let command {
            command.withCString { cmd in
                config.command = cmd
                createSurface()
            }
        } else if let initialInput {
            initialInput.withCString { input in
                config.initial_input = input
                createSurface()
            }
        } else {
            createSurface()
        }

        for env in envVars {
            if let key = env.key { free(UnsafeMutableRawPointer(mutating: key)) }
            if let value = env.value { free(UnsafeMutableRawPointer(mutating: value)) }
        }
    }

    private func updateContentScale() {
        guard let surface = surface.value else { return }
        let backingFrame = convertToBacking(bounds)
        guard bounds.width > 0, bounds.height > 0 else { return }
        let xScale = backingFrame.width / bounds.width
        let yScale = backingFrame.height / bounds.height
        ghostty_surface_set_content_scale(surface, xScale, yScale)
    }

    private func updateSurfaceSize() {
        guard let surface = surface.value else { return }
        let size = convertToBacking(bounds.size)
        guard size.width > 0, size.height > 0 else { return }
        ghostty_surface_set_size(surface, UInt32(size.width), UInt32(size.height))
    }
}

struct GhosttySurfaceConfiguration {
    var fontSize: Float = 0
    var workingDirectory: String?
    var command: String?
    var environmentVariables: [String: String] = [:]
    var initialInput: String?
    var waitAfterCommand: Bool = false
    var context: ghostty_surface_context_e = GHOSTTY_SURFACE_CONTEXT_WINDOW
}
