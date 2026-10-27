import Darwin
import Dispatch
import Foundation

#if canImport(MacSSHDaemonShared)
import MacSSHDaemonShared
#endif

/// Main server for `macsshd`. Manages the Unix domain socket listener, lock file,
/// incoming client connections, and routing of control requests and streaming bridge frames.
final class DaemonServer: @unchecked Sendable {
    let registry: SessionRegistry

    private var lockFD: Int32 = -1
    private var serverFD: Int32 = -1
    private var listenerSource: DispatchSourceRead?
    private var sigintSource: DispatchSourceSignal?
    private var sigtermSource: DispatchSourceSignal?
    private var clients: [UUID: ClientConnection] = [:]
    private var isStopping = false

    init() {
        self.registry = SessionRegistry()
        self.registry.shutdownHandler = { [weak self] in
            self?.stopAndExit()
        }
    }

    func start() throws {
        // 1. Ensure run directory exists with 0700 permissions
        try DaemonPaths.ensureRunDirectory()

        // 2. Acquire exclusive lock on macsshd.lock
        let lockPath = DaemonPaths.lockPath
        let lfd = Darwin.open(lockPath, O_RDWR | O_CREAT, 0o600)
        guard lfd >= 0 else {
            throw DaemonWireError.daemonError(
                code: "LOCK_FAILED",
                message: "Failed to open lock file at \(lockPath): \(String(cString: strerror(errno)))"
            )
        }
        guard flock(lfd, LOCK_EX | LOCK_NB) == 0 else {
            Darwin.close(lfd)
            throw DaemonWireError.daemonError(
                code: "ALREADY_RUNNING",
                message: "Another instance of macsshd is already running."
            )
        }
        self.lockFD = lfd

        // 3. Remove any stale socket file
        let socketPath = DaemonPaths.socketPath
        _ = Darwin.unlink(socketPath)

        // 4. Create, bind, and listen on AF_UNIX socket
        let sfd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard sfd >= 0 else {
            throw DaemonWireError.socketCreationFailed(errno)
        }

        var noSigPipe: Int32 = 1
        _ = setsockopt(sfd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
        _ = fcntl(sfd, F_SETFD, FD_CLOEXEC)
        _ = fcntl(sfd, F_SETFL, O_NONBLOCK)

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(socketPath.utf8CString)
        let maxLen = MemoryLayout.size(ofValue: addr.sun_path)
        guard pathBytes.count <= maxLen else {
            Darwin.close(sfd)
            throw DaemonWireError.daemonError(
                code: "PATH_TOO_LONG",
                message: "Socket path exceeds sun_path maximum length (\(maxLen))."
            )
        }

        withUnsafeMutablePointer(to: &addr.sun_path) { sunPathPtr in
            let rawPtr = UnsafeMutableRawPointer(sunPathPtr).assumingMemoryBound(to: CChar.self)
            for (i, byte) in pathBytes.enumerated() {
                rawPtr[i] = byte
            }
        }

        let sockLen = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.bind(sfd, sockPtr, sockLen)
            }
        }

        guard bindResult == 0 else {
            let err = errno
            Darwin.close(sfd)
            throw DaemonWireError.daemonError(
                code: "BIND_FAILED",
                message: "Failed to bind Unix socket at \(socketPath): \(String(cString: strerror(err)))"
            )
        }

        _ = Darwin.chmod(socketPath, 0o600)

        guard Darwin.listen(sfd, 128) == 0 else {
            let err = errno
            Darwin.close(sfd)
            throw DaemonWireError.daemonError(
                code: "LISTEN_FAILED",
                message: "Failed to listen on Unix socket: \(String(cString: strerror(err)))"
            )
        }

        self.serverFD = sfd

        // 5. Setup DispatchSourceRead listener on registry queue
        let lSource = DispatchSource.makeReadSource(fileDescriptor: sfd, queue: registry.queue)
        lSource.setEventHandler { [weak self] in
            self?.acceptIncomingClients()
        }
        self.listenerSource = lSource
        lSource.resume()

