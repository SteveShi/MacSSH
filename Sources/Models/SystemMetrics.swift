import Foundation

struct SystemMetrics: Sendable {
    var load1Min: Double = 0.0
    var load5Min: Double = 0.0
    var load15Min: Double = 0.0
    var cpuUsage: Double = 0.0
    var memoryTotalBytes: UInt64 = 0
    var memoryUsedBytes: UInt64 = 0
    var swapTotalBytes: UInt64 = 0
    var swapUsedBytes: UInt64 = 0
    var networkRxSpeedBytes: Double = 0.0
    var networkTxSpeedBytes: Double = 0.0
    var processCount: Int = 0
    
    var osName: String = "Unknown"
    var uptimeSeconds: Int = 0
    var cpuModel: String = "Unknown"
    var cpuCores: Int = 1
    var diskTotalBytes: UInt64 = 0
    var diskUsedBytes: UInt64 = 0
}
