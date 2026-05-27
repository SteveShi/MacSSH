import Foundation
import Observation
import libssh2_swift

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
        transferTask?.cancel()
        status = .transferring(item.name)
        transferTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.service.download(remotePath: item.path, localURL: url)
                if Task.isCancelled { return }
                self.status = .idle
            } catch {
                if Task.isCancelled { return }
                self.status = .error(error.localizedDescription)
            }
        }
    }

    func download(_ items: [SFTPItem], to directory: URL) {
        transferTask?.cancel()
        status = .loading
        transferTask = Task { [weak self] in
            guard let self else { return }
            do {
                for item in items where !item.isDirectory {
                    if Task.isCancelled { return }
                    self.status = .transferring(item.name)
                    let target = directory.appendingPathComponent(item.name)
                    try await self.service.download(remotePath: item.path, localURL: target)
                }
                if Task.isCancelled { return }
                self.status = .idle
            } catch {
                if Task.isCancelled { return }
                self.status = .error(error.localizedDescription)
            }
        }
    }

    func upload(from url: URL) {
        transferTask?.cancel()
        status = .transferring(url.lastPathComponent)
        let target = currentPath.hasSuffix("/") ? currentPath + url.lastPathComponent : currentPath + "/" + url.lastPathComponent
        transferTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.service.upload(localURL: url, remotePath: target)
                if Task.isCancelled { return }
                self.refresh()
            } catch {
                if Task.isCancelled { return }
                self.status = .error(error.localizedDescription)
            }
        }
    }

    func upload(from urls: [URL]) {
        transferTask?.cancel()
        status = .loading
        transferTask = Task { [weak self] in
            guard let self else { return }
            do {
                for url in urls {
                    if Task.isCancelled { return }
                    self.status = .transferring(url.lastPathComponent)
                    let target = self.currentPath.hasSuffix("/")
                        ? self.currentPath + url.lastPathComponent
                        : self.currentPath + "/" + url.lastPathComponent
                    try await self.service.upload(localURL: url, remotePath: target)
                }
                if Task.isCancelled { return }
                self.refresh()
            } catch {
                if Task.isCancelled { return }
                self.status = .error(error.localizedDescription)
            }
        }
    }
}
