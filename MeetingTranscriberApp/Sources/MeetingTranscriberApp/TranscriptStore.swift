import Foundation

// MARK: - TranscriptEntry

struct TranscriptEntry: Identifiable, Equatable {
    let id: String          // filename stem, e.g. "2026-02-13T14-30-00"
    let filePath: String
    let date: Date
    let duration: String
    let snippet: String
    let rawContent: String
}

// MARK: - TranscriptStore

/// Loads and watches ~/transcripts/ for markdown transcript files.
/// Publishes a sorted list and exposes search/selection state.
class TranscriptStore: ObservableObject {
    static let defaultDir: URL =
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("transcripts")

    @Published var transcripts: [TranscriptEntry] = []
    @Published var searchQuery: String = ""
    @Published var selectedID: String?

    var filtered: [TranscriptEntry] {
        guard !searchQuery.isEmpty else { return transcripts }
        let q = searchQuery.lowercased()
        return transcripts.filter {
            $0.rawContent.lowercased().contains(q) ||
            $0.id.contains(q)
        }
    }

    private let dir: URL
    private var fsSource: DispatchSourceFileSystemObject?
    private var dirFD: Int32 = -1

    init(dir: URL = TranscriptStore.defaultDir) {
        self.dir = dir
        load()
        startWatching()
    }

    deinit {
        fsSource?.cancel()
        if dirFD >= 0 { Darwin.close(dirFD) }
    }

    // MARK: - Load

    func load() {
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(atPath: dir.path)) ?? []
        let entries = files
            .filter { $0.hasSuffix(".md") }
            .compactMap { makeEntry(filename: $0) }
            .sorted { $0.date > $1.date }
        DispatchQueue.main.async { self.transcripts = entries }
    }

    private func makeEntry(filename: String) -> TranscriptEntry? {
        let stem = String(filename.dropLast(3))  // drop ".md"
        guard let date = parseDate(stem) else { return nil }
        let path = dir.appendingPathComponent(filename).path
        let content = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        return TranscriptEntry(
            id: stem,
            filePath: path,
            date: date,
            duration: extractDuration(from: content),
            snippet: extractSnippet(from: content),
            rawContent: content
        )
    }

    // MARK: - Parsing helpers

    /// Parses "2026-02-13T14-30-00" → Date (UTC)
    private func parseDate(_ stem: String) -> Date? {
        let parts = stem.split(separator: "T")
        guard parts.count == 2 else { return nil }
        let d = parts[0].split(separator: "-")
        let t = parts[1].split(separator: "-")
        guard d.count == 3, t.count == 3,
              let y = Int(d[0]), let mo = Int(d[1]), let dy = Int(d[2]),
              let h = Int(t[0]), let mi = Int(t[1]), let s = Int(t[2]) else { return nil }
        var c = DateComponents()
        c.year = y; c.month = mo; c.day = dy
        c.hour = h; c.minute = mi; c.second = s
        c.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: c)
    }

    /// Extracts duration from "# Meeting Transcript — DATE (5m 30s)"
    private func extractDuration(from content: String) -> String {
        let first = content.components(separatedBy: .newlines).first ?? ""
        if let open = first.lastIndex(of: "("),
           let close = first.lastIndex(of: ")"),
           open < close {
            return String(first[first.index(after: open)..<close])
        }
        return "?"
    }

    /// Returns the first speaker line text as a plain-text snippet.
    private func extractSnippet(from content: String) -> String {
        let lines = content.components(separatedBy: .newlines).dropFirst(2)
        for line in lines {
            let t = line.trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty, !t.hasPrefix("#"), !t.hasPrefix("*[") else { continue }
            // Strip **Speaker:** prefix
            if t.hasPrefix("**"), let range = t.range(of: ":** ") {
                return String(t[range.upperBound...].prefix(120))
            }
            return String(t.prefix(120))
        }
        return ""
    }

    // MARK: - FSEvents directory watcher

    private func startWatching() {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fd = Darwin.open(dir.path, O_EVTONLY)
        guard fd >= 0 else { return }
        dirFD = fd
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete],
            queue: .global(qos: .utility)
        )
        src.setEventHandler { [weak self] in self?.load() }
        src.setCancelHandler { Darwin.close(fd) }
        src.resume()
        fsSource = src
    }
}
