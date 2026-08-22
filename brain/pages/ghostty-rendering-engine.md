---
id: ghostty-rendering-engine
title: Adopt Ghostty core for terminal rendering
category: decision
status: active
created: "2026-08-21T06:38:35"
updated: "2026-08-22T20:38:45"
---

<!-- compiled_truth -->
Adopted libghostty-swift wrapping GhosttyKit.xcframework for 120fps Metal-accelerated terminal rendering and ANSI parsing; eliminated legacy libghostty-vt.dylib binary and embedding script.


## Timeline

- time: 2026-08-21T06:38:35
  kind: decision
  summary: "Created this page: Adopt Ghostty core for terminal rendering"
  source: git log
  affects: [ghostty-rendering-engine]

- time: 2026-08-21T06:38:35
  kind: decision
  summary: Adopted Ghostty core for terminal rendering.
  source: git log
  affects: [ghostty-rendering-engine]

- time: 2026-08-22T20:38:45
  kind: decision
  summary: Migrated fully to GhosttyKit.xcframework and removed legacy libghostty-vt.dylib
  source: brain update-truth
  affects: [ghostty-rendering-engine]
