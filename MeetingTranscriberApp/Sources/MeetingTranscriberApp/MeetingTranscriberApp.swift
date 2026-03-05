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
    let transcriptStore = TranscriptStore(dir: AppConfig.shared.resolvedTranscriptDir)
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
            onOpenSettings: { [weak self] in self?.showSettings() },
            onInstallCLI: { [weak self] in self?.runCLIScript("install-cli-command.sh") },
            onUninstallCLI: { [weak self] in self?.runCLIScript("uninstall-cli-command.sh") }
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
        NSWorkspace.shared.open(AppConfig.shared.resolvedTranscriptDir)
    }

    // MARK: - Settings

    func showSettings() {
        if let existing = settingsWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = SettingsView(
            onInstallCLI:       { [weak self] in self?.runCLIScript("install-cli-command.sh") },
            onRerunSetupWizard: { [weak self] in self?.showOnboarding(startEngineOnComplete: false) }
        )
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

    // MARK: - CLI Install / Uninstall

    /// Runs one of the CLI shell scripts from Contents/Resources/ and shows the output in an alert.
    private func runCLIScript(_ scriptName: String) {
        let executableURL = URL(fileURLWithPath: ProcessInfo.processInfo.arguments[0])
            .resolvingSymlinksInPath()
        let resourcesURL = executableURL
            .deletingLastPathComponent()   // MacOS/
            .deletingLastPathComponent()   // Contents/
            .appendingPathComponent("Resources")
        let scriptURL = resourcesURL.appendingPathComponent(scriptName)

        guard FileManager.default.isExecutableFile(atPath: scriptURL.path) else {
            showAlert(
                title: "Script Not Found",
                message: "Could not locate \(scriptName) in the app bundle.\nTry reinstalling from the latest DMG.",
                style: .critical
            )
            return
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        task.arguments = [scriptURL.path]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            showAlert(title: "Error", message: error.localizedDescription, style: .critical)
            return
        }

        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let success = task.terminationStatus == 0
        showAlert(
            title: success ? "Done" : "Error",
            message: output.trimmingCharacters(in: .whitespacesAndNewlines),
            style: success ? .informational : .critical
        )
    }

    private func showAlert(title: String, message: String, style: NSAlert.Style) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = message
            alert.alertStyle = style
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
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
