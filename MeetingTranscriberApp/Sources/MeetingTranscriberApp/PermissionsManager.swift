import Foundation
import AVFoundation
import ScreenCaptureKit

enum PermissionStatus: Equatable {
    case unknown
    case granted
    case denied
}

/// Checks and requests microphone, screen recording, and notification permissions.
class PermissionsManager: ObservableObject {
    @Published var micStatus: PermissionStatus = .unknown
    @Published var screenStatus: PermissionStatus = .unknown
    @Published var notificationStatus: PermissionStatus = .unknown

    /// Only mic + screen are required to proceed; notifications are optional.
    var allGranted: Bool { micStatus == .granted && screenStatus == .granted }

    /// Populate initial status without triggering OS prompts.
    func checkInitialStatuses() {
        micStatus = currentMicStatus()
        screenStatus = heuristicScreenStatus()
        Task { notificationStatus = await NotificationManager.shared.checkStatus() }
    }

    func requestMicAccess() async {
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        await MainActor.run { micStatus = granted ? .granted : .denied }
    }

    /// Triggers the screen recording permission prompt on first call.
    /// Subsequent calls return the cached OS decision without prompting.
    func requestScreenAccess() async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: false
            )
            await MainActor.run {
                screenStatus = content.displays.isEmpty ? .denied : .granted
            }
        } catch {
            await MainActor.run { screenStatus = .denied }
        }
    }

    func refreshMicStatus() {
        micStatus = currentMicStatus()
    }

    func openMicSettings() {
        NSWorkspace.shared.open(
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
        )
    }

    func openScreenSettings() {
        NSWorkspace.shared.open(
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        )
    }

    func requestNotificationAccess() {
        NotificationManager.shared.requestPermission()
        Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            let s = await NotificationManager.shared.checkStatus()
            await MainActor.run { notificationStatus = s }
        }
    }

    func refreshNotificationStatus() {
        Task {
            let s = await NotificationManager.shared.checkStatus()
            await MainActor.run { notificationStatus = s }
        }
    }

    func openNotificationSettings() {
        NSWorkspace.shared.open(
            URL(string: "x-apple.systempreferences:com.apple.preference.notifications")!
        )
    }

    // MARK: - Private

    private func currentMicStatus() -> PermissionStatus {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return .granted
        case .denied, .restricted: return .denied
        case .notDetermined: return .unknown
        @unknown default: return .unknown
        }
    }

    /// Heuristic: CGWindowList returns other-app windows only when screen recording is granted.
    private func heuristicScreenStatus() -> PermissionStatus {
        let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        let list = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] ?? []
        let myPID = Int32(ProcessInfo.processInfo.processIdentifier)
        let hasOtherWindows = list.contains { ($0[kCGWindowOwnerPID as String] as? Int32 ?? 0) != myPID }
        return hasOtherWindows ? .granted : .unknown
    }
}
