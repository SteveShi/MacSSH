import Foundation

/// Manages persistent storage of scrollback history for local terminal tabs.
/// Data is stored under `~/Library/Application Support/MacSSH/local_session_history/`.
@MainActor
public final class SessionHistoryStore {
    public static let shared = SessionHistoryStore()

    public struct Metadata: Codable, Sendable {
        public let quittedAt: Date
        public let tabName: String

        public init(quittedAt: Date, tabName: String) {
            self.quittedAt = quittedAt
            self.tabName = tabName
        }
    }

    private let fileManager = FileManager.default
    private let historyDir: URL

    private init() {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        self.historyDir = appSupport.appendingPathComponent("MacSSH/local_session_history")
        ensureDirectoryExists()
    }

    private func ensureDirectoryExists() {
        if !fileManager.fileExists(atPath: historyDir.path) {
            try? fileManager.createDirectory(at: historyDir, withIntermediateDirectories: true)
        }
    }

    private func textFileURL(for tabID: UUID) -> URL {
        historyDir.appendingPathComponent("\(tabID.uuidString).txt")
    }

    private func metaFileURL(for tabID: UUID) -> URL {
        historyDir.appendingPathComponent("\(tabID.uuidString).meta.json")
    }

    /// Saves the scrollback text and metadata for a specific tab.
    public func save(tabID: UUID, text: String, metadata: Metadata) {
        ensureDirectoryExists()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            remove(tabID: tabID)
            return
        }

        let textURL = textFileURL(for: tabID)
        let metaURL = metaFileURL(for: tabID)

        do {
            try text.write(to: textURL, atomically: true, encoding: .utf8)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let metaData = try encoder.encode(metadata)
            try metaData.write(to: metaURL, options: .atomic)
        } catch {
            NSLog("[SessionHistoryStore] Failed to save history for tab \(tabID): \(error)")
        }
    }

    /// Loads the saved scrollback text and metadata for a tab, if available.
    public func load(tabID: UUID) -> (text: String, metadata: Metadata)? {
        let textURL = textFileURL(for: tabID)
        let metaURL = metaFileURL(for: tabID)

        guard fileManager.fileExists(atPath: textURL.path),
              fileManager.fileExists(atPath: metaURL.path),
              let text = try? String(contentsOf: textURL, encoding: .utf8),
              let metaData = try? Data(contentsOf: metaURL) else {
            return nil
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let metadata = try? decoder.decode(Metadata.self, from: metaData) else {
            return nil
        }

        return (text, metadata)
    }

    /// Removes history files for the specified tab ID.
    public func remove(tabID: UUID) {
        let textURL = textFileURL(for: tabID)
        let metaURL = metaFileURL(for: tabID)
        try? fileManager.removeItem(at: textURL)
        try? fileManager.removeItem(at: metaURL)
    }

    /// Cleans up orphaned history files not associated with any active tab ID.
    public func prune(activeTabIDs: Set<UUID>) {
        guard !activeTabIDs.isEmpty else { return }
        guard let contents = try? fileManager.contentsOfDirectory(at: historyDir, includingPropertiesForKeys: nil) else {
            return
        }

        for fileURL in contents {
            var rawName = fileURL.lastPathComponent
            if rawName.hasSuffix(".meta.json") {
                rawName = String(rawName.dropLast(".meta.json".count))
            } else if rawName.hasSuffix(".txt") {
                rawName = String(rawName.dropLast(".txt".count))
            } else {
                continue
            }
            if let uuid = UUID(uuidString: rawName), !activeTabIDs.contains(uuid) {
                try? fileManager.removeItem(at: fileURL)
            }
        }
    }

    /// Clears all saved session history files.
    public func clearAll() {
        guard let contents = try? fileManager.contentsOfDirectory(at: historyDir, includingPropertiesForKeys: nil) else {
            return
        }
        for fileURL in contents {
            try? fileManager.removeItem(at: fileURL)
        }
    }
}
