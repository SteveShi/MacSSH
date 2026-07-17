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
    /// Fallback terminal type when none is inherited (libghostty normally sets
    /// `TERM=xterm-ghostty` itself when it spawns the PTY).
    static let fallbackTerm = "xterm-256color"

    static func make() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = fallbackTerm
        return env
    }
}
