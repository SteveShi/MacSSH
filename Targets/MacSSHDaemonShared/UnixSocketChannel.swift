import Darwin
import Foundation

public enum DaemonWireError: Error, LocalizedError, Sendable {
    case socketCreationFailed(Int32)
    case connectionFailed(String)
    case unauthorizedPeer
    case frameTooLarge(Int)
    case invalidFrame
    case unexpectedEOF
    case ioError(Int32)
    case daemonError(code: String, message: String)

    public var errorDescription: String? {
        switch self {
        case .socketCreationFailed(let code):
            return "Socket creation failed: \(String(cString: strerror(code)))"
        case .connectionFailed(let reason):
            return "Failed to connect to macsshd: \(reason)"
        case .unauthorizedPeer:
            return "Unauthorized peer credentials on Unix domain socket."
        case .frameTooLarge(let size):
            return "IPC frame size (\(size) bytes) exceeds limit."
        case .invalidFrame:
            return "Malformed IPC frame received."
        case .unexpectedEOF:
            return "Connection closed by peer."
        case .ioError(let code):
            return "Socket I/O error: \(String(cString: strerror(code)))"
        case .daemonError(_, let message):
            return message
        }
    }
}

public enum UnixSocketWire {
    /// Writes a framed packet (`[4-byte BE payload+1 length][1-byte kind][payload]`) to a blocking or non-blocking descriptor.
    public static func writeFrame(fd: Int32, kind: DaemonFrameKind, payload: Data = Data()) throws {
        let totalLength = payload.count + 1
        guard totalLength <= DaemonProtocol.maxFrameByteCount else {
            throw DaemonWireError.frameTooLarge(totalLength)
        }
        var header = [UInt8](repeating: 0, count: 5)
        let len32 = UInt32(totalLength).bigEndian
        withUnsafeBytes(of: len32) { bytes in
            header[0] = bytes[0]
            header[1] = bytes[1]
            header[2] = bytes[2]
            header[3] = bytes[3]
        }
        header[4] = kind.rawValue
        try writeAll(fd: fd, bytes: header)
        if !payload.isEmpty {
            try payload.withUnsafeBytes { rawBuffer in
                guard let base = rawBuffer.baseAddress else { return }
                try writeAllRaw(fd: fd, base: base, count: rawBuffer.count)
            }
        }
    }

    /// Reads a single framed packet from `fd`.
    public static func readFrame(fd: Int32) throws -> (kind: DaemonFrameKind, payload: Data) {
        let header = try readExact(fd: fd, count: 5)
        let length: UInt32 = header.withUnsafeBytes { raw in
            raw.loadUnaligned(fromByteOffset: 0, as: UInt32.self).bigEndian
        }
        let totalLength = Int(length)
        guard totalLength >= 1, totalLength <= DaemonProtocol.maxFrameByteCount else {
            throw DaemonWireError.frameTooLarge(totalLength)
        }
        guard let kind = DaemonFrameKind(rawValue: header[4]) else {
            throw DaemonWireError.invalidFrame
        }
        let payloadLength = totalLength - 1
        let payload = payloadLength > 0 ? try readExact(fd: fd, count: payloadLength) : Data()
        return (kind, payload)
    }

