import Foundation
import os

private let storeLog = Logger(subsystem: "com.steveshi.macssh", category: "ConnectionsStore")

struct ConnectionsStore {
    static func load() -> [SSHConnection] {
        let url = storageURL()
        guard let data = try? Data(contentsOf: url) else { return [] }
        return decode(data)
    }

    static func save(_ connections: [SSHConnection]) {
        let url = storageURL()
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(connections)
            try data.write(to: url, options: .atomic)
        } catch {
            storeLog.error("Failed to save connections: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func export(_ connections: [SSHConnection], to url: URL) {
        do {
            let data = try JSONEncoder().encode(connections)
            try data.write(to: url, options: .atomic)
        } catch {
            storeLog.error("Failed to export connections: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func `import`(from url: URL) -> [SSHConnection]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return decode(data)
    }

    private static func decode(_ data: Data) -> [SSHConnection] {
        do {
            return try JSONDecoder().decode([SSHConnection].self, from: data)
        } catch {
            storeLog.error("Failed to decode connections: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    private static func storageURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = base.appendingPathComponent("MacSSH", isDirectory: true)
        return appDir.appendingPathComponent("connections.json")
    }
}
