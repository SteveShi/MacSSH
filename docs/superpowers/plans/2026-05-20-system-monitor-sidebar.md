# 侧边栏系统监控与连接历史实现计划 (System Monitor & Connection History Implementation Plan)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在右侧侧边栏中增加分段选项卡以分离 SFTP 文件和系统监控/物理规格/连接历史，并通过后台 SSH 自动命令轮询获取实时硬件状态并持久化连接历史。

**Architecture:** 
1. 在 `SSHConnection` 中添加 `history` 字段，并在 `AppModel` 中提供操作 API 以持久化存储连接历史记录。
2. 在 `SSHSession` actor 内实现非交互式 `executeCommand` 方法以运行轻量级 exec 命令通道。
3. 在 `TerminalSessionViewModel` 中开启每 3 秒一次的监控查询循环任务，解析 Key-Value 格式输出，计算 CPU/网速并管理生命周期。
4. 在右侧侧边栏 (Inspector) 顶部使用 Segmented Picker 原生分段选择器切换 SFTP 视图和全新的 `SystemInfoPanelView` 视图。

**Tech Stack:** Swift 6.0, SwiftUI, libssh2, Xcode 17, macOS 15+

---

### Task 1: 历史记录数据模型与持久化处理

**Files:**
- Modify: `Sources/Models/SSHConnection.swift`
- Modify: `Sources/App/AppModel.swift`
- Verification: 编译应用并检查无类型编译错误。

- [ ] **Step 1: 定义 `ConnectionHistoryEntry` 并修改 `SSHConnection`**
  
  在 `Sources/Models/SSHConnection.swift` 的末尾添加 `ConnectionHistoryEntry` 结构体，并在 `SSHConnection` 中增加历史记录数组：
  
  ```swift
  struct ConnectionHistoryEntry: Codable, Hashable, Sendable, Identifiable {
      var id = UUID()
      let timestamp: Date
      let isSuccess: Bool
  }
  ```
  
  修改 `SSHConnection` 结构体，添加属性：
  ```swift
  var history: [ConnectionHistoryEntry]? = []
  ```
  同时需要相应修改 `init` 方法提供默认值：
  ```swift
  init(id: UUID = UUID(), name: String, host: String, port: Int, username: String, keyPath: String? = nil, usePublicKey: Bool = false, history: [ConnectionHistoryEntry]? = []) {
      self.id = id
      self.name = name
      self.host = host
      self.port = port
      self.username = username
      self.keyPath = keyPath
      self.usePublicKey = usePublicKey
      self.history = history
  }
  ```

- [ ] **Step 2: 在 `AppModel` 中实现添加历史记录的接口**
  
  在 `Sources/App/AppModel.swift` 中添加 `recordHistory` 方法，用于添加连接状态并限制历史条数（最多 10 条）：
  
  ```swift
  func recordHistory(for connectionID: SSHConnection.ID, isSuccess: Bool) {
      guard let index = connections.firstIndex(where: { $0.id == connectionID }) else { return }
      var currentHistory = connections[index].history ?? []
      let newEntry = ConnectionHistoryEntry(timestamp: Date(), isSuccess: isSuccess)
      currentHistory.insert(newEntry, at: 0)
      if currentHistory.count > 10 {
          currentHistory = Array(currentHistory.prefix(10))
      }
      connections[index].history = currentHistory
      persist()
  }
  ```

- [ ] **Step 3: 运行编译以验证基本模型可用**
  
  运行：`xcodebuild -scheme MacSSH -configuration Debug -sdk macosx build`
  预期：BUILD SUCCEEDED

- [ ] **Step 4: 提交代码变更**
  
  ```bash
  git add Sources/Models/SSHConnection.swift Sources/App/AppModel.swift
  git commit -m "feat: add ConnectionHistoryEntry model and AppModel persistence integration"
  ```

---

### Task 2: 实现 SSHSession 命令行执行通道

**Files:**
- Modify: `Sources/SSH/SSHSession.swift`
- Verification: 编译应用并检查编译正确性。

