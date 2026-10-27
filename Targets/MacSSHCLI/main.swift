import AppKit
import Darwin
import Foundation

#if canImport(MacSSHDaemonShared)
import MacSSHDaemonShared
#endif

private enum CLIError: Error, LocalizedError {
    case invalidUsage(String)
    case executionFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidUsage(let message):
            return message
        case .executionFailed(let message):
            return message
        }
    }
}

private enum MacSSHCLI {
    static func main() -> Never {
        let args = Array(CommandLine.arguments.dropFirst())
        guard let subcommand = args.first else {
            printUsage()
            Darwin.exit(0)
        }

        let remaining = Array(args.dropFirst())

        do {
            switch subcommand {
            case "list", "ls":
                try runList(args: remaining)
            case "capture":
                try runCapture(args: remaining)
            case "send":
                try runSend(args: remaining)
            case "new":
                try runNew(args: remaining)
            case "kill", "close", "rm":
                try runKill(args: remaining)
            case "detach":
                try runDetach(args: remaining)
            case "status":
                try runStatus(args: remaining)
            case "ssh", "connect":
                try runSSH(args: remaining)
            case "bridge":
                try runBridge(args: remaining)
            case "help", "--help", "-h":
                printUsage()
            case "version", "--version", "-v":
                print("macssh-cli (protocol v\(DaemonProtocol.version))")
            default:
                throw CLIError.invalidUsage("Unknown command '\(subcommand)'. Run 'macssh help' for usage.")
            }
            Darwin.exit(0)
        } catch let error as CLIError {
            writeStderr("Error: \(error.localizedDescription)\n")
            if case .invalidUsage = error {
                writeStderr("Run 'macssh help' for usage information.\n")
                Darwin.exit(64)
            }
            Darwin.exit(1)
        } catch {
            writeStderr("Error: \(error.localizedDescription)\n")
            Darwin.exit(1)
        }
    }

    // MARK: - Subcommands

    private static func runList(args: [String]) throws {
        var jsonOutput = false
        for arg in args {
            switch arg {
            case "--json", "-j":
                jsonOutput = true
            case "--help", "-h":
                printUsage()
                return
            default:
                throw CLIError.invalidUsage("Unexpected argument '\(arg)' for 'list'.")
            }
        }

        let response: DaemonControlResponse
        do {
            response = try UnixSocketWire.sendOneShotRequest(.listSessions, autostart: false)
        } catch DaemonWireError.connectionFailed {
            if jsonOutput {
                print("[]")
            } else {
                print("No active sessions (macsshd is not running)")
            }
            return
        }

        guard case .sessionList(let sessions) = response else {
            throw CLIError.executionFailed("Unexpected response from macsshd.")
        }

        if jsonOutput {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(sessions)
            if let text = String(data: data, encoding: .utf8) {
                print(text)
            }
            return
        }

        if sessions.isEmpty {
            print("No active sessions")
            return
        }

        let headers = ["ID", "NAME", "PROCESS", "PID", "SIZE", "STATE", "DIRECTORY", "KEY"]
        let sorted = sessions.sorted { $0.shortID < $1.shortID }
        let rows: [[String]] = sorted.map { session in
            [
                String(session.shortID),
                session.title.isEmpty ? "-" : session.title,
                session.foregroundProcessName.isEmpty ? "-" : session.foregroundProcessName,
                String(session.shellPID),
                "\(session.columns)x\(session.rows)",
                session.isAttached ? "attached" : "detached",
                abbreviateHome(session.currentDirectory),
                session.sessionKey
            ]
        }

        printTable(headers: headers, rows: rows)
    }

