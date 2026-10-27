import Darwin
import Foundation

enum PTYSessionError: Error, LocalizedError, Sendable {
    case pipeCreationFailed(Int32)
    case forkptyFailed(Int32)
    case execFailed(step: Int32, errno: Int32, path: String)

    var errorDescription: String? {
        switch self {
        case .pipeCreationFailed(let code):
            return "Failed to create exec status pipe: \(String(cString: strerror(code)))"
        case .forkptyFailed(let code):
            return "forkpty() failed: \(String(cString: strerror(code)))"
        case .execFailed(let step, let code, let path):
            let stage = step == 1 ? "chdir" : "execve(\(path))"
            return "Child failed during \(stage): \(String(cString: strerror(code)))"
        }
    }
}

/// Manages a single local pseudo-terminal (`forkpty`) and its child process (`execve`).
/// All mutable state and DispatchSources are serialized on the registry queue passed at initialization.
final class PTYSession: @unchecked Sendable {
    let shortID: UInt64
    let sessionKey: String
    var title: String
    let shellPath: String
    let shellBasename: String
    let childPID: pid_t
    private(set) var masterFD: Int32
    private(set) var columns: UInt16
    private(set) var rows: UInt16
    private(set) var foregroundProcessName: String
    private(set) var isForegroundShell: Bool
    private(set) var currentDirectory: String?
    let createdAt: Date
    var attributes: [String: String]
    private(set) var replayBuffer = Data()
    private(set) var isClosed = false

    var onOutput: ((String, Data) -> Void)?
    var onExit: ((String, Int32) -> Void)?

    private let queue: DispatchQueue
    private var readSource: DispatchSourceRead?
    private var writeSource: DispatchSourceWrite?
    private var processSource: DispatchSourceProcess?
    private var metadataTimer: DispatchSourceTimer?
    private var killGraceTimer: DispatchSourceTimer?
    private var exitPollTimer: DispatchSourceTimer?

    private var pendingInput: [UInt8] = []
    private var lastMetadataRefreshNs: UInt64 = 0
    private var hasReapedChild = false
    private var exitNotified = false
    private var reapedExitCode: Int32 = 0
    private var exitPollAttempts = 0

    private static let knownShellNames: Set<String> = [
        "zsh", "bash", "sh", "fish", "dash", "ksh", "tcsh", "csh", "nu", "elvish", "xonsh"
    ]

