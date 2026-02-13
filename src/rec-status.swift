import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.action = #selector(stopClicked)
        statusItem.button?.target = self
        statusItem.button?.attributedTitle = NSAttributedString(
            string: "● REC",
            attributes: [
                .foregroundColor: NSColor.red,
                .font: NSFont.systemFont(ofSize: 12, weight: .medium)
            ]
        )

        // Auto-exit if parent process dies (check every second)
        let parentPID = getppid()
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            if getppid() != parentPID {
                NSApp.terminate(nil)
            }
        }
    }

    @objc func stopClicked() {
        print("stop")
        fflush(stdout)
        NSApp.terminate(nil)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