    private static func runCapture(args: [String]) throws {
        var target: String?
        var full = false
        var last = false

        for arg in args {
            switch arg {
            case "--full", "-f":
                full = true
            case "--last", "-l":
                last = true
            case "--help", "-h":
                printUsage()
                return
            default:
                if arg.hasPrefix("-") {
                    throw CLIError.invalidUsage("Unknown option '\(arg)' for 'capture'.")
                }
                if target == nil {
                    target = arg
                } else {
                    throw CLIError.invalidUsage("Unexpected extra argument '\(arg)' for 'capture'.")
                }
            }
        }

        guard let resolvedTarget = target, !resolvedTarget.isEmpty else {
            throw CLIError.invalidUsage("Usage: macssh capture <target> [--full] [--last]")
        }

        let response = try UnixSocketWire.sendOneShotRequest(
            .captureSession(target: resolvedTarget, full: full, lastCommandOnly: last),
            autostart: false
        )

        guard case .captured(_, let text) = response else {
            throw CLIError.executionFailed("Unexpected response from macsshd.")
        }

        print(text)
    }

    private static func runSend(args: [String]) throws {
        guard !args.isEmpty else {
            throw CLIError.invalidUsage("Usage: macssh send <target> (text <string> | key <name>)... [--enter]")
        }

        if args.first == "--help" || args.first == "-h" {
            printUsage()
            return
        }

        let target = args[0]
        let tokens = Array(args.dropFirst())
        guard !tokens.isEmpty else {
            throw CLIError.invalidUsage("Usage: macssh send <target> (text <string> | key <name>)... [--enter]")
        }

        var payloadBytes: [UInt8] = []
        var appendEnter = false
        var index = 0

        while index < tokens.count {
            let token = tokens[index]
            switch token {
            case "text":
                guard index + 1 < tokens.count else {
                    throw CLIError.invalidUsage("'text' requires a string argument.")
                }
                payloadBytes.append(contentsOf: tokens[index + 1].utf8)
                index += 2
            case "key":
                guard index + 1 < tokens.count else {
                    throw CLIError.invalidUsage("'key' requires a key name argument. Supported keys: \(KeyNames.vocabulary)")
                }
                let keyName = tokens[index + 1]
                guard let keyBytes = KeyNames.bytes(for: keyName) else {
                    throw CLIError.invalidUsage("Unknown key name '\(keyName)'. Supported keys: \(KeyNames.vocabulary)")
                }
                payloadBytes.append(contentsOf: keyBytes)
                index += 2
            case "--enter", "-e":
                appendEnter = true
                index += 1
            default:
                // Shorthand literal string support: `macssh send <target> "<string>" [--enter]`
                payloadBytes.append(contentsOf: token.utf8)
                index += 1
            }
        }

        if appendEnter {
            payloadBytes.append(contentsOf: KeyNames.bytes(for: "Enter") ?? [0x0D])
        }

        guard !payloadBytes.isEmpty else {
            throw CLIError.invalidUsage("No input bytes specified to send.")
        }

        let response = try UnixSocketWire.sendOneShotRequest(
            .sendInput(target: target, data: Data(payloadBytes)),
            autostart: false
        )

        guard case .ok = response else {
            throw CLIError.executionFailed("Unexpected response from macsshd.")
        }
    }

    private static func runNew(args: [String]) throws {
        var sessionKey: String?
        var title: String?
        var cwd: String? = FileManager.default.currentDirectoryPath
        var shell: String?
        var command: [String]?
        var attributes: [String: String] = [:]

        var index = 0
        while index < args.count {
            let arg = args[index]
            if arg == "--" {
                let cmdSlice = Array(args[(index + 1)...])
                if !cmdSlice.isEmpty {
                    command = cmdSlice
                }
                break
            }

            switch arg {
            case "--name", "--title", "-n":
                guard index + 1 < args.count else {
                    throw CLIError.invalidUsage("'\(arg)' requires a value.")
                }
                title = args[index + 1]
                index += 2
            case "--cwd", "-c":
                guard index + 1 < args.count else {
                    throw CLIError.invalidUsage("'\(arg)' requires a directory path.")
                }
                cwd = args[index + 1]
                index += 2
            case "--shell", "-s":
                guard index + 1 < args.count else {
                    throw CLIError.invalidUsage("'\(arg)' requires a shell path.")
                }
                shell = args[index + 1]
                index += 2
            case "--session", "--key", "-k":
                guard index + 1 < args.count else {
                    throw CLIError.invalidUsage("'\(arg)' requires a session key.")
                }
                sessionKey = args[index + 1]
                index += 2
            case "--attr":
                guard index + 1 < args.count else {
                    throw CLIError.invalidUsage("'--attr' requires a key=value pair.")
                }
                let pair = args[index + 1]
                if let eqIndex = pair.firstIndex(of: "=") {
                    let k = String(pair[..<eqIndex])
                    let v = String(pair[pair.index(after: eqIndex)...])
                    attributes[k] = v
                } else {
                    throw CLIError.invalidUsage("Invalid '--attr' format '\(pair)'; expected key=value.")
                }
                index += 2
            case "--help", "-h":
                printUsage()
                return
            default:
                throw CLIError.invalidUsage("Unknown argument '\(arg)' for 'new'.")
            }
        }

        let response = try UnixSocketWire.sendOneShotRequest(
            .openOrAttach(
                sessionKey: sessionKey,
                title: title,
                command: command,
                shell: shell,
                workingDirectory: cwd,
                environment: ProcessInfo.processInfo.environment,
                columns: DaemonProtocol.defaultColumns,
                rows: DaemonProtocol.defaultRows,
                attributes: attributes.isEmpty ? nil : attributes,
                attachStream: false
            ),
            autostart: true
        )

        guard case .openedOrAttached(let summary, _) = response else {
            throw CLIError.executionFailed("Unexpected response from macsshd.")
        }

        print("\(summary.shortID)\t\(summary.sessionKey)")
    }

