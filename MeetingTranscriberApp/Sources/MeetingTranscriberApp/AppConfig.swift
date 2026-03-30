import Foundation

/// Central app configuration backed by UserDefaults.
///
/// Changes are persisted immediately and written to config.json so the
/// TypeScript engine can read them when launched without the Swift app.
class AppConfig: ObservableObject {
    static let shared = AppConfig()

    // MARK: - Published settings

    @Published var notificationsEnabled: Bool = true {
        didSet { UserDefaults.standard.set(notificationsEnabled, forKey: "notificationsEnabled"); persist() }
    }
    /// Whisper model identifier, e.g. "large-v3-turbo", "base", "small".
    @Published var whisperModel: String = "large-v3-turbo" {
        didSet { UserDefaults.standard.set(whisperModel, forKey: "whisperModel"); persist() }
    }
    /// Empty string means use system default input device.
    @Published var audioDeviceOverride: String = "" {
        didSet { UserDefaults.standard.set(audioDeviceOverride, forKey: "audioDeviceOverride"); persist() }
    }
    @Published var aiEnabled: Bool = true {
        didSet { UserDefaults.standard.set(aiEnabled, forKey: "aiEnabled"); persist() }
    }
    @Published var claudeModel: String = "claude-sonnet-4-6" {
        didSet { UserDefaults.standard.set(claudeModel, forKey: "claudeModel"); persist() }
    }
    /// Empty string means ~/transcripts (default).
    @Published var transcriptDir: String = "" {
        didSet { UserDefaults.standard.set(transcriptDir, forKey: "transcriptDir"); persist() }
    }

    // MARK: - Paths

    /// ~/Library/Application Support/MeetingTranscriber/
    static let supportDir: URL = {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MeetingTranscriber")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static let configURL: URL = supportDir.appendingPathComponent("config.json")

    /// The resolved transcript directory URL.
    var resolvedTranscriptDir: URL {
        transcriptDir.isEmpty
            ? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("transcripts")
            : URL(fileURLWithPath: (transcriptDir as NSString).expandingTildeInPath)
    }

    /// Absolute path to the selected whisper model binary.
    /// Prefers the App Support models dir, falls back to process.cwd()/models (CLI installs).
    var resolvedModelPath: String {
        let name = "ggml-\(whisperModel).bin"
        let preferred = AppConfig.supportDir.appendingPathComponent("models").appendingPathComponent(name).path
        if FileManager.default.fileExists(atPath: preferred) { return preferred }
        return (FileManager.default.currentDirectoryPath as NSString)
            .appendingPathComponent("models/\(name)")
    }

    // MARK: - Init

    private init() {
        let d = UserDefaults.standard
        if let v = d.object(forKey: "notificationsEnabled") as? Bool { notificationsEnabled = v }
        if let v = d.string(forKey: "whisperModel"),   !v.isEmpty    { whisperModel = v }
        if let v = d.string(forKey: "audioDeviceOverride")            { audioDeviceOverride = v }
        if let v = d.object(forKey: "aiEnabled") as? Bool             { aiEnabled = v }
        if let v = d.string(forKey: "claudeModel"),    !v.isEmpty     { claudeModel = v }
        if let v = d.string(forKey: "transcriptDir")                  { transcriptDir = v }
    }

    // MARK: - Config JSON persistence

    /// Writes config.json so the standalone `mt watch` CLI can read settings
    /// even when launched without the Swift app.
    func persist() {
        var dict: [String: Any] = [
            "whisperModel":          whisperModel,
            "aiEnabled":             aiEnabled,
            "claudeModel":           claudeModel,
            "notificationsEnabled":  notificationsEnabled,
        ]
        if !transcriptDir.isEmpty {
            dict["transcriptDir"] = (transcriptDir as NSString).expandingTildeInPath
        }
        if !audioDeviceOverride.isEmpty {
            dict["audioDeviceOverride"] = audioDeviceOverride
        }
        guard let data = try? JSONSerialization.data(
            withJSONObject: dict,
            options: [.prettyPrinted, .sortedKeys]
        ) else { return }
        try? data.write(to: AppConfig.configURL)
    }
}
