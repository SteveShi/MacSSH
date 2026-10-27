import Foundation

/// Converts `tmux send-keys` compatible key names into terminal byte sequences.
public enum KeyNames {
    public static let vocabulary = """
    Enter Return Tab Escape Esc Space BSpace Backspace Delete DC IC Insert \
    Up Down Right Left Home End PgUp PgDn F1-F12 C-<key> M-<key>
    """

    public static func bytes(for name: String) -> [UInt8]? {
        if let plain = plainBytes(for: name) {
            return plain
        }
        var rest = Substring(name)
        var escapes = 0
        while rest.count > 2, rest.hasPrefix("M-") || rest.hasPrefix("m-") {
            rest = rest.dropFirst(2)
            escapes += 1
        }
        guard escapes > 0 else { return nil }
        let key = String(rest)
        return [UInt8](repeating: 0x1B, count: escapes) + (plainBytes(for: key) ?? Array(key.utf8))
    }

    private static func plainBytes(for name: String) -> [UInt8]? {
        if let simple = simpleKeys[name.lowercased()] {
            return Array(simple.utf8)
        }
        if name.count > 2, name.hasPrefix("C-") || name.hasPrefix("c-") {
            return controlBytes(for: String(name.dropFirst(2)))
        }
        return nil
    }

    private static func controlBytes(for key: String) -> [UInt8]? {
        if key.count == 1, let scalar = key.unicodeScalars.first {
            let value = scalar.value
            if value >= 97, value <= 122 {
                return [UInt8(value - 96)]
            }
            if value >= 65, value <= 90 {
                return [UInt8(value - 64)]
            }
            switch scalar {
            case "@", " ": return [0x00]
            case "[": return [0x1B]
            case "\\": return [0x1C]
            case "]": return [0x1D]
            case "^": return [0x1E]
            case "_": return [0x1F]
            case "?": return [0x7F]
            default: return nil
            }
        }
        return nil
    }

    private static let simpleKeys: [String: String] = {
        var keys: [String: String] = [
            "enter": "\r",
            "return": "\r",
            "tab": "\t",
            "escape": "\u{1B}",
            "esc": "\u{1B}",
            "space": " ",
            "bspace": "\u{7F}",
            "backspace": "\u{7F}",
            "delete": "\u{1B}[3~",
            "dc": "\u{1B}[3~",
            "insert": "\u{1B}[2~",
            "ic": "\u{1B}[2~",
            "up": "\u{1B}[A",
            "down": "\u{1B}[B",
            "right": "\u{1B}[C",
            "left": "\u{1B}[D",
            "home": "\u{1B}[H",
            "end": "\u{1B}[F",
            "pgup": "\u{1B}[5~",
            "pageup": "\u{1B}[5~",
            "pgdn": "\u{1B}[6~",
            "pagedown": "\u{1B}[6~",
        ]
        let functionKeys = [
            "\u{1B}OP", "\u{1B}OQ", "\u{1B}OR", "\u{1B}OS",
            "\u{1B}[15~", "\u{1B}[17~", "\u{1B}[18~", "\u{1B}[19~",
            "\u{1B}[20~", "\u{1B}[21~", "\u{1B}[23~", "\u{1B}[24~",
        ]
        for (index, sequence) in functionKeys.enumerated() {
            keys["f\(index + 1)"] = sequence
        }
        return keys
    }()
}