    private static func runKill(args: [String]) throws {
        guard let target = args.first, !target.isEmpty, args.count == 1 else {
            if args.first == "--help" || args.first == "-h" {
                printUsage()
                return
            }
            throw CLIError.invalidUsage("Usage: macssh kill <target>")
        }

        let response = try UnixSocketWire.sendOneShotRequest(.closeSession(target: target), autostart: false)
        guard case .ok = response else {
            throw CLIError.executionFailed("Unexpected response from macsshd.")
        }
        print("Terminated session '\(target)'")
    }

    private static func runDetach(args: [String]) throws {
        guard let target = args.first, !target.isEmpty, args.count == 1 else {
            if args.first == "--help" || args.first == "-h" {
                printUsage()
                return
            }
            throw CLIError.invalidUsage("Usage: macssh detach <target>")
        }

        let response = try UnixSocketWire.sendOneShotRequest(.detachSession(target: target), autostart: false)
        guard case .ok = response else {
            throw CLIError.executionFailed("Unexpected response from macsshd.")
        }
        print("Detached session '\(target)'")
    }

    private static func runStatus(args: [String]) throws {
        if args.first == "--help" || args.first == "-h" {
            printUsage()
            return
        }
        guard args.isEmpty else {
            throw CLIError.invalidUsage("Usage: macssh status")
        }

        let response: DaemonControlResponse
        do {
            response = try UnixSocketWire.sendOneShotRequest(.ping, autostart: false)
        } catch DaemonWireError.connectionFailed {
            print("macsshd: stopped")
            return
        }

        guard case .pong(let version, let pid, let activeSessionCount) = response else {
            throw CLIError.executionFailed("Unexpected response from macsshd.")
        }

        print("macsshd: running")
        print("  PID:              \(pid)")
        print("  Protocol Version: \(version)")
        print("  Active Sessions:  \(activeSessionCount)")
        print("  Socket Path:      \(DaemonPaths.socketPath)")
    }

