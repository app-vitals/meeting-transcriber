import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var isRecording = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.action = #selector(buttonClicked)
        statusItem.button?.target = self
        setIdle()

        // Auto-exit if parent process dies (check every second)
        let parentPID = getppid()
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            if getppid() != parentPID {
                NSApp.terminate(nil)
            }
        }

        // Read commands from stdin on a background thread
        DispatchQueue.global(qos: .userInitiated).async {
            while let line = readLine() {
                let command = line.trimmingCharacters(in: .whitespacesAndNewlines)
                DispatchQueue.main.async {
                    switch command {
                    case "record":
                        self.setRecording()
                    case "idle":
                        self.setIdle()
                    default:
                        break
                    }
                }
            }
            // stdin closed — parent is done
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        }
    }

    func setRecording() {
        isRecording = true
        statusItem.button?.attributedTitle = NSAttributedString(
            string: "● REC",
            attributes: [
                .foregroundColor: NSColor.red,
                .font: NSFont.systemFont(ofSize: 12, weight: .medium)
            ]
        )
    }

    func setIdle() {
        isRecording = false
        statusItem.button?.attributedTitle = NSAttributedString(
            string: "● REC",
            attributes: [
                .foregroundColor: NSColor(white: 0.85, alpha: 1.0),
                .font: NSFont.systemFont(ofSize: 12, weight: .medium)
            ]
        )
    }

    @objc func buttonClicked() {
        if isRecording {
            print("stop")
            fflush(stdout)
            setIdle()
        } else {
            print("start")
            fflush(stdout)
            setRecording()
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
