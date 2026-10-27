import Darwin
import Foundation

public enum DaemonProtocol {
    public static let version: UInt32 = 1
    public static let maxFrameByteCount: Int = 2 * 1024 * 1024
    public static let maxReplayByteCount: Int = 256 * 1024
    public static let maxPendingInputByteCount: Int = 256 * 1024
    public static let maxSessions: Int = 64
    public static let defaultColumns: UInt16 = 80
    public static let defaultRows: UInt16 = 24
    public static let maximumColumns: UInt16 = 500
    public static let maximumRows: UInt16 = 300
    public static let idleShutdownSeconds: TimeInterval = 30.0
}

public enum DaemonFrameKind: UInt8, Sendable {
    case controlRequest = 1
    case controlResponse = 2
    case streamInput = 3
    case streamOutput = 4
    case streamResize = 5
    case streamSessionExit = 6
    case streamRedraw = 7
}

public struct DaemonSessionSummary: Codable, Sendable, Identifiable, Equatable {
    public var id: String { sessionKey }
    public var shortID: UInt64
    public var sessionKey: String
    public var title: String
    public var shellPID: Int32
    public var foregroundProcessName: String
    public var isForegroundShell: Bool
    public var columns: UInt16
    public var rows: UInt16
    public var isAttached: Bool
    public var currentDirectory: String?
    public var createdAt: Date
    public var attributes: [String: String]

    public init(
        shortID: UInt64,
        sessionKey: String,
        title: String,
        shellPID: Int32,
        foregroundProcessName: String,
        isForegroundShell: Bool,
        columns: UInt16,
        rows: UInt16,
        isAttached: Bool,
        currentDirectory: String?,
        createdAt: Date,
        attributes: [String: String] = [:]
    ) {
        self.shortID = shortID
        self.sessionKey = sessionKey
        self.title = title
        self.shellPID = shellPID
        self.foregroundProcessName = foregroundProcessName
        self.isForegroundShell = isForegroundShell
        self.columns = columns
        self.rows = rows
        self.isAttached = isAttached
        self.currentDirectory = currentDirectory
        self.createdAt = createdAt
        self.attributes = attributes
    }
}

public enum DaemonControlRequest: Codable, Sendable {
    case ping
    case openOrAttach(
        sessionKey: String?,
        title: String?,
        command: [String]?,
        shell: String?,
        workingDirectory: String?,
        environment: [String: String]?,
        columns: UInt16,
        rows: UInt16,
        attributes: [String: String]?,
        attachStream: Bool
    )
    case listSessions
    case captureSession(target: String, full: Bool, lastCommandOnly: Bool)
    case sendInput(target: String, data: Data)
    case closeSession(target: String)
    case detachSession(target: String)
    case setAttributes(target: String, attributes: [String: String])
    case shutdownIfIdle
}

public enum DaemonControlResponse: Codable, Sendable {
    case pong(version: UInt32, pid: Int32, activeSessionCount: Int)
    case openedOrAttached(summary: DaemonSessionSummary, replayData: Data)
    case sessionList([DaemonSessionSummary])
    case captured(summary: DaemonSessionSummary, text: String)
    case ok
    case error(code: String, message: String)
}

public enum DaemonPaths {
    public static var runDirectory: URL {
        let home = NSHomeDirectory()
        return URL(fileURLWithPath: home)
            .appendingPathComponent("Library/Application Support/MacSSH/run", isDirectory: true)
    }

    public static var socketPath: String {
        runDirectory.appendingPathComponent("macsshd.sock").path
    }

    public static var lockPath: String {
        runDirectory.appendingPathComponent("macsshd.lock").path
    }

    public static var logPath: String {
        runDirectory.appendingPathComponent("macsshd.log").path
    }

    public static func ensureRunDirectory() throws {
        let fm = FileManager.default
        let dir = runDirectory
        if !fm.fileExists(atPath: dir.path) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        } else {
            try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
        }
    }

    /// Resolves the path to a sibling executable (`macsshd` or `macssh-cli`) located in the same
    /// directory as the current process executable or inside `MacSSH.app/Contents/MacOS/`.
    public static func resolveExecutable(named name: String) -> String? {
        let fm = FileManager.default
        if let mainExec = Bundle.main.executableURL {
            let sibling = mainExec.deletingLastPathComponent().appendingPathComponent(name).path
            if fm.isExecutableFile(atPath: sibling) {
                return sibling
            }
        }
        // Fallback: resolve argv[0] realpath (handles symlinks like /usr/local/bin/macssh -> .../Contents/MacOS/macssh-cli)
        if let arg0 = CommandLine.arguments.first {
            var resolved = [CChar](repeating: 0, count: Int(PATH_MAX))
            if realpath(arg0, &resolved) != nil {
                let realURL = URL(fileURLWithPath: String(cString: resolved))
                let sibling = realURL.deletingLastPathComponent().appendingPathComponent(name).path
                if fm.isExecutableFile(atPath: sibling) {
                    return sibling
                }
            }
        }
        let standardAppPath = "/Applications/MacSSH.app/Contents/MacOS/\(name)"
        if fm.isExecutableFile(atPath: standardAppPath) {
            return standardAppPath
        }
        return nil
    }
}
