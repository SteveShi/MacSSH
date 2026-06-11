import Foundation

/// Builds the environment for a local shell PTY.
///
/// Beyond inheriting the user's environment and guaranteeing a sane `TERM`, this
/// presents a **Ghostty terminal identity** so Kiro CLI (the Fig / Amazon Q
/// Developer CLI successor) treats MacSSH's local terminal as a supported
/// terminal and engages its inline completions / autocomplete engine.
///
/// This is legitimate: MacSSH renders with libghostty, so to the shell and to
/// Kiro's terminal integration it *is* a Ghostty terminal. Kiro's `qterm` layer
/// reports `__CFBundleIdentifier` / `TERM_PROGRAM` to its desktop helper, which
/// matches them against its list of supported terminals.
enum LocalShellEnvironment {
    /// Ghostty.app's bundle identifier — reported by Kiro's `qterm` to its
    /// desktop helper for the "supported terminal" check.
    static let ghosttyBundleID = "com.mitchellh.ghostty"
    static let ghosttyTermProgram = "ghostty"
    /// Only needs to be a plausible, non-empty Ghostty version; safe to bump.
    static let ghosttyTermProgramVersion = "1.3.1"

    /// Fallback terminal type when none is inherited (libghostty normally sets
    /// `TERM=xterm-ghostty` itself when it spawns the PTY).
    static let fallbackTerm = "xterm-256color"

    static func make() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        if env["TERM"] == nil || env["TERM"] == "dumb" {
            env["TERM"] = fallbackTerm
        }
        env["TERM_PROGRAM"] = ghosttyTermProgram
        env["TERM_PROGRAM_VERSION"] = ghosttyTermProgramVersion
        env["__CFBundleIdentifier"] = ghosttyBundleID
        return env
    }
}
