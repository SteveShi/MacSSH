import AppKit
import Foundation
import GhosttyKit

// Use a top-level function for the C callback to ensure NO implicit actor isolation.
// This is critical because this function is called from Ghostty's background renderer thread.
private func ghostty_wakeup_callback(userdata: UnsafeMutableRawPointer?) {
    guard let userdata else { return }
    
    // Convert the pointer to an Int (bit pattern). Int is Sendable, 
    // which allows it to cross from the background thread to the MainActor 
    // without triggering Swift 6's data race detection for UnsafeMutableRawPointer.
    let bitPattern = Int(bitPattern: userdata)
    
    DispatchQueue.main.async {
        // Re-construct the pointer from the bit pattern on the main thread.
        guard let opaque = UnsafeMutableRawPointer(bitPattern: bitPattern) else { return }
        
        // Now on the main thread, we can safely re-acquire the GhosttyRuntime (which is @MainActor)
        let runtime = Unmanaged<GhosttyRuntime>.fromOpaque(opaque).takeUnretainedValue()
        runtime.appTick()
    }
}

private func ghostty_read_clipboard_callback(
    userdata: UnsafeMutableRawPointer?,
    clipboard: ghostty_clipboard_e,
    request: UnsafeMutableRawPointer?
) -> Bool {
    guard let userdata, let request else { return false }
    let viewAddress = Int(bitPattern: userdata)
    let requestAddress = Int(bitPattern: request)
    
    DispatchQueue.main.async {
        guard let viewPtr = UnsafeMutableRawPointer(bitPattern: viewAddress) else { return }
        guard let reqPtr = UnsafeMutableRawPointer(bitPattern: requestAddress) else { return }
        
        let surfaceView = Unmanaged<GhosttySurfaceView>.fromOpaque(viewPtr).takeUnretainedValue()
        guard let surface = surfaceView.rawSurface else { return }
        
        let pasteboard = NSPasteboard.general
        if let text = pasteboard.string(forType: .string) {
            text.withCString { cStr in
                ghostty_surface_complete_clipboard_request(surface, cStr, reqPtr, true)
            }
        } else {
            ghostty_surface_complete_clipboard_request(surface, nil, reqPtr, false)
        }
    }
    return true
}

private func ghostty_write_clipboard_callback(
    userdata: UnsafeMutableRawPointer?,
    clipboard: ghostty_clipboard_e,
    content: UnsafePointer<ghostty_clipboard_content_s>?,
    contentLen: Int,
    confirm: Bool
) {
    guard let content, contentLen > 0 else { return }
    
    // String is Sendable, so we copy it out on the calling background thread
    // before sending it to the MainActor
    var textToCopy: String? = nil
    for i in 0..<contentLen {
        let item = content[i]
        guard let mimePtr = item.mime, let dataPtr = item.data else { continue }
        let mime = String(cString: mimePtr)
        let data = String(cString: dataPtr)
        
        if mime == "text/plain" || mime.hasPrefix("text/") {
            textToCopy = data
            break
        }
    }
    
    guard let text = textToCopy else { return }
    
    DispatchQueue.main.async {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}

@MainActor
final class GhosttyRuntime {
    static let shared = GhosttyRuntime()

    private(set) var app: ghostty_app_t?
    private(set) var config: ghostty_config_t?

    private init() {
        _ = ghostty_init(0, nil)

        let cfg = ghostty_config_new()
        if let cfg {
            ghostty_config_load_default_files(cfg)
            ghostty_config_finalize(cfg)
        }
        self.config = cfg

        // ghostty_runtime_config_s members are @convention(c)
        var runtimeCfg = ghostty_runtime_config_s()
        runtimeCfg.userdata = Unmanaged.passUnretained(self).toOpaque()
        runtimeCfg.supports_selection_clipboard = true
        runtimeCfg.wakeup_cb = ghostty_wakeup_callback
        
        // Use empty closures for other callbacks to avoid any potential isolation issues in inline closures
        runtimeCfg.action_cb = { _, _, _ in false }
        runtimeCfg.read_clipboard_cb = ghostty_read_clipboard_callback
        runtimeCfg.confirm_read_clipboard_cb = { _, _, _, _ in }
        runtimeCfg.write_clipboard_cb = ghostty_write_clipboard_callback
        runtimeCfg.close_surface_cb = { _, _ in }

        if let cfg {
            self.app = ghostty_app_new(&runtimeCfg, cfg)
        }
    }

    fileprivate func appTick() {
        guard let app else { return }
        ghostty_app_tick(app)
    }
}