- [ ] **Step 1: 在 `SSHSession` actor 中添加 `executeCommand` 方法**
  
  在 `Sources/SSH/SSHSession.swift` 中添加新方法，使用 libssh2 在单独的会话 channel 中执行 shell 命令并返回字符输出：
  
  ```swift
  func executeCommand(_ command: String) async throws -> String {
      try await withRawSession { sessionPtr in
          guard let channel = libssh2_channel_open_ex(
              sessionPtr,
              "session",
              UInt32("session".utf8.count),
              2 * 1024 * 1024,
              32_768,
              nil,
              0
          ) else {
              throw SSHError.channelOpenFailed
          }
          
          let rc = libssh2_channel_process_startup(
              channel,
              "exec",
              UInt32("exec".utf8.count),
              command,
              UInt32(command.utf8.count)
          )
          guard rc == 0 else {
              libssh2_channel_free(channel)
              throw SSHError.shellFailed(rc)
          }
          
          var resultData = Data()
          var buffer = [UInt8](repeating: 0, count: 4096)
          while true {
              let bytesRead = buffer.withUnsafeMutableBytes { rawBuffer in
                  libssh2_channel_read_ex(channel, 0, rawBuffer.bindMemory(to: Int8.self).baseAddress, rawBuffer.count)
              }
              if bytesRead > 0 {
                  resultData.append(buffer, count: bytesRead)
              } else if bytesRead == 0 {
                  break
              } else if bytesRead == Int(LIBSSH2_ERROR_EAGAIN) {
                  try? await Task.sleep(nanoseconds: 10_000_000)
                  continue
              } else {
                  break
              }
          }
          
          libssh2_channel_send_eof(channel)
          libssh2_channel_close(channel)
          libssh2_channel_free(channel)
          
          return String(decoding: resultData, as: UTF8.self)
      }
  }
  ```

- [ ] **Step 2: 运行编译以验证 SSHSession 接口代码**
  
  运行：`xcodebuild -scheme MacSSH -configuration Debug -sdk macosx build`
  预期：BUILD SUCCEEDED

- [ ] **Step 3: 提交代码变更**
  
  ```bash
  git add Sources/SSH/SSHSession.swift
  git commit -m "feat: add executeCommand API to SSHSession actor"
  ```

---

### Task 3: 周期性查询与指标解析机制

**Files:**
- Create: `Sources/Models/SystemMetrics.swift`
- Modify: `Sources/Terminal/TerminalSessionViewModel.swift`
- Verification: 编译应用并检查类型与周期性任务逻辑。

- [ ] **Step 1: 创建 `SystemMetrics` 指标模型**
  
  新建文件 `Sources/Models/SystemMetrics.swift`，内容如下：
  
  ```swift
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
  ```

- [ ] **Step 2: 在 `TerminalSessionViewModel.swift` 中增加相关属性和方法**
  
  在 `TerminalSessionViewModel` 中增加以下属性：
  ```swift
  var metrics: SystemMetrics = SystemMetrics()
  private var monitorTask: Task<Void, Never>? = nil
  var appModel: AppModel? = nil // 为了调用 recordHistory 写入连接历史
  ```
  
  实现周期性检测的 shell 脚本常量及获取任务：
  ```swift
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
  
  func startMonitoring() {
      monitorTask?.cancel()
      monitorTask = Task {
          var prevCpuTicks: (user: UInt64, system: UInt64, idle: UInt64, total: UInt64)? = nil
          var prevNetBytes: (rx: UInt64, tx: UInt64)? = nil
          var lastPollTime = Date()
          
          while !Task.isCancelled {
              do {
                  let output = try await session.executeCommand(monitorScript)
                  if Task.isCancelled { break }
                  
                  let now = Date()
                  let timeInterval = now.timeIntervalSince(lastPollTime)
                  lastPollTime = now
                  
                  await parseMetrics(output, timeInterval: timeInterval, prevCpu: &prevCpuTicks, prevNet: &prevNetBytes)
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
              await parseMetrics(output, timeInterval: 3.0, prevCpu: &prevCpuTicks, prevNet: &prevNetBytes)
          } catch {
              print("Force refresh failed: \(error.localizedDescription)")
          }
      }
  }
  ```

