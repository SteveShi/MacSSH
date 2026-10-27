import Darwin
import Dispatch
import Foundation

#if canImport(MacSSHDaemonShared)
import MacSSHDaemonShared
#endif

/// Protocol implemented by attached client bridges (such as `ClientConnection`)
/// to receive streaming PTY output and process exit notifications.
protocol SessionClientBridge: AnyObject, Sendable {
    var id: UUID { get }
    func sendOutput(data: Data)
    func sendSessionExit(exitCode: Int32)
    func detachBridge()
}

extension PTYSession {
    func makeSummary(isAttached: Bool) -> DaemonSessionSummary {
        refreshProcessMetadata(force: false)
        return DaemonSessionSummary(
            shortID: shortID,
            sessionKey: sessionKey,
            title: title,
            shellPID: childPID,
            foregroundProcessName: foregroundProcessName,
            isForegroundShell: isForegroundShell,
            columns: columns,
            rows: rows,
            isAttached: isAttached,
            currentDirectory: currentDirectory,
            createdAt: createdAt,
            attributes: attributes
        )
    }
}

/// Central registry managing all live `PTYSession` instances, target resolution,
/// streaming client attachments, and idle daemon shutdown.
/// All mutable state is strictly serialized on `queue`.
final class SessionRegistry: @unchecked Sendable {
    let queue = DispatchQueue(label: "com.steveshi.macsshd.registry")

    private var sessions: [String: PTYSession] = [:]
    private var attachedClients: [String: [UUID: any SessionClientBridge]] = [:]
    private var nextShortID: UInt64 = 1
    private(set) var activeClientCount: Int = 0
    private var idleTimer: DispatchSourceTimer?

    var shutdownHandler: (@Sendable () -> Void)?

    var sessionCount: Int {
        sessions.count
    }

    init() {}

    // MARK: - Client Activity & Idle Shutdown

    func incrementActiveClients() {
        activeClientCount += 1
        cancelIdleTimer()
    }

    func decrementActiveClients() {
        if activeClientCount > 0 {
            activeClientCount -= 1
        }
        checkIdleShutdown()
    }

    func checkIdleShutdown() {
        if sessions.isEmpty && activeClientCount == 0 {
            if idleTimer == nil {
                let timer = DispatchSource.makeTimerSource(queue: queue)
                timer.schedule(deadline: .now() + DaemonProtocol.idleShutdownSeconds)
                timer.setEventHandler { [weak self] in
                    guard let self else { return }
                    if self.sessions.isEmpty && self.activeClientCount == 0 {
                        if let handler = self.shutdownHandler {
                            handler()
                        } else {
                            Darwin.exit(0)
                        }
                    }
                }
                self.idleTimer = timer
                timer.resume()
            }
        } else {
            cancelIdleTimer()
        }
    }

    private func cancelIdleTimer() {
        if let timer = idleTimer {
            timer.cancel()
            self.idleTimer = nil
        }
    }

    func shutdownIfIdle() -> Bool {
        if sessions.isEmpty && activeClientCount <= 1 {
            return true
        }
        return false
    }

    // MARK: - Target Resolution

    /// Resolves target lookups by:
    /// 1. `shortID` (e.g. `"1"`, `"2"`)
    /// 2. Exact `sessionKey`
    /// 3. Unique `sessionKey` prefix
    /// 4. Case-insensitive `title`
    func resolveSession(target: String) -> PTYSession? {
        let trimmed = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // 1. Exact match by shortID
        if let id = UInt64(trimmed), let session = sessions.values.first(where: { $0.shortID == id }) {
            return session
        }

        // 2. Exact match by sessionKey
        if let session = sessions[trimmed] {
            return session
        }

        // 3. Unique prefix match on sessionKey
        let prefixMatches = sessions.values.filter { $0.sessionKey.hasPrefix(trimmed) }
        if prefixMatches.count == 1 {
            return prefixMatches[0]
        }

        // 4. Case-insensitive title match
        let titleMatches = sessions.values.filter {
            $0.title.caseInsensitiveCompare(trimmed) == .orderedSame
        }
        if titleMatches.count == 1 {
            return titleMatches[0]
        }

        return nil
    }

