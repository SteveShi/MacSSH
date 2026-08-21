---
slug: architecture
title: System architecture
role: system architecture
updated: "2026-08-21T06:38:34"
---

# System architecture

```mermaid
graph TD
    App[MacSSH App] --> Terminal[Terminal Surface via libghostty-swift]
    App --> SFTP[SFTP Manager via libssh2-swift]
    App --> Keychain[macOS Keychain Store]
    App --> Session[SSH Session Coordinator]
    Session --> Net[AWS-LC & libssh2 Network Layer]
```
