import Foundation
import UserNotifications
import os

final class NotificationManager {
    static let shared = NotificationManager()
    private let logger = Logger(subsystem: "com.orca.whisper", category: "Notifications")

    private init() {
        requestAuthorization()
    }

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [weak self] granted, error in
            if let error = error {
                self?.logger.error("Notification authorization error: \(error.localizedDescription)")
            } else {
                self?.logger.debug("Notification permission granted: \(granted)")
            }
        }
    }

    func showNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { [weak self] error in
            if let error = error {
                self?.logger.error("Failed to present notification: \(error.localizedDescription)")
            }
        }
    }
}
