import Foundation
import Observation
import libssh2_swift

@MainActor
@Observable
final class TerminalSessionViewModel {
    enum Status: Equatable {
        case idle
        case connecting
        case connected
        case failed(String)
    }

    struct HostKeyPrompt: Identifiable {
        let id = UUID()
        let host: String
        let status: HostKeyStatus
    }

    let connection: SSHConnection
    private let session: SSHSession
    let sftpService: SFTPService
    let sftpViewModel: SFTPViewModel

    var status: Status = .idle
    var password: String = ""
    var rememberPassword: Bool = false
    var usePublicKey: Bool = false
    var keyPath: String = ""
    var keyPassphrase: String = ""
    var hostKeyPrompt: HostKeyPrompt?
    var lastErrorMessage: String = ""

    var metrics: SystemMetrics = SystemMetrics()
    private let monitorTaskHolder = TaskHolder()
    private let connectTaskHolder = TaskHolder()
    var appModel: AppModel? = nil

    private let monitorScript = """
    OS_NAME=$([ -f /etc/os-release ] && ( . /etc/os-release && echo "$PRETTY_NAME" ) || uname -s)
    OS_ARCH=$(uname -m)
    echo "OS: ${OS_NAME} (${OS_ARCH})"
    if [ -f /proc/uptime ]; then
        echo "Uptime: $(cut -d. -f1 /proc/uptime)"
    else
        echo "Uptime: $(uptime | awk -F, '{print $1}')"
    fi
    if [ -f /proc/cpuinfo ]; then
        CPU_BRAND=$(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2 | xargs)
    else
        CPU_BRAND=$(sysctl -n machdep.cpu.brand_string 2>/dev/null || uname -m)
    fi
    echo "CPU_Model: ${CPU_BRAND}"
    echo "CPU_Cores: $(nproc 2>/dev/null || grep -c '^processor' /proc/cpuinfo 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 1)"
    if [ -f /proc/meminfo ]; then
        echo "Mem_Total: $(awk '/MemTotal/ {print $2}' /proc/meminfo)"
        echo "Mem_Free: $(awk '/MemFree/ {print $2}' /proc/meminfo)"
        echo "Mem_Available: $(awk '/MemAvailable/ {print $2}' /proc/meminfo || awk '/MemFree/ {print $2}' /proc/meminfo)"
        echo "Buffers: $(awk '/Buffers/ {print $2}' /proc/meminfo || echo 0)"
        echo "Cached: $(awk '/^Cached/ {print $2}' /proc/meminfo || echo 0)"
        echo "Swap_Total: $(awk '/SwapTotal/ {print $2}' /proc/meminfo || echo 0)"
        echo "Swap_Free: $(awk '/SwapFree/ {print $2}' /proc/meminfo || echo 0)"
    else
        MEM_SIZE=$(sysctl -n hw.memsize 2>/dev/null || echo 0)
        echo "Mem_Total: $((MEM_SIZE / 1024))"
        echo "Mem_Free: 0"
        echo "Mem_Available: 0"
        echo "Buffers: 0"
        echo "Cached: 0"
        echo "Swap_Total: 0"
        echo "Swap_Free: 0"
    fi
    if [ -f /proc/loadavg ]; then
        echo "Load: $(cut -d' ' -f1,2,3 /proc/loadavg)"
    else
        echo "Load: $(uptime | awk -F'load average' '{print $2}' | awk -F: '{print $NF}' | xargs)"
    fi
    echo "Processes: $(ps -ax 2>/dev/null | wc -l || ps -e 2>/dev/null | wc -l || echo 0)"
    if df -B1 / >/dev/null 2>&1; then
        echo "Disk: $(df -B1 / | tail -n 1 | awk '{print $(NF-4),$(NF-3)}')"
    else
        echo "Disk: $(df -k / | tail -n 1 | awk '{print $(NF-4)*1024,$(NF-3)*1024}')"
    fi
    if [ -f /proc/net/dev ]; then
        echo "Net_Dev: $(tail -n +3 /proc/net/dev | awk '{rx+=$2; tx+=$10} END {print rx, tx}')"
    else
        echo "Net_Dev: 0 0"
    fi
    if [ -f /proc/stat ]; then
        echo "CPU_Stat: $(grep -m1 '^cpu ' /proc/stat)"
    else
        echo "CPU_Stat: "
    fi
    """

