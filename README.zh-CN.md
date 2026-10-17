# MacSSH

[English](README.md) | [简体中文](README.zh-CN.md)

`MacSSH` 是一款专为 macOS 精心打造的原生现代 **SSH 与 SFTP 客户端**。

应用全量基于 SwiftUI 与 Swift 6 严格并发模型构建，借助 Ghostty 终端核心引擎（`MactermKit`）实现丝滑的 Metal GPU 硬件加速渲染，并通过独立的 Swift Package 模块（`SSH2Kit`）保障高并发 SSH2 会话的稳定性与安全性。

---

## 🏛️ 双通道核心架构

为了杜绝后台网络阻塞导致终端卡顿，并保持极高的系统可靠性，`MacSSH` 采用独创的 **双通道解耦架构**：

1. **主终端交互通道（PTY）**：直接通过 Ghostty 引擎运行 macOS 原生 `/usr/bin/ssh`（或用于持久化密码认证的 expect 脚本），直接依托 Metal GPU 进行硬件渲染，完整支持 ANSI TrueColor（真彩色）、原生中文/日文输入法（IME）以及语义化 Shell Integration。
2. **辅助服务通道（后台遥测与 SFTP）**：由 `SSH2Kit`（静态封装 `libssh2` 与 `AWS-LC`）提供基于 Swift Actor 隔离的 `SSHSession` 与 `SFTPService`，在后台独立执行多级目录遍历、文件传输与主机性能指标实时采集，彻底避免与主终端交互流量产生争抢。

```mermaid
flowchart TD
    subgraph UI_Layer["MacSSH 视图层 (SwiftUI)"]
        MainWindow["主窗口与标签栏 (Tabs & Split)"]
        SettingsView["SettingsView (外观与主题配置)"]
        ThemePicker["ThemePickerView (调色板矩阵)"]
        ToastOverlay["ToastOverlayView (浮动 HUD 胶囊)"]
        Inspector["右侧检查器 (SFTP 与系统指标面板)"]
        ConnEditor["ConnectionEditor (单机专属配色与认证)"]
    end

    subgraph State_Layer["核心状态与业务逻辑层 (@Observable)"]
        AppModel["AppModel (全局导航与连接中心)"]
        SessionTab["SessionTab / LocalTerminalTab (会话生命周期)"]
        ThemeManager["ThemeManager (内置 JSON + 自定义主题管理)"]
        ToastManager["ToastManager (HUD 队列与计时器)"]
        SFTPVM["SFTPViewModel (工作目录导航器)"]
        MonitorVM["TerminalSessionViewModel (系统指标解析)"]
    end

    subgraph Dual_Channel["双通道核心解耦引擎"]
        subgraph Channel_PTY["1. 主终端交互 PTY 通道"]
            GhosttySurface["GhosttySurfaceView (Metal 渲染画布)"]
            NativeSSH["macOS /usr/bin/ssh (原生 SSH 进程)"]
            LocalProcess["本地 Shell (zsh / bash)"]
        end

        subgraph Channel_Aux["2. 辅助服务后台通道"]
            SSHActor["SSHSession Actor (libssh2 独立会话)"]
            SFTPActor["SFTPService Actor"]
        end
    end

    subgraph Native_Packages["独立封装 Swift Packages"]
        MactermKit["MactermKit / MactermKitCore<br/>(Ghostty C/Zig 核心 + Metal VSYNC)"]
        SSH2Kit["SSH2Kit<br/>(libssh2 + AWS-LC Actor 封装)"]
        Sparkle["Sparkle (自动更新框架)"]
    end

    %% UI to State
    MainWindow --> AppModel
    SettingsView --> ThemeManager
    ThemePicker --> ThemeManager
    ConnEditor --> ThemeManager
    ToastManager --> ToastOverlay
    Inspector --> SFTPVM
    Inspector --> MonitorVM

    %% State to Channels
    AppModel --> SessionTab
    SessionTab --> GhosttySurface
    SessionTab --> SFTPVM
    SessionTab --> MonitorVM
    ThemeManager -->|实时热重载| GhosttySurface

    %% PTY Channel & Shell Integration
    LocalProcess & NativeSSH -->|OSC 7 / OSC 133 / OSC 2| MactermKit
    MactermKit -->|Action 回调响应| GhosttySurface
    GhosttySurface -->|目录变更 / 命令结束| SessionTab
    SessionTab -->|OSC 7 联动跳转| SFTPVM
    SessionTab -->|命令完成弹出| ToastManager

    %% Aux Channel
    MonitorVM --> SSHActor
    SFTPVM --> SFTPActor
    SSHActor --> SSH2Kit
    SFTPActor --> SSH2Kit

    %% Sparkle
    MainWindow -.-> Sparkle
```

