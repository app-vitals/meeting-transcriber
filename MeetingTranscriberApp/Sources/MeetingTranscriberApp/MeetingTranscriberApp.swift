import Cocoa
import SwiftUI

/// App entry point. Uses @main with a static main() so Swift Package Manager
/// does not require a main.swift file.
///
/// Sets LSUIElement behaviour via NSApp.setActivationPolicy(.accessory) —
/// the app appears only in the menu bar with no Dock icon.
@main
struct MeetingTranscriberApp {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        let delegate = AppDelegate()
        app.delegate = delegate

        app.run()
    }
}

// MARK: - AppDelegate

class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()
    let processManager = ProcessManager()
    var menuBarController: MenuBarController?
    var onboardingWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        processManager.appState = appState
        menuBarController = MenuBarController(
            appState: appState,
            processManager: processManager,
            onShowSetupWizard: { [weak self] in self?.showOnboarding(startEngineOnComplete: false) }
        )

        if UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
            processManager.start()
        } else {
            showOnboarding(startEngineOnComplete: true)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        processManager.shutdown()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    // MARK: - Onboarding

    func showOnboarding(startEngineOnComplete: Bool) {
        // Bring an already-open onboarding window to front if re-running wizard.
        if let existing = onboardingWindow {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = OnboardingView {
            UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
            self.onboardingWindow?.close()
            self.onboardingWindow = nil
            if startEngineOnComplete {
                self.processManager.start()
            }
        }

        let controller = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: controller)
        window.title = "Meeting Transcriber — Setup"
        window.setContentSize(NSSize(width: 540, height: 460))
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        onboardingWindow = window
    }
}