- [ ] **Step 3: 实现 `parseMetrics` 解析方法**
  
  在 `TerminalSessionViewModel.swift` 的主作用域中实现 Key-Value 解析和科学计算逻辑：
  
  ```swift
  private func parseMetrics(
      _ rawText: String,
      timeInterval: TimeInterval,
      prevCpu: inout (user: UInt64, system: UInt64, idle: UInt64, total: UInt64)?,
      prevNet: inout (rx: UInt64, tx: UInt64)?
  ) async {
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
          let components = loadStr.split(separator: " ").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
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
          newMetrics.memoryUsedBytes = (memTotalKb - memAvailableKb) * 1024
      } else if memTotalKb > memFreeKb {
          let usedKb = memTotalKb - memFreeKb - buffersKb - cachedKb
          newMetrics.memoryUsedBytes = usedKb * 1024
      }
      
      // Swap Parsing (values in kB)
      let swapTotalKb = UInt64(parsedValues["Swap_Total"] ?? "0") ?? 0
      let swapFreeKb = UInt64(parsedValues["Swap_Free"] ?? "0") ?? 0
      newMetrics.swapTotalBytes = swapTotalKb * 1024
      if swapTotalKb >= swapFreeKb {
          newMetrics.swapUsedBytes = (swapTotalKb - swapFreeKb) * 1024
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
                  newMetrics.networkRxSpeedBytes = Double(deltaRx) / timeInterval
                  newMetrics.networkTxSpeedBytes = Double(deltaTx) / timeInterval
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
  ```

- [ ] **Step 4: 在连接状态转换时挂接历史记录和监控任务**
  
  修改 `TerminalSessionViewModel.swift` 中的 `connect()`（约 73 行起）及 `trustHostKeyAndConnect()`（约 98 行起），确保连接成功时调用 `recordHistory(..., isSuccess: true)` 和 `startMonitoring()`；连接失败时调用 `recordHistory(..., isSuccess: false)`。
  同时，在 `disconnect()` 中添加 `monitorTask?.cancel(); monitorTask = nil`；在 `deinit` 中取消任务。
  
  例如在 `connect()` 方法中：
  ```swift
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
          // ... 其它处理 ...
      } catch {
          appModel?.recordHistory(for: connection.id, isSuccess: false)
          // ...
      }
  }
  ```
  在 `TerminalView.swift` 构造主 View Model 时，将 `appModel` 引用传入 `TerminalSessionViewModel`。

- [ ] **Step 5: 运行编译以验证生命周期与解析逻辑**
  
  运行：`xcodebuild -scheme MacSSH -configuration Debug -sdk macosx build`
  预期：BUILD SUCCEEDED

- [ ] **Step 6: 提交代码变更**
  
  ```bash
  git add Sources/Models/SystemMetrics.swift Sources/Terminal/TerminalSessionViewModel.swift
  git commit -m "feat: implement SystemMetrics parsing and background loop in TerminalSessionViewModel"
  ```

---

### Task 4: 创建系统监控 UI 面板

**Files:**
- Create: `Sources/Terminal/SystemInfoPanelView.swift`
- Verification: 编译应用并验证 SwiftUI 视图代码无误。

- [ ] **Step 1: 新建 `SystemInfoPanelView.swift` 视图代码**
  
  创建文件 `Sources/Terminal/SystemInfoPanelView.swift`，内容如下：
  
  ```swift
  import SwiftUI
  
  struct SystemInfoPanelView: View {
      let connection: SSHConnection
      let metrics: SystemMetrics
      var onRefresh: () -> Void
  
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
                  specRow(title: String(localized: "CPU"), value: "\(metrics.cpuModel) (\(metrics.cpuCores) cores)")
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
          let kb = Double(bytes) / 1024.0
          let mb = kb / 1024.0
          let gb = mb / 1024.0
          if gb >= 1.0 {
              return String(format: "%.2f GB", gb)
          } else if mb >= 1.0 {
              return String(format: "%.1f MB", mb)
          } else if kb >= 1.0 {
              return String(format: "%.0f KB", kb)
          } else {
              return "\(bytes) Bytes"
          }
      }
  
      private func formatUptime(_ seconds: Int) -> String {
          let days = seconds / 86400
          let hours = (seconds % 86400) / 3600
          let minutes = (seconds % 3600) / 60
          if days > 0 {
              return "\(days)d \(hours)h"
          } else if hours > 0 {
              return "\(hours)h \(minutes)m"
          } else {
              return "\(minutes)m"
          }
      }
  }
  ```

- [ ] **Step 2: 运行编译以验证 Panel UI**
  
  运行：`xcodebuild -scheme MacSSH -configuration Debug -sdk macosx build`
  预期：BUILD SUCCEEDED

- [ ] **Step 3: 提交代码变更**
  
  ```bash
  git add Sources/Terminal/SystemInfoPanelView.swift
  git commit -m "feat: add SystemInfoPanelView layout cards"
  ```

