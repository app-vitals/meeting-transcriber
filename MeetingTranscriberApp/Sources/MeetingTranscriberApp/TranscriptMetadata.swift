import Foundation

// MARK: - TranscriptMetadata

struct TranscriptMetadata: Equatable {
    /// Duration in seconds, parsed from "5m 30s" for sorting. 0 if unknown.
    let durationSeconds: Int
    /// Participant names from **Participants:** line (AI summary) or unique speaker labels.
    let participantNames: [String]
    /// Count of unchecked action items ("- [ ]") in the transcript.
    let actionItemCount: Int
    /// TL;DR paragraph from the ## Summary section, if present.
    let summarySnippet: String
}

// MARK: - SortOrder

enum SortOrder: String, CaseIterable, Identifiable {
    case dateDesc     = "Date (Newest)"
    case durationDesc = "Duration"
    case actionItems  = "Action Items"

    var id: Self { self }
}

// MARK: - DateFilter

enum DateFilter: String, CaseIterable, Identifiable {
    case all   = "All Time"
    case today = "Today"
    case week  = "This Week"
    case month = "This Month"

    var id: Self { self }

    func includes(_ date: Date) -> Bool {
        let cal = Calendar.current
        let now = Date()
        switch self {
        case .all:   return true
        case .today: return cal.isDateInToday(date)
        case .week:  return cal.isDate(date, equalTo: now, toGranularity: .weekOfYear)
        case .month: return cal.isDate(date, equalTo: now, toGranularity: .month)
        }
    }
}
