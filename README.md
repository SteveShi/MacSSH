# MacSSH

[中文版](README_zh.md)

`MacSSH` is a modern, fast, and native **SSH & SFTP client** handcrafted for macOS.

Built entirely with SwiftUI, it features GPU-accelerated terminal rendering driven by the Ghostty emulator engine (`libghostty-swift`) and robust SSH2 session handling via an isolated SPM package (`libssh2-swift`).

---

## Modular Architecture

To ensure separation of concerns and maintain a repository size under 1MB, `MacSSH` decomposes its modules cleanly:

```mermaid
graph TD
    App[MacSSH App SwiftUI] --> |UI Layer / SFTP Panels| Core
    Core[App Logic & ViewModels] --> |Terminal Emulator View| Ghostty[libghostty-swift]
    Core --> |SSH2 & SFTP Protocol| SSH[libssh2-swift Package]
    SSH --> |Remote BinaryTarget| C_Libs["libssh2 & openssl XCFrameworks"]
```

- **Host Application (`MacSSH`)**: Governs SSH settings editor, tabs management, Keychain data flow, side-panel dashboard, and localized SwiftUI assets.
- **Terminal System (`libghostty-swift`)**: Embeds high-performance virtual terminal state machines and Metal views.
- **Connection Core (`libssh2-swift`)**: Bridges raw TCP socket structures to Swift `actor` mechanisms, resolving low-level C libraries (`libssh2` and `openssl`) via remote binary targets.

---

## Core Features

- ⚡ **Metal-Accelerated VT**: Powered by Ghostty's core, offering lag-free interactive shell rendering.
- 📦 **Ultra Lightweight**: No bulky static binary `.a` files committed to Git. Resolved strictly on-demand during build phases.
- 🛡️ **Swift 6 Concurrency**: Conforms 100% to rigid concurrency rules, eliminating data-races during multiplexed SSH channel tasks.
- 📊 **Host System Monitor**: Displays host health metrics (CPU utilization, physical memory usage, disk storage, and average loads) right in the sidebar.
- 📁 **Built-in SFTP Panels**: Visual directory inspector enabling instant recursive uploads, downloads, and navigation.

---

## 🛠️ Build from Source

### Requirements

- macOS 15.0 (Sequoia) or later
- Xcode 16.4 or later

### Steps

The Xcode project file (`MacSSH.xcodeproj`) is generated dynamically using [Tuist](https://tuist.io/).

1. **Install Tuist**:
   ```bash
   mise install tuist
   ```

2. **Clone and generate**:
   ```bash
   git clone https://github.com/SteveShi/MacSSH.git
   cd MacSSH
   tuist generate
   ```

3. Open `MacSSH.xcodeproj` in Xcode and build.

## 🔧 Tech Stack

| Layer | Technology |
|-------|-----------|
| Terminal Engine | [Ghostty VT](https://ghostty.org/) (`libghostty-vt`) |
| UI Framework | SwiftUI (macOS 15+) |
| SSH Transport | Built-in `ssh` command |
| Credential Store | macOS Keychain via [KeychainAccess](https://github.com/kishikawakatsumi/KeychainAccess) |
| Auto Update | [Sparkle](https://sparkle-project.org/) |
| Project Generation | [Tuist](https://tuist.io/) |
