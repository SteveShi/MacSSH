---
slug: stack
title: Tech stack
role: tech-stack choices
updated: "2026-08-21T06:38:35"
---

# Tech stack

| Domain | Technology | Rationale |
| :--- | :--- | :--- |
| **Language** | Swift 6.0 | Strict concurrency and low-level FFI safety |
| **Terminal Core** | `libghostty-swift` | Native Zig-based Ghostty terminal emulator with Metal GPU rendering |
| **SSH/SFTP Core** | `libssh2-swift` & AWS-LC | High-performance C SSH2 library backed by modern AWS-LC crypto |
| **Project Gen** | Tuist (`Project.swift`) | Multi-target modular workspace generation |
