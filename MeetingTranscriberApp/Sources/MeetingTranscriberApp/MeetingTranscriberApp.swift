import Cocoa

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

    func applicationDidFinishLaunching(_ notification: Notification) {
        processManager.appState = appState
        menuBarController = MenuBarController(appState: appState, processManager: processManager)
        processManager.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        processManager.shutdown()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
}
