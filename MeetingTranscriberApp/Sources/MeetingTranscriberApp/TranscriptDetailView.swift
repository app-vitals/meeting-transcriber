import SwiftUI

// MARK: - Turn model

private struct Turn: Identifiable {
    let id = UUID()
    /// "You", "Them", or "" for system/header notes
    let speaker: String
    let text: String
}

// MARK: - TranscriptDetailView

/// Full transcript detail pane. Parses speaker turns and renders them
/// as styled chat bubbles (You = right/accent, Them = left/gray).
struct TranscriptDetailView: View {
    let entry: TranscriptEntry

    private var turns: [Turn] { parseTurns(entry.rawContent) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                headerView
                if turns.isEmpty {
                    Text("Empty transcript.")
                        .foregroundColor(.secondary)
                        .padding(24)
                } else {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(turns) { turn in
                            TurnView(turn: turn)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Header

    private var headerView: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.date, style: .date)
                    .font(.title2).fontWeight(.semibold)
                HStack(spacing: 4) {
                    Text(entry.date, style: .time)
                    Text("·").foregroundColor(.secondary)
                    Text(entry.duration)
                }
                .font(.subheadline)
                .foregroundColor(.secondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            Divider()
        }
    }

    // MARK: - Parser

    /// Converts raw markdown transcript content into Turn objects.
    ///
    /// Supported line patterns:
    ///   **Speaker:** text   → speaker turn
    ///   *[note]*            → system note (speaker separation unavailable)
    ///   blank / header      → skipped
    private func parseTurns(_ content: String) -> [Turn] {
        var result: [Turn] = []
        // Track an in-progress turn (turns may span multiple consecutive lines)
        var pendingSpeaker: String?
        var pendingLines: [String] = []

        func flush() {
            guard let s = pendingSpeaker, !pendingLines.isEmpty else { return }
            let text = pendingLines.joined(separator: " ").trimmingCharacters(in: .whitespaces)
            if !text.isEmpty { result.append(Turn(speaker: s, text: text)) }
            pendingSpeaker = nil
            pendingLines = []
        }

        for line in content.components(separatedBy: .newlines).dropFirst(2) {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.isEmpty { continue }

            if t.hasPrefix("**"), let markerRange = t.range(of: ":** ") {
                // e.g. "**You:** Hello there"
                flush()
                // Extract speaker name: between the two ** markers
                let nameStart = t.index(after: t.startIndex)  // skip first *
                let nameStr = String(t[nameStart..<markerRange.lowerBound])
                let speaker = nameStr.hasPrefix("*") ? String(nameStr.dropFirst()) : nameStr
                let text = String(t[markerRange.upperBound...])
                pendingSpeaker = speaker
                pendingLines = [text]
            } else if t.hasPrefix("*[") && t.hasSuffix("]*") {
                // System note: *[Speaker separation unavailable...]*
                flush()
                let note = String(t.dropFirst(2).dropLast(2))
                result.append(Turn(speaker: "", text: note))
            } else if t.hasPrefix("#") {
                flush()  // skip header lines
            } else if pendingSpeaker != nil {
                pendingLines.append(t)
            } else {
                // Raw text (no speaker label) — render as a note
                result.append(Turn(speaker: "", text: t))
            }
        }
        flush()
        return result
    }
}

// MARK: - TurnView

private struct TurnView: View {
    let turn: Turn

    var body: some View {
        if turn.speaker.isEmpty {
            // System / info note — centred, italic
            Text(turn.text)
                .font(.caption)
                .foregroundColor(.secondary)
                .italic()
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 6)
        } else {
            let isYou = turn.speaker.lowercased() == "you"
            HStack(alignment: .top, spacing: 0) {
                if isYou { Spacer(minLength: 60) }
                VStack(alignment: isYou ? .trailing : .leading, spacing: 3) {
                    Text(turn.speaker)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(isYou ? .accentColor : .secondary)
                        .padding(.horizontal, 4)
                    Text(turn.text)
                        .font(.body)
                        .textSelection(.enabled)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            isYou
                                ? Color.accentColor.opacity(0.12)
                                : Color(NSColor.controlBackgroundColor)
                        )
                        .cornerRadius(12)
                }
                if !isYou { Spacer(minLength: 60) }
            }
        }
    }
}
