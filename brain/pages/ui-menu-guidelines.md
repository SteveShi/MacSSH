---
id: ui-menu-guidelines
title: UI menu placement conventions
category: decision
status: active
created: "2026-09-10T20:32:12"
updated: "2026-09-10T20:33:52"
---

<!-- compiled_truth -->
## Menu Placement Rules

### What's New Sheet (WhatsNewSheetView)
- **DO**: Place in Help menu (`CommandGroup(replacing: .help)`)
- **DO NOT**: Place in About / App Info menu (`CommandGroup(after: .appInfo)`)
- Rationale: The About menu should only contain About AppName and Check for Updates. What's New is informational/help content.

### About / App Info Menu
Allowed items only:
- About MacSSH (system-provided)
- Check for Updates… (Sparkle)

### Help Menu
- What's New in MacSSH


## Timeline

- time: 2026-09-10T20:32:12
  kind: decision
  summary: "Created this page: UI menu placement conventions"
  source: created via brain create-page
  affects: [ui-menu-guidelines]

- time: 2026-09-10T20:33:52
  kind: decision
  summary: "Establish menu placement rules: What's New in Help menu only, not in About/App Info menu"
  source: brain update-truth
  affects: [ui-menu-guidelines]