    private static func runSSH(args: [String]) throws {
        if args.first == "--help" || args.first == "-h" {
            printUsage()
            return
        }

        var targetSpec: String?
        var explicitUser: String?
        var explicitPort: UInt16?

        var index = 0
        while index < args.count {
            let arg = args[index]
            switch arg {
            case "-p", "--port":
                guard index + 1 < args.count, let p = UInt16(args[index + 1]), p > 0 else {
                    throw CLIError.invalidUsage("Invalid port number for '\(arg)'.")
                }
                explicitPort = p
                index += 2
            case "-l", "--user":
                guard index + 1 < args.count else {
                    throw CLIError.invalidUsage("'\(arg)' requires a username.")
                }
                explicitUser = args[index + 1]
                index += 2
            default:
                if arg.hasPrefix("-") {
                    throw CLIError.invalidUsage("Unknown option '\(arg)' for 'ssh'.")
                }
                if targetSpec == nil {
                    targetSpec = arg
                    index += 1
                } else {
                    throw CLIError.invalidUsage("Unexpected argument '\(arg)' for 'ssh'.")
                }
            }
        }

        guard let spec = targetSpec, !spec.isEmpty else {
            throw CLIError.invalidUsage("Usage: macssh ssh <[user@]host[:port]>")
        }

        let parsed = try parseSSHTarget(spec)
        let finalUser = explicitUser ?? parsed.user
        let finalPort = explicitPort ?? parsed.port

        var components = URLComponents()
        components.scheme = "macssh"
        components.host = "connect"
        var queryItems = [URLQueryItem(name: "host", value: parsed.host)]
        if let finalUser, !finalUser.isEmpty {
            queryItems.append(URLQueryItem(name: "user", value: finalUser))
        }
        if let finalPort {
            queryItems.append(URLQueryItem(name: "port", value: String(finalPort)))
        }
        components.queryItems = queryItems

        guard let url = components.url else {
            throw CLIError.executionFailed("Failed to construct macssh:// URL.")
        }

        let openProcess = Process()
        openProcess.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        openProcess.arguments = [url.absoluteString]
        try openProcess.run()
        openProcess.waitUntilExit()

        if openProcess.terminationStatus != 0 {
            if !NSWorkspace.shared.open(url) {
                throw CLIError.executionFailed("Failed to open \(url.absoluteString) in MacSSH.app.")
            }
        }
        print("Opening \(url.absoluteString) in MacSSH...")
    }

    private static func runBridge(args: [String]) throws -> Never {
        var sessionKey: String?
        var title: String?
        var cwd: String?
        var shell: String?
        var command: [String]?
        var attributes: [String: String] = [:]

        var index = 0
        while index < args.count {
            let arg = args[index]
            if arg == "--" {
                let slice = Array(args[(index + 1)...])
                if !slice.isEmpty {
                    command = slice
                }
                break
            }
            switch arg {
            case "--session", "--key", "-k":
                guard index + 1 < args.count else {
                    throw CLIError.invalidUsage("'\(arg)' requires a session key.")
                }
                sessionKey = args[index + 1]
                index += 2
            case "--name", "--title", "-n":
                guard index + 1 < args.count else {
                    throw CLIError.invalidUsage("'\(arg)' requires a title.")
                }
                title = args[index + 1]
                index += 2
            case "--cwd", "-c":
                guard index + 1 < args.count else {
                    throw CLIError.invalidUsage("'\(arg)' requires a working directory.")
                }
                cwd = args[index + 1]
                index += 2
            case "--shell", "-s":
                guard index + 1 < args.count else {
                    throw CLIError.invalidUsage("'\(arg)' requires a shell path.")
                }
                shell = args[index + 1]
                index += 2
            case "--attr":
                guard index + 1 < args.count else {
                    throw CLIError.invalidUsage("'--attr' requires a key=value pair.")
                }
                let pair = args[index + 1]
                if let eqIndex = pair.firstIndex(of: "=") {
                    let k = String(pair[..<eqIndex])
                    let v = String(pair[pair.index(after: eqIndex)...])
                    attributes[k] = v
                }
                index += 2
            case "--help", "-h":
                printUsage()
                Darwin.exit(0)
            default:
                throw CLIError.invalidUsage("Unknown option '\(arg)' for 'bridge'.")
            }
        }

        let resolvedKey = sessionKey ?? UUID().uuidString
        try BridgeRunner.run(
            sessionKey: resolvedKey,
            title: title,
            cwd: cwd,
            shell: shell,
            command: command,
            attributes: attributes.isEmpty ? nil : attributes
        )
    }

    // MARK: - Formatting & Parsing Helpers

