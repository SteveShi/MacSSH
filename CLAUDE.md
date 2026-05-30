# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

MacSSH is a native macOS SSH & SFTP client built entirely with SwiftUI. It features GPU-accelerated terminal rendering via the Ghostty emulator engine and robust SSH2 session handling through isolated Swift packages.

**Key Technologies:**
- SwiftUI with Swift 6 strict concurrency
- Metal-accelerated terminal rendering (libghostty-swift)
- SSH2 protocol via libssh2-swift
- Sparkle for auto-updates
- XcodeGen for project generation

## Build System

This project uses **XcodeGen** to generate the Xcode project from `project.yml`. Never edit `MacSSH.xcodeproj` directly.

### Initial Setup

```bash
# Install XcodeGen
brew install xcodegen

# Generate Xcode project
xcodegen

# Open in Xcode
open MacSSH.xcodeproj
```

### Building

```bash
# Generate project (always run after modifying project.yml)
xcodegen

# Build via xcodebuild
xcodebuild -scheme MacSSH -configuration Debug build

# Build release version
xcodebuild -scheme MacSSH -configuration Release -destination 'generic/platform=macOS' build
```

### Running

Open `MacSSH.xcodeproj` in Xcode and press `Cmd+R`. On first launch, Xcode will fetch remote Swift packages (libghostty-swift, libssh2-swift, Sparkle) which may take a minute.

## Architecture

### Modular Design

```
MacSSH App (SwiftUI)
├── libghostty-swift → Metal-accelerated terminal emulator
├── libssh2-swift → SSH2 protocol + SFTP (wraps native XCFrameworks)
└── Sparkle → Auto-update framework
```

### Source Structure

- **Sources/App/**: Main application logic
  - `MacSSHApp.swift`: App entry point, command menus, keyboard shortcuts
  - `AppModel.swift`: Central @Observable state manager for connections, tabs, sidebar
  - `AppSettings.swift`: User preferences (input method switching, etc.)
  - `ConnectionEditorView.swift`: SSH connection configuration UI
  - `InputSourceManager.swift`: macOS input source switching integration
  - `Updater.swift`: Sparkle update checker wrapper

- **Sources/Terminal/**: Terminal and session views
  - `TerminalView.swift`: Main terminal container with tab management
  - `GhosttyTerminalView.swift`: NSViewRepresentable wrapper for Ghostty Metal views
  - `LocalTerminalView.swift`: Local shell terminal (no SSH)
  - `TerminalSessionViewModel.swift`: SSH session lifecycle management
  - `SFTPPanelView.swift` + `SFTPViewModel.swift`: File browser and transfer UI
  - `SystemInfoPanelView.swift`: Host metrics display (CPU, memory, disk, load)

- **Sources/Models/**: Data models
  - `SSHConnection.swift`: Connection configuration with Keychain integration
  - `SessionTab.swift`: SSH session tab state
  - `LocalTerminalTab.swift`: Local terminal tab state
  - `ConnectionsStore.swift`: Persistence layer for connections (JSON + Keychain)
  - `SystemMetrics.swift`: Host system monitoring data structures

### Key Architectural Patterns

**1. Swift 6 Concurrency**
- `AppModel` is `@Observable` and `@MainActor`
- All UI state mutations happen on the main actor
- SSH operations use Swift actors via libssh2-swift

**2. Tab Management**
- **SSH tabs** (`openTabs: [SessionTab]`): One tab per SSH connection, managed by `AppModel`
- **Local tabs** (`localTabs: [LocalTerminalTab]`): Independent local shell sessions
- Tabs are persisted to UserDefaults and restored on launch
- Terminal surfaces are cached (`cachedSurface`) to survive SwiftUI navigation

**3. Terminal Surface Lifecycle**
- Ghostty surfaces are created once and cached in tab models
- Reconnect clears `cachedSurface` to force fresh PTY allocation
- Local terminal tabs own their `GhosttySurfaceView` instances directly

**4. Connection Persistence**
- Connection metadata stored in `~/Library/Application Support/MacSSH/connections.json`
- Passwords stored in macOS Keychain using connection UUID as account identifier
- Connection history (last 10 attempts) tracked for reliability indicators

**5. Input Source Management**
- `InputSourceManager` switches macOS input methods when app becomes active
- Configured via Settings → Default Input Source
- Uses Carbon framework APIs for input source control

## Version Management

Version numbers are defined in `project.yml`:
```yaml
MARKETING_VERSION: "1.8.0"      # User-facing version
CURRENT_PROJECT_VERSION: "180"  # Build number for Sparkle
```

**Release Process:**
1. Update version in `project.yml`
2. Update `CHANGELOG.md` with new version section
3. Push to main branch
4. GitHub Actions automatically builds, packages, and releases

## CI/CD

GitHub Actions workflows in `.github/workflows/`:

- **release.yml**: Triggered by CHANGELOG.md changes
  - Extracts version from CHANGELOG.md
  - Builds arm64 binary
  - Creates ZIP and DMG packages
  - Generates Sparkle appcast with EdDSA signatures
  - Creates GitHub release with bilingual release notes (en/zh-Hans)
  - Updates Homebrew tap automatically

- **auto_bump_dependencies.yml**: Dependency updates

## Native Dependencies

The `ThirdParty/` directory contains pre-built native libraries:
- `libghostty-vt.dylib`: Ghostty's VT emulator core (Zig-based)
- Build scripts in `scripts/` for rebuilding dependencies if needed

The post-build script in `project.yml` embeds `libghostty-vt.dylib` into the app bundle and code-signs it.

## Localization

Supports English and Chinese (zh-Hans). Localized strings use SwiftUI's `String(localized:)` API with `Localizable.xcstrings` catalog.

## Swift Package Dependencies

Resolved via Swift Package Manager:
- **Sparkle** (2.0.0+): Auto-update framework
- **libghostty-swift** (1.0.5+): Terminal emulator with Metal rendering
- **libssh2-swift** (1.3.2+): SSH2 protocol implementation

These are fetched automatically by Xcode. To update: Product → Update Package Dependencies.

## Important Constraints

- **macOS 15.0+**: Minimum deployment target
- **Apple Silicon only**: `ARCHS: "arm64"` (no Intel builds)
- **Swift 6.2**: Uses strict concurrency checking
- **Classic Linker**: Required for libghostty-vt compatibility (`LD_USE_CLASSIC_LINKER: "YES"`)

## Working with Connections

When modifying connection-related code:
- Connection UUIDs are stable identifiers used for Keychain lookups
- `SSHConnection.keychainAccount` returns the UUID string for Keychain queries
- `ConnectionsStore.save()` persists to JSON; passwords go to Keychain separately
- Connection history is limited to 10 entries and stored in the JSON file

## Working with Terminal Views

- Ghostty surfaces must be initialized on the main thread (see `MacSSHApp.init()`)
- `GhosttyRuntime.shared` is a singleton that must be accessed before any surface creation
- Terminal views use `NSViewRepresentable` to bridge AppKit Metal views into SwiftUI
- PTY file descriptors are managed by libghostty-swift; don't close them manually

## Keyboard Shortcuts

Defined in `MacSSHApp.swift`:
- `Cmd+R`: Reconnect current SSH session
- `Cmd+W`: Close current tab
- `Cmd+[` / `Cmd+]`: Previous/Next tab
- `Cmd+1` through `Cmd+9`: Jump to tab by index

## Settings

User preferences in `AppSettings.swift`:
- Default input source ID for automatic switching
- Stored in UserDefaults with `@AppStorage` property wrappers
