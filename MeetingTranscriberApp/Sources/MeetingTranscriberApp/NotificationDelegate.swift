import UserNotifications

/// UNUserNotificationCenterDelegate — routes notification clicks to the transcript viewer.
class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    /// Called on the main thread with the transcript stem when the user taps a notification.
    var onTranscriptClicked: ((String) -> Void)?

    /// Handle tap on a delivered notification — open the transcript viewer.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let path = response.notification.request.content.userInfo["transcriptPath"] as? String ?? ""
        let stem = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        DispatchQueue.main.async { self.onTranscriptClicked?(stem) }
        completionHandler()
    }

    /// Show banner + play sound even when the app is in the foreground.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
