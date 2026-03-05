import SwiftUI
import ServiceManagement

/// App settings window. Currently exposes the Launch at Login toggle.
struct SettingsView: View {
    @ObservedObject private var loginItem = LoginItemManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Settings")
                .font(.title2).fontWeight(.semibold)
                .padding(.bottom, 20)

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle(isOn: Binding(
                        get: { loginItem.isEnabled },
                        set: { loginItem.setEnabled($0) }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Launch at Login")
                                .fontWeight(.medium)
                            Text("Automatically start Meeting Transcriber when you log in.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .toggleStyle(.switch)

                    if SMAppService.mainApp.status == .requiresApproval {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                                .font(.caption)
                            Text("Requires approval in System Settings → General → Login Items.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Button("Open") {
                                SMAppService.openSystemSettingsLoginItems()
                            }
                            .font(.caption)
                        }
                    }
                }
                .padding(4)
            }
        }
        .padding(24)
        .frame(width: 380)
        .onAppear { loginItem.refresh() }
    }
}
