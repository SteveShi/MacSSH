# Changelog

All notable changes to this project will be documented in this file.

## [1.5.0] - 2026-05-20

### Added
- Added a segmented Picker tab control in the inspector sidebar, integrating the SFTP panel and the new Real-time System Monitor panel.
- Implemented a Real-time System Monitor panel that displays remote CPU usage, memory, disk, network RX/TX bandwidth, uptime, and system specifications.
- Added comprehensive Chinese (Simplified) translation support for the System Monitor dashboard.

### Changed
- Refactored the inspector sidebar to support user-adjustable resizable width, ranging between 280 and 600 pixels.

### Fixed
- Fixed the monitoring script evaluating as literal text by removing the nested shell Here-Doc `cat << 'EOF'` structure.
- Fixed a potential arithmetic overflow/underflow crash during CPU ticks subtraction under CPU core frequency scaling or load fluctuations.

---

### Chinese
### 新增
- 侧边栏集成了分段式 Picker 标签切换控件，无缝整合 SFTP 面板和全新的系统实时监控面板。
- 引入服务器系统实时监控面板，能够动态收集并呈现远程主机的 CPU 占用率、内存/SWAP 占用、磁盘用量、实时网速吞吐、运行时间及系统型号规格等核心指标。
- 完成了系统监控面板所有界面文本的简体中文国际化适配。

### 变更
- 重构了侧边栏的宽度调整逻辑，允许用户自由拖动分割线以 280 至 600 像素范围缩放侧边栏。

### 修复
- 修复监控脚本因 nested Here-Doc `cat << 'EOF'` 机制导致以字面量形式输出命令原文而非执行结果的 Bug。
- 修复了在远程主机 CPU 滴答数（ticks）数据偏差或频率变动时，计算 tick 减法差值可能导致 Swift 触发算术下溢崩溃的问题。

---

## [1.1.0] - 2026-05-16

### Added
- Rebuilt the embedded Ghostty terminal dependency from the latest upstream source and refreshed the bundled macOS library products.

### Changed
- Updated the Ghostty build helper to use the official Zig 0.15.2 toolchain requirement and copy the current upstream artifact layout.
- Updated the application bundle identifier to `com.steveshi.macssh`.

### Fixed
- Fixed saved-password SSH sessions becoming unresponsive after login by handing terminal control back to the interactive SSH process after authentication.
- Removed stale temporary SSH password handoff files and made new handoff files clean themselves up after launch.

---

### Chinese
### 新增
- 基于最新上游源码重新编译内置 Ghostty 终端依赖，并刷新随应用打包的 macOS 库产物。

### 变更
- 更新 Ghostty 构建辅助脚本，遵循官方 Zig 0.15.2 工具链要求，并复制当前上游产物布局。
- 将应用 Bundle Identifier 更新为 `com.steveshi.macssh`。

### 修复
- 修复保存密码的 SSH 会话在登录后运行命令无响应的问题，认证完成后会将终端控制权交还给交互式 SSH 进程。
- 清理旧的 SSH 密码交接临时文件，并让新的交接文件在启动后自动删除。

---

## [1.0.0] - 2026-03-29

### Added
- Integrated Sparkle update framework for automated in-app updates.
- Added "Check for Updates..." to the application menu.
- Updated application version to 1.0.0 for the first official stable release.

---

### Chinese
### 新增
- 集成了 Sparkle 更新框架，支持应用内自动检查更新。
- 在应用菜单中添加了“检查更新...”选项。
- 将应用程序版本更新至 1.0.0，作为首个正式稳定版发布。

---

## [0.1.0] - 2026-03-28

### Added
- **Backup & Restore**: Added a new "Data" tab in Settings to export all SSH connection data to a JSON file and import it back.
- **Improved Connection Controls**: Added explicit "Connect" and "Disconnect" buttons to the terminal toolbar for better visibility and control.