    // MARK: - Session Operations

    func openOrAttach(
        sessionKey: String?,
        title: String?,
        command: [String]?,
        shell: String?,
        workingDirectory: String?,
        environment: [String: String]?,
        columns: UInt16,
        rows: UInt16,
        attributes: [String: String]?,
        attachStream: Bool,
        clientBridge: (any SessionClientBridge)?
    ) throws -> (summary: DaemonSessionSummary, replayData: Data, session: PTYSession) {
        // 1. Check if matching session already exists
        if let key = sessionKey, !key.isEmpty, let existing = resolveSession(target: key) {
            if columns > 0 && rows > 0 {
                existing.resize(columns: columns, rows: rows)
            }
            if let attributes {
                for (k, v) in attributes {
                    existing.attributes[k] = v
                }
            }
            if let title, !title.isEmpty {
                existing.title = title
            }
            if attachStream, let clientBridge {
                attachClient(clientBridge, to: existing.sessionKey)
            }
            cancelIdleTimer()
            let summary = existing.makeSummary(isAttached: isSessionAttached(existing.sessionKey))
            return (summary, existing.replayBuffer, existing)
        }

        // 2. Enforce session limit
        guard sessions.count < DaemonProtocol.maxSessions else {
            throw DaemonWireError.daemonError(
                code: "MAX_SESSIONS_EXCEEDED",
                message: "Maximum session limit reached (\(DaemonProtocol.maxSessions))."
            )
        }

        // 3. Create new session
        let shortID = nextShortID
        nextShortID += 1

        let resolvedKey = (sessionKey?.isEmpty == false) ? sessionKey! : UUID().uuidString.lowercased()
        let resolvedTitle: String
        if let title, !title.isEmpty {
            resolvedTitle = title
        } else if let firstCmd = command?.first, !firstCmd.isEmpty {
            resolvedTitle = URL(fileURLWithPath: firstCmd).lastPathComponent
        } else {
            resolvedTitle = "Terminal"
        }

        let session = try PTYSession(
            shortID: shortID,
            sessionKey: resolvedKey,
            title: resolvedTitle,
            command: command,
            shell: shell,
            workingDirectory: workingDirectory,
            environment: environment,
            columns: columns,
            rows: rows,
            attributes: attributes,
            queue: queue
        )

        session.onOutput = { [weak self] sKey, data in
            self?.handleSessionOutput(sessionKey: sKey, data: data)
        }
        session.onExit = { [weak self] sKey, exitCode in
            self?.handleSessionExit(sessionKey: sKey, exitCode: exitCode)
        }

        sessions[resolvedKey] = session
        session.start()

        if attachStream, let clientBridge {
            attachClient(clientBridge, to: resolvedKey)
        }

        cancelIdleTimer()
        let summary = session.makeSummary(isAttached: isSessionAttached(resolvedKey))
        return (summary, session.replayBuffer, session)
    }

    func listSummaries() -> [DaemonSessionSummary] {
        sessions.values
            .sorted { $0.shortID < $1.shortID }
            .map { $0.makeSummary(isAttached: isSessionAttached($0.sessionKey)) }
    }

    func capture(target: String, full: Bool, lastCommandOnly: Bool) throws -> (summary: DaemonSessionSummary, text: String) {
        guard let session = resolveSession(target: target) else {
            throw DaemonWireError.daemonError(code: "SESSION_NOT_FOUND", message: "Session '\(target)' not found.")
        }
        let renderer = ScreenRenderer(columns: session.columns, rows: session.rows)
        renderer.feed(session.replayBuffer)
        let text = renderer.render(includeScrollback: full, lastCommandOnly: lastCommandOnly)
        let summary = session.makeSummary(isAttached: isSessionAttached(session.sessionKey))
        return (summary, text)
    }