---

## ✨ 核心特性

- ⚡ **Metal GPU 硬件加速**：基于 Ghostty 终端核心，支持 120Hz VSYNC 垂直同步、亚毫秒级输入响应，完整支持 ANSI 256 色与 24 位 TrueColor 真彩色。
- 🎨 **甄选主题生态与实时无感热切换**：内置精选自 `iTerm2-Color-Schemes` 的 110+ 款主流经典主题（Tokyo Night、Catppuccin、Nord、Dracula、Gruvbox、One Dark、Solarized、Warm Beige Cream 与 Slate Dark），支持深浅外观自动配对、单机专属覆盖，所有活跃会话实时秒级生效无需断开重连。
- 🪄 **原生 Shell 深度集成与智能 HUD 气泡**：
  - **OSC 7 目录实时跟随**：远端终端切换工作目录时，右侧 SFTP 检查器面板自动同步跳转至对应路径。
  - **OSC 0 / OSC 2 动态标题更新**：窗口与标签栏标题随远程执行程序动态呈现。
  - **零外部依赖 Toast HUD**：长耗时命令（>=5秒）执行完毕后自动弹出耗时与退出码悬浮胶囊，后台静默时联动 macOS 原生系统通知。
- 🔀 **多向分屏与本地终端**：支持水平与垂直方向多向分屏，拥有独立的 PTY 生命周期，同时支持并排运行原生 macOS 本地 Shell。
- 📊 **实时主机系统监控**：全宽微拟态胶囊进度条呈现 CPU、内存、交换分区、磁盘使用、网络实时吞吐与多核平均负载。
- 📁 **内置可视 SFTP 面板**：集成侧边栏文件管理器，支持多层目录快速浏览、拖拽上传与递归批量下载。
- 🛡️ **双通道严苛并发隔离**：100% 遵循 Swift 6 并发模型，彻底物理隔离终端交互 PTY 与后台 SFTP / 监控流量，告别卡顿与状态伪报错。
- 🔑 **系统级密钥安全管理**：智能支持 `.pub` 公钥到私钥自动推导回退，全量密码存储于 macOS 系统钥匙串（Keychain），严格执行 Host Key 变更安全校验。
- 🔄 **Sparkle 2.x 自动更新**：支持一键检查新版本，所有更新包均由 EdDSA 高强度数字签名保障。

---

## 🛠️ 源码构建

### 环境要求

1. **macOS 15.0+**（Apple Silicon / `arm64`）。
2. **Xcode 16+**（包含 macOS SDK）。
3. **Tuist**：确保已安装 Tuist（`mise install tuist` 或 `curl -fsSL https://get.tuist.io | bash`）。

### 生成与编译工程

```bash
# 1. 克隆代码仓库
git clone https://github.com/SteveShi/MacSSH.git
cd MacSSH

# 2. 通过 Tuist 生成 Xcode Workspace
tuist generate --no-open

# 3. 通过 xcodebuild 编译调试版本
xcodebuild -workspace MacSSH.xcworkspace -scheme MacSSH -configuration Debug build
```

---

## 📄 开源协议

`MacSSH` 遵循 [MIT 开源协议](LICENSE)。
