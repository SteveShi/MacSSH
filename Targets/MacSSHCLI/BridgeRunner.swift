import Darwin
import Dispatch
import Foundation

#if canImport(MacSSHDaemonShared)
import MacSSHDaemonShared
#endif

/// Thread-safe holder for the original terminal attributes on `STDIN_FILENO` so they can be
/// reliably restored both on normal exit and from a C `atexit` handler under Swift 6 concurrency.
private final class TermiosGuard: @unchecked Sendable {
    static let shared = TermiosGuard()

    private let lock = NSLock()
    private var originalTermios: termios?
    private var rawModeActive = false

    func enterRawMode(fd: Int32 = STDIN_FILENO) {
        lock.lock()
        defer { lock.unlock() }

        var orig = termios()
        guard tcgetattr(fd, &orig) == 0 else { return }
        if originalTermios == nil {
            originalTermios = orig
        }
        var raw = orig
        cfmakeraw(&raw)
        if tcsetattr(fd, TCSANOW, &raw) == 0 {
            rawModeActive = true
        }
    }

    func restore(fd: Int32 = STDIN_FILENO) {
        lock.lock()
        defer { lock.unlock() }

        guard rawModeActive, var orig = originalTermios else { return }
        _ = tcsetattr(fd, TCSANOW, &orig)
        rawModeActive = false
    }
}

/// Synchronizes frame writes to the daemon Unix domain socket across the main I/O loop and the `SIGWINCH` handler.
private final class SocketFrameWriter: @unchecked Sendable {
    private let lock = NSLock()
    private let fd: Int32

    init(fd: Int32) {
        self.fd = fd
    }

    func writeFrame(kind: DaemonFrameKind, payload: Data = Data()) throws {
        lock.lock()
        defer { lock.unlock() }
        try UnixSocketWire.writeFrame(fd: fd, kind: kind, payload: payload)
    }
}

