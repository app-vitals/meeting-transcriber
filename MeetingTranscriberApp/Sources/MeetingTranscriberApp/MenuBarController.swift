import Cocoa

/// Owns the NSStatusItem and contextual menu. Ported from src/rec-status.swift.
///
/// Icon: "● REC" — red while recording, yellow while processing, light-gray while idle.
/// Clicking the icon shows a contextual menu with Start/Stop/Quit.
class MenuBarController: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let appState: AppState
    private let processManager: ProcessManager
    private let onShowSetupWizard: () -> Void
    private let onViewTranscripts: () -> Void
    private let onOpenTranscriptsFolder: () -> Void
    private let onOpenSettings: () -> Void
    private let menu = NSMenu()

    init(
        appState: AppState,
        processManager: ProcessManager,
        onShowSetupWizard: @escaping () -> Void,
        onViewTranscripts: @escaping () -> Void,
        onOpenTranscriptsFolder: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void
    ) {
        self.appState = appState
        self.processManager = processManager
        self.onShowSetupWizard = onShowSetupWizard
        self.onViewTranscripts = onViewTranscripts
        self.onOpenTranscriptsFolder = onOpenTranscriptsFolder
        self.onOpenSettings = onOpenSettings
        super.init()
        setupStatusItem()
        appState.onChange = { [weak self] in
            DispatchQueue.main.async { self?.updateIcon() }
        }
        updateIcon()
    }

    // MARK: - Setup

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        menu.delegate = self
        statusItem.menu = menu
        updateIcon()
    }

    // MARK: - NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        buildMenu()
    }

    // MARK: - Icon

    private func updateIcon() {
        guard let button = statusItem.button else { return }

        let color: NSColor
        switch appState.recordingState {
        case .idle:
            color = NSColor(white: 0.85, alpha: 1.0)
        case .recording:
            color = .red
        case .processing:
            color = .systemYellow
        }

        button.attributedTitle = NSAttributedString(
            string: "● REC",
            attributes: [
                .foregroundColor: color,
                .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            ]
        )
    }

    // MARK: - Menu

    private func buildMenu() {
        menu.removeAllItems()

        // Status label (non-interactive)
        let stateTitle: String
        switch appState.recordingState {
        case .idle:
            stateTitle = appState.engineRunning ? "Idle" : "Engine starting…"
        case .recording:
            stateTitle = "Recording…"
        case .processing:
            stateTitle = "Processing…"
        }
        let stateItem = NSMenuItem(title: stateTitle, action: nil, keyEquivalent: "")
        stateItem.isEnabled = false
        menu.addItem(stateItem)

        menu.addItem(.separator())

        let startItem = NSMenuItem(
            title: "Start Recording",
            action: #selector(startRecording),
            keyEquivalent: ""
        )
        startItem.target = self
        startItem.isEnabled = appState.recordingState == .idle && appState.engineRunning
        menu.addItem(startItem)

        let stopItem = NSMenuItem(
            title: "Stop Recording",
            action: #selector(stopRecording),
            keyEquivalent: ""
        )
        stopItem.target = self
        stopItem.isEnabled = appState.recordingState == .recording
        menu.addItem(stopItem)

        menu.addItem(.separator())

        let viewTranscriptsItem = NSMenuItem(
            title: "View Transcripts",
            action: #selector(viewTranscripts),
            keyEquivalent: "t"
        )
        viewTranscriptsItem.target = self
        menu.addItem(viewTranscriptsItem)

        let openFolderItem = NSMenuItem(
            title: "Open Transcripts Folder",
            action: #selector(openTranscriptsFolder),
            keyEquivalent: ""
        )
        openFolderItem.target = self
        menu.addItem(openFolderItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        let wizardItem = NSMenuItem(
            title: "Setup Wizard…",
            action: #selector(runSetupWizard),
            keyEquivalent: ""
        )
        wizardItem.target = self
        menu.addItem(wizardItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    // MARK: - Actions

    @objc private func startRecording() {
        processManager.startRecording()
    }

    @objc private func stopRecording() {
        processManager.stopRecording()
    }

    @objc private func viewTranscripts() {
        onViewTranscripts()
    }

    @objc private func openTranscriptsFolder() {
        onOpenTranscriptsFolder()
    }

    @objc private func openSettings() {
        onOpenSettings()
    }

    @objc private func runSetupWizard() {
        onShowSetupWizard()
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
