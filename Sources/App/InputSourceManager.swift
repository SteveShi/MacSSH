import Carbon
import os.log

/// Encapsulates macOS input source (input method) management via the TIS API.
enum InputSourceManager {

    private static let logger = Logger(subsystem: "com.steveshi.macssh", category: "InputSource")

    /// Represents a single enabled keyboard input source.
    struct InputSource: Identifiable, Hashable, Sendable {
        let id: String
        let localizedName: String
    }

    /// Returns all currently enabled, selectable keyboard input sources.
    static func enabledInputSources() -> [InputSource] {
        let conditions: CFDictionary = [
            kTISPropertyInputSourceCategory as String: kTISCategoryKeyboardInputSource as String,
            kTISPropertyInputSourceIsEnabled as String: true,
            kTISPropertyInputSourceIsSelectCapable as String: true,
        ] as CFDictionary

        guard let sourceList = TISCreateInputSourceList(conditions, false)?.takeRetainedValue() as? [TISInputSource] else {
            logger.warning("Failed to retrieve input source list from TIS API")
            return []
        }

        let sources = sourceList.compactMap { source -> InputSource? in
            guard let idPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID),
                  let namePtr = TISGetInputSourceProperty(source, kTISPropertyLocalizedName) else {
                return nil
            }
            let id = Unmanaged<CFString>.fromOpaque(idPtr).takeUnretainedValue() as String
            let name = Unmanaged<CFString>.fromOpaque(namePtr).takeUnretainedValue() as String
            return InputSource(id: id, localizedName: name)
        }
        logger.debug("Found \(sources.count) enabled input sources")
        return sources
    }

    /// Selects (activates) the input source with the given identifier.
    /// - Parameter id: The `kTISPropertyInputSourceID` value, e.g. `"com.apple.keylayout.ABC"`.
    static func selectInputSource(id: String) {
        let conditions: CFDictionary = [
            kTISPropertyInputSourceID as String: id,
        ] as CFDictionary

        guard let sourceList = TISCreateInputSourceList(conditions, false)?.takeRetainedValue() as? [TISInputSource],
              let source = sourceList.first else {
            logger.error("Input source not found for id: \(id)")
            return
        }

        let status = TISSelectInputSource(source)
        if status == noErr {
            logger.info("Switched input source to: \(id)")
        } else {
            logger.error("TISSelectInputSource failed with status: \(status) for id: \(id)")
        }
    }
}
