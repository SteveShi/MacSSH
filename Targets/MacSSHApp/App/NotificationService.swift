import AppKit
import UserNotifications
import MactermKit

/// Central place that turns app events into macOS system notifications, gated by
/// the user's `AppSettings`. All entry points are main-actor isolated.
@MainActor
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationService()
    
    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    private weak var settings: AppSettings?

    func configure(settings: AppSettings) {
        self.settings = settings
        UNUserNotificationCenter.current().delegate = self
    }

    /// Asks the system for notification permission (no-op if notifications are off).
    func requestAuthorizationIfNeeded() {
        guard settings?.notificationsEnabled == true else { return }
        Task {
            _ = try? await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Allow notifications to display as banners and play sounds even when the app is active
        completionHandler([.banner, .sound, .list])
    }

    // MARK: - SSH

    func notifyConnection(success: Bool, name: String) {
        guard let settings, settings.notificationsEnabled, settings.notifyConnectionEvents else { return }
        if success {
            send(title: String(localized: "SSH Connected"),
                 body: String(localized: "Connected to \(name)"))
        } else {
            send(title: String(localized: "SSH Connection Failed"),
                 body: String(localized: "Failed to connect to \(name)"))
        }
    }

    // MARK: - SFTP

    func notifySFTP(success: Bool, name: String) {
        guard let settings, settings.notificationsEnabled, settings.notifySFTPEvents else { return }
        send(title: success ? String(localized: "Transfer Complete")
                            : String(localized: "Transfer Failed"),
             body: name)
    }

    // MARK: - Local terminal

    func notifyTerminal(_ event: GhosttyTerminalEvent) {
        guard let settings, settings.notificationsEnabled else { return }
        switch event {
        case .desktopNotification(let title, let body):
            guard settings.notifyTerminalEvents else { return }
            send(title: title.isEmpty ? String(localized: "Terminal") : title, body: body)
        case .childExited(let exitCode):
            guard settings.notifyTerminalEvents else { return }
            send(title: String(localized: "Process Exited"),
                 body: String(localized: "Exited with code \(String(exitCode))"))
        case .bell:
            guard settings.notifyTerminalBell else { return }
            NSSound.beep()
            send(title: String(localized: "Terminal Bell"), body: "")
        }
    }

    // MARK: - Send

    private func send(title: String, body: String) {
        guard let settings else { return }
        // Avoid interrupting the user while they're actively in the app.
        if settings.notifyOnlyWhenInactive && NSApp.isActive { return }

        let content = UNMutableNotificationContent()
        content.title = title
        if !body.isEmpty { content.body = body }
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                NSLog("[NotificationService] Failed to schedule notification: \(error)")
            }
        }
    }
}
