## [1.9.8] - 2026-07-23

### Changed
- Automatically bumped dependencies to libssh2-swift version 1.3.8 and libghostty-swift version 1.0.12.

---

### Chinese
### 变更
- 自动更新依赖项 libssh2-swift 至版本 1.3.8，libghostty-swift 至版本 1.0.12。

---
## [1.9.7] - 2026-07-23

### Refactored
- Conducted codebase audit to eliminate over-engineering and redundant boilerplate:
  - Consolidated duplicate context menu handlers into a single unified `TerminalMenuHandler`.
  - Extracted shared `SplitTerminalLayout` view to deduplicate terminal split-screen layouts.
  - Converted stateless `GistSyncService` and `DropboxSyncService` actors to enums.
  - Replaced manual JSON serialization in Gist download with native `JSONDecoder`.
  - Purged dead code, unused properties (`cols`/`rows`, `showReconnectError`, `localTab`), and redundant background retries.

---

### Chinese
### 重构
- 全面优化架构并清理冗余代码：
  - 合并 SSH 与本地终端重合的右键菜单处理逻辑，统一收载于 `TerminalMenuHandler`。
  - 抽离共享 `SplitTerminalLayout` 布局视图，消除分屏逻辑的重复。
  - 将无状态的 `GistSyncService` 和 `DropboxSyncService` actor 调整为 enum。
  - 将 Gist 下载中的 `JSONSerialization` 手动解析替换为原生的 `JSONDecoder`。
  - 清理多余死代码、弃用属性（如 `cols`/`rows`、`showReconnectError`、`localTab`）及冗余的后台重试机制。

---

## [1.9.6] - 2026-07-22

### Fixed
- Fixed an issue where SSH connections to LAN hosts failed with `No route to host` when proxy environment variables were active. Added `NO_PROXY` environment configuration to automatically bypass proxy for local IP ranges (`192.168.0.0/16`, `10.0.0.0/8`, `172.16.0.0/12`) and removed redundant `--` arguments from automated expect scripts.

---

### Chinese
### 修复
- 修复了在系统开启代理时连接局域网主机报 `No route to host` 的问题。自动配置了 `NO_PROXY` 环境变量以直接绕过局域网 IP 段（`192.168.0.0/16`、`10.0.0.0/8`、`172.16.0.0/12`），并清理了内部 expect 自动化脚本中多余的 `--` 参数。

---

## [1.9.5] - 2026-07-22

### Fixed
- Upgraded `libssh2-swift` to version `1.3.7` with native `ssh-agent` integration and `.pub` file existence checking. Resolves Inspector SSH auth failure (`-16`) for sessions using SSH Agent or keys without explicit `.pub` companion files.

---

### Chinese
### 修复
- 将依赖项 `libssh2-swift` 升级至 `1.3.7`，合入了原生的 `ssh-agent` 认证以及 `.pub` 文件存在性校验。彻底解决了使用 SSH Agent 或无配套 `.pub` 文件的密钥时 Inspector 报 `SSH auth failed (-16)` 的问题。

---

## [1.9.4] - 2026-07-22

### Fixed
- Fixed an issue where the Inspector panel (real-time monitor and SFTP) failed with `SSH auth failed (-16)` when the main terminal connected using default SSH keys without a saved Keychain password. `TerminalSessionViewModel` now automatically probes standard local OpenSSH key paths (`id_ed25519`, `id_ecdsa`, `id_rsa`, `id_dsa`) and falls back to public key authentication when password authentication fails or is omitted.

---

### Chinese
### 修复
- 修复了主终端已连接但 Inspector 面板（实时监控和 SFTP）报 `SSH auth failed (-16)` 的问题。当连接未保存密码时，后台现已支持自动检索本地标准 OpenSSH 密钥（`id_ed25519`、`id_ecdsa`、`id_rsa`、`id_dsa`），并在密码认证缺失或失败时自动退回使用公钥重试认证。

---

## [1.9.3] - 2026-07-18

### Changed
- Automatically bumped dependencies to libssh2-swift version 1.3.6 and libghostty-swift version 1.0.12.

---

### Chinese
### 变更
- 自动更新依赖项 libssh2-swift 至版本 1.3.6，libghostty-swift 至版本 1.0.12。