    private static func parseSSHTarget(_ spec: String) throws -> (user: String?, host: String, port: UInt16?) {
        var user: String?
        var hostAndPort = spec

        if let atIndex = spec.lastIndex(of: "@") {
            let u = String(spec[..<atIndex])
            guard !u.isEmpty else {
                throw CLIError.invalidUsage("Invalid SSH target '\(spec)': empty username before '@'.")
            }
            user = u
            hostAndPort = String(spec[spec.index(after: atIndex)...])
        }

        var host = hostAndPort
        var port: UInt16?

        if hostAndPort.hasPrefix("[") {
            guard let closeBracket = hostAndPort.firstIndex(of: "]") else {
                throw CLIError.invalidUsage("Invalid IPv6 host in '\(spec)'.")
            }
            host = String(hostAndPort[hostAndPort.index(after: hostAndPort.startIndex)..<closeBracket])
            let remainder = hostAndPort[hostAndPort.index(after: closeBracket)...]
            if remainder.hasPrefix(":") {
                let portStr = String(remainder.dropFirst())
                guard let parsedPort = UInt16(portStr), parsedPort > 0 else {
                    throw CLIError.invalidUsage("Invalid port '\(portStr)' in '\(spec)'.")
                }
                port = parsedPort
            } else if !remainder.isEmpty {
                throw CLIError.invalidUsage("Invalid characters after IPv6 address in '\(spec)'.")
            }
        } else if let colonIndex = hostAndPort.lastIndex(of: ":"),
                  hostAndPort.firstIndex(of: ":") == colonIndex {
            host = String(hostAndPort[..<colonIndex])
            let portStr = String(hostAndPort[hostAndPort.index(after: colonIndex)...])
            guard let parsedPort = UInt16(portStr), parsedPort > 0 else {
                throw CLIError.invalidUsage("Invalid port '\(portStr)' in '\(spec)'.")
            }
            port = parsedPort
        }

        guard !host.isEmpty else {
            throw CLIError.invalidUsage("Invalid SSH target '\(spec)': missing host.")
        }

        return (user, host, port)
    }

    private static func abbreviateHome(_ path: String?) -> String {
        guard let path, !path.isEmpty else { return "-" }
        let home = NSHomeDirectory()
        if path == home {
            return "~"
        }
        if path.hasPrefix(home + "/") {
            return "~" + String(path.dropFirst(home.count))
        }
        return path
    }

    private static func printTable(headers: [String], rows: [[String]]) {
        var widths = headers.map(\.count)
        for row in rows {
            for (idx, cell) in row.enumerated() where idx < widths.count {
                widths[idx] = max(widths[idx], cell.count)
            }
        }

        func formatRow(_ cells: [String]) -> String {
            cells.enumerated().map { idx, cell in
                if idx == cells.count - 1 {
                    return cell
                }
                let padCount = max(0, widths[idx] - cell.count)
                return cell + String(repeating: " ", count: padCount + 2)
            }.joined()
        }

        print(formatRow(headers))
        for row in rows {
            print(formatRow(row))
        }
    }

    private static func writeStderr(_ message: String) {
        let bytes = Array(message.utf8)
        try? UnixSocketWire.writeAll(fd: STDERR_FILENO, bytes: bytes)
    }

    private static func printUsage() {
        let usage = """
        macssh — MacSSH Persistent Session & Terminal Automation CLI

        USAGE:
          macssh <command> [options]

        COMMANDS:
          list, ls                                    List active persistent terminal sessions
          capture <target> [--full] [--last]          Capture visible screen, scrollback, or last command output
          send <target> (text <str> | key <name>)...  Send literal text and/or special keys to a session
          send <target> "<string>" [--enter]          Send literal text (optionally followed by Enter)
          new [--name <title>] [--cwd <dir>] [-- <cmd...>]
                                                      Create a new background persistent session
          kill <target>                               Terminate a persistent session
          detach <target>                             Detach any attached client from a session
          status                                      Show macsshd daemon status and active session count
          ssh <[user@]host[:port]>                    Open or focus an SSH connection in MacSSH.app
          bridge --session <key> [--name <title>] [--cwd <dir>] [--shell <shell>]
                                                      Run the transparent PTY bridge (used by GhosttySurfaceView)
          help                                        Show this help message

        TARGETS:
          <target> can be a session's numeric ID, session key, or title.

        SUPPORTED KEYS FOR 'send':
          \(KeyNames.vocabulary)
        """
        print(usage)
    }
}

MacSSHCLI.main()
