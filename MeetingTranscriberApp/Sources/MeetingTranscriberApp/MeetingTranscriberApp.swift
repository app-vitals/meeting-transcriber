import Cocoa
import SwiftUI
import UserNotifications

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
    let transcriptStore = TranscriptStore()
    let notificationDelegate = NotificationDelegate()
    var menuBarController: MenuBarController?
    var onboardingWindow: NSWindow?
    var transcriptViewerWindow: NSWindow?
    var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Register notification delegate so clicks open the transcript viewer.
        notificationDelegate.onTranscriptClicked = { [weak self] stem in
            self?.showTranscriptViewer(highlightID: stem)
        }
        UNUserNotificationCenter.current().delegate = notificationDelegate

        processManager.appState = appState

        // Auto-open viewer and highlight new transcript when transcription completes.
        processManager.onTranscriptSaved = { [weak self] stem in
            self?.showTranscriptViewer(highlightID: stem)
        }

        menuBarController = MenuBarController(
            appState: appState,
            processManager: processManager,
            onShowSetupWizard: { [weak self] in self?.showOnboarding(startEngineOnComplete: false) },
            onViewTranscripts: { [weak self] in self?.showTranscriptViewer() },
            onOpenTranscriptsFolder: { [weak self] in self?.openTranscriptsFolder() },
            onOpenSettings: { [weak self] in self?.showSettings() }
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

    // MARK: - Transcript Viewer

    func showTranscriptViewer(highlightID: String? = nil) {
        // Update selection before showing the window so the view picks it up.
        if let id = highlightID {
            transcriptStore.selectedID = id
        }

        if let existing = transcriptViewerWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        // Restore last-viewed transcript if no specific highlight was requested.
        if transcriptStore.selectedID == nil {
            transcriptStore.selectedID = UserDefaults.standard.string(forKey: "lastViewedTranscriptID")
        }

        let view = TranscriptWindowView(store: transcriptStore)
        let controller = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: controller)
        window.title = "Meeting Transcripts"
        window.setContentSize(NSSize(width: 900, height: 580))
        window.minSize = NSSize(width: 600, height: 400)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        transcriptViewerWindow = window
    }

    private func openTranscriptsFolder() {
        NSWorkspace.shared.open(TranscriptStore.defaultDir)
    }

    // MARK: - Settings

    func showSettings() {
        if let existing = settingsWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = SettingsView()
        let controller = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: controller)
        window.title = "Meeting Transcriber — Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        settingsWindow = window
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
