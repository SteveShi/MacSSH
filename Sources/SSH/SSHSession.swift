import Foundation
import Darwin
import libssh2

enum HostKeyStatus {
    case notFound
    case mismatch
}

actor SSHSession {
    enum State: Equatable {
        case disconnected
        case connecting
        case connected
        case failed(String)
    }

    private(set) var state: State = .disconnected

    private var session: OpaquePointer?
    private var channel: OpaquePointer?
    private var socketFD: Int32 = -1
    private var outputContinuation: AsyncStream<Data>.Continuation?

    private var pendingHostKey: Data?
    private var pendingHostKeyType: Int32?
    private var pendingHost: String?
    private var pendingPort: Int?
    private var pendingHostStatus: HostKeyStatus?
    private var pendingUsername: String?

    /// libssh2_init / libssh2_exit reference counting (process-wide).
    /// libssh2 documents that init/exit must be balanced, and calling init
    /// concurrently across multiple sessions can race. The mutable count is
    /// guarded by `initLock` — `nonisolated(unsafe)` is required because
    /// actor-isolated `static` storage is otherwise unreachable from the lock-
    /// guarded helpers below under Swift 6 strict concurrency.
    nonisolated(unsafe) private static let initLock = NSLock()
    nonisolated(unsafe) private static var initRefCount: Int = 0

    private nonisolated static func libsshInit() throws {
        initLock.lock()
        defer { initLock.unlock() }
        if initRefCount == 0 {
            guard libssh2_init(0) == 0 else { throw SSHError.initializationFailed }
        }
        initRefCount += 1
    }

    private nonisolated static func libsshExit() {
        initLock.lock()
        defer { initLock.unlock() }
        guard initRefCount > 0 else { return }
        initRefCount -= 1
        if initRefCount == 0 {
            libssh2_exit()
        }
    }

    func withRawSession<T: Sendable>(_ body: @Sendable (OpaquePointer) throws -> T) throws -> T {
        guard let session else { throw SSHError.notConnected }
        libssh2_session_set_blocking(session, 1)
        defer { libssh2_session_set_blocking(session, 0) }
        return try body(session)
    }

    func connect(connection: SSHConnection, auth: SSHAuth, cols: Int = 80, rows: Int = 24) async throws -> AsyncStream<Data> {
        // Reentry guard: if a previous attempt left state inconsistent, clean up first.
        if session != nil || socketFD != -1 {
            await disconnect()
        }
        state = .connecting

        var didInit = false
        var localFD: Int32 = -1
        var localSession: OpaquePointer? = nil

        // Cleanup helper for the failure path — frees only what we acquired locally,
        // leaves no half-initialized resources behind in `self`.
        func rollback() {
            if let s = localSession { libssh2_session_free(s) }
            if localFD != -1 { close(localFD) }
            if didInit { SSHSession.libsshExit() }
            self.session = nil
            self.socketFD = -1
            state = .disconnected
        }

        do {
            localFD = try openSocket(host: connection.host, port: connection.port)

            try SSHSession.libsshInit()
            didInit = true

            guard let s = libssh2_session_init_ex(nil, nil, nil, nil) else {
                throw SSHError.sessionInitFailed
            }
            localSession = s
            libssh2_session_set_blocking(s, 1)

            let handshake = libssh2_session_handshake(s, localFD)
            guard handshake == 0 else { throw SSHError.handshakeFailed(handshake) }

            // Commit to `self` only once handshake succeeded.
            self.socketFD = localFD
            self.session = s
            pendingUsername = connection.username

            switch try KnownHostsStore.check(session: s, host: connection.host, port: connection.port) {
            case .match:
                break
            case .notFound(let keyData, let keyType):
                pendingHostKey = keyData
                pendingHostKeyType = keyType
                pendingHost = connection.host
                pendingPort = connection.port
                pendingHostStatus = .notFound
                throw SSHError.hostKeyNotTrusted(.notFound)
            case .mismatch(let keyData, let keyType):
                pendingHostKey = keyData
                pendingHostKeyType = keyType
                pendingHost = connection.host
                pendingPort = connection.port
                pendingHostStatus = .mismatch
                throw SSHError.hostKeyNotTrusted(.mismatch)
            }

            return try await authenticateAndOpenChannel(auth: auth, cols: cols, rows: rows)
        } catch SSHError.hostKeyNotTrusted(let status) {
            // Keep socket+session alive so the user can accept the key and continue.
            // The pending* fields are already populated above.
            throw SSHError.hostKeyNotTrusted(status)
        } catch {
            rollback()
            throw error
        }
    }

    func acceptHostKeyAndConnect(auth: SSHAuth, cols: Int = 80, rows: Int = 24) async throws -> AsyncStream<Data> {
        guard let session,
              let host = pendingHost,
              let port = pendingPort,
              let keyData = pendingHostKey,
              let keyType = pendingHostKeyType,
              let status = pendingHostStatus
        else {
            throw SSHError.hostKeyUnavailable
        }
        let replace = status == .mismatch
        try KnownHostsStore.addOrReplace(session: session, host: host, port: port, keyData: keyData, keyType: keyType, replace: replace)
        pendingHostKey = nil
        pendingHostKeyType = nil
        pendingHost = nil
        pendingPort = nil
        pendingHostStatus = nil

        return try await authenticateAndOpenChannel(auth: auth, cols: cols, rows: rows)
    }

    func send(_ data: Data) async throws {
        guard let channel else { throw SSHError.notConnected }
        var totalSent = 0
        while totalSent < data.count {
            let sent = data.withUnsafeBytes { buffer -> Int in
                guard let base = buffer.bindMemory(to: Int8.self).baseAddress else { return 0 }
                return libssh2_channel_write_ex(channel, 0, base.advanced(by: totalSent), buffer.count - totalSent)
            }
            if sent == Int(LIBSSH2_ERROR_EAGAIN) {
                // Yield to the actor so other consumers (read loop, monitoring) can progress
                // without busy-spinning on the lock.
                try await Task.sleep(nanoseconds: 5_000_000)
                continue
            }
            if sent < 0 {
                throw SSHError.writeFailed(sent)
            }
            totalSent += sent
        }
    }

    func resize(cols: Int, rows: Int) async {
        guard let channel else { return }
        _ = libssh2_channel_request_pty_size_ex(channel, Int32(cols), Int32(rows), 0, 0)
    }

    func disconnect() async {
        outputContinuation?.finish()
        outputContinuation = nil

        if let channel {
            libssh2_channel_send_eof(channel)
            libssh2_channel_close(channel)
            libssh2_channel_free(channel)
        }
        self.channel = nil

        if let session {
            libssh2_session_disconnect_ex(session, SSH_DISCONNECT_BY_APPLICATION, "Client disconnect", "")
            libssh2_session_free(session)
        }
        self.session = nil

        if socketFD != -1 {
            close(socketFD)
            socketFD = -1
        }

        pendingHostKey = nil
        pendingHostKeyType = nil
        pendingHost = nil
        pendingPort = nil
        pendingHostStatus = nil
        pendingUsername = nil

        SSHSession.libsshExit()
        state = .disconnected
    }

    func executeCommand(_ command: String) async throws -> String {
        try withRawSession { sessionPtr in
            guard let channel = libssh2_channel_open_ex(
                sessionPtr,
                "session",
                UInt32("session".utf8.count),
                2 * 1024 * 1024,
                32_768,
                nil,
                0
            ) else {
                throw SSHError.channelOpenFailed
            }
            defer {
                libssh2_channel_free(channel)
            }

            let rc = libssh2_channel_process_startup(
                channel,
                "exec",
                UInt32("exec".utf8.count),
                command,
                UInt32(command.utf8.count)
            )
            guard rc == 0 else {
                throw SSHError.shellFailed(rc)
            }

            var resultData = Data()
            var buffer = [UInt8](repeating: 0, count: 8192)
            while true {
                let bytesRead = buffer.withUnsafeMutableBytes { rawBuffer in
                    libssh2_channel_read_ex(channel, 0, rawBuffer.bindMemory(to: Int8.self).baseAddress, rawBuffer.count)
                }
                if bytesRead > 0 {
                    resultData.append(buffer, count: bytesRead)
                } else if bytesRead == 0 {
                    break
                } else {
                    // In blocking mode EAGAIN should not occur; any negative
                    // return is a hard error — surface it instead of silently
                    // truncating the output.
                    if bytesRead != Int(LIBSSH2_ERROR_EAGAIN) {
                        // Clean shutdown order: EOF -> close -> free (via defer).
                        libssh2_channel_send_eof(channel)
                        libssh2_channel_close(channel)
                        throw SSHError.readFailed(Int32(bytesRead))
                    }
                    break
                }
            }

            libssh2_channel_send_eof(channel)
            libssh2_channel_close(channel)

            return String(decoding: resultData, as: UTF8.self)
        }
    }


    private func authenticateAndOpenChannel(auth: SSHAuth, cols: Int, rows: Int) async throws -> AsyncStream<Data> {
        guard let session else { throw SSHError.sessionInitFailed }
        guard let username = pendingUsername else { throw SSHError.sessionInitFailed }

        switch auth {
        case .password(let password, _):
            let userauth = libssh2_userauth_password_ex(session, username, UInt32(username.utf8.count), password, UInt32(password.utf8.count), nil)
            guard userauth == 0 else {
                throw SSHError.authFailed(userauth)
            }

        case .publicKey(let path, let passphrase):
            let pubPath = path + ".pub"
            let passphraseCString = passphrase?.utf8CString
            let passphrasePtr = passphraseCString?.withUnsafeBufferPointer { $0.baseAddress }
            let userauth = libssh2_userauth_publickey_fromfile_ex(
                session,
                username,
                UInt32(username.utf8.count),
                pubPath,
                path,
                passphrasePtr
            )
            guard userauth == 0 else {
                throw SSHError.authFailed(userauth)
            }
        }

        let windowSize: UInt32 = 2 * 1024 * 1024
        let packetSize: UInt32 = 32_768
        guard let channel = libssh2_channel_open_ex(
            session,
            "session",
            UInt32("session".utf8.count),
            windowSize,
            packetSize,
            nil,
            0
        ) else {
            throw SSHError.channelOpenFailed
        }
        self.channel = channel

        let ptyResult = libssh2_channel_request_pty_ex(channel, "xterm-256color", UInt32("xterm-256color".utf8.count), nil, 0, Int32(cols), Int32(rows), 0, 0)
        guard ptyResult == 0 else {
            throw SSHError.ptyFailed(ptyResult)
        }

        let shellResult = libssh2_channel_process_startup(
            channel,
            "shell",
            UInt32("shell".utf8.count),
            nil,
            0
        )
        guard shellResult == 0 else {
            throw SSHError.shellFailed(shellResult)
        }

        state = .connected
        libssh2_session_set_blocking(session, 0)
        return startReadingLoop()
    }

    private func startReadingLoop() -> AsyncStream<Data> {
        AsyncStream { continuation in
            Task { [weak self] in
                await self?.saveContinuation(continuation)
                await self?.readLoop(continuation: continuation)
            }
        }
    }

    private func saveContinuation(_ continuation: AsyncStream<Data>.Continuation) {
        outputContinuation = continuation
    }

    private func readLoop(continuation: AsyncStream<Data>.Continuation) async {
        var buffer = [UInt8](repeating: 0, count: 16 * 1024)
        // Adaptive backoff: idle period grows when nothing arrives,
        // shrinks immediately when data appears. Avoids a hot 10ms spin
        // while keeping latency low under load.
        var idleNanos: UInt64 = 2_000_000   // 2ms
        let maxIdle: UInt64 = 50_000_000    // 50ms
        while !Task.isCancelled {
            guard let channel else { break }
            let rc = buffer.withUnsafeMutableBytes { rawBuffer in
                libssh2_channel_read_ex(channel, 0, rawBuffer.bindMemory(to: Int8.self).baseAddress, rawBuffer.count)
            }
            if rc > 0 {
                let data = Data(buffer[0..<rc])
                continuation.yield(data)
                idleNanos = 2_000_000
                continue
            }
            if rc == 0 {
                // EOF only when channel really reports closed.
                if libssh2_channel_eof(channel) != 0 { break }
                // Otherwise treat as transient and back off.
                do { try await Task.sleep(nanoseconds: idleNanos) } catch { break }
                idleNanos = min(idleNanos * 2, maxIdle)
                continue
            }
            if rc == Int(LIBSSH2_ERROR_EAGAIN) {
                do { try await Task.sleep(nanoseconds: idleNanos) } catch { break }
                idleNanos = min(idleNanos * 2, maxIdle)
                continue
            }
            break
        }
        continuation.finish()
    }

    private func openSocket(host: String, port: Int) throws -> Int32 {
        var hints = addrinfo(
            ai_flags: AI_ADDRCONFIG,
            ai_family: AF_UNSPEC,
            ai_socktype: SOCK_STREAM,
            ai_protocol: IPPROTO_TCP,
            ai_addrlen: 0,
            ai_canonname: nil,
            ai_addr: nil,
            ai_next: nil
        )

        var result: UnsafeMutablePointer<addrinfo>?
        let portString = String(port)
        let status = getaddrinfo(host, portString, &hints, &result)
        guard status == 0, let result else {
            throw SSHError.resolutionFailed(String(cString: gai_strerror(status)))
        }
        defer { freeaddrinfo(result) }

        // 15s connect timeout per address. The default kernel timeout
        // (~75s) makes the UI feel hung when the host is unreachable.
        var timeout = timeval(tv_sec: 15, tv_usec: 0)

        var current: UnsafeMutablePointer<addrinfo>? = result
        while let addrInfo = current?.pointee {
            let fd = socket(addrInfo.ai_family, addrInfo.ai_socktype, addrInfo.ai_protocol)
            if fd >= 0 {
                // Apply a send/recv timeout so a stalled peer can't wedge the actor.
                setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
                setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
                // Disable Nagle to reduce input latency for an interactive shell.
                var one: Int32 = 1
                setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &one, socklen_t(MemoryLayout<Int32>.size))
                // Enable TCP keepalive so half-open connections get detected.
                setsockopt(fd, SOL_SOCKET, SO_KEEPALIVE, &one, socklen_t(MemoryLayout<Int32>.size))

                let connectResult = Darwin.connect(fd, addrInfo.ai_addr, addrInfo.ai_addrlen)
                if connectResult == 0 {
                    return fd
                }
                close(fd)
            }
            current = addrInfo.ai_next
        }

        throw SSHError.connectionFailed
    }
}

