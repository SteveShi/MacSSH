# MacSSH

A modern, high-performance SSH & SFTP client for macOS, powered by the **Ghostty** terminal engine.

> [!WARNING]
> **早期预览版本 / Early Preview**
> MacSSH 目前处于早期开发阶段，功能尚未完整，可能存在 Bug 和不稳定情况，请谨慎用于生产环境。  
> MacSSH is currently in early development. It may contain bugs and stability issues. Use in production environments at your own risk.

## Features

- **Ghostty Terminal Engine**: Blazing fast rendering with modern terminal features.
- **True Color Support**: Full 24-bit TrueColor and 256-color palette support for a rich CLI experience.
- **SFTP Integration**: Built-in SFTP browser with drag-and-drop support and real-time transfer progress.
- **Native macOS Experience**: Built with SwiftUI, featuring native tabs, searchable connection lists, and modern layout tokens.
- **Advanced Connectivity**: Reliable SSH sessions using `libssh2` with non-blocking I/O for maximum stability.
- **Localized UI**: Fully localized and ready for internationalization.

## Installation

You can install **MacSSH** via [Steve's Homebrew Tap](https://github.com/SteveShi/homebrew-tap):

```bash
brew tap SteveShi/tap
brew install --cask macssh
```

## Requirements

- macOS 15.0 or later
- Xcode 16.0 or later (for development)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (to generate the project)

## Getting Started

1. Clone the repository:
   ```bash
   git clone https://github.com/SteveShi/MacSSH.git
   cd MacSSH
   ```

2. Install dependencies (requires `cmake` and `git`):
   ```bash
   ./scripts/build_deps.sh
   ```

3. Generate the Xcode project:
   ```bash
   xcodegen generate
   ```

4. Open `MacSSH.xcodeproj` and build the project.

## Development

This project uses **Git LFS** for managing large binary dependencies. Ensure you have Git LFS installed:
```bash
git lfs install
git lfs pull
```

## License

This project is licensed under the **MIT License** - see the [LICENSE](LICENSE) file for details.