        // 6. Handle SIGINT and SIGTERM gracefully
        signal(SIGINT, SIG_IGN)
        signal(SIGTERM, SIG_IGN)

        let iSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: registry.queue)
        iSource.setEventHandler { [weak self] in
            self?.stopAndExit()
        }
        self.sigintSource = iSource
        iSource.resume()

        let tSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: registry.queue)
        tSource.setEventHandler { [weak self] in
            self?.stopAndExit()
        }
        self.sigtermSource = tSource
        tSource.resume()

        // 7. Arm idle shutdown timer
        registry.checkIdleShutdown()
    }

    func stopAndExit() {
        guard !isStopping else { return }
        isStopping = true

        listenerSource?.cancel()
        listenerSource = nil

        sigintSource?.cancel()
        sigintSource = nil

        sigtermSource?.cancel()
        sigtermSource = nil

        for client in Array(clients.values) {
            client.closeConnection()
        }
        clients.removeAll()

        registry.terminateAll()

        if serverFD >= 0 {
            Darwin.close(serverFD)
            serverFD = -1
        }
        _ = Darwin.unlink(DaemonPaths.socketPath)

        if lockFD >= 0 {
            flock(lockFD, LOCK_UN)
            Darwin.close(lockFD)
            lockFD = -1
        }

        Darwin.exit(0)
    }

    func removeClient(id: UUID) {
        clients.removeValue(forKey: id)
    }

    private func acceptIncomingClients() {
        guard serverFD >= 0 else { return }

        while true {
            var clientAddr = sockaddr_un()
            var addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)
            let clientFD = withUnsafeMutablePointer(to: &clientAddr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                    Darwin.accept(serverFD, sockPtr, &addrLen)
                }
            }

            if clientFD < 0 {
                if errno == EINTR { continue }
                if errno == EAGAIN || errno == EWOULDBLOCK { break }
                break
            }

            var noSigPipe: Int32 = 1
            _ = setsockopt(clientFD, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
            _ = fcntl(clientFD, F_SETFD, FD_CLOEXEC)
            _ = fcntl(clientFD, F_SETFL, O_NONBLOCK)

            guard UnixSocketWire.verifyPeerSameUser(fd: clientFD) else {
                Darwin.close(clientFD)
                continue
            }

            let connection = ClientConnection(
                fd: clientFD,
                server: self,
                registry: registry,
                queue: registry.queue
            )
            clients[connection.id] = connection
            connection.start()
        }
    }
}

/// Represents an individual Unix socket connection from `macssh-cli` or `MacSSH.app`.
/// Handles reading framed packets, executing control requests, and bridging interactive streaming I/O.
final class ClientConnection: SessionClientBridge, @unchecked Sendable {
    let id = UUID()
    let fd: Int32
    unowned let server: DaemonServer
    let registry: SessionRegistry
    let queue: DispatchQueue

    private var readSource: DispatchSourceRead?
    private var readBuffer = Data()
    private var isClosed = false
    private(set) var attachedSessionKey: String?

    init(
        fd: Int32,
        server: DaemonServer,
        registry: SessionRegistry,
        queue: DispatchQueue
    ) {
        self.fd = fd
        self.server = server
        self.registry = registry
        self.queue = queue
    }

