import SwiftUI
import Observation
import MactermKit

@MainActor
@Observable
public final class TerminalProgramStatusStore {
    public private(set) var records: [String: GhosttyProgramStatusReport] = [:]
    public private(set) var osc9Progress: GhosttyProgressReport? = nil
    public var hoveredLink: String? = nil

    private static let maxRecords = 64
    private static let notificationCooldown: TimeInterval = 1.5
    private var lastNotificationTime: Date = .distantPast

    private static func sanitize(_ value: String, maxLength: Int) -> String {
        let stripped = String(value.unicodeScalars.filter { $0.value >= 0x20 && $0.value != 0x7F })
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if stripped.count > maxLength {
            return String(stripped.prefix(maxLength))
        }
        return stripped
    }

    public struct TransitionNotification: Sendable {
        public let report: GhosttyProgramStatusReport
        public let previousState: GhosttyProgramStatusState?

        public init(report: GhosttyProgramStatusReport, previousState: GhosttyProgramStatusState?) {
            self.report = report
            self.previousState = previousState
        }
    }

    public init() {}

    /// Applies an OSC 7501 Program Status Report. Returns a TransitionNotification if a significant state transition occurred.
    @discardableResult
    public func apply(_ report: GhosttyProgramStatusReport) -> TransitionNotification? {
        let sanitizedId = Self.sanitize(report.id, maxLength: 64)
        let sanitizedApp = Self.sanitize(report.app, maxLength: 64)
        let sanitizedTitle = Self.sanitize(report.title, maxLength: 256)
        let sanitizedMessage = Self.sanitize(report.message, maxLength: 256)

        if report.state == .clear {
            if sanitizedId.isEmpty {
                records.removeAll()
            } else {
                let prefix = "\(sanitizedId)/"
                records = records.filter { key, _ in
                    key != sanitizedId && !key.hasPrefix(prefix)
                }
            }
            return nil
        }

        if records[sanitizedId] == nil {
            if report.state == .idle {
                return nil
            }
            if records.count >= Self.maxRecords {
                records = records.filter { $0.value.state != .idle && $0.value.state != .done }
                if records.count >= Self.maxRecords {
                    return nil
                }
            }
        }

        // Inherit app: if sanitizedApp is empty, walk up ancestor id prefixes separated by "/"
        var resolvedApp = sanitizedApp
        if resolvedApp.isEmpty {
            if !sanitizedId.isEmpty {
                let segments = sanitizedId.split(separator: "/")
                if segments.count > 1 {
                    for i in stride(from: segments.count - 1, through: 1, by: -1) {
                        let ancestorKey = segments[0..<i].joined(separator: "/")
                        if let ancestor = records[ancestorKey], !ancestor.app.isEmpty {
                            resolvedApp = ancestor.app
                            break
                        }
                    }
                }
            }
            if resolvedApp.isEmpty {
                if let existing = records[sanitizedId]?.app, !existing.isEmpty {
                    resolvedApp = existing
                } else if let root = records[""]?.app, !root.isEmpty {
                    resolvedApp = root
                }
            }
        }

        let resolvedReport = GhosttyProgramStatusReport(
            state: report.state,
            kind: report.kind,
            progress: report.progress,
            id: sanitizedId,
            app: resolvedApp,
            title: sanitizedTitle,
            message: sanitizedMessage
        )

        let previousState = records[sanitizedId]?.state
        records[sanitizedId] = resolvedReport

        if previousState != resolvedReport.state &&
            (resolvedReport.state == .blocked || resolvedReport.state == .error || resolvedReport.state == .done) {
            let now = Date()
            guard now.timeIntervalSince(lastNotificationTime) >= Self.notificationCooldown else {
                return nil
            }
            lastNotificationTime = now
            return TransitionNotification(report: resolvedReport, previousState: previousState)
        }
        return nil
    }

    /// Applies a ConEmu OSC 9;4 progress report.
    public func applyProgress(_ report: GhosttyProgressReport) {
        if report.state == .remove {
            osc9Progress = nil
        } else {
            osc9Progress = report
        }
    }

    /// Removes working and blocked statuses when a shell command finishes.
    public func clearWorkingOnCommandFinished() {
        records = records.filter { _, report in
            report.state != .working && report.state != .blocked
        }
        osc9Progress = nil
    }

    /// Acknowledges and dismisses completed (.done) statuses.
    public func acknowledgeDoneStatuses() {
        records = records.filter { _, report in
            report.state != .done
        }
    }

    /// Resets all program status and progress tracking.
    public func reset() {
        records.removeAll()
        osc9Progress = nil
        hoveredLink = nil
        lastNotificationTime = .distantPast
    }

    // MARK: - Computed Properties for UI

    private func statePriority(_ state: GhosttyProgramStatusState) -> Int {
        switch state {
        case .blocked: return 4
        case .error: return 3
        case .working: return 2
        case .done: return 1
        case .idle, .clear: return 0
        }
    }

