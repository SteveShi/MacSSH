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
        let envShell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        return (envShell as NSString).lastPathComponent
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
