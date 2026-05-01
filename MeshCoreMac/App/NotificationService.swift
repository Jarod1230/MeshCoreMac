// MeshCoreMac/App/NotificationService.swift
import UserNotifications
import Foundation

final class NotificationService: Sendable {

    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound, .badge]
        ) { _, _ in }
    }

    func sendNewMessageNotification(senderName: String, preview: String) {
        let content = UNMutableNotificationContent()
        content.title = senderName
        content.body = preview
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
