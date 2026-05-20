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

    func withRawSession<T: Sendable>(_ body: @Sendable (OpaquePointer) throws -> T) throws -> T {
        guard let session else { throw SSHError.notConnected }
        libssh2_session_set_blocking(session, 1)
        defer { libssh2_session_set_blocking(session, 0) }
        return try body(session)
    }

    func connect(connection: SSHConnection, auth: SSHAuth, cols: Int = 80, rows: Int = 24) async throws -> AsyncStream<Data> {
        state = .connecting

        let fd = try openSocket(host: connection.host, port: connection.port)
        socketFD = fd

        guard libssh2_init(0) == 0 else {
            throw SSHError.initializationFailed
        }

        guard let session = libssh2_session_init_ex(nil, nil, nil, nil) else {
            throw SSHError.sessionInitFailed
        }
        self.session = session

        libssh2_session_set_blocking(session, 1)

        let handshake = libssh2_session_handshake(session, fd)
        guard handshake == 0 else {
            throw SSHError.handshakeFailed(handshake)
        }

        pendingUsername = connection.username

        switch try KnownHostsStore.check(session: session, host: connection.host, port: connection.port) {
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
                try? await Task.sleep(nanoseconds: 10_000_000)
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

        libssh2_exit()
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
                libssh2_channel_close(channel)
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
            var buffer = [UInt8](repeating: 0, count: 4096)
            while true {
                let bytesRead = buffer.withUnsafeMutableBytes { rawBuffer in
                    libssh2_channel_read_ex(channel, 0, rawBuffer.bindMemory(to: Int8.self).baseAddress, rawBuffer.count)
                }
                if bytesRead > 0 {
                    resultData.append(buffer, count: bytesRead)
                } else if bytesRead == 0 {
                    break
                } else {
                    // Under blocking mode (which withRawSession enforces), the call blocks
                    // and EAGAIN won't be returned, so checking < 0 and breaking is correct and safe.
                    break
                }
            }
            
            libssh2_channel_send_eof(channel)
            
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
        while true {
            guard let channel else { break }
            let rc = buffer.withUnsafeMutableBytes { rawBuffer in
                libssh2_channel_read_ex(channel, 0, rawBuffer.bindMemory(to: Int8.self).baseAddress, rawBuffer.count)
            }
            if rc > 0 {
                let data = Data(buffer[0..<rc])
                continuation.yield(data)
                continue
            }
            if rc == 0 {
                break
            }
            if rc == Int(LIBSSH2_ERROR_EAGAIN) {
                try? await Task.sleep(nanoseconds: 10_000_000)
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

        var current: UnsafeMutablePointer<addrinfo>? = result
        while let addrInfo = current?.pointee {
            let fd = socket(addrInfo.ai_family, addrInfo.ai_socktype, addrInfo.ai_protocol)
            if fd >= 0 {
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
