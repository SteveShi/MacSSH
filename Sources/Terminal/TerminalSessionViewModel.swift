import Foundation
import Observation

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
    
    // Rows/Cols are now managed by the Metal view, but we keep them for logic/API if needed
    var cols: UInt16 = 80
    var rows: UInt16 = 24

    var metrics: SystemMetrics = SystemMetrics()
    private let monitorTaskHolder = TaskHolder()
    var appModel: AppModel? = nil

    private let monitorScript = """
    cat << 'EOF'
    OS: $([ -f /etc/os-release ] && . /etc/os-release && echo "$PRETTY_NAME" || uname -s) ($(uname -m))
    Uptime: $(cat /proc/uptime 2>/dev/null | cut -d. -f1 || uptime | awk -F, '{print $1}')
    CPU_Model: $(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2 | xargs 2>/dev/null || sysctl -n machdep.cpu.brand_string 2>/dev/null || uname -m)
    CPU_Cores: $(nproc 2>/dev/null || grep -c '^processor' /proc/cpuinfo 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 1)
    Mem_Total: $(awk '/MemTotal/ {print $2}' /proc/meminfo 2>/dev/null || sysctl -n hw.memsize 2>/dev/null | awk '{print $1/1024}' || echo 0)
    Mem_Free: $(awk '/MemFree/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)
    Mem_Available: $(awk '/MemAvailable/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)
    Buffers: $(awk '/Buffers/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)
    Cached: $(awk '/^Cached/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)
    Swap_Total: $(awk '/SwapTotal/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)
    Swap_Free: $(awk '/SwapFree/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)
    Load: $(cat /proc/loadavg 2>/dev/null | cut -d' ' -f1,2,3 || sysctl -n vm.loadavg 2>/dev/null | awk '{print $2,$3,$4}' || uptime | awk -F'load average:' '{print $2}' | xargs)
    Processes: $(ps -ax 2>/dev/null | wc -l || ps -e 2>/dev/null | wc -l || echo 0)
    Disk: $(df -B1 / 2>/dev/null | awk 'NR==2 {print $2,$3}' || df -k / 2>/dev/null | awk 'NR==2 {print $2*1024,$3*1024}')
    Net_Dev: $(cat /proc/net/dev 2>/dev/null | tail -n +3 | awk '{rx+=$2; tx+=$10} END {print rx, tx}' || echo "0 0")
    CPU_Stat: $(cat /proc/stat 2>/dev/null | grep -m1 '^cpu ' || echo "")
    EOF
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
        status = .connecting

        let auth = makeAuth()

        Task {
            do {
                _ = try await session.connect(connection: connection, auth: auth)
                status = .connected
                handlePasswordPersistence(auth)
                appModel?.recordHistory(for: connection.id, isSuccess: true)
                startMonitoring()
                sftpViewModel.refresh()
            } catch let error as SSHError {
                appModel?.recordHistory(for: connection.id, isSuccess: false)
                switch error {
                case .hostKeyNotTrusted(let status):
                    hostKeyPrompt = HostKeyPrompt(host: connection.host, status: status)
                    self.status = .idle
                default:
                    self.status = .failed(error.localizedDescription)
                }
            } catch {
                appModel?.recordHistory(for: connection.id, isSuccess: false)
                status = .failed(error.localizedDescription)
                lastErrorMessage = error.localizedDescription
            }
        }
    }

    func trustHostKeyAndConnect() {
        guard status != .connected else { return }
        status = .connecting
        let auth = makeAuth()
        Task {
            do {
                _ = try await session.acceptHostKeyAndConnect(auth: auth)
                hostKeyPrompt = nil
                status = .connected
                handlePasswordPersistence(auth)
                appModel?.recordHistory(for: connection.id, isSuccess: true)
                startMonitoring()
            } catch {
                appModel?.recordHistory(for: connection.id, isSuccess: false)
                status = .failed(error.localizedDescription)
                lastErrorMessage = error.localizedDescription
            }
        }
    }

    func disconnect() {
        monitorTaskHolder.cancel()
        Task {
            await session.disconnect()
            status = .idle
        }
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
                
                let totalTicks = user + nice + system + idle + iowait + irq + softirq + steal
                let idleTicks = idle + iowait
                
                if let prev = prevCpu {
                    let diffTotal = totalTicks >= prev.total ? totalTicks - prev.total : 0
                    let diffIdle = idleTicks >= prev.idle ? idleTicks - prev.idle : 0
                    if diffTotal > 0 {
                        newMetrics.cpuUsage = Double(diffTotal - diffIdle) / Double(diffTotal) * 100.0
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
