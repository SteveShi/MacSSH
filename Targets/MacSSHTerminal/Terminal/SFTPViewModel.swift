import Foundation
import Observation
import SSH2Kit

@MainActor
@Observable
final class SFTPViewModel {
    enum Status: Equatable {
        case idle
        case loading
        case transferring(String)
        case error(String)
    }

    private let service: SFTPService
    var currentPath: String = "."
    var items: [SFTPItem] = []
    var status: Status = .idle
    var settings: AppSettings? = nil

    /// Tracks the currently running directory listing / refresh so that a new
    /// navigation cancels any in-flight one. Without this, fast clicks could
    /// race and stale results from an earlier directory would overwrite the
    /// newer ones in `items`.
    private var refreshTask: Task<Void, Never>?
    private var transferTask: Task<Void, Never>?

    init(service: SFTPService) {
        self.service = service
    }

    func refresh() {
        refreshTask?.cancel()
        status = .loading
        let path = currentPath
        refreshTask = Task { [weak self] in
            guard let self else { return }
            do {
                let items = try await self.service.list(path: path)
                if Task.isCancelled { return }
                // Drop the result if the user navigated away while we were waiting.
                guard path == self.currentPath else { return }
                self.items = items
                self.status = .idle
            } catch {
                if Task.isCancelled { return }
                self.status = .error(error.localizedDescription)
            }
        }
    }

    func changeDirectory(_ item: SFTPItem) {
        guard item.isDirectory else { return }
        currentPath = item.path
        refresh()
    }

    func goUp() {
        guard currentPath != "." else { return }
        let url = URL(fileURLWithPath: currentPath)
        let parent = url.deletingLastPathComponent().path
        currentPath = parent.isEmpty ? "/" : parent
        refresh()
    }

    func download(_ item: SFTPItem, to url: URL) {
        let shouldOverwrite = settings?.overwriteExistingFiles ?? AppSettings().overwriteExistingFiles
        if !shouldOverwrite && FileManager.default.fileExists(atPath: url.path) {
            self.status = .error(String(localized: "File already exists. Overwrite is disabled in Settings."))
            return
        }

        transferTask?.cancel()
        status = .transferring(item.name)
        transferTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.service.download(remotePath: item.path, localURL: url)
                if Task.isCancelled { return }
                self.status = .idle
                NotificationService.shared.notifySFTP(success: true, name: item.name)
            } catch {
                if Task.isCancelled { return }
                self.status = .error(error.localizedDescription)
                NotificationService.shared.notifySFTP(success: false, name: item.name)
            }
        }
    }

    func download(_ items: [SFTPItem], to directory: URL) {
        let shouldOverwrite = settings?.overwriteExistingFiles ?? AppSettings().overwriteExistingFiles
        transferTask?.cancel()
        status = .loading
        transferTask = Task { [weak self] in
            guard let self else { return }
            do {
                var skippedCount = 0
                for item in items where !item.isDirectory {
                    if Task.isCancelled { return }
                    let target = directory.appendingPathComponent(item.name)
                    if !shouldOverwrite && FileManager.default.fileExists(atPath: target.path) {
                        skippedCount += 1
                        continue
                    }
                    self.status = .transferring(item.name)
                    try await self.service.download(remotePath: item.path, localURL: target)
                }
                if Task.isCancelled { return }
                self.status = .idle
                let summaryName = skippedCount > 0
                    ? String(localized: "Transferred with \(skippedCount) skipped")
                    : String(localized: "Multiple files")
                NotificationService.shared.notifySFTP(success: true, name: summaryName)
            } catch {
                if Task.isCancelled { return }
                self.status = .error(error.localizedDescription)
                NotificationService.shared.notifySFTP(success: false, name: String(localized: "Multiple files"))
            }
        }
    }

    func upload(from url: URL) {
        let filename = url.lastPathComponent
        let shouldOverwrite = settings?.overwriteExistingFiles ?? AppSettings().overwriteExistingFiles
        if !shouldOverwrite && items.contains(where: { $0.name == filename }) {
            self.status = .error(String(localized: "Remote file already exists. Overwrite is disabled in Settings."))
            return
        }

        transferTask?.cancel()
        status = .transferring(filename)
        let target = (currentPath as NSString).appendingPathComponent(filename)
        transferTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.service.upload(localURL: url, remotePath: target)
                if Task.isCancelled { return }
                self.refresh()
                NotificationService.shared.notifySFTP(success: true, name: filename)
            } catch {
                if Task.isCancelled { return }
                self.status = .error(error.localizedDescription)
                NotificationService.shared.notifySFTP(success: false, name: filename)
            }
        }
    }

    func upload(from urls: [URL]) {
        let shouldOverwrite = settings?.overwriteExistingFiles ?? AppSettings().overwriteExistingFiles
        transferTask?.cancel()
        status = .loading
        transferTask = Task { [weak self] in
            guard let self else { return }
            do {
                var skippedCount = 0
                for url in urls {
                    if Task.isCancelled { return }
                    let filename = url.lastPathComponent
                    if !shouldOverwrite && self.items.contains(where: { $0.name == filename }) {
                        skippedCount += 1
                        continue
                    }
                    self.status = .transferring(filename)
                    let target = (self.currentPath as NSString).appendingPathComponent(filename)
                    try await self.service.upload(localURL: url, remotePath: target)
                }
                if Task.isCancelled { return }
                self.refresh()
                let summaryName = skippedCount > 0
                    ? String(localized: "Uploaded with \(skippedCount) skipped")
                    : String(localized: "Multiple files")
                NotificationService.shared.notifySFTP(success: true, name: summaryName)
            } catch {
                if Task.isCancelled { return }
                self.status = .error(error.localizedDescription)
                NotificationService.shared.notifySFTP(success: false, name: String(localized: "Multiple files"))
            }
        }
    }
}