public enum BridgeRunner {
    public static func run(
        sessionKey: String,
        title: String?,
        cwd: String?,
        shell: String?,
        command: [String]? = nil,
        attributes: [String: String]? = nil
    ) throws -> Never {
        signal(SIGPIPE, SIG_IGN)
        signal(SIGHUP, SIG_IGN)

        let initialSize = queryTerminalSize()

        atexit {
            TermiosGuard.shared.restore(fd: STDIN_FILENO)
        }
        TermiosGuard.shared.enterRawMode(fd: STDIN_FILENO)
        defer {
            TermiosGuard.shared.restore(fd: STDIN_FILENO)
        }

        let socketFD = try UnixSocketWire.connectToDaemon(autostart: true)
        let env = ProcessInfo.processInfo.environment

        try UnixSocketWire.writeControlRequest(
            fd: socketFD,
            .openOrAttach(
                sessionKey: sessionKey,
                title: title,
                command: command,
                shell: shell,
                workingDirectory: cwd,
                environment: env,
                columns: initialSize.cols,
                rows: initialSize.rows,
                attributes: attributes,
                attachStream: true
            )
        )

        let (respKind, respPayload) = try UnixSocketWire.readFrame(fd: socketFD)
        guard respKind == .controlResponse else {
            Darwin.close(socketFD)
            throw DaemonWireError.invalidFrame
        }

        let response = try UnixSocketWire.decodeControlResponse(respPayload)
        switch response {
        case .openedOrAttached(_, let replayData):
            if !replayData.isEmpty {
                try replayData.withUnsafeBytes { rawBuffer in
                    guard let base = rawBuffer.baseAddress else { return }
                    try UnixSocketWire.writeAllRaw(fd: STDOUT_FILENO, base: base, count: rawBuffer.count)
                }
            }
        case .error(let code, let message):
            Darwin.close(socketFD)
            throw DaemonWireError.daemonError(code: code, message: message)
        default:
            Darwin.close(socketFD)
            throw DaemonWireError.invalidFrame
        }

        let writer = SocketFrameWriter(fd: socketFD)

        // Send current terminal dimensions and trigger a SIGWINCH redraw for the attached process group.
        let currentSize = queryTerminalSize()
        let initialResizePayload = UnixSocketWire.encodeResizePayload(
            columns: currentSize.cols,
            rows: currentSize.rows,
            widthPx: currentSize.widthPx,
            heightPx: currentSize.heightPx
        )
        try writer.writeFrame(kind: .streamResize, payload: initialResizePayload)
        try writer.writeFrame(kind: .streamRedraw)

        // Forward terminal window size changes via SIGWINCH.
        signal(SIGWINCH, SIG_IGN)
        let bridgeQueue = DispatchQueue(label: "com.steveshi.macssh.bridge.sigwinch")
        let sigwinchSource = DispatchSource.makeSignalSource(signal: SIGWINCH, queue: bridgeQueue)
        sigwinchSource.setEventHandler {
            let size = Self.queryTerminalSize()
            let payload = UnixSocketWire.encodeResizePayload(
                columns: size.cols,
                rows: size.rows,
                widthPx: size.widthPx,
                heightPx: size.heightPx
            )
            try? writer.writeFrame(kind: .streamResize, payload: payload)
        }
        sigwinchSource.resume()

        var inputBuffer = [UInt8](repeating: 0, count: 16 * 1024)
        var pollFDs = [
            pollfd(fd: STDIN_FILENO, events: Int16(POLLIN), revents: 0),
            pollfd(fd: socketFD, events: Int16(POLLIN), revents: 0)
        ]

        var exitCode: Int32 = 0

        while true {
            pollFDs[0].revents = 0
            pollFDs[1].revents = 0

            let ready = Darwin.poll(&pollFDs, 2, -1)
            if ready < 0 {
                if errno == EINTR || errno == EAGAIN {
                    continue
                }
                break
            }

            // 1. Process incoming frames from macsshd
            if (pollFDs[1].revents & Int16(POLLIN)) != 0 {
                do {
                    let (kind, payload) = try UnixSocketWire.readFrame(fd: socketFD)
                    switch kind {
                    case .streamOutput:
                        if !payload.isEmpty {
                            try payload.withUnsafeBytes { rawBuffer in
                                guard let base = rawBuffer.baseAddress else { return }
                                try UnixSocketWire.writeAllRaw(fd: STDOUT_FILENO, base: base, count: rawBuffer.count)
                            }
                        }
                    case .streamSessionExit:
                        exitCode = UnixSocketWire.decodeExitPayload(payload)
                        sigwinchSource.cancel()
                        TermiosGuard.shared.restore(fd: STDIN_FILENO)
                        Darwin.close(socketFD)
                        Darwin.exit(exitCode)
                    case .controlResponse:
                        if case .error(_, let message) = try? UnixSocketWire.decodeControlResponse(payload) {
                            let errBytes = Array("macssh-cli bridge error: \(message)\r\n".utf8)
                            try? UnixSocketWire.writeAll(fd: STDERR_FILENO, bytes: errBytes)
                            break
                        }
                    default:
                        break
                    }
                } catch {
                    break
                }
            } else if (pollFDs[1].revents & Int16(POLLHUP | POLLERR | POLLNVAL)) != 0 {
                break
            }

            // 2. Process incoming bytes from STDIN (GhosttySurfaceView PTY slave)
            if (pollFDs[0].revents & Int16(POLLIN)) != 0 {
                let bytesRead = Darwin.read(STDIN_FILENO, &inputBuffer, inputBuffer.count)
                if bytesRead > 0 {
                    let chunk = Data(bytes: inputBuffer, count: bytesRead)
                    do {
                        try writer.writeFrame(kind: .streamInput, payload: chunk)
                    } catch {
                        break
                    }
                } else if bytesRead == 0 {
                    // STDIN reached EOF (GhosttySurfaceView closed): close socket and exit 0 without killing remote session.
                    break
                } else {
                    if errno == EINTR || errno == EAGAIN {
                        continue
                    }
                    // EIO on PTY slave means the master side closed: detach cleanly and exit 0.
                    break
                }
            } else if (pollFDs[0].revents & Int16(POLLHUP | POLLERR | POLLNVAL)) != 0 {
                // PTY master hung up: detach cleanly without killing remote session.
                break
            }
        }

        sigwinchSource.cancel()
        TermiosGuard.shared.restore(fd: STDIN_FILENO)
        Darwin.close(socketFD)
        Darwin.exit(exitCode)
    }

    private static func queryTerminalSize() -> (cols: UInt16, rows: UInt16, widthPx: UInt16, heightPx: UInt16) {
        var ws = winsize()
        if ioctl(STDIN_FILENO, TIOCGWINSZ, &ws) == 0, ws.ws_col > 0, ws.ws_row > 0 {
            return (ws.ws_col, ws.ws_row, ws.ws_xpixel, ws.ws_ypixel)
        }
        if ioctl(STDOUT_FILENO, TIOCGWINSZ, &ws) == 0, ws.ws_col > 0, ws.ws_row > 0 {
            return (ws.ws_col, ws.ws_row, ws.ws_xpixel, ws.ws_ypixel)
        }
        return (DaemonProtocol.defaultColumns, DaemonProtocol.defaultRows, 0, 0)
    }
}