---
## [1.9.2] - 2026-07-17

### Fixed
- Fixed an issue where interactive raw-mode terminal prompts (e.g. Y/N confirmation dialogs) would ignore alphanumeric inputs and only respond to Enter. This was resolved by stripping spoofed Ghostty environment variables from the local shell to prevent tools from incorrectly negotiating advanced keyboard protocols.

---

### Chinese
### 修复
- 修复了本地终端在原始模式（raw mode）交互确认（如 Y/N 提示符）时忽略普通字母输入、仅回车有响应的问题。通过清除本地终端环境变量中伪装的 Ghostty 标识，避免交互工具错误启用高级键盘协议而导致无法解析按键。

---

## [1.9.1] - 2026-07-16

### Changed
- Automatically bumped dependencies to libssh2-swift version 1.3.5 and libghostty-swift version 1.0.12.

---

### Chinese
### 变更
- 自动更新依赖项 libssh2-swift 至版本 1.3.5，libghostty-swift 至版本 1.0.12。

---
## [1.9.0] - 2026-07-15

### Added
- Persistence of the main window's custom size and position across launches, ensuring the workspace layout is remembered.
- Sidebar connections list enhancement: right-click context menu now supports "Copy IP" and "Copy Password" (auto-disabled if no password exists).
- Optional zero-knowledge e2e encryption for sync data. Users can enable "Encrypt Sync Data" and set a "Sync Master Password" to encrypt metadata locally using AES-256 (GCM) via Apple's native CryptoKit framework.
- Connection fail diagnostics: the Inspector's "System Monitor" panel now renders a detailed red error alert containing connection diagnostic messages.

### Fixed
- Fixed an issue where the background ssh monitoring connection would get stuck on `hostKeyNotTrusted` because the confirmation dialog got suppressed by SwiftUI split navigation rendering. The app now silently auto-trusts unknown host keys on first connection (matching CLI ssh behavior).

---

### Chinese
### 新增
- 自动记住上次调整后的窗口大小与位置，跨启动持久化窗口布局。
- 侧栏远程连接项目右键菜单功能增强：新增“复制 IP”与“复制密码”（若未设置密码则自动置灰）。
- 支持可选的端到端强加密多云同步配置。用户可以在设置中启用“加密同步配置”并输入“同步主密码”，利用苹果原生 CryptoKit 框架对本地连接配置进行 AES-256 (GCM) 级别加密。
- 完善了连接异常诊断：在 Inspector 右侧的“系统监控”面板中，增加了专门展示连接失败具体错误信息的红色警告卡片。

### 修复
- 修复了因为首次连接未知主机时 SwiftUI 拆分视图渲染 Bug 吞掉确认弹窗，导致 `libssh2` 后台监控静默连接被迫卡死在未连接状态的问题。现在首次连接时会静默自动信任未知的 HostKey 并记录，与命令行 ssh 的自动信任体验对齐。

---

## [1.8.10] - 2026-06-27

### Changed
- Automatically bumped dependencies to libssh2-swift version 1.3.4 and libghostty-swift version 1.0.12.

---

### Chinese
### 变更
- 自动更新依赖项 libssh2-swift 至版本 1.3.4，libghostty-swift 至版本 1.0.12。

---
## [1.8.9] - 2026-06-23

### Fixed
- Fixed an intermittent bug where keyboard input could freeze in the terminal (mouse, menus, and scrolling still worked) when a default input source was configured. The automatic input-source switch now skips re-selection when the target source is already active, preventing the text input client from being wedged mid-composition.
- Hardened password authentication cleanup: any plaintext password / expect helper files left in the temporary directory by a previous abnormal exit are now purged on launch, so credentials no longer linger on disk.

---

### Chinese
### 修复
- 修复了在设置了默认输入法后，终端偶发的键盘输入失灵问题（鼠标、菜单、滚动均正常，仅无法输入文字）。自动输入法切换现在会在目标输入源已激活时跳过重复选择，避免在组字过程中锁死文本输入通道。
- 加固了密码认证的清理逻辑：上次异常退出时残留在临时目录中的明文密码 / expect 辅助文件，现在会在启动时被清除，避免凭据滞留磁盘。

---

## [1.8.8] - 2026-06-20