### Changed
- **Liquid Glass UI**: Refined the local terminal tab selection style with a modern, clean "Liquid Glass" frosted material effect (no glow or shadows).
- **Tab Bar Relocation**: Moved local terminal tabs out of the title bar to a dedicated tab bar below the toolbar, eliminating the common "collapsing menu" (>>) issue.
- **SSH Workflow**: Simplified SSH session management by removing internal tabs, focusing on a 1:1 relationship between sidebar connections and terminal sessions.
- **Streamlined Toolbar**: Simplified the title bar and sidebar toolbars to provide a cleaner macOS-native experience.

### Fixed
- Fixed a fatal crash in the "Tab" menu caused by index-based access during connection state changes.
- Fixed the "ugly blue frame" selection indicator in the local terminal tabs.
- Moved backup/import/export features from the sidebar to the Settings window for better organization.
- Resolved an issue where local terminal tabs would remain visible when switching to an SSH connection.

---

## [0.1.0] - 2026-03-28

### 新增
- **备份与恢复**：在设置中新增“数据”选项卡，支持将所有 SSH 连接数据导出为 JSON 文件并在需要时导入。
- **改进的连接控制**：在终端工具栏中添加了显式的“连接”和“断开”按钮，提升了操作的可视性和便捷性。

### 变更
- **Liquid Glass UI**：优化了本地终端标签页的选中样式，采用干净、简约的“Liquid Glass”磨砂玻璃特效（取消了蓝色发光和阴影效果）。
- **标签栏重构**：将本地终端标签页从标题栏移至下方的专门标签栏中，彻底解决了标题栏按钮溢出（>>）的问题。
- **SSH 工作流**：移除了 SSH 的内部标签页，使其与侧边栏的连接项保持 1:1 的清晰关系。
- **精简工具栏**：简化了标题栏和侧边栏工具栏，提供了更清爽的原生 macOS 体验。

### 修复
- 修复了“标签”菜单由于在连接状态切换期间使用索引访问导致的严重崩溃。
- 修复了本地终端标签页中“丑陋的蓝色边框”选中指示器。
- 将备份/导入/导出功能从侧边栏移动到设置窗口，使界面组织更合理。
- 解决了切换到 SSH 连接时本地终端标签页仍保持可见的问题。

---

## [0.0.3] - 2026-03-24

### Fixed
- Terminal scroll direction now correctly follows macOS Natural Scrolling preference.
- Terminal content truncation: added a deferred size update so the PTY receives the correct column count after layout completes.
- Removed redundant "Native Ghostty Engine" subtitle from the Local Terminal toolbar.

---

## [0.0.2] - 2026-03-21

### Added
- Full Chinese (Simplified) localization via `Localizable.xcstrings`.
- Local Terminal support powered by the native Ghostty engine.
- SFTP panel with file browsing and transfer; fixed race condition crash on first open.
- Mouse scroll wheel / trackpad scrolling support inside the terminal.

### Fixed
- Local terminal shell crashing on launch due to empty environment; now injects the host Mac's environment variables.
- Starship prompt reporting `TERM=dumb` error inside terminal; forced `TERM=xterm-256color`.
- Terminal content compressed to very few columns; fixed `setFrameSize` not triggering Ghostty dimension recalculation.
- Terminal view rendered underneath the sidebar; removed incorrect `.ignoresSafeArea()` modifier.
- SSH session socket not released when closing a tab, causing background resource leak; added async `deinit` cleanup.

### Removed
- Deprecated legacy VT100 source files (`AnsiParser`, `GhosttyVTBridge`, etc.).

---

## [0.0.1] - 2026-03-20

### Added
- Initial release of MacSSH.
- Integrated Ghostty terminal engine for high-performance rendering.
- Added full ANSI color support (256-color and 24-bit TrueColor).
- Integrated SFTP panel with file browsing and transfer capabilities.
- Added localized UI support.
- Implemented non-blocking SSH I/O to prevent UI/Terminal deadlocks.
- Configured Git LFS for efficient binary dependency management.
- Optimized repository size by excluding 2.4GB of redundant build artifacts.
