import SwiftUI
import Observation

public enum ToastPreset: Sendable, Equatable {
    case done
    case error
    case warning
    case info
    case custom(systemImage: String, tintColor: Color)
}

public struct ToastItem: Identifiable, Sendable, Equatable {
    public let id = UUID()
    public let title: String
    public let message: String?
    public let preset: ToastPreset
    public let duration: TimeInterval

    public init(
        title: String,
        message: String? = nil,
        preset: ToastPreset = .done,
        duration: TimeInterval = 2.5
    ) {
        self.title = title
        self.message = message
        self.preset = preset
        self.duration = duration
    }
}

@Observable
@MainActor
public final class ToastManager {
    public static let shared = ToastManager()

    public private(set) var currentToast: ToastItem?
    private var dismissTask: Task<Void, Never>?

    private init() {}

    public func show(
        _ title: String,
        message: String? = nil,
        preset: ToastPreset = .done,
        duration: TimeInterval = 2.5
    ) {
        let item = ToastItem(title: title, message: message, preset: preset, duration: duration)
        show(item)
    }

    public func show(
        _ title: String,
        message: String? = nil,
        type: ToastPreset,
        duration: TimeInterval = 2.5
    ) {
        show(title, message: message, preset: type, duration: duration)
    }

    public func showDone(_ title: String, message: String? = nil, duration: TimeInterval = 2.5) {
        show(title, message: message, preset: .done, duration: duration)
    }

    public func showError(_ title: String, message: String? = nil, duration: TimeInterval = 3.0) {
        show(title, message: message, preset: .error, duration: duration)
    }

    public func show(_ toast: ToastItem) {
        dismissTask?.cancel()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            self.currentToast = toast
        }

        dismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(toast.duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.25)) {
                if self.currentToast?.id == toast.id {
                    self.currentToast = nil
                }
            }
        }
    }

    public func dismiss() {
        dismissTask?.cancel()
        withAnimation(.easeInOut(duration: 0.2)) {
            self.currentToast = nil
        }
    }
}