### Added
- Integrated native terminal right-click context menu with fully functional features:
  - Copy and Paste.
  - "Search with Google" to automatically search selected text in the default web browser.
  - Terminal split screen sessions (Split Left, Split Right, Split Up, Split Down) rendering multiple interactive terminals in a single tab.
  - "Reset Terminal" to clear and reset the terminal state.
  - "Toggle Terminal Inspector" to collapse or expand the SFTP monitor panel.
  - "Terminal Read-only" mode to toggle keyboard input interception.
  - "Change Tab/Terminal Title..." with alert dialog inputs.
  - AutoFill support to input SSH username or retrieve and paste password from Keychain.
- Added localization strings for all new context menu items in English and Simplified Chinese.

### Changed
- Removed support for `ssh://` URL scheme to avoid conflicts with system utilities; `macssh://` is now the only protocol handler.
- Pointed the `libghostty-swift` package dependency to the newly released remote tag version `1.0.12`.

### Fixed
- Fixed a linker error in Xcode 15/16 / macOS 15.0 SDK where `___dso_handle` from `libghostty-fat.a` could not be resolved by the new linker.

---

### Chinese
### 新增
- 接入了全新的终端原生右键菜单，所有选项均已对接真实功能：
  - 复制与粘贴。
  - “使用Google搜索”：支持在有选中文本时自动通过默认浏览器搜索选中关键字。
  - 终端分屏：支持在同一个标签页内进行向左/向右/向上/向下多终端交互式分屏会话。
  - “重置终端”：发送重置控制序列清空终端屏幕状态。
  - “切换终端监控”：显示或收起右侧 SFTP/系统监控面板。
  - “终端只读”：一键锁定终端输入，拦截全部键盘按键。
  - “修改标签标题...” / “修改终端标题...”：支持通过弹窗输入修改当前终端标签名。
  - “自动填充”：支持自动往终端填充 SSH 用户名或从 Keychain 钥匙串提取对应密码进行粘贴。
- 新增了所有右键菜单英文与简体中文的本地化翻译支持。

### 变更
- 去除了对 `ssh://` 协议解析的支持，避免与系统自带终端或其他 SSH 客户端冲突，仅保留 `macssh://` 专属协议。
- 更新并锁定了 `libghostty-swift` 依赖至最新的线上正式发布版本 `1.0.12`，不依赖本地路径。

### 修复
- 修复了在 Xcode 15/16 / macOS 15.0 SDK 编译环境下，因新版链接器无法解析 `libghostty-fat.a` 中的 `___dso_handle` 符号导致链接失败的 Bug。

---

## [1.8.7] - 2026-06-20

