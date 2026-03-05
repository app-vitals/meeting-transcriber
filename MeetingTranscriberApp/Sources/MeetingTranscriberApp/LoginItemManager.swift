import Foundation
import ServiceManagement

/// Wraps SMAppService to register/unregister the app as a macOS login item.
///
/// Uses the `mainApp` variant — no helper bundle required. The app appears in
/// System Settings → General → Login Items when registered.
class LoginItemManager: ObservableObject {
    static let shared = LoginItemManager()

    @Published private(set) var isEnabled: Bool = false

    private init() {
        refresh()
    }

    /// Refresh `isEnabled` from the live SMAppService status.
    func refresh() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    /// Register the app as a login item. No-op if already registered.
    func register() {
        do {
            if SMAppService.mainApp.status != .enabled {
                try SMAppService.mainApp.register()
            }
            isEnabled = true
        } catch {
            print("[LoginItemManager] register failed: \(error.localizedDescription)")
            refresh()
        }
    }

    /// Unregister the app from login items.
    func unregister() {
        do {
            try SMAppService.mainApp.unregister()
            isEnabled = false
        } catch {
            print("[LoginItemManager] unregister failed: \(error.localizedDescription)")
            refresh()
        }
    }

    func setEnabled(_ enabled: Bool) {
        if enabled { register() } else { unregister() }
    }

    /// Human-readable status for diagnostics.
    var statusDescription: String {
        switch SMAppService.mainApp.status {
        case .enabled:           return "Enabled"
        case .notRegistered:     return "Not registered"
        case .requiresApproval:  return "Requires approval in System Settings"
        case .notFound:          return "Not found (app not in /Applications?)"
        @unknown default:        return "Unknown"
        }
    }
}