    func sendInput(target: String, data: Data) throws {
        guard let session = resolveSession(target: target) else {
            throw DaemonWireError.daemonError(code: "SESSION_NOT_FOUND", message: "Session '\(target)' not found.")
        }
        guard session.write(data) else {
            throw DaemonWireError.daemonError(
                code: "INPUT_WRITE_FAILED",
                message: "Failed to write input to session '\(target)': buffer full or session closed."
            )
        }
    }

    func closeSession(target: String) throws {
        guard let session = resolveSession(target: target) else {
            throw DaemonWireError.daemonError(code: "SESSION_NOT_FOUND", message: "Session '\(target)' not found.")
        }
        session.terminate()
        if session.isClosed {
            handleSessionExit(sessionKey: session.sessionKey, exitCode: 0)
        }
    }

    func detachSession(target: String) throws {
        guard let session = resolveSession(target: target) else {
            throw DaemonWireError.daemonError(code: "SESSION_NOT_FOUND", message: "Session '\(target)' not found.")
        }
        if let bridges = attachedClients.removeValue(forKey: session.sessionKey) {
            for bridge in bridges.values {
                bridge.detachBridge()
            }
        }
    }

    func setAttributes(target: String, attributes: [String: String]) throws {
        guard let session = resolveSession(target: target) else {
            throw DaemonWireError.daemonError(code: "SESSION_NOT_FOUND", message: "Session '\(target)' not found.")
        }
        for (k, v) in attributes {
            session.attributes[k] = v
        }
    }

    func writeInput(to sessionKey: String, data: Data) {
        guard let session = sessions[sessionKey] else { return }
        session.write(data)
    }

    func resize(sessionKey: String, columns: UInt16, rows: UInt16, widthPx: UInt16 = 0, heightPx: UInt16 = 0) {
        guard let session = sessions[sessionKey] else { return }
        session.resize(columns: columns, rows: rows, widthPx: widthPx, heightPx: heightPx)
    }

    func redraw(sessionKey: String) {
        guard let session = sessions[sessionKey] else { return }
        session.redrawForeground()
    }

    // MARK: - Streaming Bridge Attachments

    func isSessionAttached(_ sessionKey: String) -> Bool {
        guard let bridges = attachedClients[sessionKey] else { return false }
        return !bridges.isEmpty
    }

    func attachClient(_ bridge: any SessionClientBridge, to sessionKey: String) {
        if attachedClients[sessionKey] == nil {
            attachedClients[sessionKey] = [:]
        }
        attachedClients[sessionKey]?[bridge.id] = bridge
    }

    func detachClient(id: UUID, from sessionKey: String) {
        attachedClients[sessionKey]?.removeValue(forKey: id)
        if attachedClients[sessionKey]?.isEmpty == true {
            attachedClients.removeValue(forKey: sessionKey)
        }
    }

    func terminateAll() {
        for session in sessions.values {
            session.terminate()
        }
        for bridges in attachedClients.values {
            for bridge in bridges.values {
                bridge.detachBridge()
            }
        }
        sessions.removeAll()
        attachedClients.removeAll()
    }

    // MARK: - Private Callbacks

    private func handleSessionOutput(sessionKey: String, data: Data) {
        guard let bridges = attachedClients[sessionKey], !bridges.isEmpty else { return }
        for bridge in bridges.values {
            bridge.sendOutput(data: data)
        }
    }

    private func handleSessionExit(sessionKey: String, exitCode: Int32) {
        if let bridges = attachedClients.removeValue(forKey: sessionKey) {
            for bridge in bridges.values {
                bridge.sendSessionExit(exitCode: exitCode)
                bridge.detachBridge()
            }
        }
        sessions.removeValue(forKey: sessionKey)
        checkIdleShutdown()
    }
}