enum SSHError: LocalizedError {
    case initializationFailed
    case sessionInitFailed
    case handshakeFailed(Int32)
    case authFailed(Int32)
    case channelOpenFailed
    case ptyFailed(Int32)
    case shellFailed(Int32)
    case writeFailed(Int)
    case readFailed(Int32)
    case resolutionFailed(String)
    case connectionFailed
    case notConnected
    case knownHostsInitFailed
    case knownHostsMismatch
    case knownHostsCheckFailed(Int32)
    case knownHostsWriteFailed(Int32)
    case hostKeyUnavailable
    case hostKeyNotTrusted(HostKeyStatus)

    var errorDescription: String? {
        switch self {
        case .initializationFailed:
            return "libssh2 init failed"
        case .sessionInitFailed:
            return "libssh2 session init failed"
        case .handshakeFailed(let code):
            return "SSH handshake failed (\(code))"
        case .authFailed(let code):
            return "SSH auth failed (\(code))"
        case .channelOpenFailed:
            return "SSH channel open failed"
        case .ptyFailed(let code):
            return "SSH PTY request failed (\(code))"
        case .shellFailed(let code):
            return "SSH shell failed (\(code))"
        case .writeFailed(let code):
            return "SSH write failed (\(code))"
        case .readFailed(let code):
            return "SSH read failed (\(code))"
        case .resolutionFailed(let message):
            return "DNS resolution failed (\(message))"
        case .connectionFailed:
            return "Socket connection failed"
        case .notConnected:
            return "Not connected"
        case .knownHostsInitFailed:
            return "known_hosts init failed"
        case .knownHostsMismatch:
            return "Host key mismatch. Connection aborted."
        case .knownHostsCheckFailed(let code):
            return "known_hosts check failed (\(code))"
        case .knownHostsWriteFailed(let code):
            return "known_hosts write failed (\(code))"
        case .hostKeyUnavailable:
            return "Host key unavailable"
        case .hostKeyNotTrusted(let status):
            switch status {
            case .notFound:
                return "Host key not found. Confirmation required."
            case .mismatch:
                return "Host key mismatch. Confirmation required."
            }
        }
    }
}
