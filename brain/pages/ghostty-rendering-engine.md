---
id: ghostty-rendering-engine
title: Adopt Ghostty core for terminal rendering
category: decision
status: active
created: "2026-08-21T06:38:35"
updated: "2026-08-22T22:04:51"
---

<!-- compiled_truth -->
Adopted MactermKit wrapping MactermKitCore.xcframework for 120fps Metal-accelerated terminal rendering and ANSI parsing with clean Swift 6 Concurrency.


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

- time: 2026-08-22T22:04:51
  kind: decision
  summary: Migrated binary xcframework to MactermKitCore.xcframework
  source: brain update-truth
  affects: [ghostty-rendering-engine]
