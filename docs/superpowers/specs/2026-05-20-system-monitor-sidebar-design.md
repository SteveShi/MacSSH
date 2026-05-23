# 侧边栏系统监控与连接历史设计文档 (System Monitor & Connection History Design)

本设计文档旨在为 MacSSH 增加远程系统状态实时监控、服务器物理规格展示以及连接历史记录功能，并在右侧 Inspector 侧边栏中通过 Segmented Picker (分段选择器) 将这些参数与现有的 SFTP 文件管理用选项卡分离开来。

## 需求概述

1. **选项卡式侧边栏**：将右侧侧边栏分为“文件 (SFTP)”和“系统 (System)”两个选项卡。
2. **实时监控 (Real-time Monitor)**：展示 CPU、内存、负载、网络速率、交换区以及进程数量，每 3 秒刷新一次。
3. **系统规格 (Server Specs)**：展示 OS 版本与架构、CPU 型号、物理内存、硬盘空间、运行时间 (Uptime)。支持手动刷新。
4. **连接历史 (Connection History)**：本地持久化保存连接尝试的成功或失败记录，显示最近 10 次记录。

## 方案设计

### 1. 数据模型与持久化

#### 1.1 `ConnectionHistoryEntry`
用于定义每一次连接尝试的数据。
```swift
struct ConnectionHistoryEntry: Codable, Hashable, Sendable, Identifiable {
    var id = UUID()
    let timestamp: Date
    let isSuccess: Bool
}
```

#### 1.2 `SystemMetrics`
用于表示远程服务器的所有运行指标和硬件规格。
```swift
struct SystemMetrics: Sendable {
    // 实时监控 (Real-time Monitor)
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
    
    // 服务器规格 (Server Specs)
    var osName: String = "Unknown"
    var uptimeSeconds: Int = 0
    var cpuModel: String = "Unknown"
    var cpuCores: Int = 1
    var diskTotalBytes: UInt64 = 0
    var diskUsedBytes: UInt64 = 0
}
```

#### 1.3 `SSHConnection` 变更
添加 `history` 选项并默认设为空数组，从而自动支持 JSON 的序列化和反序列化持久化。
```swift
struct SSHConnection: Identifiable, Hashable, Codable {
    // ... 原有字段 ...
    var history: [ConnectionHistoryEntry]? = []
}
```

### 2. 后台命令执行与监控任务

#### 2.1 SSHSession 中增加非交互式 exec 执行方法
```swift
func executeCommand(_ command: String) async throws -> String
```
此方法在独立的 libssh2 channel 内执行 shell 指令，等待其执行完毕并读取返回的字符串。

#### 2.2 TerminalSessionViewModel 的周期性监控循环
在 `TerminalSessionViewModel` 成功连接时，会启动一个 `monitorTask`，在后台独立循环：
* 循环间隔为 3 秒。
* 发送下述复合 shell 脚本并对返回的 Key-Value 数据进行解析。
* 缓存前一次的 `/proc/stat` 计算 CPU 使用率。
* 缓存前一次的 `/proc/net/dev` 字节累计量，结合实际时间差计算出网络上传下载速度。
* 在标签页被断开或销毁时（`disconnect()` 或 `deinit`），取消此 `monitorTask` 任务。

#### 2.3 指标计算规则
* **CPU 使用率**：
  $\text{Total Ticks} = \text{user} + \text{nice} + \text{system} + \text{idle} + \text{iowait} + \text{irq} + \text{softirq} + \text{steal}$
  $\text{Idle Ticks} = \text{idle} + \text{iowait}$
  $\text{CPU Usage} = 1.0 - \frac{\Delta \text{Idle Ticks}}{\Delta \text{Total Ticks}}$
* **网络速率**：
  $\text{Rx Speed} = \frac{\Delta \text{Rx Bytes}}{\Delta t}$，$\text{Tx Speed} = \frac{\Delta \text{Tx Bytes}}{\Delta t}$
* **内存/磁盘使用率**：
  使用进度条直观显示已用与总量的比例。

### 3. UI 布局与多语言支持

#### 3.1 界面设计 (SystemInfoPanelView)
采用现代且符合 macOS 精致感的设计风格，由三块区域（VStack 卡片）组成，并在暗色和亮色模式下均有优秀表现：
* **实时监控区**：显示 Live 闪烁指示器，数据网格包含负载、CPU 使用率（进度条）、内存（进度条）、Swap 和网络流量速度。
* **物理规格区**：显示 OS 详细信息、运行时间、CPU 核心配置、磁盘使用情况（带进度条），右上角配有刷新按钮。
* **连接历史区**：列出最近 10 条连接成功的绿色指示点或失败的红色指示点记录。

#### 3.2 Inspector 选项卡集成 (`TerminalView.swift`)
使用原生的 `Picker` 控制 `InspectorTab` 状态，实现 `sftp` 与 `systemInfo` 的分段式切换。

#### 3.3 多语言本地化
在 `Localizable.xcstrings` 中加入所有相关界面的多语言字条（如“实时监控”、“服务器规格”、“连接历史”、“文件”、“系统”等），严格遵守不使用硬编码字符串原则。