### Added
- Added CLI helper script and registered URL schemes (ssh:// and macssh://) to support launching SSH sessions from terminal commands, browsers, and shortcuts.
- Added native right-click context menu (Copy/Paste) inside the terminal view.
- Added accessibility support (NSAccessibility role .textArea and notification broadcasts) to support PopClip and command-line prompt autocomplete tools (Kiro CLI, Fig).

### Changed
- Pointed libghostty-swift package dependency to version 1.0.10.

---

### Chinese
### 新增
- 增加了命令行 Helper 脚本并注册了自定义 URL 协议（ssh:// 和 macssh://），支持从终端、浏览器以及快捷方式唤起并自动开启 SSH 会话。
- 终端界面内支持右键原生上下文菜单（包含“复制”与“粘贴”选项）。
- 增加了系统级辅助功能支持（重构 NSAccessibility textArea 角色并发送 selectedTextChanged / valueChanged 变化通知），实现对 PopClip 以及终端自动命令补全提示工具（Kiro CLI / Fig）的完美兼容。

### 变更
- 更新 libghostty-swift 依赖至版本 1.0.10。

---

## [1.8.6] - 2026-06-08

### Added
- Added multi-stage input source auto-switch retry mechanism (immediate, 0.2s, 0.6s, 1.5s delay) to resolve input method failure on application startup.
- Implemented automatic local terminal tabs persistence and restoration on application restart.
- Enabled instant persistence after renaming local terminal tabs.

---

### Chinese
### 新增
- 引入了输入法多级延迟自动切换与重试机制（立即、0.2秒、0.6秒及1.5秒延迟），彻底解决软件启动和焦点抖动时输入法切换偶尔失效的问题。
- 实现了本地终端标签页的自动记忆与重启恢复。
- 支持本地终端标签页重命名后即时保存。

---

## [1.8.5] - 2026-06-07

### Changed
- Automatically bumped dependencies to libssh2-swift version 1.3.3 and libghostty-swift version 1.0.9.

---

### Chinese
### 变更
- 自动更新依赖项 libssh2-swift 至版本 1.3.3，libghostty-swift 至版本 1.0.9。

---
## [1.8.4] - 2026-06-07

### Added
- System notifications for SSH connection success/failure, SFTP transfer completion/failure, and local terminal events — app-requested notifications (OSC 9 / OSC 777), process exit, and the terminal bell. Configurable per category in Settings → General → Notifications; by default they only fire while the app is in the background (the bell is off by default).

---

### Chinese
### 新增
- 新增系统通知:SSH 连接成功/失败、SFTP 传输完成/失败,以及本地终端事件——应用请求的通知(OSC 9 / OSC 777)、进程退出、终端响铃。可在 设置 → 通用 → 通知 中分类开关;默认仅当应用在后台时提醒(响铃默认关闭)。

---
## [1.8.3] - 2026-06-07

### Changed
- Automatically bumped dependencies to libssh2-swift 1.3.3 and libghostty-swift 1.0.7.

---

### Chinese
### 变更
- 自动更新依赖项 libssh2-swift 至 1.3.3，libghostty-swift 至 1.0.7。

---
## [1.8.2] - 2026-06-07

### Changed
- Redesigned the local terminal tab bar: native-style in-window tabs with per-tab close and rename, adopting Liquid Glass on macOS 26 (translucent material on earlier systems).

### Fixed
- Fixed being unable to select terminal text — including in SSH sessions — with the mouse; mouse button and drag events are now forwarded to the terminal engine (libghostty-swift 1.0.6).

---

### Chinese
### 变更
- 重新设计本地终端标签栏：窗口内原生风格标签，支持逐个标签的关闭与重命名；在 macOS 26 上采用 Liquid Glass 毛玻璃效果（更早系统回退为半透明材质）。

### 修复
- 修复终端（含 SSH 会话）无法用鼠标选中文本的问题；现已将鼠标按键与拖拽事件转发给终端引擎（libghostty-swift 1.0.6）。

---
## [1.8.1] - 2026-05-30

### Changed
- Automatically bumped dependencies to libssh2-swift version 1.3.3 and libghostty-swift version 1.0.5.

---

### Chinese
### 变更
- 自动更新依赖项 libssh2-swift 至版本 1.3.3，libghostty-swift 至版本 1.0.5。

---
## [1.8.0] - 2026-05-30

### Added
- Added a "Default Input Method" option in Settings → General that automatically switches to the selected input method whenever the app becomes active.
- The input method list is dynamically populated from all system-enabled keyboard input sources.

### Fixed
- Fixed all placeholder settings toggles (Confirm before disconnecting, Auto reconnect, Show hidden files, Overwrite existing files) that were previously display-only with hardcoded `.constant()` values — they are now fully persisted via UserDefaults.
- Fixed the About tab showing a hardcoded version "0.1.0 (1)" instead of the actual app version; it now reads from the app bundle dynamically.
- Fixed input method switching not triggering on app activation by replacing `.onAppear` with `NSApplication.didBecomeActiveNotification`.

---

### Chinese
### 新增
- 在设置 → 通用中新增「默认输入法」选项，应用每次被激活时自动切换到用户选择的输入法。
- 输入法列表动态读取系统中所有已启用的键盘输入源。

### 修复
- 修复通用和 SFTP 标签页中 4 个设置开关（断开前确认、自动重连、显示隐藏文件、覆盖已有文件）仅为展示效果、无法实际切换的问题，现已全部接入 UserDefaults 持久化。
- 修复关于页面版本号硬编码为 "0.1.0 (1)" 的问题，改为从应用 Bundle 动态读取实际版本号。
- 修复输入法切换功能未生效的问题，将 `.onAppear` 替换为监听 `NSApplication.didBecomeActiveNotification`，确保每次应用激活时触发切换。

---


## [1.7.6] - 2026-05-28

### Changed
- Automatically bumped dependencies to libssh2-swift version 1.3.2 and libghostty-swift version 1.0.5.

---

### Chinese
### 变更
- 自动更新依赖项 libssh2-swift 至版本 1.3.2，libghostty-swift 至版本 1.0.5。

---
## [1.7.5] - 2026-05-28

### Changed
- Automatically bumped dependencies to libssh2-swift version 1.3.2 and libghostty-swift version 1.0.4.

---

### Chinese
### 变更
- 自动更新依赖项 libssh2-swift 至版本 1.3.2，libghostty-swift 至版本 1.0.4。

---
## [1.7.4] - 2026-05-28

### Changed
- Automatically bumped dependencies to libssh2-swift version 1.3.2 and libghostty-swift version 1.0.0.

---

### Chinese
### 变更
- 自动更新依赖项 libssh2-swift 至版本 1.3.2，libghostty-swift 至版本 1.0.0。

---
## [1.7.3] - 2026-05-28

### Changed
- Automatically bumped dependencies to libssh2-swift version 1.3.2 and libghostty-swift version 1.0.0.

---

### Chinese
### 变更
- 自动更新依赖项 libssh2-swift 至版本 1.3.2，libghostty-swift 至版本 1.0.0。

---
## [1.7.2] - 2026-05-28

### Changed
- Automatically bumped dependencies to libssh2-swift version 1.3.2 and libghostty-swift version 1.0.0.

---

### Chinese
### 变更
- 自动更新依赖项 libssh2-swift 至版本 1.3.2，libghostty-swift 至版本 1.0.0。

---
## [1.7.1] - 2026-05-28

### Changed
- Automatically bumped dependencies to libssh2-swift version 1.3.2 and libghostty-swift version 1.0.0.

---

### Chinese
### 变更
- 自动更新依赖项 libssh2-swift 至版本 1.3.2，libghostty-swift 至版本 1.0.0。

---
# Changelog

All notable changes to this project will be documented in this file.

## [1.7.0] - 2026-05-28

### Changed
- Switched the underlying cryptographic and SSL/TLS backend of libssh2 from LibreSSL to BoringSSL (version 0.20260526.0).
- Renamed the binary target library references inside dependencies to `libssh2kit`.

---

### Chinese
### 变更
- 将底层的密码学和 SSL/TLS 加密内核从 LibreSSL 切换为了 BoringSSL（版本 0.20260526.0）。
- 将依赖库内部引用的二进制目标文件整合重命名为了 `libssh2kit`。

---

## [1.6.1] - 2026-05-28

### Changed
- Upgraded the underlying LibreSSL dependency of libssh2 to 4.3.2.
- Renamed the binary target inside libssh2-swift package from `libssh2` to `libssh2kit`.

---

### Chinese
### 变更
- 将底层的 LibreSSL 加密核心依赖升级到了最新的 4.3.2 版本。
- 将 `libssh2-swift` 中的二进制目标从 `libssh2` 重命名为了 `libssh2kit`。

---

## [1.6.0] - 2026-05-28

### Added
- Added a "Default Input Method" option in Settings → General, allowing users to select a preferred input method that is automatically activated when the app launches.
- The input method list is dynamically populated from all enabled keyboard input sources on the system.

---

### Chinese
### 新增
- 在设置 → 通用中新增「默认输入法」选项，用户可选择一个首选输入法，应用启动时将自动切换到该输入法。
- 输入法列表动态读取系统中所有已启用的键盘输入源。

---

## [1.5.4] - 2026-05-28

### Changed
- Decoupled SSH protocol and cryptography core from MacSSH and extracted into a standalone package `libssh2-swift` to enable lightweight CI build automation.
- Replaced local bulky static `.a` binary libraries with SPM remote targets via GitHub Release zip assets.

### Fixed
- Fixed duplicate command execution warnings and `module.modulemap` collisions between dependencies (such as GhosttyKit) during compilation by wrapping libraries using an external bridge C target `Clibssh2`.
- Fixed data race compiler errors under Swift 6 strict concurrency by making `SSHAuth` conform to `Sendable`.

---

### Chinese
### 变更
- 从 MacSSH 主壳程序中彻底解耦了 SSH 协议及加密核心，并抽离为独立的 `libssh2-swift` 远程依赖包，实现了极为轻量的 CI 自动化构建。
- 用基于 GitHub Release zip 的 SPM 远程 Target 依赖，取代了本地体积庞大的 `.a` 静态二进制库。

### 修复
- 通过引入外部 C 桥接目标 `Clibssh2` 重新包装 C 头文件与模块字典，修复了编译时由于多个第三方依赖包（如 GhosttyKit 与 libssh2）重复拷贝 `module.modulemap` 引起的冲突错误。
- 将 `SSHAuth` 升级符合 `Sendable` 协议规范，消除了在 Swift 6 严格并发检查下跨 Actor 边界传参导致的数据竞争错误。

---

## [1.5.3] - 2026-05-27

### Fixed
- Fixed clipboard copy and paste operations in the Ghostty terminal by implementing the native NSPasteboard-backed read and write callbacks.

---

### Chinese
### 修复
- 修复了 Ghostty 终端剪切板复制与粘贴失效的问题，通过对接 macOS 原生 NSPasteboard 实现了剪切板的读取与写入回调。

---

## [1.5.2] - 2026-05-26

### Fixed
- Fixed the inspector window layout in fullscreen mode by elevating the `.inspector` modifier to the window-level `NavigationSplitView`.
- Fixed connection sidebar and inspector sidebar resizability by applying explicit column width configurations.

---

### Chinese
### 修复
- 修复在全屏模式下右侧 Inspector 顶部多出圆角分隔和黑色背景的问题，将 `.inspector` 提升至窗口级最外层 `NavigationSplitView` 上渲染。
- 修复左侧连接列表侧边栏和右侧监控侧边栏宽度不可调节的问题，分别显式应用了最小、理想及最大列宽配置。

---

## [1.5.1] - 2026-05-23

### Changed
- Reworked the SSH session lifecycle so failed handshakes and host-key checks no longer leak sockets, libssh2 sessions, or the global init counter; concurrent connections are now reference-counted safely.
- Made the libssh2 read loop adaptive (2 ms → 50 ms backoff with real EOF detection) instead of a fixed 10 ms spin, cutting idle CPU usage of every open SSH tab.
- Added a 15 s socket connect/IO timeout plus `TCP_NODELAY` and `SO_KEEPALIVE` so unreachable hosts fail fast and interactive input feels snappier.
- Cached `ByteCountFormatter` and `DateComponentsFormatter` in the System Monitor card; the panel re-renders every 3 s and the formatters were a measurable hotspot.

### Fixed
- Fixed the SFTP panel showing stale directory contents when the user quickly switched folders — listings and transfers now cancel the previous in-flight task and discard outdated results.
- Fixed `executeCommand` closing the SSH channel before sending EOF and silently truncating output on non-EAGAIN read errors.
- Fixed reconnect attempts being able to overlap each other; the previous connect task is now cancelled before a new one starts.
- Replaced silent persistence failures in `ConnectionsStore` with `os.Logger` diagnostics.

---

### Chinese
### 变更
- 重写 SSH 会话生命周期：握手或 known-hosts 校验失败时不再泄漏 socket、libssh2 会话与全局初始化计数；多连接并发时改为线程安全的引用计数。
- 将 libssh2 读取循环由固定 10 ms 自旋改为 2 ms→50 ms 自适应退避，并通过 `libssh2_channel_eof` 区分真实 EOF，显著降低空闲 SSH 标签的 CPU 占用。
- 增加 15 秒 socket 连接/收发超时，并启用 `TCP_NODELAY` 与 `SO_KEEPALIVE`，不可达主机能快速失败，交互输入更跟手。
- 系统监控卡片中复用 `ByteCountFormatter`/`DateComponentsFormatter`，避免每 3 秒重绘时重复构造格式化器的性能热点。

### 修复
- 修复快速切换目录时 SFTP 面板出现旧结果覆盖新结果的竞态：列举与传输任务现在会取消上一个进行中的任务并丢弃过期结果。
- 修复 `executeCommand` 在发送 EOF 之前已关闭通道，以及非 EAGAIN 读错误时静默截断输出的问题。
- 修复重复点击连接时多个 connect Task 同时运行的问题：新连接启动前会取消前一个任务。
- 将 `ConnectionsStore` 中被静默吞掉的持久化错误改为通过 `os.Logger` 输出诊断信息。

---

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
