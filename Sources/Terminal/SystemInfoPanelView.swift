import SwiftUI
import AppKit

@MainActor
struct SystemInfoPanelView: View {
    let connection: SSHConnection
    let metrics: SystemMetrics
    var onRefresh: @MainActor () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
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
            
            // Load, CPU
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "Load"))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.2f / %.2f / %.2f", metrics.load1Min, metrics.load5Min, metrics.load15Min))
                        .font(.system(size: 12, weight: .semibold))
                }
                Spacer()
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "CPU"))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        ProgressView(value: min(max(metrics.cpuUsage / 100.0, 0.0), 1.0))
                            .progressViewStyle(.linear)
                            .tint(.blue)
                            .frame(width: 80)
                        Text(String(format: "%.1f%%", metrics.cpuUsage))
                            .font(.system(size: 11, weight: .semibold))
                    }
                }
            }
            
            // Memory, Network
            HStack(alignment: .top) {
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
                        Text(String(format: "%.0f%%", memPercent * 100.0))
                            .font(.system(size: 11, weight: .semibold))
                    }
                    Text("\(formatBytes(metrics.memoryUsedBytes)) / \(formatBytes(metrics.memoryTotalBytes))")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "Network"))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.green)
                        Text("\(formatBytes(UInt64(metrics.networkRxSpeedBytes)))/s")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.blue)
                        Text("\(formatBytes(UInt64(metrics.networkTxSpeedBytes)))/s")
                            .font(.system(size: 11, weight: .semibold))
                    }
                }
            }
            
            // Swap, Processes
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "Swap"))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("\(formatBytes(metrics.swapUsedBytes)) / \(formatBytes(metrics.swapTotalBytes))")
                        .font(.system(size: 11, weight: .semibold))
                }
                Spacer()
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "Processes"))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("\(metrics.processCount)")
                        .font(.system(size: 12, weight: .semibold))
                }
                .frame(width: 120, alignment: .leading)
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
            
            VStack(alignment: .leading, spacing: 8) {
                specRow(title: String(localized: "OS"), value: metrics.osName)
                specRow(title: String(localized: "Uptime"), value: formatUptime(metrics.uptimeSeconds))
                specRow(title: String(localized: "CPU"), value: "\(metrics.cpuModel) (\(String(localized: "\(metrics.cpuCores) cores")))")
                specRow(title: String(localized: "Memory"), value: formatBytes(metrics.memoryTotalBytes))
                
                // Disk Row with progress
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "Disk"))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                    let diskPercent = metrics.diskTotalBytes > 0 ? Double(metrics.diskUsedBytes) / Double(metrics.diskTotalBytes) : 0.0
                    HStack(spacing: 8) {
                        ProgressView(value: min(max(diskPercent, 0.0), 1.0))
                            .progressViewStyle(.linear)
                            .tint(.blue)
                        Text(String(format: "%.0f%%", diskPercent * 100.0))
                            .font(.system(size: 11, weight: .semibold))
                    }
                    Text("\(formatBytes(metrics.diskUsedBytes)) / \(formatBytes(metrics.diskTotalBytes))")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
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

    private func specRow(title: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .leading)
            Text(value)
                .font(.system(size: 11, weight: .medium))
                .multilineTextAlignment(.leading)
            Spacer()
        }
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }

    private func formatUptime(_ seconds: Int) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day, .hour, .minute]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: TimeInterval(seconds)) ?? ""
    }
}
