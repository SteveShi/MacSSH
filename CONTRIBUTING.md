# Contributing to MacSSH

Thank you for your interest in contributing to **MacSSH**! MacSSH is a modern, high-performance native SSH terminal client for macOS.

We welcome bug reports, feature requests, documentation enhancements, and pull requests from everyone.

---

## Code of Conduct

All contributors and participants are expected to adhere to our [Code of Conduct](CODE_OF_CONDUCT.md). Please report unacceptable behavior to **xuanlian@mac.com**.

---

## Development Setup

### Prerequisites
- macOS 15.0+ (macOS 26 Tahoe recommended)
- Xcode 16.0+ (Swift 6.0+ toolchain)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

### Getting Started
1. Fork the repository and clone your fork locally:
   ```bash
   git clone https://github.com/<your-username>/MacSSH.git
   cd MacSSH
   ```
2. Generate the Xcode project:
   ```bash
   open MacSSH.xcodeproj
   ```
3. Open the generated project in Xcode.

---

## Contribution Guidelines

1. **Always Target `main`**: All feature branches and pull requests must be based on and target `main` (never `master`).
   ```bash
   git checkout -b feature/your-feature-name
   ```
2. **Swift 6 & Modern Standards**:
   - Write clean, idiomatic Swift with full Swift 6 Concurrency checks enabled.
   - Decouple business logic and persistence from SwiftUI view declarations.
   - Use `@Observable` for observable state models.
3. **Zero Hardcoded User-Facing Strings**:
   - All user-visible strings must be localized using String Catalogs (`Localizable.xcstrings`).
   - Never commit hardcoded string literals for UI labels or alerts.

4. **Verification & Testing**:
   - Verify that the project compiles cleanly without warnings:
     ```bash
     xcodebuild -scheme MacSSH -destination 'platform=macOS' build
     ```
5. **Commit Conventions**:
   - Write clear, concise commit messages following Conventional Commits (e.g., `feat: ...`, `fix: ...`, `docs: ...`, `refactor: ...`).
6. **Submitting a Pull Request**:
   - Push your branch to your fork and submit a PR against `main`.
   - Provide a clear summary of what changes were made, why they are needed, and how they were tested.

---

## License

By contributing to MacSSH, you agree that your contributions will be licensed under the [MIT License](LICENSE).