    init(
        shortID: UInt64,
        sessionKey: String,
        title: String,
        command: [String]?,
        shell: String?,
        workingDirectory: String?,
        environment: [String: String]?,
        columns: UInt16,
        rows: UInt16,
        attributes: [String: String]?,
        queue: DispatchQueue
    ) throws {
        self.shortID = shortID
        self.sessionKey = sessionKey
        self.title = title
        self.queue = queue
        self.createdAt = Date()
        self.attributes = attributes ?? [:]

        let clampedCols = max(1, min(columns == 0 ? DaemonProtocol.defaultColumns : columns, DaemonProtocol.maximumColumns))
        let clampedRows = max(1, min(rows == 0 ? DaemonProtocol.defaultRows : rows, DaemonProtocol.maximumRows))
        self.columns = clampedCols
        self.rows = clampedRows

        let resolvedShell = Self.resolveLoginShell(preferred: shell, environment: environment)
        self.shellPath = resolvedShell
        self.shellBasename = URL(fileURLWithPath: resolvedShell).lastPathComponent.lowercased()

        let resolvedWorkDir = Self.resolveWorkingDirectory(workingDirectory)
        self.currentDirectory = resolvedWorkDir

        let mergedEnv = Self.buildEnvironment(
            custom: environment,
            shellPath: resolvedShell,
            shortID: shortID,
            sessionKey: sessionKey
        )

        let (executablePath, argvStrings) = Self.resolveCommand(
            command: command,
            shellPath: resolvedShell,
            pathEnv: mergedEnv["PATH"]
        )

        let initialProcName = URL(fileURLWithPath: executablePath).lastPathComponent
        self.foregroundProcessName = initialProcName
        self.isForegroundShell = Self.isShellProcess(name: initialProcName, shellBasename: self.shellBasename)

        // Pre-allocate all C strings BEFORE forkpty so the child only runs async-signal-safe syscalls.
        let cExecPath = strdup(executablePath)
        let cWorkDir = strdup(resolvedWorkDir)
        var cArgv: [UnsafeMutablePointer<CChar>?] = argvStrings.map { strdup($0) }
        cArgv.append(nil)

        let envStrings = mergedEnv.map { "\($0.key)=\($0.value)" }
        var cEnvp: [UnsafeMutablePointer<CChar>?] = envStrings.map { strdup($0) }
        cEnvp.append(nil)

        defer {
            if let cExecPath { free(cExecPath) }
            if let cWorkDir { free(cWorkDir) }
            for ptr in cArgv where ptr != nil { free(ptr) }
            for ptr in cEnvp where ptr != nil { free(ptr) }
        }

        var errPipe: [Int32] = [-1, -1]
        guard Darwin.pipe(&errPipe) == 0 else {
            throw PTYSessionError.pipeCreationFailed(errno)
        }
        _ = fcntl(errPipe[0], F_SETFD, FD_CLOEXEC)
        _ = fcntl(errPipe[1], F_SETFD, FD_CLOEXEC)

        var ws = winsize(
            ws_row: clampedRows,
            ws_col: clampedCols,
            ws_xpixel: 0,
            ws_ypixel: 0
        )

        var master: Int32 = -1
        let spawnedPID: pid_t = cArgv.withUnsafeMutableBufferPointer { argvBuf in
            cEnvp.withUnsafeMutableBufferPointer { envpBuf in
                let pid = forkpty(&master, nil, nil, &ws)
                if pid == 0 {
                    // Child process: strictly async-signal-safe calls only.
                    Darwin.close(errPipe[0])

                    var emptyMask = sigset_t()
                    sigemptyset(&emptyMask)
                    _ = sigprocmask(SIG_SETMASK, &emptyMask, nil)
                    _ = Darwin.signal(SIGPIPE, SIG_DFL)
                    _ = Darwin.signal(SIGINT, SIG_DFL)
                    _ = Darwin.signal(SIGQUIT, SIG_DFL)
                    _ = Darwin.signal(SIGTERM, SIG_DFL)
                    _ = Darwin.signal(SIGHUP, SIG_DFL)
                    _ = Darwin.signal(SIGCHLD, SIG_DFL)
                    _ = Darwin.signal(SIGTSTP, SIG_DFL)
                    _ = Darwin.signal(SIGTTIN, SIG_DFL)
                    _ = Darwin.signal(SIGTTOU, SIG_DFL)

                    if let cWorkDir {
                        if Darwin.chdir(cWorkDir) != 0 {
                            var failure: (Int32, Int32) = (1, errno)
                            _ = withUnsafeBytes(of: &failure) { raw in
                                Darwin.write(errPipe[1], raw.baseAddress, raw.count)
                            }
                            Darwin.close(errPipe[1])
                            Darwin._exit(126)
                        }
                    }

                    if let cExecPath,
                       let argvBase = argvBuf.baseAddress,
                       let envpBase = envpBuf.baseAddress {
                        _ = Darwin.execve(cExecPath, argvBase, envpBase)
                    }

                    var failure: (Int32, Int32) = (2, errno)
                    _ = withUnsafeBytes(of: &failure) { raw in
                        Darwin.write(errPipe[1], raw.baseAddress, raw.count)
                    }
                    Darwin.close(errPipe[1])
                    Darwin._exit(127)
                }
                return pid
            }
        }

        if spawnedPID < 0 {
            Darwin.close(errPipe[0])
            Darwin.close(errPipe[1])
            if master >= 0 { Darwin.close(master) }
            throw PTYSessionError.forkptyFailed(errno)
        }

        Darwin.close(errPipe[1])
        var childFailure: (Int32, Int32) = (0, 0)
        let failureBytesRead: Int = withUnsafeMutableBytes(of: &childFailure) { raw in
            while true {
                let n = Darwin.read(errPipe[0], raw.baseAddress, raw.count)
                if n < 0 && errno == EINTR { continue }
                return n
            }
        }
        Darwin.close(errPipe[0])

        if failureBytesRead > 0 && childFailure.0 != 0 {
            if master >= 0 { Darwin.close(master) }
            var status: Int32 = 0
            _ = waitpid(spawnedPID, &status, 0)
            throw PTYSessionError.execFailed(step: childFailure.0, errno: childFailure.1, path: executablePath)
        }

        let fdFlags = fcntl(master, F_GETFD)
        if fdFlags >= 0 {
            _ = fcntl(master, F_SETFD, fdFlags | FD_CLOEXEC)
        }
        let flFlags = fcntl(master, F_GETFL)
        if flFlags >= 0 {
            _ = fcntl(master, F_SETFL, flFlags | O_NONBLOCK)
        }

        self.childPID = spawnedPID
        self.masterFD = master
    }

