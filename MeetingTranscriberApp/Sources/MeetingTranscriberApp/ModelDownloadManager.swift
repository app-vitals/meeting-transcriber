import Foundation

struct ModelSpec {
    let name: String
    let url: URL
    let resumeKey: String
}

/// Downloads whisper model files with URLSession progress tracking and resume support.
///
/// On cancellation or interrupted downloads, resume data is stored in UserDefaults.
/// On next `startDownload()` call, the download resumes from where it left off.
class ModelDownloadManager: NSObject, ObservableObject {
    static let mainModel = ModelSpec(
        name: "ggml-large-v3-turbo.bin",
        url: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin")!,
        resumeKey: "resumeData.large-v3-turbo"
    )
    static let vadModel = ModelSpec(
        name: "ggml-silero-v5.1.2.bin",
        url: URL(string: "https://huggingface.co/ggml-org/whisper-vad/resolve/main/ggml-silero-v5.1.2.bin")!,
        resumeKey: "resumeData.silero-vad"
    )

    static let modelsDir: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("MeetingTranscriber/models")
    }()

    @Published var mainProgress: Double = 0
    @Published var mainBytesWritten: Int64 = 0
    @Published var mainTotalBytes: Int64 = 0
    @Published var vadProgress: Double = 0
    @Published var isDownloading = false
    @Published var errorMessage: String?
    @Published var isComplete = false

    private var session: URLSession?
    /// Maps an active download task to its model spec.
    private var taskToModel: [URLSessionDownloadTask: ModelSpec] = [:]
    private var pendingCount = 0

    override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppWillTerminate),
            name: NSApplication.willTerminateNotification,
            object: nil
        )
    }

    /// Synchronously cancels active download tasks and stores resume data before process exit.
    @objc private func handleAppWillTerminate() {
        guard isDownloading else { return }
        let snapshot = taskToModel
        let sema = DispatchSemaphore(value: 0)
        var remaining = snapshot.count
        for (task, model) in snapshot {
            task.cancel { resumeData in
                if let resumeData {
                    UserDefaults.standard.set(resumeData, forKey: model.resumeKey)
                }
                remaining -= 1
                if remaining == 0 { sema.signal() }
            }
        }
        _ = sema.wait(timeout: .now() + 5.0)
        UserDefaults.standard.synchronize()
    }

    var modelsExist: Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: Self.modelsDir.appendingPathComponent(Self.mainModel.name).path) &&
               fm.fileExists(atPath: Self.modelsDir.appendingPathComponent(Self.vadModel.name).path)
    }

    func startDownload() {
        guard !isDownloading else { return }
        errorMessage = nil

        try? FileManager.default.createDirectory(at: Self.modelsDir, withIntermediateDirectories: true)

        let config = URLSessionConfiguration.default
        let newSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        session = newSession
        taskToModel = [:]
        pendingCount = 0

        for model in [Self.mainModel, Self.vadModel] {
            let dest = Self.modelsDir.appendingPathComponent(model.name)
            guard !FileManager.default.fileExists(atPath: dest.path) else { continue }

            let task: URLSessionDownloadTask
            if let resumeData = UserDefaults.standard.data(forKey: model.resumeKey) {
                task = newSession.downloadTask(withResumeData: resumeData)
                UserDefaults.standard.removeObject(forKey: model.resumeKey)
            } else {
                task = newSession.downloadTask(with: model.url)
            }
            taskToModel[task] = model
            pendingCount += 1
            task.resume()
        }

        if pendingCount == 0 {
            isComplete = true
        } else {
            isDownloading = true
        }
    }
}

// MARK: - URLSessionDownloadDelegate

extension ModelDownloadManager: URLSessionDownloadDelegate {
    func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask,
        didWriteData _: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64
    ) {
        guard let model = taskToModel[downloadTask] else { return }
        let progress = totalBytesExpectedToWrite > 0
            ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) : 0

        DispatchQueue.main.async {
            if model.name == Self.mainModel.name {
                self.mainProgress = progress
                self.mainBytesWritten = totalBytesWritten
                self.mainTotalBytes = totalBytesExpectedToWrite
            } else {
                self.vadProgress = progress
            }
        }
    }

    func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let model = taskToModel[downloadTask] else { return }
        let dest = Self.modelsDir.appendingPathComponent(model.name)
        do {
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.moveItem(at: location, to: dest)
        } catch {
            print("[ModelDownload] Failed to move \(model.name): \(error)")
        }

        DispatchQueue.main.async {
            self.taskToModel.removeValue(forKey: downloadTask)
            self.pendingCount -= 1
            if self.pendingCount <= 0 {
                self.isDownloading = false
                self.isComplete = true
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        let nsError = error as NSError

        // Store resume data so the download can continue next time.
        if let downloadTask = task as? URLSessionDownloadTask,
           let resumeData = nsError.userInfo[NSURLSessionDownloadTaskResumeData] as? Data,
           let model = taskToModel[downloadTask] {
            UserDefaults.standard.set(resumeData, forKey: model.resumeKey)
            DispatchQueue.main.async { self.taskToModel.removeValue(forKey: downloadTask) }
            return  // Cancelled — not an error to surface
        }

        DispatchQueue.main.async {
            self.isDownloading = false
            self.errorMessage = error.localizedDescription
            self.taskToModel = [:]
        }
    }
}
