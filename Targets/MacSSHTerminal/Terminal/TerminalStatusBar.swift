import SwiftUI

// MARK: - SSH Remote Terminal Status Bar

@MainActor
struct TerminalStatusBar: View {
    let connection: SSHConnection
    let status: TerminalSessionViewModel.Status
    let metrics: SystemMetrics
    let connectedAt: Date?

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
                    .fill(Color(white: 0.12).opacity(0.92))
                    .overlay(Capsule().stroke(Color.white.opacity(0.08), lineWidth: 0.8))
                    .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
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
        switch status {
        case .connected: Color(red: 0.2, green: 0.85, blue: 0.4)
        case .connecting: Color.yellow
        case .failed: Color.red
        case .idle: Color.secondary.opacity(0.5)
        }
    }

    private func stateText(now: Date) -> String {
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
                    .fill(Color(white: 0.12).opacity(0.92))
                    .overlay(Capsule().stroke(Color.white.opacity(0.08), lineWidth: 0.8))
                    .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
            )
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 8)
    }

    private var shellName: String {
        // Locate the tab's shell either by the surface-reported PTY pid
        // (MactermKit ghostty_surface_pid) or by start-time matching, then
        // walk down to the foreground command (e.g. zsh -> bash -> vim).
        if let name = Self.foregroundProcessName(ptyPid: tab.surfaceView.ptyPID, tab: tab) {
            return name
        }
        // Last resort: the user's default shell.
        let envShell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        return (envShell as NSString).lastPathComponent
    }

    private struct ProcEntry {
        let pid: pid_t
        let ppid: pid_t
        let start: TimeInterval
        let name: String?
    }

    /// Resolves the foreground command for a tab.
    /// - If `ptyPid` is known, the walk starts there (exact, no guessing).
    /// - Otherwise the direct child of this app whose start time is closest
    ///   to the tab's `connectedAt` is used (each tab spawns exactly one PTY
    ///   child).
    ///
    /// Child enumeration uses a sysctl KERN_PROC_ALL snapshot: newer macOS
    /// releases no longer report other processes' children through
    /// `proc_listchildpids` (it returns an empty list even for live direct
    /// children of the caller), so the targeted libproc walk silently broke.
    private static func foregroundProcessName(ptyPid: pid_t?, tab: LocalTerminalTab) -> String? {
        let procs = allProcesses()
        guard !procs.isEmpty else { return nil }

        var current: ProcEntry?
        if let ptyPid, ptyPid > 0, let node = procs.first(where: { $0.pid == ptyPid }) {
            current = node
        } else {
            let tabStartTime = tab.connectedAt.timeIntervalSince1970
            current = procs
                .filter { $0.ppid == getpid() }
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
        return name
    }

    /// One sysctl snapshot of every process on the system with parent pid,
    /// start time and command name. This is what the working pre-2.1.0
    /// detection used; libproc's child-listing API is a no-op on macOS 27.
    private static func allProcesses() -> [ProcEntry] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 0 else { return [] }
        let stride = MemoryLayout<kinfo_proc>.stride
        var count = size / stride + 16
        // Retry a few times: processes may appear between the size query and
        // the data query, which makes sysctl fail with ENOMEM.
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