    deinit {
        if masterFD >= 0 {
            Darwin.close(masterFD)
        }
    }

    func start() {
        guard !isClosed, masterFD >= 0 else { return }

        let rSource = DispatchSource.makeReadSource(fileDescriptor: masterFD, queue: queue)
        rSource.setEventHandler { [weak self] in
            self?.handleReadable()
        }
        self.readSource = rSource
        rSource.resume()

        let pSource = DispatchSource.makeProcessSource(identifier: childPID, eventMask: .exit, queue: queue)
        pSource.setEventHandler { [weak self] in
            self?.handleProcessExitEvent()
        }
        self.processSource = pSource
        pSource.resume()

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + .milliseconds(500), repeating: .milliseconds(750))
        timer.setEventHandler { [weak self] in
            guard let self, !self.isClosed else { return }
            self.refreshProcessMetadata(force: true)
            if self.pollChildExitNonBlocking() {
                self.drainRemainingOutput()
                self.finishExitIfNeeded()
            }
        }
        self.metadataTimer = timer
        timer.resume()

        refreshProcessMetadata(force: true)
    }

    /// Writes input bytes to the PTY master without blocking or dropping bytes when exceeding XNU TTYHOG.
    @discardableResult
    func write(_ data: Data) -> Bool {
        guard !isClosed, masterFD >= 0 else { return false }
        guard !data.isEmpty else { return true }

        if pendingInput.isEmpty {
            var writtenCount = 0
            let total = data.count
            let failed: Bool = data.withUnsafeBytes { raw in
                guard let base = raw.baseAddress else { return false }
                while writtenCount < total {
                    let n = Darwin.write(masterFD, base.advanced(by: writtenCount), total - writtenCount)
                    if n > 0 {
                        writtenCount += n
                        continue
                    }
                    if n < 0 && errno == EINTR {
                        continue
                    }
                    if n < 0 && (errno == EAGAIN || errno == EWOULDBLOCK) {
                        return false
                    }
                    return true
                }
                return false
            }
            if failed {
                return false
            }
            if writtenCount == total {
                return true
            }
            let remaining = data.dropFirst(writtenCount)
            guard pendingInput.count + remaining.count <= DaemonProtocol.maxPendingInputByteCount else {
                return false
            }
            pendingInput.append(contentsOf: remaining)
            armWriteSourceIfNeeded()
            return true
        } else {
            guard pendingInput.count + data.count <= DaemonProtocol.maxPendingInputByteCount else {
                return false
            }
            pendingInput.append(contentsOf: data)
            armWriteSourceIfNeeded()
            return true
        }
    }

    func resize(columns: UInt16, rows: UInt16, widthPx: UInt16 = 0, heightPx: UInt16 = 0) {
        guard !isClosed, masterFD >= 0 else { return }
        let clampedCols = max(1, min(columns, DaemonProtocol.maximumColumns))
        let clampedRows = max(1, min(rows, DaemonProtocol.maximumRows))
        self.columns = clampedCols
        self.rows = clampedRows
        var ws = winsize(
            ws_row: clampedRows,
            ws_col: clampedCols,
            ws_xpixel: widthPx,
            ws_ypixel: heightPx
        )
        _ = ioctl(masterFD, UInt(TIOCSWINSZ), &ws)
    }

    func redrawForeground() {
        guard !isClosed, masterFD >= 0 else { return }
        let pgrp = tcgetpgrp(masterFD)
        if pgrp > 0 {
            _ = Darwin.kill(-pgrp, SIGWINCH)
        } else if childPID > 0 {
            _ = Darwin.kill(-childPID, SIGWINCH)
            _ = Darwin.kill(childPID, SIGWINCH)
        }
    }

    func terminate() {
        guard !isClosed else { return }

        if !hasReapedChild && childPID > 0 {
            if masterFD >= 0 {
                let pgrp = tcgetpgrp(masterFD)
                if pgrp > 0 {
                    _ = Darwin.kill(-pgrp, SIGHUP)
                }
            }
            _ = Darwin.kill(-childPID, SIGHUP)
            _ = Darwin.kill(childPID, SIGHUP)
        }

        if pollChildExitNonBlocking() {
            closeResourcesAndNotifyExit()
            return
        }

        guard killGraceTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + .milliseconds(1500))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            self.killGraceTimer?.cancel()
            self.killGraceTimer = nil
            if !self.hasReapedChild && self.childPID > 0 {
                _ = Darwin.kill(-self.childPID, SIGKILL)
                _ = Darwin.kill(self.childPID, SIGKILL)
                _ = self.pollChildExitNonBlocking()
            }
            self.closeResourcesAndNotifyExit()
        }
        self.killGraceTimer = timer
        timer.resume()
    }

    func refreshProcessMetadata(force: Bool = false) {
        guard !isClosed, childPID > 0 else { return }
        let nowNs = DispatchTime.now().uptimeNanoseconds
        if !force && (nowNs - lastMetadataRefreshNs) < 250_000_000 {
            return
        }
        lastMetadataRefreshNs = nowNs

        let pgrp = masterFD >= 0 ? tcgetpgrp(masterFD) : -1
        let targetPID = pgrp > 0 ? pgrp : childPID

        if let procName = Self.queryProcessName(pid: targetPID) ?? Self.queryProcessName(pid: childPID) {
            let clean = procName.hasPrefix("-") ? String(procName.dropFirst()) : procName
            if !clean.isEmpty {
                self.foregroundProcessName = clean
                self.isForegroundShell = Self.isShellProcess(name: clean, shellBasename: shellBasename)
            }
        }

        if let cwd = Self.queryCurrentDirectory(pid: targetPID) ?? Self.queryCurrentDirectory(pid: childPID) {
            self.currentDirectory = cwd
        }
    }

    // MARK: - Private I/O & Process Handlers

    private func handleReadable() {
        guard !isClosed, masterFD >= 0 else { return }
        let drainedEOF = drainRemainingOutput()
        refreshProcessMetadata(force: false)

        if drainedEOF {
            if pollChildExitNonBlocking() {
                finishExitIfNeeded()
            } else {
                scheduleExitPollTimer()
            }
        }
    }

    /// Drains all currently readable bytes from `masterFD`. Returns `true` if EOF or terminal hangup occurred.
    @discardableResult
    private func drainRemainingOutput() -> Bool {
        guard masterFD >= 0 else { return true }
        var temp = [UInt8](repeating: 0, count: 65536)
        var reachedEOF = false

        while true {
            let n = Darwin.read(masterFD, &temp, temp.count)
            if n > 0 {
                let chunk = Data(bytes: temp, count: n)
                appendToReplayBuffer(chunk)
                onOutput?(sessionKey, chunk)
                continue
            }
            if n == 0 {
                reachedEOF = true
                break
            }
            if errno == EINTR {
                continue
            }
            if errno == EAGAIN || errno == EWOULDBLOCK {
                break
            }
            // EIO or EBADF on a PTY master indicates the slave side closed.
            reachedEOF = true
            break
        }
        return reachedEOF
    }

    private func appendToReplayBuffer(_ chunk: Data) {
        guard !chunk.isEmpty else { return }
        if chunk.count >= DaemonProtocol.maxReplayByteCount {
            replayBuffer = Data(chunk.suffix(DaemonProtocol.maxReplayByteCount))
            return
        }
        replayBuffer.append(chunk)
        if replayBuffer.count > DaemonProtocol.maxReplayByteCount {
            replayBuffer = Data(replayBuffer.suffix(DaemonProtocol.maxReplayByteCount))
        }
    }

    private func armWriteSourceIfNeeded() {
        guard writeSource == nil, !isClosed, masterFD >= 0 else { return }
        let wSource = DispatchSource.makeWriteSource(fileDescriptor: masterFD, queue: queue)
        wSource.setEventHandler { [weak self] in
            self?.handleWritable()
        }
        self.writeSource = wSource
        wSource.resume()
    }

    private func disarmWriteSource() {
        writeSource?.cancel()
        writeSource = nil
    }

    private func handleWritable() {
        guard !isClosed, masterFD >= 0 else {
            pendingInput.removeAll()
            disarmWriteSource()
            return
        }
        guard !pendingInput.isEmpty else {
            disarmWriteSource()
            return
        }

        var writtenCount = 0
        let total = pendingInput.count
        var fatalError = false

        pendingInput.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            while writtenCount < total {
                let n = Darwin.write(masterFD, base.advanced(by: writtenCount), total - writtenCount)
                if n > 0 {
                    writtenCount += n
                    continue
                }
                if n < 0 && errno == EINTR {
                    continue
                }
                if n < 0 && (errno == EAGAIN || errno == EWOULDBLOCK) {
                    break
                }
                fatalError = true
                break
            }
        }

        if fatalError {
            pendingInput.removeAll()
            disarmWriteSource()
            return
        }

        if writtenCount > 0 {
            pendingInput.removeFirst(writtenCount)
        }
        if pendingInput.isEmpty {
            disarmWriteSource()
        }
    }

    private func handleProcessExitEvent() {
        guard !isClosed else { return }
        _ = drainRemainingOutput()
        if pollChildExitNonBlocking() {
            finishExitIfNeeded()
        } else {
            scheduleExitPollTimer()
        }
    }

    private func scheduleExitPollTimer() {
        guard exitPollTimer == nil, !isClosed else { return }
        exitPollAttempts = 0
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + .milliseconds(40), repeating: .milliseconds(40))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            self.exitPollAttempts += 1
            _ = self.drainRemainingOutput()
            if self.pollChildExitNonBlocking() || self.exitPollAttempts >= 25 {
                self.exitPollTimer?.cancel()
                self.exitPollTimer = nil
                self.finishExitIfNeeded()
            }
        }
        self.exitPollTimer = timer
        timer.resume()
    }

    @discardableResult
    private func pollChildExitNonBlocking() -> Bool {
        if hasReapedChild { return true }
        guard childPID > 0 else { return true }
        var status: Int32 = 0
        let rc = waitpid(childPID, &status, WNOHANG)
        if rc == childPID {
            hasReapedChild = true
            reapedExitCode = Self.decodeWaitStatus(status)
            return true
        }
        if rc < 0 && errno == ECHILD {
            hasReapedChild = true
            reapedExitCode = 0
            return true
        }
        return false
    }

    private func finishExitIfNeeded() {
        closeResourcesAndNotifyExit()
    }

    private func closeResourcesAndNotifyExit() {
        guard !isClosed else { return }
        isClosed = true

        readSource?.cancel()
        readSource = nil

        disarmWriteSource()
        pendingInput.removeAll()

        processSource?.cancel()
        processSource = nil

        metadataTimer?.cancel()
        metadataTimer = nil

        killGraceTimer?.cancel()
        killGraceTimer = nil

        exitPollTimer?.cancel()
        exitPollTimer = nil

        if masterFD >= 0 {
            Darwin.close(masterFD)
            masterFD = -1
        }

        _ = pollChildExitNonBlocking()

        if !exitNotified {
            exitNotified = true
            onExit?(sessionKey, reapedExitCode)
        }
    }

    // MARK: - Static Helpers

    private static func decodeWaitStatus(_ status: Int32) -> Int32 {
        let wstatus = status & 0x7F
        if wstatus == 0 {
            return (status >> 8) & 0xFF
        }
        if wstatus != 0x7F && wstatus != 0 {
            return 128 + wstatus
        }
        return 0
    }

    private static func queryProcessName(pid: pid_t) -> String? {
        guard pid > 0 else { return nil }
        var bsdInfo = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        let rc = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsdInfo, size)
        guard rc == size else { return nil }

        let fullName = withUnsafePointer(to: &bsdInfo.pbi_name) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: Int(MAXCOMLEN) * 2) {
                String(cString: $0)
            }
        }
        if !fullName.isEmpty {
            return fullName
        }
        let commName = withUnsafePointer(to: &bsdInfo.pbi_comm) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: Int(MAXCOMLEN)) {
                String(cString: $0)
            }
        }
        return commName.isEmpty ? nil : commName
    }

    private static func queryCurrentDirectory(pid: pid_t) -> String? {
        guard pid > 0 else { return nil }
        var vnodeInfo = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        let rc = proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &vnodeInfo, size)
        guard rc == size else { return nil }

        let path = withUnsafePointer(to: &vnodeInfo.pvi_cdir.vip_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) {
                String(cString: $0)
            }
        }
        return path.isEmpty ? nil : path
    }

    private static func isShellProcess(name: String, shellBasename: String) -> Bool {
        let cleaned = (name.hasPrefix("-") ? String(name.dropFirst()) : name)
        let base = URL(fileURLWithPath: cleaned).lastPathComponent.lowercased()
        return base == shellBasename || knownShellNames.contains(base)
    }

    private static func resolveLoginShell(preferred: String?, environment: [String: String]?) -> String {
        let fm = FileManager.default
        if let preferred, !preferred.isEmpty, fm.isExecutableFile(atPath: preferred) {
            return preferred
        }
        if let envShell = environment?["SHELL"], !envShell.isEmpty, fm.isExecutableFile(atPath: envShell) {
            return envShell
        }
        if let procShell = ProcessInfo.processInfo.environment["SHELL"], !procShell.isEmpty, fm.isExecutableFile(atPath: procShell) {
            return procShell
        }
        if let pw = getpwuid(getuid()), let shellPtr = pw.pointee.pw_shell {
            let pwShell = String(cString: shellPtr)
            if !pwShell.isEmpty, fm.isExecutableFile(atPath: pwShell) {
                return pwShell
            }
        }
        if fm.isExecutableFile(atPath: "/bin/zsh") {
            return "/bin/zsh"
        }
        return "/bin/sh"
    }

    private static func resolveWorkingDirectory(_ requested: String?) -> String {
        let fm = FileManager.default
        if let requested, !requested.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let expanded = (requested as NSString).expandingTildeInPath
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: expanded, isDirectory: &isDir), isDir.boolValue {
                return expanded
            }
        }
        let home = NSHomeDirectory()
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: home, isDirectory: &isDir), isDir.boolValue {
            return home
        }
        return "/"
    }

    private static func buildEnvironment(
        custom: [String: String]?,
        shellPath: String,
        shortID: UInt64,
        sessionKey: String
    ) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        if env["TERM"] == nil || env["TERM"] == "dumb" || env["TERM"]?.isEmpty == true {
            env["TERM"] = "xterm-256color"
        }
        if env["COLORTERM"] == nil {
            env["COLORTERM"] = "truecolor"
        }
        if env["TERM_PROGRAM"] == nil {
            env["TERM_PROGRAM"] = "ghostty"
        }
        if env["TERM_PROGRAM_VERSION"] == nil {
            env["TERM_PROGRAM_VERSION"] = "1.1.2"
        }
        if env["LANG"] == nil || env["LANG"]?.isEmpty == true {
            env["LANG"] = "en_US.UTF-8"
        }
        if env["HOME"] == nil || env["HOME"]?.isEmpty == true {
            env["HOME"] = NSHomeDirectory()
        }
        env["SHELL"] = shellPath
        env["MACSSH_SESSION_ID"] = String(shortID)
        env["MACSSH_SESSION_KEY"] = sessionKey

        // Ensure standard Homebrew & system paths are present when spawned from a GUI bundle.
        let standardPaths = ["/opt/homebrew/bin", "/opt/homebrew/sbin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        let existingPath = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        var pathParts = existingPath.split(separator: ":").map(String.init)
        for std in standardPaths where !pathParts.contains(std) {
            pathParts.append(std)
        }
        env["PATH"] = pathParts.joined(separator: ":")

        if let custom {
            for (k, v) in custom {
                if k == "TERM" && (v.isEmpty || v == "dumb") {
                    continue
                }
                env[k] = v
            }
        }
        if env["TERM"] == nil || env["TERM"] == "dumb" || env["TERM"]?.isEmpty == true {
            env["TERM"] = "xterm-256color"
        }
        return env
    }

    private static func resolveCommand(
        command: [String]?,
        shellPath: String,
        pathEnv: String?
    ) -> (executable: String, argv: [String]) {
        guard let command, !command.isEmpty else {
            return (shellPath, [shellPath, "-l"])
        }
        if command.count == 1 {
            let single = command[0].trimmingCharacters(in: .whitespacesAndNewlines)
            if !single.isEmpty,
               !single.contains(" "),
               let resolved = resolveExecutableInPath(single, pathEnv: pathEnv) {
                return (resolved, [resolved])
            }
            return (shellPath, [shellPath, "-l", "-c", command[0]])
        }
        if let resolved = resolveExecutableInPath(command[0], pathEnv: pathEnv) {
            var argv = command
            argv[0] = resolved
            return (resolved, argv)
        }
        return (shellPath, [shellPath, "-l", "-c", command.joined(separator: " ")])
    }

    private static func resolveExecutableInPath(_ name: String, pathEnv: String?) -> String? {
        let fm = FileManager.default
        if name.contains("/") {
            let expanded = (name as NSString).expandingTildeInPath
            return fm.isExecutableFile(atPath: expanded) ? expanded : nil
        }
        let searchPath = pathEnv ?? "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        for dir in searchPath.split(separator: ":") {
            let candidate = String(dir) + "/" + name
            if fm.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }
}
