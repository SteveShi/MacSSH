import SwiftUI

// MARK: - SSH Remote Terminal Status Bar

@MainActor
struct TerminalStatusBar: View {
    let connection: SSHConnection
    let status: TerminalSessionViewModel.Status
    let metrics: SystemMetrics
    let connectedAt: Date?
    var isDarkMode: Bool = true
    var isTerminalRunning: Bool = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0)) { context in
            HStack(spacing: 8) {
                // Left: Status dot + user@host + state/duration
                HStack(spacing: 6) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 5.5, height: 5.5)

                    Text("\(connection.username)@\(connection.host)")
                        .foregroundStyle(Color.secondary)

                    Text(stateText(now: context.date))
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                // Right: CPU / Mem / Disk / Clock
                if status == .connected {
                    Text("CPU \(cpuText)")
                        .foregroundStyle(.secondary)
                    separatorDot
                    Text("\(String(localized: "Memory")) \(memText)")
                        .foregroundStyle(.secondary)
                    separatorDot
                    Text("\(String(localized: "Disk")) \(diskText)")
                        .foregroundStyle(.secondary)
                    separatorDot
                }

                Text(context.date.formatted(date: .omitted, time: .standard))
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 11, design: .monospaced))
            .lineLimit(1)
            .padding(.horizontal, 14)
            .frame(height: 28)
            .background(
                Capsule()
                    .fill(isDarkMode ? Color(white: 0.12).opacity(0.92) : Color.white.opacity(0.88))
                    .overlay(
                        Capsule().stroke(
                            isDarkMode ? Color.white.opacity(0.08) : Color(red: 215.0 / 255.0, green: 210.0 / 255.0, blue: 200.0 / 255.0),
                            lineWidth: 0.8
                        )
                    )
                    .shadow(
                        color: isDarkMode ? Color.black.opacity(0.25) : Color.black.opacity(0.08),
                        radius: 6,
                        y: 2
                    )
            )
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 8)
    }

    // MARK: - Helpers

    private var separatorDot: some View {
        Text("·").foregroundStyle(.quaternary)
    }

    private var statusColor: Color {
        if isTerminalRunning {
            switch status {
            case .connected: Color(red: 0.2, green: 0.85, blue: 0.4)
            case .connecting: Color(red: 0.2, green: 0.85, blue: 0.4)
            case .failed: Color.orange
            case .idle: Color(red: 0.2, green: 0.85, blue: 0.4)
            }
        } else {
            switch status {
            case .connected: Color(red: 0.2, green: 0.85, blue: 0.4)
            case .connecting: Color.yellow
            case .failed: Color.red
            case .idle: Color.secondary.opacity(0.5)
            }
        }
    }

    private func stateText(now: Date) -> String {
        if isTerminalRunning {
            let duration: String
            if let start = connectedAt {
                duration = " \(durationString(from: start, to: now))"
            } else {
                duration = ""
            }

            switch status {
            case .connected:
                return "\(String(localized: "已连接"))\(duration)"
            case .connecting:
                return "\(String(localized: "已连接"))\(duration) (\(String(localized: "监控同步中…")))"
            case .failed(let reason):
                return "\(String(localized: "终端已连接"))\(duration) (\(String(localized: "监控未就绪")): \(reason))"
            case .idle:
                return "\(String(localized: "已连接"))\(duration)"
            }
        } else {
            switch status {
            case .idle: return String(localized: "未连接")
            case .connecting: return String(localized: "连接中…")
            case .connected:
                guard let start = connectedAt else { return String(localized: "已连接") }
                return "\(String(localized: "已连接")) \(durationString(from: start, to: now))"
            case .failed(let reason):
                return "\(String(localized: "连接失败")): \(reason)"
            }
        }
    }

    private var cpuText: String {
        if metrics.cpuUsage > 0 && metrics.cpuUsage < 1.0 {
            return String(format: "%.1f%%", metrics.cpuUsage)
        }
        return String(format: "%.0f%%", metrics.cpuUsage)
    }

    private var memText: String {
        guard metrics.memoryTotalBytes > 0 else { return "—" }
        let pct = Double(metrics.memoryUsedBytes) / Double(metrics.memoryTotalBytes) * 100
        return String(format: "%.0f%%", pct)
    }

    private var diskText: String {
        guard metrics.diskTotalBytes > 0 else { return "—" }
        let pct = Double(metrics.diskUsedBytes) / Double(metrics.diskTotalBytes) * 100
        return String(format: "%.0f%%", pct)
    }

    private func durationString(from start: Date, to now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
}

// MARK: - Local Terminal Status Bar (Berth Parity)

