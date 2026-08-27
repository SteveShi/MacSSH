import SwiftUI
import AppKit

@MainActor
struct SystemInfoPanelView: View {
    let connection: SSHConnection
    let metrics: SystemMetrics
    let status: TerminalSessionViewModel.Status
    let lastErrorMessage: String
    var onRefresh: @MainActor () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if case .failed(let errorMsg) = status {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                            Text(String(localized: "Connection Failed"))
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.red)
                        }
                        Text(errorMsg)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.red.opacity(0.2), lineWidth: 1))
                }

                realTimeMonitorCard
                serverSpecsCard
                connectionHistoryCard
            }
            .padding(12)
        }
    }

    // MARK: - Real-time Monitor Card (Matching Image 2 Style 1:1)

    private var realTimeMonitorCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(String(localized: "Real-time Monitor"), systemImage: "chart.bar.fill")
                    .font(.system(size: 12.5, weight: .semibold))
                Spacer()
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color(red: 0.2, green: 0.85, blue: 0.4))
                        .frame(width: 5.5, height: 5.5)
                    Text(String(localized: "LIVE"))
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color(red: 0.2, green: 0.85, blue: 0.4))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color(red: 0.2, green: 0.85, blue: 0.4).opacity(0.12))
                .clipShape(Capsule())
            }

            Divider()
                .opacity(0.3)

            VStack(spacing: 12) {
                // 1. 内存 (Memory)
                let memTotalMB = metrics.memoryTotalBytes / 1024 / 1024
                let memUsedMB = metrics.memoryUsedBytes / 1024 / 1024
                let memPct = metrics.memoryTotalBytes > 0 ? Double(metrics.memoryUsedBytes) / Double(metrics.memoryTotalBytes) : 0.0
                MetricProgressRow(
                    title: String(localized: "内存"),
                    valueText: memTotalMB > 0 ? "\(memUsedMB) / \(memTotalMB) MB" : "—",
                    statusText: String(format: "%.0f%%", memPct * 100),
                    percent: memPct,
                    statusColor: Color(red: 0.2, green: 0.85, blue: 0.4)
                )

                // 2. 磁盘 / (Disk)
                let diskTotalGB = metrics.diskTotalBytes / 1024 / 1024 / 1024
                let diskUsedGB = metrics.diskUsedBytes / 1024 / 1024 / 1024
                let diskPct = metrics.diskTotalBytes > 0 ? Double(metrics.diskUsedBytes) / Double(metrics.diskTotalBytes) : 0.0
                MetricProgressRow(
                    title: String(localized: "磁盘 /"),
                    valueText: diskTotalGB > 0 ? "\(diskUsedGB)G/\(diskTotalGB)G" : "—",
                    statusText: String(format: "%.0f%%", diskPct * 100),
                    percent: diskPct,
                    statusColor: Color(red: 0.2, green: 0.85, blue: 0.4)
                )

                // 3. 负载 (Load)
                let cores = max(1, metrics.cpuCores)
                let loadPct = Double(metrics.load1Min) / Double(cores)
                MetricProgressRow(
                    title: String(localized: "负载"),
                    valueText: String(format: "%.2f  %.2f  %.2f", metrics.load1Min, metrics.load5Min, metrics.load15Min),
                    statusText: "\(cores) 核",
                    percent: loadPct,
                    statusColor: Color(red: 0.2, green: 0.85, blue: 0.4)
                )

                // 4. CPU (CPU Usage)
                let cpuPct = min(max(metrics.cpuUsage / 100.0, 0.0), 1.0)
                MetricProgressRow(
                    title: "CPU",
                    valueText: "",
                    statusText: String(format: "%.0f%%", metrics.cpuUsage),
                    percent: cpuPct,
                    statusColor: Color(red: 0.2, green: 0.85, blue: 0.4)
                )

                // 5. Swap (if present)
                if metrics.swapTotalBytes > 0 {
                    let swapUsedMB = metrics.swapUsedBytes / 1024 / 1024
                    let swapTotalMB = metrics.swapTotalBytes / 1024 / 1024
                    let swapPct = Double(metrics.swapUsedBytes) / Double(metrics.swapTotalBytes)
                    MetricProgressRow(
                        title: "Swap",
                        valueText: "\(swapUsedMB) / \(swapTotalMB) MB",
                        statusText: String(format: "%.0f%%", swapPct * 100),
                        percent: swapPct,
                        statusColor: Color(red: 0.2, green: 0.85, blue: 0.4)
                    )
                }

                // 6. Network & Processes footer row
                HStack(alignment: .center) {
                    HStack(spacing: 8) {
                        Text(String(localized: "网络"))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text("↓ \(formatBytes(UInt64(metrics.networkRxSpeedBytes)))/s")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Color(red: 0.2, green: 0.85, blue: 0.4))
                        Text("↑ \(formatBytes(UInt64(metrics.networkTxSpeedBytes)))/s")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Color(red: 0.3, green: 0.65, blue: 1.0))
                    }

                    Spacer()

                    HStack(spacing: 4) {
                        Text(String(localized: "进程"))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text("\(metrics.processCount)")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.primary)
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(14)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.8)
        )
    }

    // MARK: - Server Specs Card

    private var serverSpecsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(String(localized: "Server Specs"), systemImage: "info.circle.fill")
                    .font(.system(size: 12.5, weight: .semibold))
                Spacer()
                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .help(String(localized: "Refresh Specs"))
            }

            Divider()
                .opacity(0.3)

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    Text(String(localized: "OS"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(metrics.osName)
                        .font(.system(size: 11, weight: .medium))
                }
                GridRow {
                    Text(String(localized: "Uptime"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(formatUptime(metrics.uptimeSeconds))
                        .font(.system(size: 11, weight: .medium))
                }
                GridRow {
                    Text(String(localized: "CPU"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(String(format: String(localized: "%@ (%lld cores)"), metrics.cpuModel, Int64(metrics.cpuCores)))
                        .font(.system(size: 11, weight: .medium))
                }
                GridRow {
                    Text(String(localized: "Memory"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(formatBytes(metrics.memoryTotalBytes))
                        .font(.system(size: 11, weight: .medium))
                }
            }
        }
        .padding(14)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.8)
        )
    }

    // MARK: - Connection History Card

    private var connectionHistoryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "Connection History"))
                .font(.system(size: 12.5, weight: .semibold))

            Divider()
                .opacity(0.3)

            let entries = connection.history ?? []
            if entries.isEmpty {
                Text(String(localized: "No connection history."))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 8) {
                    ForEach(entries) { entry in
                        HStack {
                            Circle()
                               .fill(entry.isSuccess ? Color(red: 0.2, green: 0.85, blue: 0.4) : Color.red)
                               .frame(width: 6, height: 6)

                            Text(entry.timestamp.formatted(date: .abbreviated, time: .shortened))
                                .font(.system(size: 11))

                            Spacer()

                            Text(entry.isSuccess ? String(localized: "Success") : String(localized: "Failed"))
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(entry.isSuccess ? Color(red: 0.2, green: 0.85, blue: 0.4) : Color.red)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(entry.isSuccess ? Color.green.opacity(0.12) : Color.red.opacity(0.12))
                                .clipShape(Capsule())
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.8)
        )
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        SystemInfoFormatters.byteFormatter.string(fromByteCount: Int64(bytes))
    }

    private func formatUptime(_ seconds: Int) -> String {
        SystemInfoFormatters.uptimeFormatter.string(from: TimeInterval(seconds)) ?? ""
    }
}

// MARK: - Metric Progress Row (Image 2 Parity)

private struct MetricProgressRow: View {
    let title: String
    let valueText: String
    let statusText: String
    let percent: Double
    var statusColor: Color = Color(red: 0.2, green: 0.85, blue: 0.4)

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.primary)

                Spacer(minLength: 8)

                if !valueText.isEmpty {
                    Text(valueText)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(Color.secondary)
                }

                Text(statusText)
                    .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(statusColor)
            }

            // Full-width linear capsule progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.08))
                        .frame(height: 4)

                    Capsule()
                        .fill(statusColor)
                        .frame(width: max(0, min(geo.size.width, geo.size.width * CGFloat(min(max(percent, 0.0), 1.0)))), height: 4)
                        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: percent)
                }
            }
            .frame(height: 4)
        }
    }
}

@MainActor
private enum SystemInfoFormatters {
    static let byteFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useAll]
        f.countStyle = .file
        return f
    }()

    static let uptimeFormatter: DateComponentsFormatter = {
        let f = DateComponentsFormatter()
        f.allowedUnits = [.day, .hour, .minute]
        f.unitsStyle = .abbreviated
        return f
    }()
}