---

### Task 5: 侧边栏多选项卡切换集成

**Files:**
- Modify: `Sources/Terminal/TerminalView.swift`
- Verification: 编译应用。

- [ ] **Step 1: 在 `TerminalView.swift` 中增加 `InspectorTab` 并改造 `.inspector` 绑定**
  
  在 `TerminalView.swift` 中，添加一个 `@State` 跟踪当前选项卡，并将 `.inspector` 部分改造为 Segmented Picker + 分发渲染。
  
  在 `TerminalView` 结构体顶部（第 9 行之后）添加：
  ```swift
  @State private var inspectorTab: InspectorTab = .sftp
  
  enum InspectorTab: String, CaseIterable, Identifiable {
      case sftp
      case systemInfo
      
      var id: String { rawValue }
  }
  ```
  
  修改初始化 model（约 18 行起），挂接 `appModel`：
  ```swift
  private var model: TerminalSessionViewModel {
      if let existing = tab.terminalModel {
          existing.appModel = appModel
          return existing
      }
      let newModel = TerminalSessionViewModel(connection: tab.connection)
      newModel.appModel = appModel
      tab.terminalModel = newModel
      return newModel
  }
  ```
  
  替换 `.inspector` 部分（约 72-74 行）：
  ```swift
  .inspector(isPresented: $showSftp) {
      VStack(spacing: 0) {
          Picker("", selection: $inspectorTab) {
              Text(String(localized: "Files", comment: "SFTP tab title")).tag(InspectorTab.sftp)
              Text(String(localized: "System", comment: "System monitor tab title")).tag(InspectorTab.systemInfo)
          }
          .pickerStyle(.segmented)
          .padding()
          
          Divider()
          
          switch inspectorTab {
          case .sftp:
              SFTPPanelView(model: model.sftpViewModel)
          case .systemInfo:
              SystemInfoPanelView(connection: tab.connection, metrics: model.metrics) {
                  model.forceRefreshMetrics()
              }
          }
      }
      .frame(minWidth: 280, idealWidth: 340)
  }
  ```

- [ ] **Step 2: 运行编译以验证 Tab 集成效果**
  
  运行：`xcodebuild -scheme MacSSH -configuration Debug -sdk macosx build`
  预期：BUILD SUCCEEDED

- [ ] **Step 3: 提交代码变更**
  
  ```bash
  git add Sources/Terminal/TerminalView.swift
  git commit -m "feat: integrate Picker and SystemInfoPanelView inside TerminalView inspector"
  ```

---

### Task 6: 更新多语言资源包

**Files:**
- Modify: `Sources/App/Localizable.xcstrings`
- Verification: 编译应用并测试是否符合 Localizable 规范。

- [ ] **Step 1: 在 String Catalog 中写入新增 UI 字条的本地化键值对**
  
  修改 `Sources/App/Localizable.xcstrings`。我们需要将下列英文与中文键值对安全地添加到 JSON 的 "strings" 对象下。
  新增词条包括：
  - `Files` -> 中文 "文件"
  - `System` -> 中文 "系统"
  - `Real-time Monitor` -> 中文 "实时监控"
  - `Server Specs` -> 中文 "服务器规格"
  - `Connection History` -> 中文 "连接历史"
  - `OS` -> 中文 "系统"
  - `CPU` -> 中文 "CPU"
  - `Memory` -> 中文 "内存"
  - `Disk` -> 中文 "磁盘"
  - `Swap` -> 中文 "交换区"
  - `Network` -> 中文 "网络"
  - `Processes` -> 中文 "进程"
  - `LIVE` -> 中文 "实时"
  - `Refresh Specs` -> 中文 "刷新物理规格"
  - `No connection history.` -> 中文 "暂无连接历史记录。"
  - `Success` -> 中文 "成功"
  - `Failed` -> 中文 "失败"
  - `Load` -> 中文 "负载"
  - `Uptime` -> 中文 "运行时间"

- [ ] **Step 2: 最终完整编译测试**
  
  运行：`xcodebuild -scheme MacSSH -configuration Debug -sdk macosx build`
  预期：BUILD SUCCEEDED

- [ ] **Step 3: 提交本地化代码变更**
  
  ```bash
  git add Sources/App/Localizable.xcstrings
  git commit -m "loc: add system monitor and connections history translations"
  ```
