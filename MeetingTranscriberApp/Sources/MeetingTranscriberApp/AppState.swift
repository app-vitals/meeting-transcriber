import Foundation

enum RecordingState {
    case idle
    case recording
    case processing
}

/// Observable app state. Mutate only on the main thread.
class AppState {
    var recordingState: RecordingState = .idle {
        didSet { onChange?() }
    }
    var engineRunning: Bool = false {
        didSet { onChange?() }
    }

    /// Called on main thread whenever state changes.
    var onChange: (() -> Void)?
}
