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
            VStack(spacing: 16) {
                if case .failed(let errorMsg) = status {
                    VStack(alignment: .leading, spacing: 8) {
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
                    .cornerRadius(6)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.red.opacity(0.2), lineWidth: 1))
                }

                realTimeMonitorCard
                serverSpecsCard
                connectionHistoryCard
            }
            .padding()
        }
    }

    private var realTimeMonitorCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(String(localized: "Real-time Monitor"), systemImage: "chart.bar.fill")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                    Text(String(localized: "LIVE"))
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.green)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.green.opacity(0.15))
                .clipShape(Capsule())
            }
            
            Divider()
            
            // 使用原生 Grid 保持两列完美的左右对齐
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                // 第一行: Load, CPU
                GridRow {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(localized: "Load"))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text(String(format: String(localized: "%.2f / %.2f / %.2f"), metrics.load1Min, metrics.load5Min, metrics.load15Min))
                            .font(.system(size: 12, weight: .semibold))
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(localized: "CPU"))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            ProgressView(value: min(max(metrics.cpuUsage / 100.0, 0.0), 1.0))
                                .progressViewStyle(.linear)
                                .tint(.blue)
                                .frame(width: 80)
                            Text(metrics.cpuUsage / 100.0, format: .percent.precision(.fractionLength(1)))
                                .font(.system(size: 11, weight: .semibold))
                        }
                    }
                }
                
                // 第二行: Memory, Network
                GridRow {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(localized: "Memory"))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                        let memPercent = metrics.memoryTotalBytes > 0 ? Double(metrics.memoryUsedBytes) / Double(metrics.memoryTotalBytes) : 0.0
                        HStack(spacing: 8) {
                            ProgressView(value: min(max(memPercent, 0.0), 1.0))
                                .progressViewStyle(.linear)
                                .tint(.green)
                                .frame(width: 80)
                            Text(memPercent, format: .percent.precision(.fractionLength(0)))
                                .font(.system(size: 11, weight: .semibold))
                        }
                        Text(String(format: String(localized: "%@ / %@"), formatBytes(metrics.memoryUsedBytes), formatBytes(metrics.memoryTotalBytes)))
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(localized: "Network"))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.down")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.green)
                            Text(String(format: String(localized: "%@/s"), formatBytes(UInt64(metrics.networkRxSpeedBytes))))
                                .font(.system(size: 11, weight: .semibold))
                        }
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.blue)
                            Text(String(format: String(localized: "%@/s"), formatBytes(UInt64(metrics.networkTxSpeedBytes))))
                                .font(.system(size: 11, weight: .semibold))
                        }
                    }
                }
                
                // 第三行: Swap, Processes
                GridRow {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(localized: "Swap"))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text(String(format: String(localized: "%@ / %@"), formatBytes(metrics.swapUsedBytes), formatBytes(metrics.swapTotalBytes)))
                            .font(.system(size: 11, weight: .semibold))
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(localized: "Processes"))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text(metrics.processCount, format: .number)
                            .font(.system(size: 12, weight: .semibold))
                    }
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor).opacity(0.8))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 1)
        )
    }

    private var serverSpecsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(String(localized: "Server Specs"), systemImage: "info.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .help(String(localized: "Refresh Specs"))
            }
            
            Divider()
            
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
                GridRow {
                    Text(String(localized: "Disk"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 4) {
                        let diskPercent = metrics.diskTotalBytes > 0 ? Double(metrics.diskUsedBytes) / Double(metrics.diskTotalBytes) : 0.0
                        HStack(spacing: 8) {
                            ProgressView(value: min(max(diskPercent, 0.0), 1.0))
                                .progressViewStyle(.linear)
                                .tint(.blue)
                            Text(diskPercent, format: .percent.precision(.fractionLength(0)))
                                .font(.system(size: 11, weight: .semibold))
                        }
                        Text(String(format: String(localized: "%@ / %@"), formatBytes(metrics.diskUsedBytes), formatBytes(metrics.diskTotalBytes)))
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor).opacity(0.8))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 1)
        )
    }

    private var connectionHistoryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "Connection History"))
                .font(.system(size: 13, weight: .semibold))
            
            Divider()
            
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
                               .fill(entry.isSuccess ? Color.green : Color.red)
                               .frame(width: 6, height: 6)
                            
                            Text(entry.timestamp.formatted(date: .abbreviated, time: .shortened))
                                .font(.system(size: 11))
                            
                            Spacer()
                            
                            Text(entry.isSuccess ? String(localized: "Success") : String(localized: "Failed"))
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(entry.isSuccess ? .green : .red)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(entry.isSuccess ? Color.green.opacity(0.15) : Color.red.opacity(0.15))
                                .clipShape(Capsule())
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor).opacity(0.8))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 1)
        )
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        SystemInfoFormatters.byteFormatter.string(fromByteCount: Int64(bytes))
    }

    private func formatUptime(_ seconds: Int) -> String {
        SystemInfoFormatters.uptimeFormatter.string(from: TimeInterval(seconds)) ?? ""
    }
}

/// Heavy `Foundation` formatters are expensive to construct (locale lookup,
/// CFNumberFormatter cache, …). The system info card re-renders every 3s and
/// calls these helpers ~10 times per render — re-creating the formatters each
/// time was a measurable hotspot under Instruments.
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
