import SwiftUI

// MARK: - OnboardingView

struct OnboardingView: View {
    enum Step: Int, CaseIterable { case welcome, permissions, download, done }

    @State private var step: Step = .welcome
    @State private var launchAtLogin: Bool = true
    @StateObject private var perms = PermissionsManager()
    @StateObject private var downloader = ModelDownloadManager()
    let onComplete: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            stepContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(32)
            Divider()
            HStack {
                HStack(spacing: 6) {
                    ForEach(Step.allCases, id: \.rawValue) { s in
                        Circle()
                            .fill(s == step ? Color.accentColor : Color.secondary.opacity(0.35))
                            .frame(width: 7, height: 7)
                    }
                }
                Spacer()
                nextButton
            }
            .padding()
        }
        .frame(width: 540, height: 460)
        .onAppear { perms.checkInitialStatuses() }
    }

    @ViewBuilder private var stepContent: some View {
        switch step {
        case .welcome:
            VStack(spacing: 20) {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 64)).foregroundColor(.accentColor)
                Text("Welcome to Meeting Transcriber")
                    .font(.title).fontWeight(.semibold)
                Text("Automatically detects, records, and transcribes your meetings.\nWe'll set up permissions and download the AI model in a few steps.")
                    .multilineTextAlignment(.center).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .permissions:
            PermissionsStep(perms: perms)
        case .download:
            DownloadStep(downloader: downloader)
        case .done:
            VStack(spacing: 20) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64)).foregroundColor(.green)
                Text("You're All Set!")
                    .font(.title).fontWeight(.semibold)
                Text("Meeting Transcriber will run in your menu bar and automatically detect when you start a meeting.")
                    .multilineTextAlignment(.center).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .toggleStyle(.switch)
                    .frame(maxWidth: 260)
                    .onChange(of: launchAtLogin) { enabled in
                        LoginItemManager.shared.setEnabled(enabled)
                    }
            }
            .onAppear {
                // Register by default (opt-out model). User may toggle off above.
                LoginItemManager.shared.register()
                launchAtLogin = LoginItemManager.shared.isEnabled
            }
        }
    }

    @ViewBuilder private var nextButton: some View {
        switch step {
        case .welcome:
            Button("Get Started") { step = .permissions }.buttonStyle(.borderedProminent)
        case .permissions:
            Button("Continue") { step = .download }
                .buttonStyle(.borderedProminent).disabled(!perms.allGranted)
        case .download:
            if downloader.isComplete {
                Button("Continue") { step = .done }.buttonStyle(.borderedProminent)
            } else {
                Button(downloader.isDownloading ? "Downloading…" : "Start Download") {
                    downloader.startDownload()
                }
                .buttonStyle(.borderedProminent)
                .disabled(downloader.isDownloading)
            }
        case .done:
            Button("Start Using Meeting Transcriber") { onComplete() }.buttonStyle(.borderedProminent)
        }
    }
}

// MARK: - PermissionsStep

private struct PermissionsStep: View {
    @ObservedObject var perms: PermissionsManager

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Grant Permissions").font(.title2).fontWeight(.semibold)
            Text("Meeting Transcriber needs these permissions to function:")
                .foregroundColor(.secondary)
            PermissionRow(
                icon: "mic.fill", title: "Microphone",
                detail: "Records your voice during meetings.",
                status: perms.micStatus,
                onRequest: { Task { await perms.requestMicAccess() } },
                onOpenSettings: { perms.openMicSettings() },
                onRecheck: { perms.refreshMicStatus() }
            )
            PermissionRow(
                icon: "display", title: "Screen Recording",
                detail: "Captures system audio from other participants. No screen content is recorded.",
                status: perms.screenStatus,
                onRequest: { Task { await perms.requestScreenAccess() } },
                onOpenSettings: { perms.openScreenSettings() },
                onRecheck: { Task { await perms.requestScreenAccess() } }
            )
            PermissionRow(
                icon: "bell.fill", title: "Notifications",
                detail: "Alerts you when a transcript is ready. Optional — app works without it.",
                status: perms.notificationStatus,
                onRequest: { perms.requestNotificationAccess() },
                onOpenSettings: { perms.openNotificationSettings() },
                onRecheck: { perms.refreshNotificationStatus() }
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Poll mic status while waiting (cheap); screen refreshed manually via buttons.
        .task {
            while !perms.allGranted {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                perms.refreshMicStatus()
            }
        }
    }
}

// MARK: - PermissionRow

private struct PermissionRow: View {
    let icon: String
    let title: String
    let detail: String
    let status: PermissionStatus
    let onRequest: () -> Void
    let onOpenSettings: () -> Void
    let onRecheck: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(status == .granted ? .green : .accentColor)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.medium)
                Text(detail).font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            statusControl
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    @ViewBuilder private var statusControl: some View {
        switch status {
        case .granted:
            Label("Granted", systemImage: "checkmark.circle.fill")
                .font(.caption).foregroundColor(.green)
        case .denied:
            HStack(spacing: 8) {
                Button("Open Settings", action: onOpenSettings).foregroundColor(.orange)
                Button(action: onRecheck) {
                    Image(systemName: "arrow.clockwise").font(.caption)
                }.help("Check again after granting in System Settings")
            }
        case .unknown:
            Button("Request Access", action: onRequest)
        }
    }
}

// MARK: - DownloadStep

private struct DownloadStep: View {
    @ObservedObject var downloader: ModelDownloadManager

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 48)).foregroundColor(.accentColor)
            Text("Download Whisper Model").font(.title2).fontWeight(.semibold)
            Text("The AI transcription model (~1.5 GB) will be downloaded once and stored locally on your Mac.")
                .multilineTextAlignment(.center).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if downloader.isDownloading || downloader.mainProgress > 0 {
                VStack(spacing: 6) {
                    ProgressView(value: max(downloader.mainProgress, 0.001))
                        .frame(maxWidth: .infinity)
                    Text(progressLabel).font(.caption).foregroundColor(.secondary)
                }
                .padding(.top, 4)
            }
            if let err = downloader.errorMessage {
                VStack(spacing: 8) {
                    Text(err).foregroundColor(.red).font(.caption).multilineTextAlignment(.center)
                    Button("Retry") { downloader.startDownload() }
                }
            }
            if downloader.isComplete {
                Label("Download complete", systemImage: "checkmark.circle.fill").foregroundColor(.green)
            }
        }
        .onAppear {
            if downloader.modelsExist { downloader.isComplete = true }
        }
    }

    private var progressLabel: String {
        guard downloader.mainTotalBytes > 0 else { return "Downloading…" }
        let fmt = ByteCountFormatter()
        fmt.countStyle = .file
        let written = fmt.string(fromByteCount: downloader.mainBytesWritten)
        let total = fmt.string(fromByteCount: downloader.mainTotalBytes)
        return "\(written) / \(total)"
    }
}
