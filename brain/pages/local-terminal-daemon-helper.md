---
id: local-terminal-daemon-helper
title: "Adopt Client-Daemon Terminal Helper (macsshd) and CLI (macssh-cli)"
category: decision
status: active
tags: [terminal, daemon, cli, architecture]
created: "2026-10-27T14:31:17"
updated: "2026-10-27T14:31:17"
---

<!-- compiled_truth -->
# Adopt Client-Daemon Terminal Helper (macsshd) and CLI (macssh-cli)

## Decision
MacSSH decouples local terminal PTY processes from the SwiftUI GUI lifecycle via a three-target architecture:
1. `MacSSHDaemonShared`: Shared Unix Domain Socket framing protocol (`~/Library/Application Support/MacSSH/run/macsshd.sock`), headless VT state machine (`ScreenRenderer`), and `tmux`-compatible key encoder (`KeyNames`).
2. `macsshd` (`Targets/MacSSHDaemon`): On-demand background daemon launched with `POSIX_SPAWN_SETSID` that owns local `PTYSession` instances (`forkpty` + `execve`), maintains a 256 KiB `ReplayRingBuffer` per session, queues large pastes via `pendingInput` + `DispatchSourceWrite`, tracks foreground process groups via `tcgetpgrp` and working directories via `PROC_PIDVNODEPATHINFO`, and exits after 30s of idle time only when `SessionRegistry` is empty.
3. `macssh-cli` (`Targets/MacSSHCLI`): Dual-mode binary embedded at `Contents/MacOS/macssh-cli` (and symlinkable to `macssh`). Runs `macssh-cli bridge --session <key>` inside `GhosttySurfaceView` to bridge `MactermKit` with `macsshd` without modifying `MactermKitCore.xcframework`, and provides `list`, `capture`, `send`, `new`, `kill`, and `ssh` commands for external automation and AI agents.


## Timeline

- time: 2026-10-27T14:31:17
  kind: decision
  summary: "Created this page: Adopt Client-Daemon Terminal Helper (macsshd) and CLI (macssh-cli)"
  source: created via brain create-page
  affects: [local-terminal-daemon-helper]

- time: 2026-10-27T14:31:17
  kind: decision
  summary: "Establish macsshd persistent PTY daemon, macssh-cli command-line tool and PTY bridge, and MacSSHDaemonShared protocol"
  source: brain update-truth
  affects: [local-terminal-daemon-helper]