    func start() {
        registry.incrementActiveClients()

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in
            self?.handleReadable()
        }
        source.setCancelHandler { [weak self] in
            self?.closeConnection()
        }
        self.readSource = source
        source.resume()
    }

    func closeConnection() {
        guard !isClosed else { return }
        isClosed = true

        readSource?.cancel()
        readSource = nil

        if let sessionKey = attachedSessionKey {
            attachedSessionKey = nil
            registry.detachClient(id: id, from: sessionKey)
        }

        Darwin.close(fd)
        registry.decrementActiveClients()
        server.removeClient(id: id)
    }

    // MARK: - SessionClientBridge

    func sendOutput(data: Data) {
        guard !isClosed, !data.isEmpty else { return }
        do {
            try UnixSocketWire.writeFrame(fd: fd, kind: .streamOutput, payload: data)
        } catch {
            closeConnection()
        }
    }

    func sendSessionExit(exitCode: Int32) {
        guard !isClosed else { return }
        let payload = UnixSocketWire.encodeExitPayload(exitCode: exitCode)
        try? UnixSocketWire.writeFrame(fd: fd, kind: .streamSessionExit, payload: payload)
        closeConnection()
    }

    func detachBridge() {
        closeConnection()
    }

    // MARK: - Framing & Dispatch

    private func handleReadable() {
        guard !isClosed else { return }
        var temp = [UInt8](repeating: 0, count: 65536)

        while true {
            let n = Darwin.read(fd, &temp, temp.count)
            if n > 0 {
                readBuffer.append(temp, count: n)
                continue
            }
            if n == 0 {
                closeConnection()
                return
            }
            if errno == EINTR { continue }
            if errno == EAGAIN || errno == EWOULDBLOCK { break }
            closeConnection()
            return
        }

        processFrames()
    }

    private func processFrames() {
        while readBuffer.count >= 5 {
            let length: UInt32 = readBuffer.withUnsafeBytes { raw in
                raw.loadUnaligned(fromByteOffset: 0, as: UInt32.self).bigEndian
            }
            let totalLength = Int(length)
            guard totalLength >= 1, totalLength <= DaemonProtocol.maxFrameByteCount else {
                closeConnection()
                return
            }
            let frameTotalBytes = 4 + totalLength
            if readBuffer.count < frameTotalBytes {
                break
            }
            guard let kind = DaemonFrameKind(rawValue: readBuffer[4]) else {
                closeConnection()
                return
            }
            let payloadLength = totalLength - 1
            let payload = payloadLength > 0 ? readBuffer.subdata(in: 5..<frameTotalBytes) : Data()
            readBuffer.removeSubrange(0..<frameTotalBytes)

            handleFrame(kind: kind, payload: payload)
            if isClosed { return }
        }
    }

    private func handleFrame(kind: DaemonFrameKind, payload: Data) {
        if let sessionKey = attachedSessionKey {
            // Long-lived streaming bridge session
            switch kind {
            case .streamInput:
                registry.writeInput(to: sessionKey, data: payload)
            case .streamResize:
                if let (cols, rows, w, h) = UnixSocketWire.decodeResizePayload(payload) {
                    registry.resize(sessionKey: sessionKey, columns: cols, rows: rows, widthPx: w, heightPx: h)
                }
            case .streamRedraw:
                registry.redraw(sessionKey: sessionKey)
            case .controlRequest:
                if let request = try? UnixSocketWire.decodeControlRequest(payload) {
                    handleControlRequest(request)
                }
            default:
                break
            }
        } else {
            // Initial request state
            guard kind == .controlRequest else {
                sendResponse(.error(code: "INVALID_FRAME", message: "Expected control request."))
                closeConnection()
                return
            }
            do {
                let request = try UnixSocketWire.decodeControlRequest(payload)
                handleControlRequest(request)
            } catch {
                sendResponse(.error(code: "DECODE_ERROR", message: error.localizedDescription))
                closeConnection()
            }
        }
    }

    private func handleControlRequest(_ request: DaemonControlRequest) {
        switch request {
        case .ping:
            let pid = ProcessInfo.processInfo.processIdentifier
            let count = registry.sessionCount
            sendResponse(.pong(version: DaemonProtocol.version, pid: pid, activeSessionCount: count))
            if attachedSessionKey == nil {
                closeConnection()
            }

        case .openOrAttach(
            let sessionKey,
            let title,
            let command,
            let shell,
            let cwd,
            let env,
            let cols,
            let rows,
            let attr,
            let attachStream
        ):
            do {
                let (summary, replayData, session) = try registry.openOrAttach(
                    sessionKey: sessionKey,
                    title: title,
                    command: command,
                    shell: shell,
                    workingDirectory: cwd,
                    environment: env,
                    columns: cols,
                    rows: rows,
                    attributes: attr,
                    attachStream: attachStream,
                    clientBridge: attachStream ? self : nil
                )
                sendResponse(.openedOrAttached(summary: summary, replayData: replayData))
                if attachStream {
                    self.attachedSessionKey = session.sessionKey
                } else {
                    closeConnection()
                }
            } catch let error as DaemonWireError {
                if case .daemonError(let code, let message) = error {
                    sendResponse(.error(code: code, message: message))
                } else {
                    sendResponse(.error(code: "OPEN_FAILED", message: error.localizedDescription))
                }
                closeConnection()
            } catch {
                sendResponse(.error(code: "OPEN_FAILED", message: error.localizedDescription))
                closeConnection()
            }

        case .listSessions:
            let summaries = registry.listSummaries()
            sendResponse(.sessionList(summaries))
            if attachedSessionKey == nil {
                closeConnection()
            }

        case .captureSession(let target, let full, let lastCommandOnly):
            do {
                let (summary, text) = try registry.capture(target: target, full: full, lastCommandOnly: lastCommandOnly)
                sendResponse(.captured(summary: summary, text: text))
            } catch let error as DaemonWireError {
                if case .daemonError(let code, let message) = error {
                    sendResponse(.error(code: code, message: message))
                } else {
                    sendResponse(.error(code: "CAPTURE_FAILED", message: error.localizedDescription))
                }
            } catch {
                sendResponse(.error(code: "CAPTURE_FAILED", message: error.localizedDescription))
            }
            if attachedSessionKey == nil {
                closeConnection()
            }

        case .sendInput(let target, let data):
            do {
                try registry.sendInput(target: target, data: data)
                sendResponse(.ok)
            } catch let error as DaemonWireError {
                if case .daemonError(let code, let message) = error {
                    sendResponse(.error(code: code, message: message))
                } else {
                    sendResponse(.error(code: "SEND_FAILED", message: error.localizedDescription))
                }
            } catch {
                sendResponse(.error(code: "SEND_FAILED", message: error.localizedDescription))
            }
            if attachedSessionKey == nil {
                closeConnection()
            }

        case .closeSession(let target):
            do {
                try registry.closeSession(target: target)
                sendResponse(.ok)
            } catch let error as DaemonWireError {
                if case .daemonError(let code, let message) = error {
                    sendResponse(.error(code: code, message: message))
                } else {
                    sendResponse(.error(code: "CLOSE_FAILED", message: error.localizedDescription))
                }
            } catch {
                sendResponse(.error(code: "CLOSE_FAILED", message: error.localizedDescription))
            }
            if attachedSessionKey == nil {
                closeConnection()
            }

        case .detachSession(let target):
            do {
                try registry.detachSession(target: target)
                sendResponse(.ok)
            } catch let error as DaemonWireError {
                if case .daemonError(let code, let message) = error {
                    sendResponse(.error(code: code, message: message))
                } else {
                    sendResponse(.error(code: "DETACH_FAILED", message: error.localizedDescription))
                }
            } catch {
                sendResponse(.error(code: "DETACH_FAILED", message: error.localizedDescription))
            }
            if attachedSessionKey == nil {
                closeConnection()
            }

        case .setAttributes(let target, let attributes):
            do {
                try registry.setAttributes(target: target, attributes: attributes)
                sendResponse(.ok)
            } catch let error as DaemonWireError {
                if case .daemonError(let code, let message) = error {
                    sendResponse(.error(code: code, message: message))
                } else {
                    sendResponse(.error(code: "SET_ATTR_FAILED", message: error.localizedDescription))
                }
            } catch {
                sendResponse(.error(code: "SET_ATTR_FAILED", message: error.localizedDescription))
            }
            if attachedSessionKey == nil {
                closeConnection()
            }

        case .shutdownIfIdle:
            let canShutdown = registry.shutdownIfIdle()
            sendResponse(.ok)
            closeConnection()
            if canShutdown {
                server.stopAndExit()
            }
        }
    }

    private func sendResponse(_ response: DaemonControlResponse) {
        guard !isClosed else { return }
        try? UnixSocketWire.writeControlResponse(fd: fd, response)
    }
}
