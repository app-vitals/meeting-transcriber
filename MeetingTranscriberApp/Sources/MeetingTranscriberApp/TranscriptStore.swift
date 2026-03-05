import Foundation

// MARK: - TranscriptEntry

struct TranscriptEntry: Identifiable, Equatable {
    let id: String          // filename stem, e.g. "2026-02-13T14-30-00"
    let filePath: String
    let date: Date
    let duration: String    // human-readable, e.g. "5m 30s"
    let snippet: String     // first speaker line (plain text)
    let rawContent: String
    let metadata: TranscriptMetadata
}

// MARK: - TranscriptStore

/// Loads and watches ~/transcripts/ for markdown transcript files.
/// Publishes a sorted, filtered list and exposes search/selection state.
class TranscriptStore: ObservableObject {
    static let defaultDir: URL =
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("transcripts")

    @Published var transcripts: [TranscriptEntry] = []
    @Published var selectedID: String?

    // MARK: - Filter / sort state

    @Published var sortOrder: SortOrder = .dateDesc
    @Published var dateFilter: DateFilter = .all
    @Published var hasActionItemsOnly: Bool = false

    /// Live-typed search query (debounced before filtering).
    @Published var searchQuery: String = "" {
        didSet { scheduleSearch() }
    }

    /// Debounced value of searchQuery — actually used by `filtered`.
    @Published private var debouncedQuery: String = ""

    // MARK: - Filtered results

    var filtered: [TranscriptEntry] {
        var result = transcripts

        // Date range filter
        if dateFilter != .all {
            result = result.filter { dateFilter.includes($0.date) }
        }

        // Action items filter
        if hasActionItemsOnly {
            result = result.filter { $0.metadata.actionItemCount > 0 }
        }

        // Full-text + filename search
        if !debouncedQuery.isEmpty {
            let q = debouncedQuery.lowercased()
            result = result.filter {
                $0.rawContent.lowercased().contains(q) || $0.id.contains(q)
            }
        }

        // Sort
        switch sortOrder {
        case .dateDesc:
            result.sort { $0.date > $1.date }
        case .durationDesc:
            result.sort { $0.metadata.durationSeconds > $1.metadata.durationSeconds }
        case .actionItems:
            result.sort { $0.metadata.actionItemCount > $1.metadata.actionItemCount }
        }

        return result
    }

    private let dir: URL
    private var fsSource: DispatchSourceFileSystemObject?
    private var searchTimer: Timer?

    init(dir: URL = TranscriptStore.defaultDir) {
        self.dir = dir
        load()
        startWatching()
    }

    deinit {
        fsSource?.cancel()
        searchTimer?.invalidate()
    }

    // MARK: - Debounced search

    private func scheduleSearch() {
        searchTimer?.invalidate()
        searchTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: false) { [weak self] _ in
            guard let self else { return }
            DispatchQueue.main.async { self.debouncedQuery = self.searchQuery }
        }
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
        let dur = extractDuration(from: content)
        return TranscriptEntry(
            id: stem,
            filePath: path,
            date: date,
            duration: dur,
            snippet: extractSnippet(from: content),
            rawContent: content,
            metadata: TranscriptMetadata(
                durationSeconds: parseDurationSeconds(dur),
                participantNames: extractParticipants(from: content),
                actionItemCount: countActionItems(in: content),
                summarySnippet: extractSummarySnippet(from: content)
            )
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

    /// Parses "5m 30s", "1h 5m 30s", "30s", "5m" → total seconds. Returns 0 on failure.
    private func parseDurationSeconds(_ duration: String) -> Int {
        var total = 0
        let pattern = try? NSRegularExpression(pattern: #"(\d+)\s*([hms])"#)
        let range = NSRange(duration.startIndex..., in: duration)
        pattern?.enumerateMatches(in: duration, range: range) { match, _, _ in
            guard let match, match.numberOfRanges == 3,
                  let valRange = Range(match.range(at: 1), in: duration),
                  let unitRange = Range(match.range(at: 2), in: duration),
                  let val = Int(duration[valRange]) else { return }
            switch duration[unitRange] {
            case "h": total += val * 3600
            case "m": total += val * 60
            case "s": total += val
            default: break
            }
        }
        return total
    }

    /// Extracts participant names from the AI-generated **Participants:** line,
    /// or falls back to collecting unique speaker labels from speaker turns.
    private func extractParticipants(from content: String) -> [String] {
        let lines = content.components(separatedBy: .newlines)

        // Prefer AI-generated participants line
        for line in lines {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("**Participants:**") {
                let names = t
                    .replacingOccurrences(of: "**Participants:**", with: "")
                    .trimmingCharacters(in: .whitespaces)
                return names.components(separatedBy: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
            }
        }

        // Fallback: collect unique speaker names from "**Speaker:** …" lines
        var seen = Set<String>()
        var names: [String] = []
        for line in lines {
            let t = line.trimmingCharacters(in: .whitespaces)
            guard t.hasPrefix("**"), let markerRange = t.range(of: ":** ") else { continue }
            let nameStart = t.index(after: t.startIndex)  // skip first *
            let nameStr = String(t[nameStart..<markerRange.lowerBound])
            let speaker = nameStr.hasPrefix("*") ? String(nameStr.dropFirst()) : nameStr
            if !speaker.isEmpty && seen.insert(speaker).inserted {
                names.append(speaker)
            }
        }
        return names
    }

    /// Counts unchecked action item lines ("- [ ]") in the content.
    private func countActionItems(in content: String) -> Int {
        content.components(separatedBy: .newlines)
            .filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("- [ ]") }
            .count
    }

    /// Extracts the TL;DR paragraph from the ## Summary section (first non-empty paragraph).
    private func extractSummarySnippet(from content: String) -> String {
        let lines = content.components(separatedBy: .newlines)
        var inSummary = false
        for line in lines {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t == "## Summary" {
                inSummary = true
                continue
            }
            if inSummary {
                if t.isEmpty { continue }
                // Stop at sub-section header or separator
                if t.hasPrefix("#") || t == "---" { break }
                return String(t.prefix(200))
            }
        }
        return ""
    }

    // MARK: - FSEvents directory watcher

    private func startWatching() {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fd = Darwin.open(dir.path, O_EVTONLY)
        guard fd >= 0 else { return }
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