    public static func writeControlRequest(fd: Int32, _ request: DaemonControlRequest) throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(request)
        try writeFrame(fd: fd, kind: .controlRequest, payload: data)
    }

    public static func writeControlResponse(fd: Int32, _ response: DaemonControlResponse) throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(response)
        try writeFrame(fd: fd, kind: .controlResponse, payload: data)
    }

    public static func decodeControlRequest(_ data: Data) throws -> DaemonControlRequest {
        let decoder = JSONDecoder()
        return try decoder.decode(DaemonControlRequest.self, from: data)
    }

    public static func decodeControlResponse(_ data: Data) throws -> DaemonControlResponse {
        let decoder = JSONDecoder()
        return try decoder.decode(DaemonControlResponse.self, from: data)
    }

    public static func encodeResizePayload(columns: UInt16, rows: UInt16, widthPx: UInt16 = 0, heightPx: UInt16 = 0) -> Data {
        var bytes = [UInt8](repeating: 0, count: 8)
        let c = columns.bigEndian
        let r = rows.bigEndian
        let w = widthPx.bigEndian
        let h = heightPx.bigEndian
        withUnsafeBytes(of: c) { bytes[0] = $0[0]; bytes[1] = $0[1] }
        withUnsafeBytes(of: r) { bytes[2] = $0[0]; bytes[3] = $0[1] }
        withUnsafeBytes(of: w) { bytes[4] = $0[0]; bytes[5] = $0[1] }
        withUnsafeBytes(of: h) { bytes[6] = $0[0]; bytes[7] = $0[1] }
        return Data(bytes)
    }

    public static func decodeResizePayload(_ data: Data) -> (columns: UInt16, rows: UInt16, widthPx: UInt16, heightPx: UInt16)? {
        guard data.count >= 4 else { return nil }
        return data.withUnsafeBytes { raw in
            let cols = raw.loadUnaligned(fromByteOffset: 0, as: UInt16.self).bigEndian
            let rows = raw.loadUnaligned(fromByteOffset: 2, as: UInt16.self).bigEndian
            let widthPx = data.count >= 8 ? raw.loadUnaligned(fromByteOffset: 4, as: UInt16.self).bigEndian : 0
            let heightPx = data.count >= 8 ? raw.loadUnaligned(fromByteOffset: 6, as: UInt16.self).bigEndian : 0
            return (cols, rows, widthPx, heightPx)
        }
    }

    public static func encodeExitPayload(exitCode: Int32) -> Data {
        var codeBE = exitCode.bigEndian
        return Data(bytes: &codeBE, count: 4)
    }

    public static func decodeExitPayload(_ data: Data) -> Int32 {
        guard data.count >= 4 else { return 0 }
        return data.withUnsafeBytes { raw in
            raw.loadUnaligned(fromByteOffset: 0, as: Int32.self).bigEndian
        }
    }

    // MARK: - Low-level POSIX Socket Helpers

    public static func writeAll(fd: Int32, bytes: [UInt8]) throws {
        try bytes.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            try writeAllRaw(fd: fd, base: base, count: raw.count)
        }
    }

    public static func writeAllRaw(fd: Int32, base: UnsafeRawPointer, count: Int) throws {
        var offset = 0
        while offset < count {
            let n = Darwin.write(fd, base.advanced(by: offset), count - offset)
            if n > 0 {
                offset += n
                continue
            }
            if n < 0 {
                if errno == EINTR { continue }
                if errno == EAGAIN || errno == EWOULDBLOCK {
                    var pfd = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
                    _ = Darwin.poll(&pfd, 1, 100)
                    continue
                }
                throw DaemonWireError.ioError(errno)
            }
            throw DaemonWireError.unexpectedEOF
        }
    }

    public static func readExact(fd: Int32, count: Int) throws -> Data {
        var data = Data(count: count)
        try data.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress else { return }
            var offset = 0
            while offset < count {
                let n = Darwin.read(fd, base.advanced(by: offset), count - offset)
                if n > 0 {
                    offset += n
                    continue
                }
                if n == 0 {
                    throw DaemonWireError.unexpectedEOF
                }
                if errno == EINTR { continue }
                if errno == EAGAIN || errno == EWOULDBLOCK {
                    var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
                    _ = Darwin.poll(&pfd, 1, 100)
                    continue
                }
                throw DaemonWireError.ioError(errno)
            }
        }
        return data
    }

    /// Verifies that the peer on a connected `AF_UNIX` socket has the same effective UID as the current process.
    public static func verifyPeerSameUser(fd: Int32) -> Bool {
        var euid: uid_t = 0
        var egid: gid_t = 0
        guard getpeereid(fd, &euid, &egid) == 0 else {
            return false
        }
        return euid == geteuid()
    }

    /// Connects to `DaemonPaths.socketPath`. If `autostart` is true and the daemon is not running,
    /// spawns `macsshd` in a new session (`POSIX_SPAWN_SETSID`) and retries connection.
    public static func connectToDaemon(autostart: Bool = true) throws -> Int32 {
        if let fd = tryConnectOnce() {
            return fd
        }
        guard autostart else {
            throw DaemonWireError.connectionFailed("macsshd is not running")
        }
        try spawnDaemonProcess()
        // Wait up to 3 seconds (30 x 100ms) for the daemon socket to come online
        for _ in 0..<30 {
            usleep(100_000)
            if let fd = tryConnectOnce() {
                return fd
            }
        }
        throw DaemonWireError.connectionFailed("Timed out waiting for macsshd to start")
    }

    public static func sendOneShotRequest(_ request: DaemonControlRequest, autostart: Bool = true) throws -> DaemonControlResponse {
        let fd = try connectToDaemon(autostart: autostart)
        defer { Darwin.close(fd) }
        try writeControlRequest(fd: fd, request)
        let (kind, payload) = try readFrame(fd: fd)
        guard kind == .controlResponse else {
            throw DaemonWireError.invalidFrame
        }
        let response = try decodeControlResponse(payload)
        if case .error(let code, let message) = response {
            throw DaemonWireError.daemonError(code: code, message: message)
        }
        return response
    }

    private static func tryConnectOnce() -> Int32? {
        let path = DaemonPaths.socketPath
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        var noSigPipe: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
        _ = fcntl(fd, F_SETFD, FD_CLOEXEC)

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(path.utf8CString)
        let maxLen = MemoryLayout.size(ofValue: addr.sun_path)
        guard pathBytes.count <= maxLen else {
            Darwin.close(fd)
            return nil
        }
        withUnsafeMutablePointer(to: &addr.sun_path) { sunPathPtr in
            let rawPtr = UnsafeMutableRawPointer(sunPathPtr).assumingMemoryBound(to: CChar.self)
            for (i, byte) in pathBytes.enumerated() {
                rawPtr[i] = byte
            }
        }
        let sockLen = socklen_t(MemoryLayout<sockaddr_un>.size)
        let connectResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.connect(fd, sockPtr, sockLen)
            }
        }
        guard connectResult == 0 else {
            Darwin.close(fd)
            return nil
        }
        guard verifyPeerSameUser(fd: fd) else {
            Darwin.close(fd)
            return nil
        }
        return fd
    }

    private static func spawnDaemonProcess() throws {
        guard let daemonPath = DaemonPaths.resolveExecutable(named: "macsshd") else {
            throw DaemonWireError.connectionFailed("Could not locate macsshd executable")
        }
        try DaemonPaths.ensureRunDirectory()

        var attr: posix_spawnattr_t? = nil
        posix_spawnattr_init(&attr)
        defer { posix_spawnattr_destroy(&attr) }
        posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETSID | POSIX_SPAWN_CLOEXEC_DEFAULT))

        var fileActions: posix_spawn_file_actions_t? = nil
        posix_spawn_file_actions_init(&fileActions)
        defer { posix_spawn_file_actions_destroy(&fileActions) }
        posix_spawn_file_actions_addopen(&fileActions, STDIN_FILENO, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_addopen(&fileActions, STDOUT_FILENO, DaemonPaths.logPath, O_WRONLY | O_CREAT | O_APPEND, 0o600)
        posix_spawn_file_actions_addopen(&fileActions, STDERR_FILENO, DaemonPaths.logPath, O_WRONLY | O_CREAT | O_APPEND, 0o600)

        let cPath = strdup(daemonPath)
        defer { free(cPath) }
        var argv: [UnsafeMutablePointer<CChar>?] = [cPath, nil]

        let envDict = ProcessInfo.processInfo.environment
        let envStrings = envDict.map { "\($0.key)=\($0.value)" }
        var envp: [UnsafeMutablePointer<CChar>?] = envStrings.map { strdup($0) }
        envp.append(nil)
        defer {
            for ptr in envp where ptr != nil {
                free(ptr)
            }
        }

        var pid: pid_t = 0
        let rc = posix_spawn(&pid, daemonPath, &fileActions, &attr, &argv, &envp)
        guard rc == 0 else {
            throw DaemonWireError.connectionFailed("posix_spawn failed with code \(rc)")
        }
    }
}
