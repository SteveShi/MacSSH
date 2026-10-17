---
id: terminal-themes-hud-shell-integration
title: "Modern Terminal Themes, Native Toast HUD, and Shell Integration Architecture"
category: decision
status: active
tags: [terminal, themes, toast, shell-integration]
created: "2026-10-17T17:42:38"
updated: "2026-10-17T18:11:05"
---

<!-- compiled_truth -->
## Context & Problem
Modern terminal users expect rich color scheme customization, subtle non-intrusive feedback, and deep integration between local/remote shell states and client GUI capabilities.
Specifically:
1. `SPIndicator` was evaluated for floating alerts, but it is strictly an iOS/UIKit library not available on macOS.
2. `bash-preexec` was evaluated for command interception, but Ghostty already natively integrates `bash-preexec` and parses OSC 7 (PWD), OSC 133 (semantic prompt & command status), and OSC 2 (titles).
3. The color theme library `iTerm2-Color-Schemes` contains thousands of schemes; loading all at runtime causes resource bloat.

## Durable Decisions
1. **Curated Theme Ecosystem**:
   - Curated 112 popular, distinct themes from `iTerm2-Color-Schemes` packed into a compact 67KB `Themes.json`.
   - Built `ThemeManager` to dynamically load built-in themes and scan `~/Library/Application Support/MacSSH/themes/` for `.itermcolors` and Ghostty conf files.
   - Designed dual-theme pairing (adaptive Dark and Light selections based on system appearance) plus per-SSH host theme overrides (e.g. Red/Alert for production servers).
2. **Native SwiftUI Toast HUD**:
   - Built zero-dependency `ToastManager` and `ToastOverlayView` using `.ultraThinMaterial` glass capsules, Spring animations, and auto-dismiss timers, replacing external iOS-only packages.
3. **Ghostty Shell Integration**:
   - Injected `TERM_PROGRAM = "ghostty"` into local shell and SSH environments to trigger automatic shell integration hooks in zsh/bash/fish.
   - Extended `MactermKit` to surface `currentDirectoryChanged(url:)`, `titleChanged(title:)`, `tabTitleChanged(title:)`, and `commandFinished(exitCode:durationNs:)`.
   - Wired OSC 7 directory changes directly into `SFTPViewModel.navigateTo(path:)` for automatic remote-to-SFTP folder tracking.
   - Displayed Toast notifications when commands taking longer than 5 seconds complete or fail, accompanied by macOS system notifications when in background.


## Timeline

- time: 2026-10-17T17:42:38
  kind: decision
  summary: "Created this page: Modern Terminal Themes, Native Toast HUD, and Shell Integration Architecture"
  source: created via brain create-page
  affects: [terminal-themes-hud-shell-integration]

- time: 2026-10-17T17:42:46
  kind: decision
  summary: "Terminal themes ecosystem, native SwiftUI HUD, and Ghostty shell integration"
  source: brain update-truth
  affects: [terminal-themes-hud-shell-integration]

- time: 2026-10-17T18:11:05
  kind: decision
  summary: "Release version 2.2.0 with curated color themes, native HUD, dual-channel resilience, and updated documentation"
  affects: [terminal-themes-hud-shell-integration]
