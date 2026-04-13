import Foundation
import UserNotifications
import AppKit

@MainActor
final class NotificationManager: ObservableObject {
    static let shared = NotificationManager()

    private let center = UNUserNotificationCenter.current()

    private init() {}

    // MARK: - Request Permission

    func requestPermission() {
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error {
                print("[VoxFlow] Notification permission error: \(error.localizedDescription)")
            }
            if !granted {
                print("[VoxFlow] Notification permission denied")
            }
        }
    }

    // MARK: - Send Transcription Complete

    func sendTranscriptionComplete(text: String) {
        // Don't send if app is frontmost — avoid spamming the user
        guard !NSApp.isActive else { return }

        let content = UNMutableNotificationContent()
        content.title = "VoxFlow"
        content.subtitle = "Transcricao concluida"
        content.body = String(text.prefix(100))
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "voxflow-transcription-\(UUID().uuidString)",
            content: content,
            trigger: nil // Deliver immediately
        )

        center.add(request) { error in
            if let error {
                print("[VoxFlow] Failed to deliver notification: \(error.localizedDescription)")
            }
        }
    }
}