@MainActor
struct LocalTerminalStatusBar: View {
    let tab: LocalTerminalTab
    var isDarkMode: Bool = true

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0)) { context in
            HStack(spacing: 8) {
                // Left: Green dot + shell name + connected duration
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color(red: 0.2, green: 0.85, blue: 0.4))
                        .frame(width: 5.5, height: 5.5)

                    Text(shellName)
                        .foregroundStyle(Color.secondary)

                    if AppSettings().keepLocalSessionsAlive {
                        Image(systemName: "bolt.horizontal.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                            .help(String(localized: "Persistent session managed by macsshd"))
                    }

                    Text("\(String(localized: "已连接")) \(durationString(from: tab.connectedAt, to: context.date))")
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                // Right: Clock
                Text(context.date.formatted(date: .omitted, time: .standard))
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 11, design: .monospaced))
            .lineLimit(1)
            .padding(.horizontal, 14)
            .frame(height: 28)
            .background(
                Capsule()
                    .fill(isDarkMode ? Color(white: 0.12).opacity(0.92) : Color.white.opacity(0.88))
                    .overlay(
                        Capsule().stroke(
                            isDarkMode ? Color.white.opacity(0.08) : Color(red: 215.0 / 255.0, green: 210.0 / 255.0, blue: 200.0 / 255.0),
                            lineWidth: 0.8
                        )
                    )
                    .shadow(
                        color: isDarkMode ? Color.black.opacity(0.25) : Color.black.opacity(0.08),
                        radius: 6,
                        y: 2
                    )
            )
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 8)
    }

    private var shellName: String {
        LocalProcessMonitor.shared.processName(for: tab)
    }

    private func durationString(from start: Date, to now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
}

// MARK: - Asynchronous Local Process Monitor

/// Monitors the foreground process of local terminal tabs on a background thread.
/// Caches resolved names so the main thread (and SwiftUI TimelineView) is NEVER blocked
/// by `sysctl(KERN_PROC_ALL)` during keystrokes, command executions, or screen clears.
@MainActor
final class LocalProcessMonitor {
    static let shared = LocalProcessMonitor()

    private var cache: [UUID: String] = [:]
    private var lastQueryTime: [UUID: Date] = [:]
    private var inFlightQueries: Set<UUID> = []

    func processName(for tab: LocalTerminalTab) -> String {
        let id = tab.id
        let now = Date()

        // Return cached value if query was performed within the last 2 seconds.
        if let cached = cache[id], let lastTime = lastQueryTime[id], now.timeIntervalSince(lastTime) < 2.0 {
            return cached
        }

        // Trigger an asynchronous background query if not already in-flight.
        if !inFlightQueries.contains(id) {
            inFlightQueries.insert(id)
            let ptyPid = tab.surfaceView.ptyPID
            let connectedAt = tab.connectedAt
            let sessionKey = tab.id.uuidString
            let defaultShell = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh").lastPathComponent

            Task.detached(priority: .utility) {
                let resolved = Self.resolveForegroundProcess(ptyPid: ptyPid, connectedAt: connectedAt, sessionKey: sessionKey) ?? defaultShell
                await MainActor.run {
                    self.cache[id] = resolved
                    self.lastQueryTime[id] = Date()
                    self.inFlightQueries.remove(id)
                }
            }
        }

        if let cached = cache[id] {
            return cached
        }
        let envShell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        return URL(fileURLWithPath: envShell).lastPathComponent
    }

    private struct ProcEntry: Sendable {
        let pid: pid_t
        let ppid: pid_t
        let start: TimeInterval
        let name: String?
    }

    private nonisolated static func resolveForegroundProcess(ptyPid: pid_t?, connectedAt: Date, sessionKey: String? = nil) -> String? {
        let procs = allProcesses()
        guard !procs.isEmpty else { return nil }

        var current: ProcEntry?
        if let ptyPid, ptyPid > 0, let node = procs.first(where: { $0.pid == ptyPid }) {
            current = node
        } else {
            let tabStartTime = connectedAt.timeIntervalSince1970
            let myPid = getpid()
            current = procs
                .filter { $0.ppid == myPid }
                .min { abs($0.start - tabStartTime) < abs($1.start - tabStartTime) }
        }
        guard current != nil else { return nil }

        var depth = 0
        while depth < 16 {
            guard let newest = procs
                .filter({ $0.ppid == current!.pid })
                .max(by: { $0.start < $1.start }) else { break }
            current = newest
            depth += 1
        }
        guard let name = current?.name, !name.isEmpty else { return nil }

        if name == "macssh-cli", let sessionKey {
            if let response = try? UnixSocketWire.sendOneShotRequest(.listSessions, autostart: false),
               case .sessionList(let sessions) = response,
               let target = sessions.first(where: { $0.sessionKey == sessionKey }),
               !target.foregroundProcessName.isEmpty {
                return target.foregroundProcessName
            }
        }

        return name
    }

    private nonisolated static func allProcesses() -> [ProcEntry] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 0 else { return [] }
        let stride = MemoryLayout<kinfo_proc>.stride
        var count = size / stride + 16
        for _ in 0..<4 {
            var buffer = [kinfo_proc](repeating: kinfo_proc(), count: count)
            var newSize = count * stride
            guard sysctl(&mib, 3, &buffer, &newSize, nil, 0) == 0 else { return [] }
            let actual = newSize / stride
            if actual <= count {
                return buffer.prefix(actual).map { kp in
                    ProcEntry(
                        pid: pid_t(kp.kp_proc.p_pid),
                        ppid: pid_t(kp.kp_eproc.e_ppid),
                        start: TimeInterval(kp.kp_proc.p_starttime.tv_sec)
                            + TimeInterval(kp.kp_proc.p_starttime.tv_usec) / 1_000_000,
                        name: withUnsafeBytes(of: kp.kp_proc.p_comm) {
                            $0.baseAddress.map { String(cString: $0.assumingMemoryBound(to: CChar.self)) }
                        }
                    )
                }
            }
            count = actual + 16
        }
        return []
    }
}
