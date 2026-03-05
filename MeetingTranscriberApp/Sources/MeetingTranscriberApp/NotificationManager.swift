import Foundation
import UserNotifications

/// Wraps UNUserNotificationCenter for posting transcript-ready notifications.
class NotificationManager {
    static let shared = NotificationManager()
    private init() {}

    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func sendTranscriptReady(stem: String, transcriptPath: String) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized ||
                  settings.authorizationStatus == .provisional else { return }

            let content = UNMutableNotificationContent()
            content.title = "Transcript Ready"
            content.body = Self.formatStem(stem)
            content.sound = .default
            content.userInfo = ["transcriptPath": transcriptPath]

            let request = UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: nil
            )
            UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
        }
    }

    func checkStatus() async -> PermissionStatus {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional: return .granted
        case .denied:                   return .denied
        case .notDetermined:            return .unknown
        @unknown default:               return .unknown
        }
    }

    // MARK: - Private

    /// Converts e.g. "2026-02-13T14-30-00" → "Feb 13, 2026 at 2:30 PM"
    private static func formatStem(_ stem: String) -> String {
        let isoLike = stem.replacingOccurrences(of: "T", with: "T")
                          .replacingOccurrences(of: #"(\d{4}-\d{2}-\d{2})T(\d{2})-(\d{2})-(\d{2})"#,
                                                with: "$1T$2:$3:$4",
                                                options: .regularExpression)
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime, .withDashSeparatorInDate]
        if let date = fmt.date(from: isoLike) {
            let df = DateFormatter()
            df.dateStyle = .medium
            df.timeStyle = .short
            return df.string(from: date)
        }
        return stem
    }
}
