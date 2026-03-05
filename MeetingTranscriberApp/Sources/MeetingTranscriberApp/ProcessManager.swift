import Foundation

/// Manages the meeting-transcriber TypeScript engine subprocess.
///
/// Launches `meeting-transcriber watch` with `NO_REC_STATUS=1` so the TS engine
/// skips its own rec-status subprocess and instead reads start/stop commands from
/// stdin (which this manager writes). Parses stdout to track recording state.
/// Automatically restarts the engine if it crashes.
class ProcessManager {
    private var process: Process?
    private var stdinHandle: FileHandle?
    private var restartWorkItem: DispatchWorkItem?
    private var isShuttingDown = false

    weak var appState: AppState?

    /// Called on the main thread with the transcript filename stem
    /// (e.g. "2026-02-13T14-30-00") when the engine saves a new transcript.
    var onTranscriptSaved: ((String) -> Void)?

    func start() {
        launchEngine()
    }

    // MARK: - Commands

    func startRecording() {
        writeToStdin("start\n")
    }

    func stopRecording() {
        writeToStdin("stop\n")
    }

    // MARK: - Lifecycle

    func shutdown() {
        isShuttingDown = true
        restartWorkItem?.cancel()
        if let proc = process, proc.isRunning {
            proc.terminate()
        }
        process = nil
        stdinHandle = nil
    }

    // MARK: - Private

    private func launchEngine() {
        guard !isShuttingDown else { return }

        guard let binary = findBinary() else {
            print("[ProcessManager] meeting-transcriber binary not found — will retry in 10s")
            scheduleRestart(delay: 10)
            return
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: binary)
        proc.arguments = ["watch"]

        // Set the working directory to the same folder as this app's executable so
        // the engine resolves its helper paths (process.cwd() + "/src/mic-check" etc.)
        // correctly both in the .app bundle (Contents/MacOS/) and during development.
        let appExecDir = URL(fileURLWithPath: ProcessInfo.processInfo.arguments[0])
            .resolvingSymlinksInPath()
            .deletingLastPathComponent()
        proc.currentDirectoryURL = appExecDir

        var env = ProcessInfo.processInfo.environment
        env["NO_REC_STATUS"] = "1"
        proc.environment = env

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        proc.standardInput = stdinPipe
        proc.standardOutput = stdoutPipe
        proc.standardError = stderrPipe

        stdinHandle = stdinPipe.fileHandleForWriting

        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] fh in
            let data = fh.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            self?.parseOutput(text)
        }

        // Drain stderr to avoid pipe buffer filling up
        stderrPipe.fileHandleForReading.readabilityHandler = { fh in
            _ = fh.availableData
        }

        proc.terminationHandler = { [weak self] p in
            print("[ProcessManager] Engine exited (status \(p.terminationStatus))")
            DispatchQueue.main.async {
                self?.appState?.engineRunning = false
                self?.appState?.recordingState = .idle
            }
            self?.scheduleRestart(delay: 3)
        }

        do {
            try proc.run()
            self.process = proc
            print("[ProcessManager] Engine started (PID \(proc.processIdentifier))")
            DispatchQueue.main.async {
                self.appState?.engineRunning = true
            }
        } catch {
            print("[ProcessManager] Failed to launch engine: \(error)")
            scheduleRestart(delay: 5)
        }
    }

    private func parseOutput(_ text: String) {
        for line in text.components(separatedBy: .newlines) {
            let l = line.trimmingCharacters(in: .whitespaces)
            if l.contains("[detect] Microphone activated") || l.contains("[record] Mic recording:") {
                DispatchQueue.main.async { self.appState?.recordingState = .recording }
            } else if l.contains("[record] Stopping recordings") {
                DispatchQueue.main.async { self.appState?.recordingState = .processing }
            } else if l.contains("[transcribe] Saved:") || l.contains("Watching for microphone")
                        || l.contains("Recording deleted") {
                // Extract transcript stem and path from "[transcribe] Saved: /path/to/STEM.md"
                let savedStem: String?
                let savedPath: String?
                if l.contains("[transcribe] Saved:"),
                   let savedRange = l.range(of: "[transcribe] Saved: ") {
                    let path = String(l[savedRange.upperBound...]).trimmingCharacters(in: .whitespaces)
                    savedStem = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
                    savedPath = path
                } else {
                    savedStem = nil
                    savedPath = nil
                }
                DispatchQueue.main.async {
                    self.appState?.recordingState = .idle
                    if let stem = savedStem, let path = savedPath {
                        NotificationManager.shared.sendTranscriptReady(stem: stem, transcriptPath: path)
                        self.onTranscriptSaved?(stem)
                    }
                }
            }
        }
    }

    private func writeToStdin(_ text: String) {
        guard let handle = stdinHandle,
              let data = text.data(using: .utf8) else { return }
        handle.write(data)
    }

    private func scheduleRestart(delay: Double = 3) {
        guard !isShuttingDown else { return }
        restartWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.process = nil
            self?.stdinHandle = nil
            self?.launchEngine()
        }
        restartWorkItem = item
        DispatchQueue.global().asyncAfter(deadline: .now() + delay, execute: item)
    }

    // MARK: - Binary discovery

    private func findBinary() -> String? {
        let fm = FileManager.default
        let execPath = ProcessInfo.processInfo.arguments[0]
        let execDir = URL(fileURLWithPath: execPath).deletingLastPathComponent()

        // Resolve symlinks so relative traversal works correctly
        let resolvedExecDir: URL
        if let resolved = try? URL(fileURLWithPath: execPath).resourceValues(forKeys: [.canonicalPathKey]).canonicalPath {
            resolvedExecDir = URL(fileURLWithPath: resolved).deletingLastPathComponent()
        } else {
            resolvedExecDir = execDir
        }

        // Check progressively higher parent dirs (handles swift build output layout)
        var dir = resolvedExecDir
        for _ in 0..<5 {
            let candidate = dir.appendingPathComponent("meeting-transcriber").path
            if fm.isExecutableFile(atPath: candidate) { return candidate }
            dir = dir.deletingLastPathComponent()
        }

        // PATH lookup
        let pathEnv = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/local/bin:/usr/bin:/bin"
        for component in pathEnv.components(separatedBy: ":") {
            let candidate = URL(fileURLWithPath: component)
                .appendingPathComponent("meeting-transcriber").path
            if fm.isExecutableFile(atPath: candidate) { return candidate }
        }

        return nil
    }
}
