import SwiftUI
import ServiceManagement
import AVFoundation

/// App settings window with General / Audio / AI / Advanced tabs.
struct SettingsView: View {
    @ObservedObject private var config = AppConfig.shared
    @ObservedObject private var loginItem = LoginItemManager.shared

    /// Called when the user taps "Install mt CLI" in the Advanced tab.
    var onInstallCLI: (() -> Void)?
    /// Called when the user taps "Re-run Setup Wizard" in the Advanced tab.
    var onRerunSetupWizard: (() -> Void)?

    // AI tab state
    @State private var apiKey: String = ""
    @State private var apiKeySaved = false

    // Audio tab state
    @State private var availableDevices: [String] = []

    // Advanced tab state
    @State private var showFolderPicker = false

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gear") }
            audioTab
                .tabItem { Label("Audio", systemImage: "waveform") }
            aiTab
                .tabItem { Label("AI", systemImage: "sparkles") }
            advancedTab
                .tabItem { Label("Advanced", systemImage: "slider.horizontal.3") }
        }
        .padding(20)
        .frame(width: 480, height: 300)
        .onAppear {
            loginItem.refresh()
            apiKey = KeychainManager.shared.retrieve(key: "ANTHROPIC_API_KEY") ?? ""
            loadDevices()
        }
    }

    // MARK: - General Tab

    private var generalTab: some View {
        Form {
            Toggle(isOn: Binding(
                get: { loginItem.isEnabled },
                set: { loginItem.setEnabled($0) }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Launch at Login")
                    if SMAppService.mainApp.status == .requiresApproval {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                                .font(.caption)
                            Text("Requires approval in System Settings → Login Items")
                                .font(.caption).foregroundColor(.secondary)
                            Button("Open") { SMAppService.openSystemSettingsLoginItems() }
                                .font(.caption)
                        }
                    }
                }
            }

            Toggle("Show notifications", isOn: $config.notificationsEnabled)
        }
        .formStyle(.grouped)
    }

    // MARK: - Audio Tab

    private var audioTab: some View {
        Form {
            Picker("Whisper model", selection: $config.whisperModel) {
                Text("Tiny  (~75 MB)").tag("tiny")
                Text("Base  (~142 MB)").tag("base")
                Text("Small  (~466 MB)").tag("small")
                Text("Medium  (~1.5 GB)").tag("medium")
                Text("Large v3 Turbo  (~809 MB)").tag("large-v3-turbo")
            }
            .help("Larger models are more accurate but use more CPU and memory.")

            Picker("Input device", selection: $config.audioDeviceOverride) {
                Text("System Default").tag("")
                ForEach(availableDevices, id: \.self) { name in
                    Text(name).tag(name)
                }
            }
            .help("Override which microphone is used for recording.")
        }
        .formStyle(.grouped)
    }

    // MARK: - AI Tab

    private var aiTab: some View {
        Form {
            Toggle("Enable AI summaries", isOn: $config.aiEnabled)

            if config.aiEnabled {
                HStack(spacing: 8) {
                    SecureField("Anthropic API key", text: $apiKey)
                        .textContentType(.password)

                    Button(apiKeySaved ? "Saved ✓" : "Save") {
                        KeychainManager.shared.save(key: "ANTHROPIC_API_KEY", value: apiKey)
                        apiKeySaved = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            apiKeySaved = false
                        }
                    }
                    .disabled(apiKey.isEmpty)
                    .buttonStyle(.borderedProminent)

                    if !apiKey.isEmpty {
                        Button("Clear") {
                            apiKey = ""
                            KeychainManager.shared.delete(key: "ANTHROPIC_API_KEY")
                        }
                        .foregroundColor(.red)
                    }
                }

                Picker("Claude model", selection: $config.claudeModel) {
                    Text("Claude Sonnet 4.6 (recommended)").tag("claude-sonnet-4-6")
                    Text("Claude Haiku 4.5 (fast)").tag("claude-haiku-4-5-20251001")
                    Text("Claude Opus 4.6 (most capable)").tag("claude-opus-4-6")
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Advanced Tab

    private var advancedTab: some View {
        Form {
            HStack {
                Text(config.transcriptDir.isEmpty
                    ? "~/transcripts (default)"
                    : config.transcriptDir)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
                Spacer()
                if !config.transcriptDir.isEmpty {
                    Button("Reset") { config.transcriptDir = "" }
                }
                Button("Choose…") { showFolderPicker = true }
            }

            HStack(spacing: 12) {
                Button("Install mt CLI") { onInstallCLI?() }
                Button("Re-run Setup Wizard…") { onRerunSetupWizard?() }
                Spacer()
            }
        }
        .formStyle(.grouped)
        .fileImporter(
            isPresented: $showFolderPicker,
            allowedContentTypes: [.folder]
        ) { result in
            if case .success(let url) = result {
                config.transcriptDir = url.path
            }
        }
    }

    // MARK: - Helpers

    private func loadDevices() {
        if #available(macOS 14.0, *) {
            let session = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.microphone],
                mediaType: .audio,
                position: .unspecified
            )
            availableDevices = session.devices.map(\.localizedName)
        } else {
            availableDevices = AVCaptureDevice.devices(for: .audio).map(\.localizedName)
        }
    }
}