    /// Active record (state != .idle && state != .clear) with highest priority.
    public var primaryReport: GhosttyProgramStatusReport? {
        let active = records.values.filter { $0.state != .idle && $0.state != .clear }
        return active.max { a, b in
            let prioA = statePriority(a.state)
            let prioB = statePriority(b.state)
            if prioA != prioB {
                return prioA < prioB
            }
            if a.id.isEmpty != b.id.isEmpty {
                return !a.id.isEmpty && b.id.isEmpty
            }
            return a.id > b.id
        }
    }

    /// Effective progress percentage (0...100).
    public var effectiveProgress: Int? {
        if let report = primaryReport, (0...100).contains(Int(report.progress)) {
            return Int(report.progress)
        }
        if let osc9 = osc9Progress, osc9.state != .remove, (0...100).contains(Int(osc9.progress)) {
            return Int(osc9.progress)
        }
        return nil
    }

    /// Concise label from title or app.
    public var badgeTitle: String? {
        guard let report = primaryReport else { return nil }
        if !report.title.isEmpty { return report.title }
        if !report.app.isEmpty { return report.app }
        return nil
    }

    /// Concise single-line summary for status bar.
    public var statusSummaryText: String? {
        guard let report = primaryReport else {
            if let progress = effectiveProgress {
                return "\(progress)%"
            }
            return nil
        }

        var parts: [String] = []
        let name = !report.app.isEmpty ? report.app : (!report.title.isEmpty ? report.title : nil)
        if let name {
            parts.append(name)
        }
        if !report.message.isEmpty {
            parts.append(report.message)
        }
        if let progress = effectiveProgress {
            parts.append("\(progress)%")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Whether there is any visible link or status content for the status bar.
    public var hasVisibleStatusBarContent: Bool {
        (hoveredLink?.isEmpty == false) || statusSummaryText != nil
    }

    /// Tooltip description for .help(...).
    public var tooltipText: String? {
        if let report = primaryReport {
            var lines: [String] = []
            let stateDesc: String
            switch report.state {
            case .blocked: stateDesc = String(localized: "Waiting for Input")
            case .error: stateDesc = String(localized: "Error")
            case .working: stateDesc = String(localized: "Running")
            case .done: stateDesc = String(localized: "Completed")
            case .idle: stateDesc = String(localized: "Idle")
            case .clear: stateDesc = ""
            }
            if !stateDesc.isEmpty {
                lines.append(stateDesc)
            }
            if !report.app.isEmpty {
                lines.append("\(String(localized: "App")): \(report.app)")
            }
            if !report.title.isEmpty {
                lines.append("\(String(localized: "Title")): \(report.title)")
            }
            if !report.message.isEmpty {
                lines.append("\(String(localized: "Message")): \(report.message)")
            }
            if let progress = effectiveProgress {
                lines.append("\(String(localized: "Progress")): \(progress)%")
            }
            return lines.isEmpty ? nil : lines.joined(separator: "\n")
        } else if let progress = effectiveProgress {
            return "\(String(localized: "Progress")): \(progress)%"
        }
        return nil
    }
}

// MARK: - SwiftUI Views

public struct ProgramStatusBadgeView: View {
    let store: TerminalProgramStatusStore

    public init(store: TerminalProgramStatusStore) {
        self.store = store
    }

    public var body: some View {
        Group {
            if let report = store.primaryReport {
                switch report.state {
                case .blocked:
                    Image(systemName: "exclamationmark.bubble.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.orange)

                case .error:
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.red)

                case .working:
                    if let progress = store.effectiveProgress {
                        Text("\(progress)%")
                            .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(.cyan)
                    } else {
                        ProgressView()
                            .controlSize(.mini)
                    }

                case .done:
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.green)

                case .idle, .clear:
                    EmptyView()
                }
            } else if let progress = store.effectiveProgress {
                Text("\(progress)%")
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(.cyan)
            }
        }
        .help(store.tooltipText ?? "")
    }
}

public struct ProgramStatusBarItemView: View {
    let store: TerminalProgramStatusStore

    public init(store: TerminalProgramStatusStore) {
        self.store = store
    }

    public var body: some View {
        if let link = store.hoveredLink, !link.isEmpty {
            HStack(spacing: 4) {
                Image(systemName: "link")
                    .font(.system(size: 10))
                Text(link)
                    .font(.system(size: 10, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .foregroundStyle(.secondary)
        } else if let summary = store.statusSummaryText {
            HStack(spacing: 4) {
                if let report = store.primaryReport {
                    switch report.state {
                    case .blocked:
                        Image(systemName: "exclamationmark.bubble.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.orange)
                    case .error:
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.red)
                    case .working:
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.cyan)
                    case .done:
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.green)
                    default:
                        EmptyView()
                    }
                } else if store.effectiveProgress != nil {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10))
                        .foregroundStyle(.cyan)
                }
                Text(summary)
                    .font(.system(size: 10))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(.secondary)
            }
            .help(store.tooltipText ?? "")
        }
    }
}
