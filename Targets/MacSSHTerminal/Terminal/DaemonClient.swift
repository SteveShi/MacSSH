import Darwin
import Foundation

public enum CLISymlinkError: LocalizedError, Sendable {
    case executableNotFound
    case symlinkCreationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .executableNotFound:
            return String(localized: "Could not locate macssh-cli inside the application bundle.")
        case .symlinkCreationFailed(let reason):
            return reason
        }
    }
}

@MainActor
public final class DaemonClient {
    public static let shared = DaemonClient()

    private init() {}

    /// Pings `macsshd` without autostarting it. Returns `(pid, activeSessionCount)` if running.
    public func ping() async -> (pid: Int32, activeSessionCount: Int)? {
        await Task.detached(priority: .utility) {
            guard let response = try? UnixSocketWire.sendOneShotRequest(.ping, autostart: false) else {
                return nil
            }
            if case .pong(_, let pid, let count) = response {
                return (pid, count)
            }
            return nil
        }.value
    }

    /// Lists all active sessions in `macsshd`.
    public func listSessions(autostart: Bool = false) async -> [DaemonSessionSummary] {
        await Task.detached(priority: .utility) {
            guard let response = try? UnixSocketWire.sendOneShotRequest(.listSessions, autostart: autostart) else {
                return []
            }
            if case .sessionList(let sessions) = response {
                return sessions
            }
            return []
        }.value
    }

    /// Terminates and removes a session in `macsshd`.
    public func closeSession(target: String) async {
        await Task.detached(priority: .utility) {
            _ = try? UnixSocketWire.sendOneShotRequest(.closeSession(target: target), autostart: false)
        }.value
    }

    /// Detaches any attached client from a session in `macsshd` while keeping the shell alive.
    public func detachSession(target: String) async {
        await Task.detached(priority: .utility) {
            _ = try? UnixSocketWire.sendOneShotRequest(.detachSession(target: target), autostart: false)
        }.value
    }

    /// Updates custom key-value attributes on a session in `macsshd`.
    public func setAttributes(target: String, attributes: [String: String]) async {
        await Task.detached(priority: .utility) {
            _ = try? UnixSocketWire.sendOneShotRequest(
                .setAttributes(target: target, attributes: attributes),
                autostart: false
            )
        }.value
    }

    /// Builds the `macssh-cli bridge` command string for `GhosttySurfaceConfiguration.command`.
    nonisolated public static func bridgeCommand(
        sessionKey: String,
        title: String,
        workingDirectory: String?,
        shell: String? = nil
    ) -> String? {
        guard let cliPath = DaemonPaths.resolveExecutable(named: "macssh-cli") else {
            return nil
        }
        var args: [String] = [
            shellQuoted(cliPath),
            "bridge",
            "--session", shellQuoted(sessionKey),
            "--name", shellQuoted(title)
        ]
        if let cwd = workingDirectory, !cwd.isEmpty {
            args.append("--cwd")
            args.append(shellQuoted(cwd))
        }
        if let shell, !shell.isEmpty {
            args.append("--shell")
            args.append(shellQuoted(shell))
        }
        return args.joined(separator: " ")
    }

    // MARK: - CLI Symlink Management

    /// Returns the currently installed symlink path (`/usr/local/bin/macssh` or `~/.local/bin/macssh`)
    /// if it points to the bundled `macssh-cli` executable.
    nonisolated public func installedCLISymlinkPath() -> String? {
        let fm = FileManager.default
        let candidates = [
            "/usr/local/bin/macssh",
            (NSHomeDirectory() as NSString).appendingPathComponent(".local/bin/macssh")
        ]
        let expectedTarget = DaemonPaths.resolveExecutable(named: "macssh-cli")
        for path in candidates {
            if let dest = try? fm.destinationOfSymbolicLink(atPath: path) {
                if let expectedTarget, dest == expectedTarget {
                    return path
                }
                if fm.isExecutableFile(atPath: path) {
                    return path
                }
            }
        }
        return nil
    }

    /// Installs the `macssh` symlink pointing to `macssh-cli`.
    /// Tries `/usr/local/bin/macssh` first; falls back to `~/.local/bin/macssh` on permission error.
    nonisolated public func installCLISymlink() -> Result<String, Error> {
        guard let cliPath = DaemonPaths.resolveExecutable(named: "macssh-cli") else {
            return .failure(CLISymlinkError.executableNotFound)
        }

        let primaryDir = "/usr/local/bin"
        let primaryPath = "/usr/local/bin/macssh"

        if tryInstallSymlink(target: cliPath, at: primaryPath, directory: primaryDir) {
            return .success(primaryPath)
        }

        let fallbackDir = (NSHomeDirectory() as NSString).appendingPathComponent(".local/bin")
        let fallbackPath = (fallbackDir as NSString).appendingPathComponent("macssh")

        do {
            try FileManager.default.createDirectory(atPath: fallbackDir, withIntermediateDirectories: true)
            _ = Darwin.unlink(fallbackPath)
            try FileManager.default.createSymbolicLink(atPath: fallbackPath, withDestinationPath: cliPath)
            return .success(fallbackPath)
        } catch {
            return .failure(CLISymlinkError.symlinkCreationFailed(error.localizedDescription))
        }
    }

    nonisolated private func tryInstallSymlink(target: String, at linkPath: String, directory: String) -> Bool {
        let fm = FileManager.default
        if !fm.fileExists(atPath: directory) {
            do {
                try fm.createDirectory(atPath: directory, withIntermediateDirectories: true)
            } catch {
                return false
            }
        }
        // Remove existing file or symlink if present (including broken symlinks)
        if fm.fileExists(atPath: linkPath) || (try? fm.attributesOfItem(atPath: linkPath)) != nil {
            if Darwin.unlink(linkPath) != 0 && errno != ENOENT {
                return false
            }
        }
        do {
            try fm.createSymbolicLink(atPath: linkPath, withDestinationPath: target)
            return true
        } catch {
            return false
        }
    }

    nonisolated private static func shellQuoted(_ string: String) -> String {
        "'" + string.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