    init(connection: SSHConnection) {
        self.connection = connection
        self.session = SSHSession()
        self.sftpService = SFTPService(session: self.session)
        self.sftpViewModel = SFTPViewModel(service: self.sftpService)

        let account = connection.keychainAccount
        if let stored = KeychainStore.loadPassword(account: account) {
            self.password = stored
            self.rememberPassword = true
        }

        self.usePublicKey = connection.usePublicKey
        if connection.usePublicKey {
            if let customKey = connection.keyPath, !customKey.isEmpty {
                self.keyPath = customKey
            } else if let defaultKey = connection.defaultKeyPath {
                self.keyPath = defaultKey
            }
        } else if self.password.isEmpty, let defaultKey = connection.defaultKeyPath {
            self.keyPath = defaultKey
        }
    }

    deinit {
        let activeSession = self.session
        Task.detached {
            await activeSession.disconnect()
        }
    }

    func connect() {
        guard status != .connected else { return }
        // Replace any in-flight connect attempt to avoid double-auth racing.
        connectTaskHolder.cancel()
        status = .connecting

        let auth = makeAuth()

        connectTaskHolder.task = Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await self.session.connect(host: self.connection.host, port: self.connection.port, username: self.connection.username, auth: auth)
                if Task.isCancelled { return }
                self.status = .connected
                self.handlePasswordPersistence(auth)
                self.appModel?.recordHistory(for: self.connection.id, isSuccess: true)
                self.startMonitoring()
                self.sftpViewModel.refresh()
            } catch let error as SSHError {
                if Task.isCancelled { return }
                switch error {
                case .hostKeyNotTrusted(let status):
                    self.hostKeyPrompt = HostKeyPrompt(host: self.connection.host, status: status)
                    self.trustHostKeyAndConnect()
                case .authFailed:
                    if case .password = auth, let defaultKey = self.connection.defaultKeyPath {
                        let fallbackAuth = SSHAuth.publicKey(path: defaultKey, passphrase: nil)
                        do {
                            _ = try await self.session.connect(host: self.connection.host, port: self.connection.port, username: self.connection.username, auth: fallbackAuth)
                            if Task.isCancelled { return }
                            self.status = .connected
                            self.appModel?.recordHistory(for: self.connection.id, isSuccess: true)
                            self.startMonitoring()
                            self.sftpViewModel.refresh()
                            return
                        } catch {
                            // Fallback auth failed
                        }
                    }
                    self.appModel?.recordHistory(for: self.connection.id, isSuccess: false)
                    self.status = .failed(error.localizedDescription)
                    self.lastErrorMessage = error.localizedDescription
                default:
                    self.appModel?.recordHistory(for: self.connection.id, isSuccess: false)
                    self.status = .failed(error.localizedDescription)
                    self.lastErrorMessage = error.localizedDescription
                }
            } catch {
                if Task.isCancelled { return }
                self.appModel?.recordHistory(for: self.connection.id, isSuccess: false)
                self.status = .failed(error.localizedDescription)
                self.lastErrorMessage = error.localizedDescription
            }
        }
    }

    func trustHostKeyAndConnect() {
        guard status != .connected else { return }
        connectTaskHolder.cancel()
        status = .connecting
        let auth = makeAuth()
        connectTaskHolder.task = Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await self.session.acceptHostKeyAndConnect(auth: auth)
                if Task.isCancelled { return }
                self.hostKeyPrompt = nil
                self.status = .connected
                self.handlePasswordPersistence(auth)
                self.appModel?.recordHistory(for: self.connection.id, isSuccess: true)
                self.startMonitoring()
            } catch let error as SSHError {
                if Task.isCancelled { return }
                if case .authFailed = error, case .password = auth, let defaultKey = self.connection.defaultKeyPath {
                    let fallbackAuth = SSHAuth.publicKey(path: defaultKey, passphrase: nil)
                    do {
                        _ = try await self.session.acceptHostKeyAndConnect(auth: fallbackAuth)
                        if Task.isCancelled { return }
                        self.hostKeyPrompt = nil
                        self.status = .connected
                        self.appModel?.recordHistory(for: self.connection.id, isSuccess: true)
                        self.startMonitoring()
                        self.sftpViewModel.refresh()
                        return
                    } catch {
                        // Fallback auth failed
                    }
                }
                self.appModel?.recordHistory(for: self.connection.id, isSuccess: false)
                self.status = .failed(error.localizedDescription)
                self.lastErrorMessage = error.localizedDescription
            } catch {
                if Task.isCancelled { return }
                self.appModel?.recordHistory(for: self.connection.id, isSuccess: false)
                self.status = .failed(error.localizedDescription)
                self.lastErrorMessage = error.localizedDescription
            }
        }
    }

    func disconnect() {
        monitorTaskHolder.cancel()
        connectTaskHolder.cancel()
        Task { [session] in
            await session.disconnect()
        }
        status = .idle
    }

    func startMonitoring() {
        monitorTaskHolder.cancel()
        monitorTaskHolder.task = Task { [weak self] in
            var prevCpuTicks: (user: UInt64, system: UInt64, idle: UInt64, total: UInt64)? = nil
            var prevNetBytes: (rx: UInt64, tx: UInt64)? = nil
            var lastPollTime = Date()
            
            while !Task.isCancelled {
                let params: (activeSession: SSHSession, script: String)? = {
                    guard let self else { return nil }
                    return (self.session, self.monitorScript)
                }()
                
                guard let (activeSession, script) = params else { break }
                
                do {
                    let output = try await activeSession.executeCommand(script)
                    if Task.isCancelled { break }
                    
                    let now = Date()
                    let timeInterval = now.timeIntervalSince(lastPollTime)
                    lastPollTime = now
                    
                    if let self {
                        self.parseMetrics(output, timeInterval: timeInterval, prevCpu: &prevCpuTicks, prevNet: &prevNetBytes)
                    } else {
                        break
                    }
                } catch {
                    print("Monitoring error: \(error.localizedDescription)")
                }
                
                do {
                    try await Task.sleep(nanoseconds: 3_000_000_000)
                } catch {
                    break
                }
            }
        }
    }

    func forceRefreshMetrics() {
        Task {
            do {
                let output = try await session.executeCommand(monitorScript)
                var prevCpuTicks: (user: UInt64, system: UInt64, idle: UInt64, total: UInt64)? = nil
                var prevNetBytes: (rx: UInt64, tx: UInt64)? = nil
                parseMetrics(output, timeInterval: 3.0, prevCpu: &prevCpuTicks, prevNet: &prevNetBytes)
            } catch {
                print("Force refresh failed: \(error.localizedDescription)")
            }
        }
    }

    private func parseMetrics(
        _ rawText: String,
        timeInterval: TimeInterval,
        prevCpu: inout (user: UInt64, system: UInt64, idle: UInt64, total: UInt64)?,
        prevNet: inout (rx: UInt64, tx: UInt64)?
    ) {
        var parsedValues: [String: String] = [:]
        let lines = rawText.components(separatedBy: .newlines)
        for line in lines {
            let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2 {
                parsedValues[parts[0]] = parts[1]
            }
        }
        
        var newMetrics = SystemMetrics()
        
        // OS Name
        if let os = parsedValues["OS"] {
            newMetrics.osName = os
        }
        
        // Uptime
        if let uptimeStr = parsedValues["Uptime"] {
            newMetrics.uptimeSeconds = Int(uptimeStr.trimmingCharacters(in: .decimalDigits.inverted)) ?? 0
        }
        
        // CPU Model
        if let cpuModel = parsedValues["CPU_Model"] {
            newMetrics.cpuModel = cpuModel
        }
        
        // CPU Cores
        if let cpuCoresStr = parsedValues["CPU_Cores"], let cores = Int(cpuCoresStr) {
            newMetrics.cpuCores = cores
        }
        
        // Processes
        if let procStr = parsedValues["Processes"], let count = Int(procStr) {
            newMetrics.processCount = count
        }
        
        // Load
        if let loadStr = parsedValues["Load"] {
            let cleanLoadStr = loadStr.replacingOccurrences(of: ",", with: " ")
            let components = cleanLoadStr.split(separator: " ").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            if components.count >= 3 {
                newMetrics.load1Min = components[0]
                newMetrics.load5Min = components[1]
                newMetrics.load15Min = components[2]
            }
        }
        
        // Memory Parsing (values in kB)
        let memTotalKb = UInt64(parsedValues["Mem_Total"] ?? "0") ?? 0
        let memFreeKb = UInt64(parsedValues["Mem_Free"] ?? "0") ?? 0
        let memAvailableKb = UInt64(parsedValues["Mem_Available"] ?? "0") ?? 0
        let buffersKb = UInt64(parsedValues["Buffers"] ?? "0") ?? 0
        let cachedKb = UInt64(parsedValues["Cached"] ?? "0") ?? 0
        
        newMetrics.memoryTotalBytes = memTotalKb * 1024
        if memAvailableKb > 0 {
            if memTotalKb > memAvailableKb {
                newMetrics.memoryUsedBytes = (memTotalKb - memAvailableKb) * 1024
            } else {
                newMetrics.memoryUsedBytes = 0
            }
        } else {
            let overhead = memFreeKb + buffersKb + cachedKb
            if memTotalKb > overhead {
                newMetrics.memoryUsedBytes = (memTotalKb - overhead) * 1024
            } else {
                newMetrics.memoryUsedBytes = 0
            }
        }
        
        // Swap Parsing (values in kB)
        let swapTotalKb = UInt64(parsedValues["Swap_Total"] ?? "0") ?? 0
        let swapFreeKb = UInt64(parsedValues["Swap_Free"] ?? "0") ?? 0
        newMetrics.swapTotalBytes = swapTotalKb * 1024
        if swapTotalKb >= swapFreeKb {
            newMetrics.swapUsedBytes = (swapTotalKb - swapFreeKb) * 1024
        } else {
            newMetrics.swapUsedBytes = 0
        }
        
        // Disk Parsing (Total, Used in Bytes)
        if let diskStr = parsedValues["Disk"] {
            let parts = diskStr.split(separator: " ").compactMap { UInt64($0) }
            if parts.count == 2 {
                newMetrics.diskTotalBytes = parts[0]
                newMetrics.diskUsedBytes = parts[1]
            }
        }
        
        // Network Speeds
        if let netDevStr = parsedValues["Net_Dev"] {
            let parts = netDevStr.split(separator: " ").compactMap { UInt64($0) }
            if parts.count == 2 {
                let currentRx = parts[0]
                let currentTx = parts[1]
                if let prev = prevNet {
                    let deltaRx = currentRx >= prev.rx ? currentRx - prev.rx : 0
                    let deltaTx = currentTx >= prev.tx ? currentTx - prev.tx : 0
                    if timeInterval > 0 {
                        newMetrics.networkRxSpeedBytes = Double(deltaRx) / timeInterval
                        newMetrics.networkTxSpeedBytes = Double(deltaTx) / timeInterval
                    } else {
                        newMetrics.networkRxSpeedBytes = 0
                        newMetrics.networkTxSpeedBytes = 0
                    }
                }
                prevNet = (currentRx, currentTx)
            }
        }
        
        // CPU Stat usage calculation
        if let cpuStatStr = parsedValues["CPU_Stat"] {
            let parts = cpuStatStr.split(separator: " ").dropFirst().compactMap { UInt64($0) }
            if parts.count >= 4 {
                // Fields: user, nice, system, idle, iowait, irq, softirq, steal
                let user = parts[0]
                let nice = parts[1]
                let system = parts[2]
                let idle = parts[3]
                let iowait = parts.count > 4 ? parts[4] : 0
                let irq = parts.count > 5 ? parts[5] : 0
                let softirq = parts.count > 6 ? parts[6] : 0
                let steal = parts.count > 7 ? parts[7] : 0
                
                let totalTicks = user &+ nice &+ system &+ idle &+ iowait &+ irq &+ softirq &+ steal
                let idleTicks = idle &+ iowait
                
                if let prev = prevCpu {
                    let diffTotal = totalTicks >= prev.total ? totalTicks - prev.total : 0
                    let diffIdle = idleTicks >= prev.idle ? idleTicks - prev.idle : 0
                    if diffTotal > 0, diffTotal >= diffIdle {
                        newMetrics.cpuUsage = Double(diffTotal - diffIdle) / Double(diffTotal) * 100.0
                    } else {
                        newMetrics.cpuUsage = 0.0
                    }
                }
                prevCpu = (user, system, idle, totalTicks)
            }
        }
        
        self.metrics = newMetrics
    }

    private func makeAuth() -> SSHAuth {
        if usePublicKey, !keyPath.isEmpty {
            let passphrase = keyPassphrase.isEmpty ? nil : keyPassphrase
            return .publicKey(path: keyPath, passphrase: passphrase)
        }
        if !password.isEmpty {
            return .password(password, remember: rememberPassword)
        }
        if !keyPath.isEmpty {
            let passphrase = keyPassphrase.isEmpty ? nil : keyPassphrase
            return .publicKey(path: keyPath, passphrase: passphrase)
        } else if let defaultKey = connection.defaultKeyPath {
            return .publicKey(path: defaultKey, passphrase: nil)
        }
        return .password(password, remember: rememberPassword)
    }

    private func handlePasswordPersistence(_ auth: SSHAuth) {
        if case .password(let pwd, let remember) = auth {
            let account = connection.keychainAccount
            if remember {
                KeychainStore.savePassword(pwd, account: account)
            } else {
                KeychainStore.deletePassword(account: account)
            }
        }
    }
}

final class TaskHolder: @unchecked Sendable {
    private let lock = NSLock()
    private var _task: Task<Void, Never>?
    
    var task: Task<Void, Never>? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _task
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _task = newValue
        }
    }
    
    func cancel() {
        lock.lock()
        let t = _task
        _task = nil
        lock.unlock()
        t?.cancel()
    }
    
    deinit {
        cancel()
    }
}
